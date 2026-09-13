from typing import Optional
from cdss.engine.base import BaseRule
from cdss.schemas import PatientClinicalInput, RuleTrace

class RuleP1SafetyContraindication(BaseRule):
    def __init__(self):
        super().__init__(
            rule_id="P1_RULE_01",
            pathway="Pathway 1 (Treatment-Naïve)",
            priority=100,
            description="Safety Gate: Renal compromise (CrCl < 35) or Hypocalcemia"
        )

    def evaluate(self, p: PatientClinicalInput) -> Optional[RuleTrace]:
        if not p.treatment_history.is_treatment_naive:
            return None
        if (p.crcl_ml_min is not None and p.crcl_ml_min < 35.0) or p.hypocalcemia:
            return RuleTrace(
                rule_id=self.rule_id,
                pathway=self.pathway,
                condition_matched=f"Contraindication: CrCl={p.crcl_ml_min} mL/min (<35) or Hypocalcemia={p.hypocalcemia}",
                priority=self.priority
            )
        return None

class RuleP1VeryHighRisk(BaseRule):
    def __init__(self):
        super().__init__(
            rule_id="P1_RULE_02",
            pathway="Pathway 1 (Treatment-Naïve)",
            priority=80,
            description="Very High/Imminent Risk: Recent hip/spine fracture or T-score <= -3.0"
        )

    def evaluate(self, p: PatientClinicalInput) -> Optional[RuleTrace]:
        if not p.treatment_history.is_treatment_naive:
            return None

        t_scores = [p.bmd.femoral_neck_t_score, p.bmd.lumbar_spine_t_score, p.bmd.total_hip_t_score]
        lowest_t = min((t for t in t_scores if t is not None), default=0.0)

        is_critical_fx = (
            p.fracture_history.has_minimal_trauma_fracture and 
            p.fracture_history.fracture_site in ["vertebral", "hip"] and
            p.fracture_history.recent_fracture_within_12m
        )

        if is_critical_fx or lowest_t <= -3.0:
            return RuleTrace(
                rule_id=self.rule_id,
                pathway=self.pathway,
                condition_matched=f"Imminent Risk: Critical Fracture ({p.fracture_history.fracture_site}) within 12m or T-Score <= -3.0 (Lowest: {lowest_t})",
                priority=self.priority
            )
        return None

class RuleP1StandardOsteoporosis(BaseRule):
    def __init__(self):
        super().__init__(
            rule_id="P1_RULE_03",
            pathway="Pathway 1 (Treatment-Naïve)",
            priority=60,
            description="Standard Osteoporosis: T-score <= -2.5 or documented fragility fracture"
        )

    def evaluate(self, p: PatientClinicalInput) -> Optional[RuleTrace]:
        if not p.treatment_history.is_treatment_naive:
            return None

        t_scores = [p.bmd.femoral_neck_t_score, p.bmd.lumbar_spine_t_score, p.bmd.total_hip_t_score]
        has_low_bmd = any(t <= -2.5 for t in t_scores if t is not None)

        if has_low_bmd or p.fracture_history.has_minimal_trauma_fracture:
            return RuleTrace(
                rule_id=self.rule_id,
                pathway=self.pathway,
                condition_matched="Standard Osteoporosis: T-score <= -2.5 or prior minimal trauma fracture confirmed",
                priority=self.priority
            )
        return None