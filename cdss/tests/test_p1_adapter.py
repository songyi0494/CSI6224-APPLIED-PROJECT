from cdss.adapter.pathway_adapter import PathwayCompatibilityAdapter
from cdss.engine.pipeline import FSFHGPipeline


def test_frozen_sample_facts_evaluation():
    engine = FSFHGPipeline()
    sample_facts = {
        "osteoporosisTreatmentStatus": False,
        "minimalTraumaFracture": True,
        "sex": "female",
        "postmenopausal": "true",
        "age": 74,
        "fractureSite": "hip",
        "eGFR": 54,
        "liveInResidentialCare": False,
        "clinicalFrailtyScore": 4,
        "lifeExpectancy": 10,
        "knownPoorMedicationAdherence": False,
        "cognitiveImpairment": False,
        "testAvailable": True,
        "testWithinLast2Years": True,
        "T-score": -2.7,
        "hipVertebralOrMultipleFracturesInLast24M": True,
        "highRisk": True,
    }

    patient = PathwayCompatibilityAdapter.flutter_facts_to_patient_input(sample_facts)
    result = engine.evaluate(patient)
    envelope = PathwayCompatibilityAdapter.cdss_output_to_flutter_envelope(result)

    assert envelope["pathway"] == "PATHWAY1"
    assert envelope["decision"] == "action_taken"
    assert envelope["actions"][0]["type"] == "consideration"
    assert "ENTRY_CONDITION_PASSED" in envelope["trace"]
    assert "P1_VERY_HIGH_RISK_ANABOLIC" in envelope["trace"]


def test_missing_renal_data_fallback():
    engine = FSFHGPipeline()
    sample_facts = {
        "osteoporosisTreatmentStatus": False,
        "minimalTraumaFracture": True,
        "sex": "male",
        "age": 62,
    }

    patient = PathwayCompatibilityAdapter.flutter_facts_to_patient_input(sample_facts)
    result = engine.evaluate(patient)

    assert result.safety_fallback is True
    assert result.requires_clinician_review is True
    assert "RENAL_DATA_MISSING_FALLBACK" in [step.rule_id for step in result.reasoning_trace]