from typing import List
from cdss.schemas import PatientClinicalInput, CDSSRecommendationOutput, RuleTrace
from cdss.engine.pathway_1 import RuleP1SafetyContraindication, RuleP1VeryHighRisk, RuleP1StandardOsteoporosis
from cdss.engine.pathway_2 import RuleP2TreatmentFailure, RuleP2DrugHoliday


class FSFHGPipeline:
    def __init__(self):
        self.rules = [
            RuleP1SafetyContraindication(),
            RuleP1VeryHighRisk(),
            RuleP1StandardOsteoporosis(),
            RuleP2TreatmentFailure(),
            RuleP2DrugHoliday()
        ]

    def evaluate(self, patient: PatientClinicalInput) -> CDSSRecommendationOutput:
        triggered: List[RuleTrace] = []

        # 1. Evaluate all rules to construct an auditable reasoning trace
        for rule in self.rules:
            trace = rule.evaluate(patient)
            if trace:
                triggered.append(trace)

        # 2. Sort traces by priority descending (highest priority executes first)
        triggered.sort(key=lambda r: r.priority, reverse=True)

        # 3. Handle cases where no specific pathway rules fired
        if not triggered:
            has_bmd = any(t is not None for t in [
                patient.bmd.femoral_neck_t_score,
                patient.bmd.lumbar_spine_t_score,
                patient.bmd.total_hip_t_score
            ])

            # Missing essential diagnostic evidence -> defer to clinician review
            if not has_bmd and not patient.fracture_history.has_minimal_trauma_fracture:
                return CDSSRecommendationOutput(
                    case_id=patient.case_id,
                    pathway="Indeterminate",
                    action_endpoint="No recommendation can be made from provided information.",
                    urgency="CLINICIAN_REVIEW",
                    confidence_indicator="INCOMPLETE_DATA",
                    requires_clinician_review=True,
                    reasoning_trace=[],
                    clinical_rationale="Case lacks DXA T-scores and fracture history. Directing to clinician review rather than making unsupported assumptions."
                )

            # Normal / Osteopenia baseline
            return CDSSRecommendationOutput(
                case_id=patient.case_id,
                pathway="Pathway 1 (Lifestyle / Monitoring)",
                action_endpoint="Lifestyle optimization: Calcium 1000-1200mg daily, Vitamin D maintenance, weight-bearing exercise; repeat DXA in 2 years.",
                urgency="ROUTINE",
                confidence_indicator="DEFINITIVE",
                requires_clinician_review=False,
                reasoning_trace=[],
                clinical_rationale="Bone mineral density values do not reach osteoporosis criteria (T > -2.5) and no minimal trauma fracture exists."
            )

        top_rule = triggered[0]

        # 4. Map top priority rule to clinical endpoint
        if top_rule.rule_id == "P1_RULE_01":
            return CDSSRecommendationOutput(
                case_id=patient.case_id,
                pathway=top_rule.pathway,
                action_endpoint="Withhold oral bisphosphonates/denosumab. Correct hypocalcemia or obtain specialist nephrology consult.",
                urgency="URGENT",
                confidence_indicator="DEFINITIVE",
                requires_clinician_review=True,
                reasoning_trace=triggered,
                clinical_rationale="Patient meets primary safety contraindication criteria (CrCl < 35 mL/min or hypocalcemia)."
            )

        if top_rule.rule_id == "P1_RULE_02":
            return CDSSRecommendationOutput(
                case_id=patient.case_id,
                pathway=top_rule.pathway,
                action_endpoint="Initiate upfront osteoanabolic therapy (e.g. Romosozumab / Teriparatide) or parenteral antiresorptive (Zoledronic Acid 5mg IV).",
                urgency="URGENT",
                confidence_indicator="DEFINITIVE",
                requires_clinician_review=True,
                reasoning_trace=triggered,
                clinical_rationale="Imminent fracture risk: recent vertebral/hip fracture within 12 months or critical T-score <= -3.0."
            )

        if top_rule.rule_id == "P1_RULE_03":
            return CDSSRecommendationOutput(
                case_id=patient.case_id,
                pathway=top_rule.pathway,
                action_endpoint="Initiate first-line antiresorptive therapy (oral Risedronate/Alendronate, yearly Zoledronic Acid, or Denosumab 60mg 6-monthly).",
                urgency="ROUTINE",
                confidence_indicator="DEFINITIVE",
                requires_clinician_review=False,
                reasoning_trace=triggered,
                clinical_rationale="Confirmed primary osteoporosis with acceptable baseline renal and electrolyte safety parameters."
            )

        if top_rule.rule_id == "P2_RULE_01":
            return CDSSRecommendationOutput(
                case_id=patient.case_id,
                pathway=top_rule.pathway,
                action_endpoint="Evaluate for treatment failure: assess compliance/absorption, screen secondary causes, and transition to anabolic therapy.",
                urgency="URGENT",
                confidence_indicator="DEFINITIVE",
                requires_clinician_review=True,
                reasoning_trace=triggered,
                clinical_rationale="Breakthrough minimal trauma fracture sustained while on active antiresorptive therapy."
            )

        if top_rule.rule_id == "P2_RULE_02":
            return CDSSRecommendationOutput(
                case_id=patient.case_id,
                pathway=top_rule.pathway,
                action_endpoint="Consider bisphosphonate drug holiday for 12-24 months. Monitor bone turnover markers (CTX/P1NP) and repeat DXA in 12 months.",
                urgency="ROUTINE",
                confidence_indicator="BORDERLINE",
                requires_clinician_review=True,
                reasoning_trace=triggered,
                clinical_rationale="Continuous bisphosphonate duration >= 5 years without incident fracture warrants drug holiday evaluation to minimize AFF risk."
            )

        return CDSSRecommendationOutput(
            case_id=patient.case_id,
            pathway="Specialist Triage",
            action_endpoint="Direct to multidisciplinary bone clinic review.",
            urgency="CLINICIAN_REVIEW",
            confidence_indicator="BORDERLINE",
            requires_clinician_review=True,
            reasoning_trace=triggered,
            clinical_rationale="Clinical condition requires manual reconciliation."
        )