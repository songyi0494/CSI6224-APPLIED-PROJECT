import uuid
from typing import Optional
from cdss.engine.pathway_1 import evaluate_pathway_1_rules
from cdss.engine.pathway_2 import evaluate_pathway_2_rules
from cdss.schemas import (
    ActionClassification,
    CDSSRecommendationOutput,
    PatientClinicalInput,
    PriorTreatmentStatus,
    TraceStep,
)


class FSFHGPipeline:
    """Primary deterministic rule engine orchestrator for FSFHG Osteoporosis Management Pathways."""

    def evaluate(self, patient: PatientClinicalInput) -> CDSSRecommendationOutput:
        trace: list[TraceStep] = []
        rec_id = str(uuid.uuid4())

        # -------------------------------------------------------------
        # 1. Global Renal Safety Check (eGFR < 30 mL/min)
        # -------------------------------------------------------------
        effective_egfr: Optional[float] = patient.egfr if patient.egfr is not None else patient.crcl_ml_min

        # Guard against claiming safety when renal data is omitted
        if effective_egfr is None:
            trace.append(
                TraceStep(
                    rule_id="RENAL_DATA_MISSING_FALLBACK",
                    rule_description="Audit check for renal biomarker availability",
                    condition_matched=True,
                    details="Renal function (eGFR) not provided. Cannot verify antiresorptive safety.",
                )
            )
            return CDSSRecommendationOutput(
                recommendation_id=rec_id,
                response_id=patient.response_id,
                pathway_evaluated="Safety Pre-Check (Missing Renal Data)",
                action_type=ActionClassification.NO_DECISION,
                recommendation_text="Baseline renal labs (UEC / eGFR) missing. Obtain bloods before initiating antiresorptive therapy.",
                safety_fallback=True,
                requires_clinician_review=True,
                reasoning_trace=trace,
            )

        if effective_egfr < 30.0:
            trace.append(
                TraceStep(
                    rule_id="RENAL_DYSFUNCTION_IDENTIFIED",
                    rule_description="Renal function gatekeeper (eGFR < 30 mL/min)",
                    condition_matched=True,
                    details=f"eGFR is {effective_egfr} mL/min (< 30). High risk of severe hypocalcaemia with antiresorptives.",
                )
            )
            return CDSSRecommendationOutput(
                recommendation_id=rec_id,
                response_id=patient.response_id,
                pathway_evaluated="Cross-Pathway Safety & Specialist Referral",
                action_type=ActionClassification.SPECIALIST_REFERRAL,
                recommendation_text="eGFR < 30 mL/min: Antiresorptive therapy carries a high hypocalcaemia risk. Seek specialist/nephrologist guidance. Avoid denosumab if pre-existing hypocalcaemia, malabsorption, or recent iron infusion.",
                safety_fallback=False,
                requires_clinician_review=True,
                reasoning_trace=trace,
            )

        trace.append(
            TraceStep(
                rule_id="RENAL_ADEQUATE",
                rule_description="Renal function gatekeeper (eGFR >= 30 mL/min)",
                condition_matched=False,
                details=f"eGFR {effective_egfr} mL/min is adequate for routine treatment pathways.",
            )
        )

        # -------------------------------------------------------------
        # 2. Pathway Routing
        # -------------------------------------------------------------
        if patient.treatment_status == PriorTreatmentStatus.NAIVE:
            action, text, fallback, review = evaluate_pathway_1_rules(patient, trace)
            return CDSSRecommendationOutput(
                recommendation_id=rec_id,
                response_id=patient.response_id,
                pathway_evaluated="FSFHG Pathway 1 (Treatment-Naïve)",
                action_type=action,
                recommendation_text=text,
                safety_fallback=fallback,
                requires_clinician_review=review,
                reasoning_trace=trace,
            )

        if patient.treatment_status == PriorTreatmentStatus.PREVIOUS:
            action, text, fallback, review = evaluate_pathway_2_rules(patient, trace)
            return CDSSRecommendationOutput(
                recommendation_id=rec_id,
                response_id=patient.response_id,
                pathway_evaluated="FSFHG Pathway 2 (Pre-Treated Subsequent Fracture)",
                action_type=action,
                recommendation_text=text,
                safety_fallback=fallback,
                requires_clinician_review=review,
                reasoning_trace=trace,
            )

        # Default Catch-all
        return CDSSRecommendationOutput(
            recommendation_id=rec_id,
            response_id=patient.response_id,
            pathway_evaluated="Unmapped Pathway",
            action_type=ActionClassification.NO_DECISION,
            recommendation_text="Case parameters outside established decision boundaries. Direct to clinician review.",
            safety_fallback=True,
            requires_clinician_review=True,
            reasoning_trace=trace,
        )