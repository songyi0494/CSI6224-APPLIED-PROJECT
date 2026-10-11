import logging
from datetime import date, datetime, timezone
from functools import lru_cache
from typing import Any, Dict, List, Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field, ValidationError

from cdss.core.config import GUIDELINE_VERSION, get_settings
from cdss.core.guidelines import ANABOLIC, ENDPOINTS, FIELD_BY_NAME, Facts, evaluate, fill_gaps
from cdss.ml.model import TreatmentModel

logger = logging.getLogger("cdss.api")


class TraceStep(BaseModel):
    rule_id: str
    question: str
    answer: str


class ModelOpinion(BaseModel):
    endpoint: str
    raw_endpoint: str
    confidence: float
    agrees_with_guideline: bool
    safety_override: Optional[str] = None
    model_version: Optional[str] = None


class Recommendation(BaseModel):
    case_id: Optional[str] = None
    patient_id: Optional[str] = None
    evaluated_at: datetime
    guideline_version: str
    endpoint: str
    decision: str
    title: str
    detail: str
    missing_inputs: List[str] = Field(default_factory=list)
    assumptions: List[str] = Field(default_factory=list)
    trace: List[TraceStep] = Field(default_factory=list)
    model_opinion: Optional[ModelOpinion] = None
    requires_clinician_review: bool = True
    review_reasons: List[str] = Field(default_factory=list)


@lru_cache
def get_model() -> TreatmentModel:
    s = get_settings()
    return TreatmentModel(s.model_path, s.model_card_path)


@lru_cache
def get_supabase() -> Optional[Any]:
    s = get_settings()
    if not s.supabase_enabled:
        return None
    from supabase import create_client

    return create_client(s.supabase_url, s.supabase_key)


def require_supabase() -> Any:
    client = get_supabase()
    if client is None:
        raise HTTPException(
            status_code=503,
            detail="Supabase is not configured: set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY."
        )
    return client


router = APIRouter(prefix="/api", tags=["Clinical Decision Support"])

YES_NO = {"yes": True, "no": False}
SEXES = ("female", "male")


def _years_between(start: date, end: date) -> int:
    return end.year - start.year - ((end.month, end.day) < (start.month, start.day))


def case_facts(
        case: Dict[str, Any],
        profile: Optional[Dict[str, Any]] = None,
        answers: Optional[Dict[str, Any]] = None,
        investigation: Optional[Dict[str, Any]] = None,
        today: Optional[date] = None
) -> Dict[str, Any]:
    """Merge a case's database rows into Facts keys.

    Priority order (later wins): profile, questionnaire answers,
    investigations, and finally explicit clinician_facts.
    """
    today = today or date.today()
    profile = profile or {}
    answers = answers or {}
    investigation = investigation or {}
    facts: Dict[str, Any] = {}

    def put(key: str, value: Any) -> None:
        if value is not None:
            facts[key] = value

    # 1. Demographics from profiles
    gender = str(profile.get("gender") or "").lower()
    if gender in SEXES:
        put("sex", gender)
    if profile.get("date_of_birth"):
        try:
            dob = date.fromisoformat(str(profile["date_of_birth"]))
            put("age", _years_between(dob, today))
        except (ValueError, TypeError):
            pass

    # 2. Patient Questionnaire Answers
    sex_ans = str(answers.get("sex") or "").lower()
    if sex_ans in SEXES:
        put("sex", sex_ans)

    if answers.get("postmenopausal") is not None:
        put("postmenopausal", YES_NO.get(str(answers.get("postmenopausal")).lower()))

    # Questionnaire minimal trauma fracture
    if answers.get("minimalTraumaFracture") is not None:
        put("minimalTraumaFracture", YES_NO.get(str(answers.get("minimalTraumaFracture")).lower()))

    # Check database snake_case field first, then fallback to camelCase
    case_mtf = case.get("minimal_trauma_fracture") if case.get("minimal_trauma_fracture") is not None else case.get(
        "minimalTraumaFracture")
    if case_mtf is not None:
        if isinstance(case_mtf, bool):
            put("minimalTraumaFracture", case_mtf)
        else:
            put("minimalTraumaFracture", YES_NO.get(str(case_mtf).lower()))

    # Fracture site verification
    excluded = YES_NO.get(str(answers.get("excludedFractureSite") or "").lower())
    if excluded is not None:
        facts["fractureSite"] = (
            "hand, foot or face (patient-reported)"
            if excluded
            else "eligible site (patient-reported)"
        )

    # 3. Investigation Results
    t_score = investigation.get("t_score")
    if t_score is not None:
        try:
            facts["T_score"] = float(t_score)
            facts["testAvailable"] = True
        except (ValueError, TypeError):
            pass

    if investigation.get("test_date"):
        try:
            test_date = date.fromisoformat(str(investigation["test_date"]))
            facts["testWithinLast2Years"] = _years_between(test_date, today) < 2
        except (ValueError, TypeError):
            pass

    # 4. Clinician Facts (Stored under alias names, rename via FIELD_BY_NAME mapping)
    clinician_dict = case.get("clinician_facts") or {}
    if isinstance(clinician_dict, dict):
        for key, value in clinician_dict.items():
            put(FIELD_BY_NAME.get(key, key), value)

    return facts


def load_case(client: Any, case_id: str) -> Optional[Dict[str, Any]]:
    """Read a case directly from base Supabase tables without requiring a SQL view."""
    # Read primary case
    res = client.table("clinical_cases").select("*").eq("id", case_id).limit(1).execute()
    if not res.data:
        return None
    case = res.data[0]

    profile: Optional[Dict[str, Any]] = None
    answers: Optional[Dict[str, Any]] = None
    investigation: Optional[Dict[str, Any]] = None

    # Read profile
    if case.get("patient_id"):
        prof_res = (
            client.table("profiles")
            .select("gender, date_of_birth")
            .eq("id", case["patient_id"])
            .limit(1)
            .execute()
        )
        if prof_res.data:
            profile = prof_res.data[0]

    # Read questionnaire response
    if case.get("questionnaire_response_id"):
        ans_res = (
            client.table("questionnaire_responses")
            .select("answers")
            .eq("id", case["questionnaire_response_id"])
            .limit(1)
            .execute()
        )
        if ans_res.data:
            answers = ans_res.data[0].get("answers")

    # Read latest investigation by revision and updated_at
    inv_res = (
        client.table("investigations")
        .select("t_score, test_date")
        .eq("case_id", case_id)
        .order("revision", desc=True)
        .order("updated_at", desc=True)
        .limit(1)
        .execute()
    )
    if inv_res.data:
        investigation = inv_res.data[0]

    merged_facts = case_facts(case, profile, answers, investigation)
    return {
        "patient_id": case.get("patient_id"),
        "facts": merged_facts,
    }


def recommend(
        facts: Facts,
        model: TreatmentModel,
        case_id: Optional[str] = None,
        patient_id: Optional[str] = None,
) -> Recommendation:
    facts, assumptions = fill_gaps(facts)
    result = evaluate(facts)
    decision, title, detail = ENDPOINTS[result.endpoint]
    opinion = model.opinion(facts, result.endpoint)

    reasons = ["All recommendations require clinician review before release."]
    if assumptions:
        reasons.append("Some facts were assumed; confirm them before acting (see assumptions).")
    if facts.sequencingFromDenosumab and result.endpoint in ANABOLIC:
        reasons.append(
            "Switching from denosumab: plan the transition, as stopping denosumab without "
            "follow-on therapy causes rebound bone loss."
        )
    if opinion:
        if opinion.get("safety_override"):
            reasons.append(f"Model safety override: {opinion['safety_override']}")
        if not opinion.get("agrees_with_guideline"):
            reasons.append(f"Model predicted {opinion['endpoint']} (confidence {opinion['confidence']:.2f}).")
        elif opinion.get("confidence", 1.0) < get_settings().confidence_floor:
            reasons.append(f"Model confidence {opinion['confidence']:.2f} is below the review floor.")

    return Recommendation(
        case_id=case_id,
        patient_id=patient_id,
        evaluated_at=datetime.now(timezone.utc),
        guideline_version=GUIDELINE_VERSION,
        endpoint=result.endpoint,
        decision=decision,
        title=title,
        detail=detail,
        missing_inputs=result.missing,
        assumptions=assumptions,
        trace=[TraceStep(rule_id=r, question=q, answer=a) for r, q, a in result.trace],
        model_opinion=opinion,
        review_reasons=reasons,
    )


@router.get("/cases/{case_id}/recommendation", response_model=Recommendation)
def recommend_for_case(
        case_id: str,
        client: Any = Depends(require_supabase),
        model: TreatmentModel = Depends(get_model),
) -> Recommendation:
    try:
        row = load_case(client, case_id)
    except Exception as exc:
        logger.exception("Case lookup failed for %s: %s", case_id, exc)
        raise HTTPException(status_code=502, detail=f"Could not load the case: {exc}")

    if row is None:
        raise HTTPException(status_code=404, detail=f"Case {case_id} not found.")

    try:
        facts = Facts.model_validate(row["facts"])
    except ValidationError as exc:
        raise HTTPException(status_code=422, detail=exc.errors(include_url=False))

    return recommend(facts, model, case_id, row["patient_id"])


@router.post("/recommendations", response_model=Recommendation)
def recommend_from_facts(
        facts: Facts,
        model: TreatmentModel = Depends(get_model),
) -> Recommendation:
    return recommend(facts, model)