"""
Clinical schemas enforcing CDSS-CONTRACT-SUPABASE-V2.2.
Strictly defines the 17-field Pathway 1 input payload, Pathway 2 criteria,
and the immutable 4-key evaluation response envelope.
"""

from typing import List, Optional, Literal, Dict, Any
from pydantic import BaseModel, Field, field_validator


class ClinicalAction(BaseModel):
    type: Literal["treatment", "consideration", "referral", "notice"]
    recommendation: str
    requireReview: bool = True


class EvaluationEnvelope(BaseModel):
    pathway: Literal["PATHWAY1", "PATHWAY2"]
    decision: Literal["action_taken", "require_review", "specialist_referral"]
    actions: List[ClinicalAction]
    trace: List[str]


class Pathway1Facts(BaseModel):
    osteoporosisTreatmentStatus: bool = Field(
        default=False, 
        description="false = Pathway 1 (Naïve); true = Pathway 2 (Pre-Treated)"
    )
    minimalTraumaFracture: bool = Field(
        ..., 
        description="Fall from standing height or less resulting in fracture"
    )
    sex: Literal["female", "male"]
    postmenopausal: bool = Field(
        default=False, 
        description="Must accept native boolean or boolean-string coercion"
    )
    age: int = Field(..., ge=18, le=120)
    fractureSite: Optional[str] = Field(
        default=None, 
        description="Hip, vertebral, wrist, etc. Non-osteoporotic sites excluded"
    )
    eGFR: Optional[float] = Field(default=None, ge=0.0, le=200.0)
    liveInResidentialCare: bool = False
    clinicalFrailtyScore: int = Field(default=1, ge=1, le=9)
    lifeExpectancy: float = Field(default=10.0, ge=0.0)
    knownPoorMedicationAdherence: bool = False
    cognitiveImpairment: bool = False
    testAvailable: bool = False
    testWithinLast2Years: bool = False
    T_score: Optional[float] = Field(default=None, ge=-6.0, le=2.0, alias="T-score")
    hipVertebralOrMultipleFracturesInLast24M: bool = False
    highRisk: bool = False

    @field_validator("postmenopausal", mode="before")
    @classmethod
    def coerce_postmenopausal(cls, v: Any) -> bool:
        if isinstance(v, str):
            return v.strip().lower() in ("true", "1", "yes", "t")
        return bool(v)

    model_config = {
        "populate_by_name": True,
        "extra": "ignore"
    }


class Pathway2Facts(BaseModel):
    osteoporosisTreatmentStatus: Literal[True] = True
    onAntiresorptiveGt12m: bool
    medicationAdherent: bool
    symptomaticFractureLast12m: bool
    lifetimeFractureCount: int = Field(ge=0)
    lowestTScore: float = Field(ge=-6.0, le=2.0)
    history_mi_or_stroke: bool = Field(
        default=False, 
        description="Cardiovascular safety clearance for anabolic agents"
    )
    eGFR: Optional[float] = Field(default=None, ge=0.0, le=200.0)
    age: int = Field(..., ge=18, le=120)
    sex: Literal["female", "male"]