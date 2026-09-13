from datetime import datetime
from enum import Enum
from typing import Any, Dict, List, Optional
from pydantic import BaseModel, Field

class PriorTreatmentStatus(str, Enum):
    NAIVE = "treatment_naive"
    PREVIOUS = "previous_treatment"

class ClinicalInputPayload(BaseModel):
    response_id: str
    age: int = Field(..., ge=18, le=120)
    treatment_status: PriorTreatmentStatus
    egfr: Optional[float] = Field(None, ge=0.0, le=150.0)
    
    # Pathway 1 specific attributes
    minimal_trauma_fracture: bool = True
    lives_in_racf: bool = False
    clinical_frailty_score_gte_6: bool = False
    life_expectancy_lt_7yrs: bool = False
    adherence_or_cognitive_concerns: bool = False
    t_score_lowest: Optional[float] = Field(None, ge=-6.0, le=2.0)
    is_hip_or_vertebral_fracture: bool = False
    fractures_in_last_24_months: int = Field(0, ge=0)
    dxa_impractical: bool = False

    # Pathway 2 specific attributes
    on_antiresorptive_gt_12_months: bool = False
    patient_adherent: bool = False
    symptomatic_fracture_in_last_12_months: bool = False
    total_lifetime_fractures: int = Field(0, ge=0)
    history_of_mi_or_stroke: bool = False
    sequencing_from_denosumab: bool = False

class TraceStep(BaseModel):
    rule_id: str
    rule_description: str
    condition_matched: bool
    details: str

class DecisionResult(BaseModel):
    recommendation_id: str
    response_id: str
    pathway_evaluated: str
    recommendation_text: str
    action_type: str
    safety_fallback: bool
    reasoning_trace: List[TraceStep]
    evaluated_at: datetime