from typing import Any, Dict, List
from cdss.schemas import (
    BiologicalSex,
    CDSSRecommendationOutput,
    PatientClinicalInput,
    PriorTreatmentStatus,
)


class PathwayCompatibilityAdapter:
    """Non-blocking adapter bridging the frozen Flutter contract and the Python CDSS engine."""

    @staticmethod
    def _coerce_bool(val: Any) -> bool:
        if isinstance(val, bool):
            return val
        if isinstance(val, str):
            return val.strip().lower() in ("true", "1", "yes")
        if isinstance(val, (int, float)):
            return val == 1
        return False

    @classmethod
    def flutter_facts_to_patient_input(cls, facts: Dict[str, Any]) -> PatientClinicalInput:
        facts = facts or {}

        # Demographics & Menopause
        age = int(facts.get("age", 65)) if facts.get("age") is not None else 65
        sex_str = str(facts.get("sex", "female")).strip().lower()
        sex = BiologicalSex.FEMALE if sex_str != "male" else BiologicalSex.MALE
        postmenopausal = cls._coerce_bool(facts.get("postmenopausal", False))

        # Treatment status
        is_treated = cls._coerce_bool(facts.get("osteoporosisTreatmentStatus", False))
        treatment_status = PriorTreatmentStatus.PREVIOUS if is_treated else PriorTreatmentStatus.NAIVE

        # Renal function: strictly preserve eGFR per Task J4
        raw_egfr = facts.get("eGFR")
        egfr = float(raw_egfr) if raw_egfr is not None else None

        # Fracture markers
        minimal_trauma = cls._coerce_bool(facts.get("minimalTraumaFracture", True))
        fracture_site = facts.get("fractureSite")
        recent_major_fx = cls._coerce_bool(facts.get("hipVertebralOrMultipleFracturesInLast24M", False))

        # Frailty & Care
        lives_in_racf = cls._coerce_bool(facts.get("liveInResidentialCare", False))
        cfs = int(facts.get("clinicalFrailtyScore", 1)) if facts.get("clinicalFrailtyScore") is not None else 1
        life_exp = float(facts.get("lifeExpectancy", 10.0)) if facts.get("lifeExpectancy") is not None else 10.0

        # Adherence / Cognitive
        adherence_issues = (
            cls._coerce_bool(facts.get("knownPoorMedicationAdherence", False))
            or cls._coerce_bool(facts.get("cognitiveImpairment", False))
        )

        # DXA
        t_score = facts.get("T-score")
        t_score_lowest = float(t_score) if t_score is not None else None
        test_available = cls._coerce_bool(facts.get("testAvailable", True))
        test_recent = cls._coerce_bool(facts.get("testWithinLast2Years", True))
        dxa_impractical = not (test_available and test_recent)

        return PatientClinicalInput(
            age=age,
            sex=sex,
            postmenopausal=postmenopausal,
            treatment_status=treatment_status,
            egfr=egfr,
            minimal_trauma_fracture=minimal_trauma,
            fracture_site=fracture_site,
            is_hip_or_vertebral_fracture=recent_major_fx or str(fracture_site).lower() in ["hip", "spine"],
            fractures_in_last_24_months=2 if recent_major_fx else 0,
            lives_in_racf=lives_in_racf,
            clinical_frailty_score=cfs,
            life_expectancy_years=life_exp,
            adherence_or_cognitive_concerns=adherence_issues,
            t_score_lowest=t_score_lowest,
            dxa_impractical=dxa_impractical,
        )

    @classmethod
    def cdss_output_to_flutter_envelope(cls, output: CDSSRecommendationOutput) -> Dict[str, Any]:
        """Translates domain output into the exact 4-key Flutter JSON envelope."""
        pathway_str = output.pathway_evaluated
        pathway = "PATHWAY2" if "Pathway 2" in pathway_str else "PATHWAY1"

        action_type = output.action_type.value
        safety_fallback = output.safety_fallback

        if safety_fallback:
            decision = "require_review"
            rec_type = "notice"
        elif action_type == "SPECIALIST_REFERRAL":
            decision = "specialist_referral"
            rec_type = "referral"
        elif "ANABOLIC" in action_type:
            decision = "action_taken"
            rec_type = "consideration"
        else:
            decision = "action_taken"
            rec_type = "treatment"

        trace_ids: List[str] = []
        for step in output.reasoning_trace:
            if step.condition_matched and step.rule_id not in trace_ids:
                trace_ids.append(step.rule_id)

        return {
            "pathway": pathway,
            "decision": decision,
            "actions": [
                {
                    "type": rec_type,
                    "recommendation": output.recommendation_text,
                    "requireReview": output.requires_clinician_review or safety_fallback,
                }
            ],
            "trace": trace_ids,
        }

    @classmethod
    def safe_error_fallback(cls, error_msg: str) -> Dict[str, Any]:
        """Non-blocking emergency fallback ensuring Flutter never receives an unhandled 500 error."""
        return {
            "pathway": "PATHWAY1",
            "decision": "require_review",
            "actions": [
                {
                    "type": "notice",
                    "recommendation": f"Evaluation deferred: {error_msg}. Directing case to clinician review.",
                    "requireReview": True,
                }
            ],
            "trace": ["EVALUATION_ERROR_FALLBACK"],
        }