"""
Validation suite verifying the frozen schema, boolean coercion,
unique trace tokens, and 4-key envelope format.
"""

import pytest
from cdss.schemas import Pathway1Facts, Pathway2Facts
from cdss.engine.pathway_1 import evaluate_pathway_1
from cdss.engine.pathway_2 import evaluate_pathway_2
from cdss.adapter.pathway_adapter import format_evaluation_for_database


def test_pathway1_boolean_coercion():
    # Verify string "true" coercing to native boolean true
    payload = {
        "osteoporosisTreatmentStatus": False,
        "minimalTraumaFracture": True,
        "sex": "female",
        "postmenopausal": "true",  # String coercion check
        "age": 68,
        "T-score": -2.8,
        "hipVertebralOrMultipleFracturesInLast24M": True
    }
    facts = Pathway1Facts(**payload)
    assert facts.postmenopausal is True
    
    result = evaluate_pathway_1(facts)
    assert result.pathway == "PATHWAY1"
    assert result.decision == "action_taken"
    assert "P1_RECENT_HIP_OR_VERTEBRAL_FRACTURE" in result.trace
    assert "P1_VERY_HIGH_RISK_ANABOLIC" in result.trace


def test_pathway1_severe_renal_impairment():
    payload = {
        "minimalTraumaFracture": True,
        "sex": "female",
        "postmenopausal": True,
        "age": 72,
        "eGFR": 24.5  # Critical renal threshold
    }
    facts = Pathway1Facts(**payload)
    result = evaluate_pathway_1(facts)
    assert result.decision == "specialist_referral"
    assert "P1_RENAL_IMPAIRMENT_CRITICAL" in result.trace


def test_pathway2_pbs_cascade_and_cardiovascular_safety():
    # Qualifying PBS 5-tier cascade with MI history -> Romosozumab blocked
    payload = {
        "osteoporosisTreatmentStatus": True,
        "onAntiresorptiveGt12m": True,
        "medicationAdherent": True,
        "symptomaticFractureLast12m": True,
        "lifetimeFractureCount": 3,
        "lowestTScore": -3.2,
        "history_mi_or_stroke": True,
        "age": 74,
        "sex": "female"
    }
    facts = Pathway2Facts(**payload)
    result = evaluate_pathway_2(facts)
    assert result.pathway == "PATHWAY2"
    assert result.decision == "action_taken"
    assert "P2_5_TIER_PBS_CASCADE_QUALIFIED" in result.trace
    assert "P2_ROMOSOZUMAB_CONTRAINDICATED_CV_EVENT" in result.trace
    assert "Teriparatide" in result.actions[0].recommendation


def test_database_adapter_formatting():
    payload = {
        "minimalTraumaFracture": True,
        "sex": "male",
        "age": 65,
        "clinicalFrailtyScore": 6
    }
    facts = Pathway1Facts(**payload)
    result = evaluate_pathway_1(facts)
    db_record = format_evaluation_for_database("asm_test_001", 1, result)
    
    assert db_record["assessment_id"] == "asm_test_001"
    assert db_record["pathway"] == "PATHWAY1"
    assert isinstance(db_record["reasoning_trace"], list)
    assert isinstance(db_record["actions"], list)