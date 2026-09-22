"""
FSFHG Pathway 1 Deterministic Rule Engine.
Evaluates treatment-naïve fracture presentations.
Guarantees non-duplicate trace tokens and strict 4-key output envelopes.
"""

from typing import List
from cdss.schemas import Pathway1Facts, EvaluationEnvelope, ClinicalAction


def evaluate_pathway_1(facts: Pathway1Facts) -> EvaluationEnvelope:
    trace: List[str] = []
    actions: List[ClinicalAction] = []
    decision: str = "action_taken"

    # Step 1: Entry Criteria Gate
    if not facts.minimalTraumaFracture:
        trace.append("P1_ENTRY_CRITERIA_FAILED")
        return EvaluationEnvelope(
            pathway="PATHWAY1",
            decision="require_review",
            actions=[
                ClinicalAction(
                    type="notice",
                    recommendation="Assessment requires confirmed minimal trauma fracture for Pathway 1 eligibility.",
                    requireReview=True
                )
            ],
            trace=trace
        )
    trace.append("P1_ENTRY_CRITERIA_MET")

    # Step 2: Site Exclusion Validation
    if facts.fractureSite:
        excluded_sites = {"hand", "foot", "skull", "ankle", "face", "toe", "finger"}
        if facts.fractureSite.strip().lower() in excluded_sites:
            trace.append("P1_NON_OSTEOPOROTIC_SITE_EXCLUDED")
            return EvaluationEnvelope(
                pathway="PATHWAY1",
                decision="require_review",
                actions=[
                    ClinicalAction(
                        type="notice",
                        recommendation=f"Fracture site ({facts.fractureSite}) is classified as non-osteoporotic.",
                        requireReview=True
                    )
                ],
                trace=trace
            )

    # Step 3: Renal Clearance Evaluation
    if facts.eGFR is not None and facts.eGFR < 30.0:
        trace.append("P1_RENAL_IMPAIRMENT_CRITICAL")
        return EvaluationEnvelope(
            pathway="PATHWAY1",
            decision="specialist_referral",
            actions=[
                ClinicalAction(
                    type="referral",
                    recommendation="Severe renal impairment (eGFR < 30 mL/min). Urgent referral to Specialist Nephrology/Endocrinology required prior to antiresorptive therapy.",
                    requireReview=True
                )
            ],
            trace=trace
        )

    # Step 4: Anabolic Upfront Cascade (Very High Risk)
    t_score = facts.T_score
    is_very_high_risk = facts.hipVertebralOrMultipleFracturesInLast24M or (
        t_score is not None and t_score <= -3.0 and facts.clinicalFrailtyScore >= 5
    )

    if is_very_high_risk and (t_score is None or t_score <= -2.5):
        trace.append("P1_RECENT_HIP_OR_VERTEBRAL_FRACTURE")
        trace.append("P1_VERY_HIGH_RISK_ANABOLIC")
        actions.append(
            ClinicalAction(
                type="treatment",
                recommendation="Very High Risk Profile: Prioritize upfront anabolic therapy (Teriparatide or Romosozumab if cardiovascular clearance confirmed).",
                requireReview=True
            )
        )
        return EvaluationEnvelope(
            pathway="PATHWAY1",
            decision="action_taken",
            actions=actions,
            trace=trace
        )

    # Step 5: Branch A - Frailty, Institutional Care or Reduced Life Expectancy
    if facts.liveInResidentialCare or facts.clinicalFrailtyScore >= 6 or facts.lifeExpectancy < 7.0:
        trace.append("P1_BRANCH_A_FRAILTY_TRIGGERED")
        actions.append(
            ClinicalAction(
                type="treatment",
                recommendation="Branch A Regimen: Initiate Subcutaneous Denosumab 60mg every 6 months with baseline Calcium and Vitamin D repletion.",
                requireReview=True
            )
        )
        return EvaluationEnvelope(
            pathway="PATHWAY1",
            decision="action_taken",
            actions=actions,
            trace=trace
        )

    # Step 6: Branch B - Standard Bone Protection & Adherence Assessment
    trace.append("P1_BRANCH_B_STANDARD_TRIGGERED")
    if facts.knownPoorMedicationAdherence or facts.cognitiveImpairment:
        trace.append("P1_PARENTERAL_ADMIN_PRIORITIZED")
        actions.append(
            ClinicalAction(
                type="treatment",
                recommendation="Adherence/Cognitive Concern: Prioritize clinician-administered annual IV Zoledronic Acid (5mg infusion) over oral bisphosphonates.",
                requireReview=True
            )
        )
    else:
        trace.append("P1_FIRST_LINE_ANTIRESORPTIVE")
        actions.append(
            ClinicalAction(
                type="treatment",
                recommendation="Initiate first-line antiresorptive therapy (Oral Alendronate 70mg weekly or annual IV Zoledronic Acid 5mg).",
                requireReview=True
            )
        )

    # Step 7: Diagnostic Confirmation Notice if DXA Missing or Aged > 2 Years
    if not facts.testAvailable or not facts.testWithinLast2Years:
        trace.append("P1_BMD_DXA_OUTDATED_OR_UNAVAILABLE")
        actions.append(
            ClinicalAction(
                type="consideration",
                recommendation="BMD test is missing or > 2 years old. Order baseline spine and hip DXA scan to establish therapeutic baseline.",
                requireReview=True
            )
        )

    return EvaluationEnvelope(
        pathway="PATHWAY1",
        decision=decision,
        actions=actions,
        trace=trace
    )