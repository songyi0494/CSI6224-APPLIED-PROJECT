from typing import List, Tuple
from cdss.schemas import (
    ActionClassification,
    PatientClinicalInput,
    TraceStep,
)


def evaluate_pathway_2_rules(
    patient: PatientClinicalInput, trace: List[TraceStep]
) -> Tuple[ActionClassification, str, bool, bool]:
    """
    Evaluates Pathway 2 rules: Pre-treated patients presenting with a subsequent fracture.
    Follows the 5-step PBS escalation cascade and cardiovascular safety check.
    Returns: (action_type, recommendation_text, safety_fallback, requires_clinician_review)
    """
    trace.append(
        TraceStep(
            rule_id="P2_ENTRY",
            rule_description="Entry eligibility check for Pathway 2 (Pre-Treated)",
            condition_matched=True,
            details="Patient presenting with subsequent fracture while on prior osteoporosis therapy.",
        )
    )

    # Evaluate the 5-tier escalation cascade criteria
    c1 = patient.on_antiresorptive_gt_12_months
    c2 = patient.patient_adherent
    c3 = patient.symptomatic_fracture_in_last_12_months
    c4 = patient.total_lifetime_fractures >= 2
    c5 = patient.t_score_lowest is not None and patient.t_score_lowest <= -3.0

    cascade_passed = all([c1, c2, c3, c4, c5])

    trace.append(
        TraceStep(
            rule_id="P2_CASCADE_CHECKLIST",
            rule_description="Pathway 2 Escalation Cascade Checklist",
            condition_matched=cascade_passed,
            details=f">12m Tx: {c1}, Adherent: {c2}, Symptomatic # in 12m: {c3}, Total # >= 2: {c4}, BMD <= -3.0: {c5}",
        )
    )

    # Escalation branch (All 5 criteria satisfied)
    if cascade_passed:
        if not patient.history_of_mi_or_stroke:
            deno_note = (
                " If sequencing from denosumab: start romosozumab 3 months post last denosumab dose, "
                "and consider restarting denosumab after 6th month of romosozumab."
                if patient.sequencing_from_denosumab
                else ""
            )
            return (
                ActionClassification.ESCALATE_ANABOLIC,
                f"Escalate to Romosozumab 210 mg SC monthly for 12 months. Refer to Fragile Bone Clinic.{deno_note}",
                False,
                True,
            )
        else:
            deno_note = (
                " If sequencing from denosumab: use combination therapy (teriparatide + denosumab concurrently) "
                "to prevent rebound bone loss."
                if patient.sequencing_from_denosumab
                else ""
            )
            return (
                ActionClassification.ESCALATE_ANABOLIC,
                f"Patient has prior MI or stroke (Romosozumab contraindicated). Escalate to Teriparatide 20 mcg SC daily for 18-24 months. Refer to Fragile Bone Clinic.{deno_note}",
                False,
                True,
            )

    # Non-escalation fallback: Maintain / switch parenteral antiresorptive
    return (
        ActionClassification.MAINTAIN_ANTIRESORPTIVE,
        "Criteria for osteoanabolic escalation not met. Continue antiresorptive therapy (prefer parenteral: IV Zoledronic acid 5 mg annual or Denosumab 60 mg SC 6-monthly). Review adherence and reassess fracture risk.",
        False,
        False,
    )