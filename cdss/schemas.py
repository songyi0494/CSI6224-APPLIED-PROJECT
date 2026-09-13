from datetime import datetime, timezone
from enum import Enum
from typing import Any, Dict, List, Optional
from pydantic import BaseModel, Field, model_validator


class BiologicalSex(str, Enum):
    FEMALE = "female"
    MALE = "male"


class PriorTreatmentStatus(str, Enum):
    NAIVE = "treatment_naive"
    PREVIOUS = "previous_treatment"


class ActionClassification(str, Enum):
    INITIATE_THERAPY = "INITIATE_THERAPY"
    INITIATE_DENOSUMAB = "INITIATE_DENOSUMAB"
    ESCALATE_ANABOLIC = "ESCALATE_ANABOLIC"
    MAINTAIN_ANTIRESORPTIVE = "MAINTAIN_ANTIRESORPTIVE"
    SPECIALIST_REFERRAL = "SPECIALIST_REFERRAL"
    MONITOR = "MONITOR"
    NO_DECISION = "NO_DECISION"


class PatientClinicalInput(BaseModel):
    response_id: str = Field(default_factory=lambda: "eval-transient")
    age: int = Field(..., ge=18, le=120)
    sex: BiologicalSex
    postmenopausal: bool = False
    treatment_status: PriorTreatmentStatus = PriorTreatmentStatus.NAIVE

    # Renal laboratory marker: preserve eGFR per Task J4 (no Cockcroft-Gault substitution)
    egfr: Optional[float] = Field(None, ge=0.0, le=200.0)
    crcl_ml_min: Optional[float] = Field(None, ge=0.0, le=200.0)

    # Fracture and physical markers
    minimal_trauma_fracture: bool = True
    fracture_site: Optional[str] = None
    is_hip_or_vertebral_fracture: bool = False
    fractures_in_last_24_months: int = Field(0, ge=0)

    # Frailty and care (FSFHG Pathway 1 Branch A)
    lives_in_racf: bool = False
    clinical_frailty_score: int = Field(1, ge=1, le=9)
    life_expectancy_years: Optional[float] = Field(10.0, ge=0.0)

    # Adherence & Cognitive (FSFHG Pathway 1 Branch B)
    adherence_or_cognitive_concerns: bool = False

    # DXA bone mineral density
    t_score_lowest: Optional[float] = Field(None, ge=-6.0, le=2.0)
    dxa_impractical: bool = False

    # Pathway 2 cascade parameters
    on_antiresorptive_gt_12_months: bool = False
    patient_adherent: bool = True
    symptomatic_fracture_in_last_12_months: bool = False
    total_lifetime_fractures: int = Field(0, ge=0)
    history_of_mi_or_stroke: bool = False
    sequencing_from_denosumab: bool = False

    @model_validator(mode="before")
    @classmethod
    def resolve_renal_parameters(cls, values: Any) -> Any:
        if isinstance(values, dict):
            egfr_val = values.get("egfr") or values.get("eGFR")
            crcl_val = values.get("crcl_ml_min")
            if egfr_val is not None and crcl_val is None:
                values["crcl_ml_min"] = float(egfr_val)
            elif crcl_val is not None and egfr_val is None:
                values["egfr"] = float(crcl_val)
        return values


class TraceStep(BaseModel):
    rule_id: str
    rule_description: str
    condition_matched: bool
    details: str


class CDSSRecommendationOutput(BaseModel):
    recommendation_id: str
    response_id: str
    pathway_evaluated: str
    action_type: ActionClassification
    recommendation_text: str
    safety_fallback: bool
    requires_clinician_review: bool
    reasoning_trace: List[TraceStep]
    shadow_ml_metrics: Optional[Dict[str, Any]] = None
    evaluated_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))