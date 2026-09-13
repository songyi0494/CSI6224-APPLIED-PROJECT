from typing import List, Optional, Literal, Dict, Any
from pydantic import BaseModel, Field

class BoneMineralDensity(BaseModel):
    femoral_neck_t_score: Optional[float] = Field(None, ge=-6.0, le=2.0)
    lumbar_spine_t_score: Optional[float] = Field(None, ge=-6.0, le=2.0)
    total_hip_t_score: Optional[float] = Field(None, ge=-6.0, le=2.0)

class FractureHistory(BaseModel):
    has_minimal_trauma_fracture: bool = False
    fracture_site: Optional[Literal["vertebral", "hip", "wrist", "other", "none"]] = "none"
    recent_fracture_within_12m: bool = False

class TreatmentHistory(BaseModel):
    is_treatment_naive: bool
    prior_antiresorptive: bool = False
    prior_anabolic: bool = False
    years_on_bisphosphonates: float = 0.0
    recent_fracture_on_treatment: bool = False
    adherence_issues: bool = False

class PatientClinicalInput(BaseModel):
    case_id: str
    age: int = Field(..., ge=18, le=120)
    gender: Literal["M", "F", "OTHER"]
    crcl_ml_min: Optional[float] = Field(None, ge=5.0, le=200.0)
    hypocalcemia: bool = False
    bmd: BoneMineralDensity
    fracture_history: FractureHistory
    treatment_history: TreatmentHistory

class RuleTrace(BaseModel):
    rule_id: str
    pathway: str
    condition_matched: str
    priority: int

class CDSSRecommendationOutput(BaseModel):
    case_id: str
    pathway: str
    action_endpoint: str
    urgency: Literal["ROUTINE", "URGENT", "CLINICIAN_REVIEW"]
    confidence_indicator: Literal["DEFINITIVE", "BORDERLINE", "INCOMPLETE_DATA"]
    requires_clinician_review: bool
    reasoning_trace: List[RuleTrace]
    clinical_rationale: str
    shadow_ml_metrics: Optional[Dict[str, Any]] = None