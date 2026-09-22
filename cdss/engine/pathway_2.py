"""
FSFHG Pathway 2 Deterministic Rule Engine.
Evaluates pre-treated osteoporosis cases with breakthrough fractures.
Enforces the 5-tier PBS escalation cascade and cardiovascular safety checks.
"""

from typing import List
from cdss.schemas import Pathway2Facts, EvaluationEnvelope, ClinicalAction


def evaluate_pathway_2(facts: Pathway2Facts) -> EvaluationEnvelope:
    trace: List[str] = ["P2_ENTRY_EVALUATION"]
    actions: List[ClinicalAction] = []

    # Cascade Condition Checks
    cond_duration = facts.onAntiresorptiveGt12m
    cond_adherence = facts.medicationAdherent
    cond_recent_fx = facts.symptomaticFractureLast12m
    cond_multiple_fx = facts.lifetimeFractureCount >= 2
    cond_severe_t_score = facts.lowestTScore <= -3.0

    # Verify 5-Tier PBS Cascade Criteria
    tier_conditions = [
        cond_duration,
        cond_adherence,
        cond_recent_fx,
        cond_multiple_fx,
        cond_severe_t_score
    ]
    pbs_cascade_qualifies = all(tier_conditions)

    if pbs_cascade_qualifies:
        trace.append("P2_5_TIER_PBS_CASCADE_QUALIFIED")
        
        # Safety Clearance: Cardiovascular History Verification
        if facts.history_mi_or_stroke:
            trace.append("P2_ROMOSOZUMAB_CONTRAINDICATED_CV_EVENT")
            actions.append(
                ClinicalAction(
                    type="treatment",
                    recommendation="PBS Escalation met. Romosozumab contraindicated due to prior MI/Stroke. Initiate Teriparatide 20mcg SC daily (max 24 months).",
                    requireReview=True
                )
            )
        else:
            trace.append("P2_ANABOLIC_ESCALATION_APPROVED")
            actions.append(
                ClinicalAction(
                    type="treatment",
                    recommendation="PBS Criteria met for Breakthrough Fracture: Escalate to Romosozumab 210mg SC monthly for 12 months, followed by antiresorptive consolidation.",
                    requireReview=True
                )
            )
            actions.append(
                ClinicalAction(
                    type="consideration",
                    recommendation="Alternative: Teriparatide 20mcg SC daily for up to 24 months.",
                    requireReview=True
                )
            )
        
        return EvaluationEnvelope(
            pathway="PATHWAY2",
            decision="action_taken",
            actions=actions,
            trace=trace
        )

    # Fallback Evaluation for Incomplete PBS Escalation Criteria
    trace.append("P2_SUB_OPTIMAL_RESPONSE_INVESTIGATION")
    
    if not cond_duration:
        trace.append("P2_TREATMENT_DURATION_UNDER_12M")
        actions.append(
            ClinicalAction(
                type="notice",
                recommendation="Patient has been on antiresorptive therapy for < 12 months. Insufficient duration to declare primary failure unless atypical presentation.",
                requireReview=True
            )
        )
    
    if not cond_adherence:
        trace.append("P2_NON_ADHERENCE_SUSPECTED")
        actions.append(
            ClinicalAction(
                type="treatment",
                recommendation="Address medication adherence barriers. Switch from oral regimen to supervised parenteral therapy (IV Zoledronic Acid 5mg annually).",
                requireReview=True
            )
        )

    if cond_duration and cond_adherence and not pbs_cascade_qualifies:
        trace.append("P2_CLINICAL_ESCALATION_REQUIRED")
        actions.append(
            ClinicalAction(
                type="referral",
                recommendation="Breakthrough fracture without meeting full 5-tier PBS criteria. Escalate to Metabolic Bone / Osteoporosis Specialist Clinic for secondary screening.",
                requireReview=True
            )
        )

    return EvaluationEnvelope(
        pathway="PATHWAY2",
        decision="require_review",
        actions=actions,
        trace=trace
    )