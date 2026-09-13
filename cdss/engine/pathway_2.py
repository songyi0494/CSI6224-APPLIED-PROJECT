from typing import Optional
from cdss.engine.base import BaseRule
from cdss.schemas import PatientClinicalInput, RuleTrace

class RuleP2TreatmentFailure(BaseRule):
    def __init__(self):
        super().__init__(
            rule_id="P2_RULE_01",
            pathway="Pathway 2 (Previously Treated)",
            priority=95,
            description="Therapy Failure: Breakthrough fracture sustained on active treatment"
        )

    def evaluate(self, p: PatientClinicalInput) -> Optional[RuleTrace]:
        if p.treatment_history.is_treatment_naive:
            return None
        if p.treatment_history.recent_fracture_on_treatment:
            return RuleTrace(
                rule_id=self.rule_id,
                pathway=self.pathway,
                condition_matched="Treatment Failure: Incident fracture sustained during active antiresorptive therapy",
                priority=self.priority
            )
        return None

class RuleP2DrugHoliday(BaseRule):
    def __init__(self):
        super().__init__(
            rule_id="P2_RULE_02",
            pathway="Pathway 2 (Previously Treated)",
            priority=70,
            description="Drug Holiday Review: Continuous bisphosphonates >= 5 years without incident fracture"
        )

    def evaluate(self, p: PatientClinicalInput) -> Optional[RuleTrace]:
        if p.treatment_history.is_treatment_naive:
            return None
        if p.treatment_history.years_on_bisphosphonates >= 5.0 and not p.treatment_history.recent_fracture_on_treatment:
            return RuleTrace(
                rule_id=self.rule_id,
                pathway=self.pathway,
                condition_matched=f"Drug Holiday Evaluation: Bisphosphonate duration >= 5 yrs ({p.treatment_history.years_on_bisphosphonates} yrs) with stable profile",
                priority=self.priority
            )
        return None