"""
FSFHG Pathways 1 and 2 as ordered rule tables.

Each rule's condition returns True, False or None (unknown). The first True
rule decides; a None stops evaluation and asks for the missing facts. Rule
order encodes the flowchart: a rule is reached only if every earlier rule
was False.
"""

import math
from dataclasses import dataclass, field
from typing import Any, Callable, Dict, List, Literal, Optional, Tuple

from pydantic import BaseModel, ConfigDict, Field, model_validator

from cdss.core.config import (ASSUME_DXA_RECENT, ASSUME_SCREENED, FRAIL_CFS, FRAX_HIGH_RISK, LIMITED_LIFE_YEARS,
                              MIN_MALE_AGE, OSTEOPOROTIC_T, RENAL_EGFR_MIN, SEVERE_T)

SITE_T_SCORES = ("hipTscore", "femoralNeckTscore", "lumbarSpineTscore")
EXCLUDED_SITE_WORDS = {"hand", "hands", "finger", "fingers", "foot", "feet", "toe", "toes",
                       "face", "facial", "ankle", "ankles"}

# Other names the same fact goes by in CSV exports and the Supabase questionnaire
ALIASES = {
    "T-score": "T_score",
    "testAvailability": "testAvailable",
    "historyOf2orMoreFractures": "twoOrMoreFractures",
    "multipleFractures": "twoOrMoreFractures",
    "antiresorptiveTreatmentStatus": "onAntiresorptiveTherapy",
    "antiresorptiveTreatmentDuration": "onAntiresorptiveGt12m",
    "adheredToTheTreatment": "medicationAdherent",
    "symptomaticFractureInLast12M": "symptomaticFractureLast12m",
    "priorMIorStroke": "historyMiOrStroke",
}


def clean(value):
    """CSV/DB cell -> plain Python value; NaN -> None, 1.0 -> 1."""
    if value is None or (isinstance(value, float) and math.isnan(value)):
        return None
    value = value.item() if hasattr(value, "item") else value
    if isinstance(value, float) and value.is_integer():
        return int(value)
    return value


def canonical(record: Dict[str, Any]) -> Dict[str, Any]:
    """Rename aliases to Facts fields and drop unknown keys. A recorded value beats a blank alias."""
    out: Dict[str, Any] = {}
    for key, value in record.items():
        name = FIELD_BY_NAME.get(key)
        value = clean(value)
        if name and (value is not None or name not in out):
            out[name] = value
    return out


class Facts(BaseModel):
    """Every field is optional: None means "not recorded" and is never defaulted."""

    model_config = ConfigDict(extra="ignore")

    osteoporosisTreatmentStatus: Optional[bool] = None
    # True when screened into the general pathway (minimal trauma fracture, eligible site,
    # postmenopausal woman or man >= 50); skips those entry gates
    entryCriteriaMet: Optional[bool] = None
    minimalTraumaFracture: Optional[bool] = None
    sex: Optional[Literal["female", "male"]] = None
    postmenopausal: Optional[bool] = None
    age: Optional[int] = Field(None, ge=18, le=120)
    fractureSite: Optional[str] = None
    eGFR: Optional[float] = Field(None, ge=0, le=200)
    liveInResidentialCare: Optional[bool] = None
    clinicalFrailtyScore: Optional[int] = Field(None, ge=1, le=9)
    lifeExpectancy: Optional[float] = Field(None, ge=0, le=120)
    knownPoorMedicationAdherence: Optional[bool] = None
    cognitiveImpairment: Optional[bool] = None
    testAvailable: Optional[bool] = None
    testWithinLast2Years: Optional[bool] = None
    T_score: Optional[float] = Field(None, ge=-6, le=2)
    hipTscore: Optional[float] = Field(None, ge=-6, le=2)
    femoralNeckTscore: Optional[float] = Field(None, ge=-6, le=2)
    lumbarSpineTscore: Optional[float] = Field(None, ge=-6, le=2)
    hipVertebralOrMultipleFracturesInLast24M: Optional[bool] = None
    highRisk: Optional[bool] = None
    FRAX10YmajorOsteoporoticFractureRiskPercent: Optional[float] = Field(None, ge=0, le=100)
    FRAX10YmajorHipFractureRiskPercent: Optional[float] = Field(None, ge=0, le=100)
    clinicalRiskFactors: Optional[bool] = None
    recentFractureWithin2Y: Optional[bool] = None
    onAntiresorptiveTherapy: Optional[bool] = None
    onAntiresorptiveGt12m: Optional[bool] = None
    medicationAdherent: Optional[bool] = None
    symptomaticFractureLast12m: Optional[bool] = None
    twoOrMoreFractures: Optional[bool] = None
    # Questionnaire answer to "T-score -3.0 or lower?"; only read when no T-score is recorded
    lowBMD: Optional[bool] = None
    historyMiOrStroke: Optional[bool] = None
    # Switching off denosumab; no rule reads it, it only adds a review note
    sequencingFromDenosumab: Optional[bool] = None

    @model_validator(mode="before")
    @classmethod
    def _resolve_aliases(cls, data):
        return canonical(data) if isinstance(data, dict) else data

    @model_validator(mode="after")
    def _lowest_t_score(self):
        # FSFHG uses the lowest T-score of femoral neck, total hip and lumbar spine
        sites = [getattr(self, s) for s in SITE_T_SCORES if getattr(self, s) is not None]
        if self.T_score is None and sites:
            self.T_score = min(sites)
        return self


FIELD_BY_NAME: Dict[str, str] = {**{n: n for n in Facts.model_fields}, **ALIASES}


def fill_gaps(f: Facts, screened: bool = ASSUME_SCREENED, dxa_recent: bool = ASSUME_DXA_RECENT,
              frax_high_risk: Optional[Tuple[float, float]] = FRAX_HIGH_RISK) -> Tuple[Facts, List[str]]:
    """Fill facts the questionnaire never asks. Only blanks are filled; returns what was assumed."""
    update: Dict[str, Any] = {}
    notes: List[str] = []
    # Treated patients go to Pathway 2, which has no entry gates
    if screened and f.entryCriteriaMet is None and f.osteoporosisTreatmentStatus is not True:
        update["entryCriteriaMet"] = True
        notes.append("Assumed screened into the general pathway: minimal trauma fracture at an eligible site, "
                     "postmenopausal woman or man aged 50 or over.")
    if dxa_recent and f.testWithinLast2Years is None and f.T_score is not None:
        update["testWithinLast2Years"] = True
        notes.append("Assumed the recorded T-scores come from a DXA within the last 2 years.")
    mof, hip = f.FRAX10YmajorOsteoporoticFractureRiskPercent, f.FRAX10YmajorHipFractureRiskPercent
    if frax_high_risk and f.highRisk is None and (mof is not None or hip is not None):
        update["highRisk"] = (mof is not None and mof >= frax_high_risk[0]) or \
                             (hip is not None and hip >= frax_high_risk[1])
        notes.append(f"Very high risk {'set' if update['highRisk'] else 'ruled out'} from FRAX "
                     f"(major osteoporotic {mof}%, hip {hip}%) against {frax_high_risk[0]:g}% / {frax_high_risk[1]:g}%.")
    return f.model_copy(update=update), notes


def excluded_site(site: Optional[str]) -> Optional[bool]:
    if site is None:
        return None
    return any(w in EXCLUDED_SITE_WORDS for w in site.lower().replace("/", " ").replace("-", " ").split())


Tri = Optional[bool]


def lt(x, t) -> Tri:
    return None if x is None else x < t


def gt(x, t) -> Tri:
    return None if x is None else x > t


def ge(x, t) -> Tri:
    return None if x is None else x >= t


def le(x, t) -> Tri:
    return None if x is None else x <= t


def no(x) -> Tri:
    return None if x is None else not x


def any_of(*values: Tri) -> Tri:
    """Kleene OR: one known True decides even when the others are unknown."""
    if any(v is True for v in values):
        return True
    return None if any(v is None for v in values) else False


@dataclass(frozen=True)
class Rule:
    id: str
    question: str
    when: Callable[[Facts], Tri]
    then: Optional[str]
    needs: Tuple[str, ...]


@dataclass
class Result:
    endpoint: str
    rule_id: str
    missing: List[str] = field(default_factory=list)
    trace: List[Tuple[str, str, str]] = field(default_factory=list)

    @property
    def decision(self) -> str:
        return ENDPOINTS[self.endpoint][0]


def screened(cond: Callable[[Facts], Tri]) -> Callable[[Facts], Tri]:
    """Entry gate that passes when the patient is recorded as screened into the pathway."""
    return lambda f: False if f.entryCriteriaMet else cond(f)


def t_above_severe(f: Facts) -> Tri:
    return gt(f.T_score, SEVERE_T) if f.T_score is not None else no(f.lowBMD)


RENAL = Rule("G_RENAL", f"eGFR < {RENAL_EGFR_MIN:.0f}?", lambda f: lt(f.eGFR, RENAL_EGFR_MIN),
             "SPECIALIST_RENAL", ("eGFR",))

PATHWAY_1 = [
    Rule("G_MTF", "No minimal trauma fracture?", screened(lambda f: no(f.minimalTraumaFracture)),
         "NOT_ELIGIBLE_NO_MINIMAL_TRAUMA", ("minimalTraumaFracture",)),
    Rule("G_SITE", "Excluded fracture site?", screened(lambda f: excluded_site(f.fractureSite)),
         "NOT_ELIGIBLE_EXCLUDED_SITE", ("fractureSite",)),
    Rule("G_SEX", "Sex not recorded?", screened(lambda f: None if f.sex is None else False), None, ("sex",)),
    Rule("G_PREMENOPAUSAL", "Premenopausal woman?",
         screened(lambda f: no(f.postmenopausal) if f.sex == "female" else False),
         "SPECIALIST_OUT_OF_SCOPE", ("postmenopausal",)),
    Rule("G_YOUNG_MALE", f"Man under {MIN_MALE_AGE}?",
         screened(lambda f: lt(f.age, MIN_MALE_AGE) if f.sex == "male" else False),
         "SPECIALIST_OUT_OF_SCOPE", ("age",)),
    RENAL,
    Rule("P1_BRANCH_A", "Residential care, frailty score ≥ 6 or life expectancy < 7 years?",
         lambda f: any_of(f.liveInResidentialCare, ge(f.clinicalFrailtyScore, FRAIL_CFS),
                          lt(f.lifeExpectancy, LIMITED_LIFE_YEARS)),
         "P1_DENOSUMAB_FRAILTY", ("liveInResidentialCare", "clinicalFrailtyScore", "lifeExpectancy")),
    Rule("P1_BRANCH_B", "Poor adherence or cognitive impairment?",
         lambda f: any_of(f.knownPoorMedicationAdherence, f.cognitiveImpairment),
         "P1_ZOLEDRONIC_ACID_ADHERENCE", ("knownPoorMedicationAdherence", "cognitiveImpairment")),
    Rule("P1_DXA_IMPRACTICAL", "DXA impractical?", lambda f: no(f.testAvailable),
         "P1_STANDARD_ANTIRESORPTIVE", ("testAvailable",)),
    Rule("P1_DXA_STALE", "No DXA within 2 years?", lambda f: no(f.testWithinLast2Years),
         "P1_DXA_REFERRAL", ("testWithinLast2Years",)),
    Rule("P1_T_ABOVE", "T-score above −2.5?", lambda f: gt(f.T_score, OSTEOPOROTIC_T),
         "P1_STANDARD_ANTIRESORPTIVE", ("T_score",)),
    Rule("P1_MAJOR_FRACTURE", "Hip, vertebral or ≥ 2 fractures in 24 months?",
         lambda f: f.hipVertebralOrMultipleFracturesInLast24M,
         "P1_OSTEOANABOLIC_SPECIALIST", ("hipVertebralOrMultipleFracturesInLast24M",)),
    Rule("P1_VERY_HIGH_RISK", "T-score ≤ −3.0 or clinician-assessed very high risk?",
         lambda f: any_of(le(f.T_score, SEVERE_T), f.highRisk),
         "P1_CONSIDER_PRIVATE_OSTEOANABOLIC", ("highRisk",)),
    Rule("P1_DEFAULT", "Otherwise", lambda f: True, "P1_STANDARD_ANTIRESORPTIVE", ()),
]

# Escalation only when every cascade answer is yes (presentation slides 15-16)
PATHWAY_2 = [
    RENAL,
    Rule("P2_Q1", "Not on antiresorptive therapy?", lambda f: no(f.onAntiresorptiveTherapy),
         "P2_CONTINUE_ANTIRESORPTIVE", ("onAntiresorptiveTherapy",)),
    Rule("P2_Q2", "On therapy ≤ 12 months?", lambda f: no(f.onAntiresorptiveGt12m),
         "P2_CONTINUE_ANTIRESORPTIVE", ("onAntiresorptiveGt12m",)),
    Rule("P2_Q3", "Not adherent?", lambda f: no(f.medicationAdherent),
         "P2_CONTINUE_ANTIRESORPTIVE", ("medicationAdherent",)),
    Rule("P2_Q4", "No symptomatic fracture in 12 months?", lambda f: no(f.symptomaticFractureLast12m),
         "P2_CONTINUE_ANTIRESORPTIVE", ("symptomaticFractureLast12m",)),
    Rule("P2_Q5", "Fewer than 2 fractures?", lambda f: no(f.twoOrMoreFractures),
         "P2_CONTINUE_ANTIRESORPTIVE", ("twoOrMoreFractures",)),
    Rule("P2_Q6", "T-score above −3.0?", t_above_severe,
         "P2_CONTINUE_ANTIRESORPTIVE", ("T_score", "lowBMD")),
    Rule("P2_Q7", "History of MI or stroke?", lambda f: f.historyMiOrStroke,
         "P2_TERIPARATIDE", ("historyMiOrStroke",)),
    Rule("P2_DEFAULT", "Otherwise", lambda f: True, "P2_ROMOSOZUMAB", ()),
]

ENDPOINTS = {
    "NEEDS_MORE_INFORMATION": ("needs_more_information", "More information required",
                               "Record the missing facts and re-run the evaluation."),
    "NOT_ELIGIBLE_NO_MINIMAL_TRAUMA": ("not_eligible", "Not eligible: no minimal trauma fracture",
                                       "The pathway covers fractures from a fall from standing height or less."),
    "NOT_ELIGIBLE_EXCLUDED_SITE": ("not_eligible", "Not eligible: excluded fracture site",
                                   "Hand, foot, face and ankle fractures are excluded."),
    "SPECIALIST_OUT_OF_SCOPE": ("specialist_referral", "Refer: outside the general pathway",
                                "Premenopausal women and men under 50 need assessment for secondary causes."),
    "SPECIALIST_RENAL": ("specialist_referral", "Refer: renal precaution",
                         "eGFR below 35: zoledronic acid and oral bisphosphonates are contraindicated. "
                         "Exclude CKD-mineral bone disorder before denosumab."),
    "SPECIALIST_SAFETY_REVIEW": ("specialist_referral", "Refer: safety review",
                                 "The model guardrail could not clear the suggested drug."),
    "P1_DENOSUMAB_FRAILTY": ("treatment_recommended", "Denosumab 60 mg SC every 6 months",
                             "Frailty, residential care or limited life expectancy; no BMD required. "
                             "Do not stop without a sequencing plan."),
    "P1_ZOLEDRONIC_ACID_ADHERENCE": ("treatment_recommended", "Zoledronic acid 5 mg IV yearly for 3 years",
                                     "Adherence concern: prefer clinician-administered therapy."),
    "P1_STANDARD_ANTIRESORPTIVE": ("treatment_recommended", "PBS-funded antiresorptive",
                                   "Zoledronic acid 5 mg IV yearly, risedronate EC 35 mg weekly, "
                                   "or denosumab 60 mg SC 6-monthly. Review at 5 years."),
    "P1_DXA_REFERRAL": ("investigation_required", "Refer for DXA scan",
                        "No DXA within 2 years. Re-run the evaluation with the result."),
    "P1_OSTEOANABOLIC_SPECIALIST": ("specialist_referral", "Osteoanabolic first: refer to fragile bone clinic",
                                    "T-score ≤ −2.5 with hip, vertebral or ≥ 2 fractures in 24 months. "
                                    "Romosozumab (confirm no MI or stroke) or teriparatide."),
    "P1_CONSIDER_PRIVATE_OSTEOANABOLIC": ("treatment_recommended", "Consider private osteoanabolic therapy",
                                          "Very high risk without PBS anabolic criteria. "
                                          "If not pursued, start a PBS-funded antiresorptive."),
    "P2_CONTINUE_ANTIRESORPTIVE": ("treatment_recommended", "Continue antiresorptive, preferably parenteral",
                                   "Escalation criteria not met. Address adherence; reassess at 5 years."),
    "P2_TERIPARATIDE": ("specialist_referral", "Teriparatide 20 µg SC daily for 18–24 months",
                        "Escalation criteria met with MI or stroke history. Specialist review."),
    "P2_ROMOSOZUMAB": ("specialist_referral", "Romosozumab 210 mg SC monthly for 12 months",
                       "Escalation criteria met, no MI or stroke. Specialist review."),
}

ZOLEDRONIC_FIRST = {"P1_ZOLEDRONIC_ACID_ADHERENCE", "P1_STANDARD_ANTIRESORPTIVE",
                    "P1_CONSIDER_PRIVATE_OSTEOANABOLIC", "P2_CONTINUE_ANTIRESORPTIVE"}
ROMOSOZUMAB_FIRST = {"P1_OSTEOANABOLIC_SPECIALIST", "P2_ROMOSOZUMAB"}
ANABOLIC = {"P1_OSTEOANABOLIC_SPECIALIST", "P2_ROMOSOZUMAB", "P2_TERIPARATIDE"}
ANTIRESORPTIVE_ONLY = {"P1_DENOSUMAB_FRAILTY", "P1_ZOLEDRONIC_ACID_ADHERENCE",
                       "P1_STANDARD_ANTIRESORPTIVE", "P2_CONTINUE_ANTIRESORPTIVE"}


def _answer(value: Tri) -> str:
    return {True: "yes", False: "no", None: "unknown"}[value]


def _walk(rules: List[Rule], f: Facts, trace: List[Tuple[str, str, str]]) -> Result:
    for rule in rules:
        value = rule.when(f)
        trace.append((rule.id, rule.question, _answer(value)))
        if value is None:
            missing = [n for n in rule.needs if getattr(f, n) is None]
            return Result("NEEDS_MORE_INFORMATION", rule.id, missing, trace)
        if value and rule.then:
            return Result(rule.then, rule.id, [], trace)
    raise AssertionError("Rule tables end with a default rule")


def evaluate(f: Facts) -> Result:
    trace: List[Tuple[str, str, str]] = []
    treated = f.osteoporosisTreatmentStatus
    trace.append(("G_ROUTING", "Already on osteoporosis treatment?", _answer(treated)))
    if treated is not None:
        return _walk(PATHWAY_2 if treated else PATHWAY_1, f, trace)

    # Unknown treatment status still decides when both pathways land on the same endpoint
    # (in practice the renal gate, which both pathways reach first once entry is screened)
    p1, p2 = _walk(PATHWAY_1, f, []), _walk(PATHWAY_2, f, [])
    if p1.endpoint == p2.endpoint != "NEEDS_MORE_INFORMATION":
        return Result(p1.endpoint, p1.rule_id, [], trace + p1.trace)
    return Result("NEEDS_MORE_INFORMATION", "G_ROUTING", ["osteoporosisTreatmentStatus"], trace)
