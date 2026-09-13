from typing import List, Tuple
from cdss.schemas import ActionClassification, PatientClinicalInput, TraceStep


def evaluate_pathway_1_rules(
    patient: PatientClinicalInput, trace: List[TraceStep]
) -> Tuple[ActionClassification, str, bool, bool]:
    """
    Evaluates Pathway 1 deterministic rules (Treatment-Naïve post-minimal trauma fracture).
    Returns (action_type, recommendation_text, safety_fallback, requires_clinician_review).
    """
    trace.append(
        TraceStep(
            rule_id="ENTRY_CONDITION_PASSED",
            rule_description="Entry eligibility check for Pathway 1",
            condition_matched=True,
            details="Patient is treatment-naïve post-minimal trauma fracture.",
        )
    )

    # 1. Fracture Site Exclusion Check (hands, feet, face, ankle)
    excluded_sites = ["hand", "hands", "foot", "feet", "face", "ankle"]
    if patient.fracture_site and patient.fracture_site.strip().lower() in excluded_sites:
        trace.append(
            TraceStep(
                rule_id="FRACTURE_SITE_EXCLUDED",
                rule_description="Excluded peripheral fracture site check",
                condition_matched=True,
                details=f"Fracture site '{patient.fracture_site}' is excluded from osteoporosis pathways.",
            )
        )
        return (
            ActionClassification.NO_DECISION,
            "Fractures of hands, feet, face, and ankle are excluded from standard osteoporosis pathways.",
            False,
            True,
        )

    # 2. Severe Frailty / RACF / Limited Life Expectancy (Branch A)
    is_frail = (
        patient.lives_in_racf
        or patient.clinical_frailty_score >= 6
        or (patient.life_expectancy_years is not None and patient.life_expectancy_years < 7.0)
    )
    if is_frail:
        trace.append(
            TraceStep(
                rule_id="P1_BRANCH_A_FRAILTY",
                rule_description="Branch A: Severe frailty, residential care, or life expectancy < 7 years",
                condition_matched=True,
                details="Patient meets frailty criteria. Subcutaneous denosumab preferred (no DXA strictly required).",
            )
        )
        return (
            ActionClassification.INITIATE_DENOSUMAB,
            "Commence Denosumab 60 mg subcutaneous 6-monthly. Follow up with GP. CRITICAL: Do not delay doses by >4 weeks due to rebound vertebral fracture risk; do not stop without specialist consolidation plan.",
            False,
            False,
        )

    # 3. Adherence or Cognitive Concerns (Branch B)
    if patient.adherence_or_cognitive_concerns:
        trace.append(
            TraceStep(
                rule_id="P1_BRANCH_B_ADHERENCE",
                rule_description="Branch B: Adherence or cognitive impairment concerns",
                condition_matched=True,
                details="Adherence concerns identified. Annual parenteral bisphosphonate preferred.",
            )
        )
        return (
            ActionClassification.INITIATE_THERAPY,
            "Commence Zoledronic acid 5 mg IV annually for 3 years (consider 3-day dexamethasone cover for first dose) OR oral Risedronate EC 35 mg weekly. Review adherence and reassess fracture risk after 5 years (or 3 ZA doses).",
            False,
            False,
        )

    # 4. Very High Fracture Risk: Osteoanabolic First (Branch C)
    has_severe_fracture = (
        patient.is_hip_or_vertebral_fracture
        or patient.fractures_in_last_24_months >= 2
        or (patient.fracture_site and patient.fracture_site.strip().lower() in ["hip", "spine", "vertebra", "vertebral"])
    )
    if patient.t_score_lowest is not None and patient.t_score_lowest <= -2.5 and has_severe_fracture:
        trace.append(
            TraceStep(
                rule_id="P1_VERY_HIGH_RISK_ANABOLIC",
                rule_description="Branch C: T-score <= -2.5 and hip, vertebral, or >=2 fractures in 24M",
                condition_matched=True,
                details=f"T-score {patient.t_score_lowest} with severe fracture profile. Osteoanabolic before antiresorptive maximizes bone gain.",
            )
        )
        return (
            ActionClassification.ESCALATE_ANABOLIC,
            "Consider commencement of osteoanabolic therapy (Romosozumab or Teriparatide) prior to antiresorptive exposure. Refer for specialist input / Fragile Bone Clinic.",
            False,
            True,
        )

    # 5. Standard PBS Antiresorptive Pathway
    if patient.dxa_impractical or (patient.t_score_lowest is not None and patient.t_score_lowest <= -2.5):
        rule_tag = "DXA_IMPRACTICAL_PBS_STANDARD" if patient.dxa_impractical else "STANDARD_PBS_ANTIRESORPTIVE"
        trace.append(
            TraceStep(
                rule_id=rule_tag,
                rule_description="Standard PBS-funded antiresorptive indication",
                condition_matched=True,
                details="DXA impractical or T-score <= -2.5 without severe anabolic criteria.",
            )
        )
        return (
            ActionClassification.INITIATE_THERAPY,
            "Prescribe standard PBS-funded antiresorptive: Zoledronic acid 5 mg IV annually for 3 years OR oral Risedronate EC 35 mg weekly OR Denosumab 60 mg SC 6-monthly. Follow up with GP; review fracture risk after 5 years (or 3 ZA doses).",
            False,
            False,
        )

    # 6. Incomplete Diagnostic Data Fallback
    trace.append(
        TraceStep(
            rule_id="P1_INCOMPLETE_DXA_REQUIRED",
            rule_description="Missing BMD DXA scan",
            condition_matched=True,
            details="T-score not provided and DXA not marked impractical.",
        )
    )
    return (
        ActionClassification.NO_DECISION,
        "Referral for BMD DXA scan required (if not performed within prior 2 years). If DXA is impractical to obtain, commence standard PBS-funded antiresorptive.",
        True,
        True,
    )