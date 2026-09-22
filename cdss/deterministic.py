"""Fail-closed, priority-encoded FSFHG Pathway 1 CDSS.

This module accepts raw clinical facts. It deliberately never defaults, coerces,
derives, rounds, or imputes any clinical parameter.
"""

from __future__ import annotations

import json
import math
import uuid
from dataclasses import dataclass
from types import MappingProxyType
from typing import Any, Callable, Mapping

PATHWAY_VERSION = "FSFHG-P1-2026.09.22"
REVIEW_STATUS = "AWAITING_CLINICIAN_REVIEW"
INCOMPLETE_RECORD = "INCOMPLETE_RECORD"

REQUIRED = (
    "osteoporosisTreatmentStatus", "minimalTraumaFracture", "sex", "postmenopausal",
    "age", "fractureSite", "eGFR", "liveInResidentialCare", "clinicalFrailtyScore",
    "lifeExpectancy", "knownPoorMedicationAdherence", "cognitiveImpairment", "T-score",
    "hipVertebralOrMultipleFracturesInLast24M",
)


@dataclass(frozen=True)
class RuleTrigger:
    rule_id: str
    priority: int
    outcome: str


@dataclass(frozen=True)
class AuditEnvelope:
    evaluation_id: str
    pathway_version: str
    inputs_received: Mapping[str, Any]
    rules_triggered: tuple[RuleTrigger, ...]
    recommendation_endpoint: str
    status: str
    decision: str
    recommendation: str
    missing_inputs: tuple[str, ...] = ()
    warnings: tuple[str, ...] = ()

    def to_dict(self) -> dict[str, Any]:
        return {
            "evaluation_id": self.evaluation_id,
            "pathway_version": self.pathway_version,
            "inputs_received": dict(self.inputs_received),
            "rules_triggered": [rule.__dict__ for rule in self.rules_triggered],
            "recommendation_endpoint": self.recommendation_endpoint,
            "status": self.status,
            "decision": self.decision,
            "recommendation": self.recommendation,
            "missing_inputs": list(self.missing_inputs),
            "warnings": list(self.warnings),
        }

    def to_json(self) -> str:
        return json.dumps(self.to_dict(), sort_keys=True, separators=(",", ":"), allow_nan=False)


@dataclass(frozen=True)
class Rule:
    rule_id: str
    priority: int
    matches: Callable[[Mapping[str, Any]], bool]
    endpoint: str
    decision: str
    recommendation: str


def _n(facts: Mapping[str, Any], key: str) -> float:
    return facts[key]


def _eligible(facts: Mapping[str, Any]) -> bool:
    return ((facts["sex"] == "female" and facts["postmenopausal"] is True)
            or (facts["sex"] == "male" and _n(facts, "age") >= 50))


def _site(facts: Mapping[str, Any]) -> str:
    return facts["fractureSite"].strip().lower()


# The list is the explicit hierarchy. First matching terminal rule wins.
TREE = (
    Rule("P10_ALREADY_ON_OSTEOPOROSIS_TREATMENT", 10, lambda f: f["osteoporosisTreatmentStatus"] is True,
         "ROUTE_TO_PATHWAY2", "NOT_APPLICABLE", "Existing osteoporosis treatment is recorded; route to the pre-treated pathway."),
    Rule("P20_ENTRY_NOT_MINIMAL_TRAUMA_FRACTURE", 20, lambda f: f["minimalTraumaFracture"] is not True,
         "PATHWAY_NOT_APPLICABLE", "NOT_APPLICABLE", "Pathway 1 applies only after a documented minimal-trauma fracture."),
    Rule("P30_ENTRY_DEMOGRAPHIC_NOT_ELIGIBLE", 30, lambda f: not _eligible(f),
         "PATHWAY_NOT_APPLICABLE", "NOT_APPLICABLE", "Demographic entry criteria are not met."),
    Rule("P40_EXCLUDED_FRACTURE_SITE", 40, lambda f: _site(f) in {"hand", "hands", "foot", "feet", "face", "ankle"},
         "PATHWAY_NOT_APPLICABLE", "NOT_APPLICABLE", "Hand, foot, face, and ankle fractures are excluded."),
    Rule("P50_EGFR_LESS_THAN_30_SPECIALIST_REVIEW", 50, lambda f: _n(f, "eGFR") < 30,
         "SPECIALIST_RENAL_REVIEW", "ACTION_TAKEN", "eGFR is below 30 mL/min; obtain specialist advice before antiresorptive treatment."),
    Rule("P60_FRAILTY_OR_RACF_OR_SHORT_LIFE_EXPECTANCY", 60,
         lambda f: f["liveInResidentialCare"] is True or _n(f, "clinicalFrailtyScore") >= 6 or _n(f, "lifeExpectancy") < 7,
         "DENOSUMAB_REVIEW", "ACTION_TAKEN", "Consider denosumab; clinician review and a discontinuation plan are required."),
    Rule("P70_ADHERENCE_OR_COGNITIVE_CONCERN", 70,
         lambda f: f["knownPoorMedicationAdherence"] is True or f["cognitiveImpairment"] is True,
         "PARENTERAL_ANTIRESORPTIVE_REVIEW", "ACTION_TAKEN", "Consider a clinician-selected supervised antiresorptive regimen."),
    # Inclusive boundary: exactly -2.5 enters the higher-priority anabolic branch.
    Rule("P80_T_SCORE_LE_MINUS_2_5_WITH_MAJOR_FRACTURE", 80,
         lambda f: _n(f, "T-score") <= -2.5 and f["hipVertebralOrMultipleFracturesInLast24M"] is True,
         "OSTEOANABOLIC_SPECIALIST_REVIEW", "ACTION_TAKEN", "Consider osteoanabolic therapy and refer for specialist review."),
    Rule("P90_STANDARD_ANTIRESORPTIVE", 90, lambda _: True,
         "STANDARD_ANTIRESORPTIVE_REVIEW", "ACTION_TAKEN", "Consider a guideline-concordant antiresorptive regimen; clinician approval is required."),
)


def _validate(facts: Any) -> tuple[tuple[str, ...], tuple[str, ...]]:
    if not isinstance(facts, Mapping):
        return ("facts",), ("facts must be a JSON object",)
    missing = tuple(key for key in REQUIRED if key not in facts or facts[key] is None or facts[key] == "")
    warnings: list[str] = []
    for key in ("osteoporosisTreatmentStatus", "minimalTraumaFracture", "postmenopausal", "liveInResidentialCare",
                "knownPoorMedicationAdherence", "cognitiveImpairment", "hipVertebralOrMultipleFracturesInLast24M"):
        if key in facts and not isinstance(facts[key], bool):
            warnings.append(f"{key}: expected boolean")
    if "sex" in facts and facts["sex"] not in {"female", "male"}:
        warnings.append("sex: expected female or male")
    if "fractureSite" in facts and (not isinstance(facts["fractureSite"], str) or not facts["fractureSite"].strip()):
        warnings.append("fractureSite: expected non-empty string")
    for key, low, high in (("age", 18, 120), ("eGFR", 0, 200), ("clinicalFrailtyScore", 1, 9), ("lifeExpectancy", 0, 120), ("T-score", -6, 2)):
        value = facts.get(key)
        if value is not None and (isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) or not low <= value <= high):
            warnings.append(f"{key}: expected finite number in [{low}, {high}]")
    return missing, tuple(warnings)


def evaluate_pathway_1(facts: Any, *, evaluation_id: str | None = None) -> AuditEnvelope:
    """Return an immutable audit envelope; incomplete records never reach treatment rules."""
    received = MappingProxyType(dict(facts)) if isinstance(facts, Mapping) else MappingProxyType({})
    missing, warnings = _validate(facts)
    evaluation_id = evaluation_id or str(uuid.uuid4())
    if missing or warnings:
        return AuditEnvelope(evaluation_id, PATHWAY_VERSION, received,
            (RuleTrigger("P00_INCOMPLETE_RECORD_GATE", 0, INCOMPLETE_RECORD),),
            "CLINICIAN_RECORD_COMPLETION", REVIEW_STATUS, INCOMPLETE_RECORD,
            "Clinical record is incomplete or invalid. No automated recommendation was produced.", missing, warnings)
    rule = next(rule for rule in TREE if rule.matches(received))
    return AuditEnvelope(evaluation_id, PATHWAY_VERSION, received,
        (RuleTrigger("P01_RECORD_COMPLETE", 1, "INPUT_VALIDATION_PASSED"), RuleTrigger(rule.rule_id, rule.priority, rule.endpoint)),
        rule.endpoint, REVIEW_STATUS, rule.decision, rule.recommendation)
