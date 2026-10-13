"""
Tests for the guideline rules, CSV loading, case fact merging and the API.

Pathway tests start from a baseline patient (``P1``/``P2``) and change one or
two facts, so each case checks a single branch of the flowchart.

:author: Jonathan Gurusinghe
ECU ID: 10658547

References:
    - pytest docs, parametrize and fixtures:
      https://docs.pytest.org/en/stable/how-to/parametrize.html
      https://docs.pytest.org/en/stable/how-to/fixtures.html
    - FastAPI docs, testing and overriding dependencies:
      https://fastapi.tiangolo.com/tutorial/testing/
      https://fastapi.tiangolo.com/advanced/testing-dependencies/


"""

import io
import math
from datetime import date

import pandas as pd
import pytest
from fastapi.testclient import TestClient

from cdss.api.main import app
from cdss.api.routes import recommendations
from cdss.core.config import PATIENTS_PATH
from cdss.core.guidelines import Facts, any_of, evaluate, excluded_site, fill_gaps
from cdss.ml.model import FEATURES, load_csv, to_frame

P1 = dict(osteoporosisTreatmentStatus=False, minimalTraumaFracture=True, sex="female", postmenopausal=True,
          age=72, fractureSite="wrist", eGFR=70.0, liveInResidentialCare=False, clinicalFrailtyScore=3,
          lifeExpectancy=15.0, knownPoorMedicationAdherence=False, cognitiveImpairment=False,
          testAvailable=True, testWithinLast2Years=True, T_score=-2.0,
          hipVertebralOrMultipleFracturesInLast24M=False, highRisk=False)
P2 = dict(osteoporosisTreatmentStatus=True, eGFR=70.0, onAntiresorptiveTherapy=True, onAntiresorptiveGt12m=True,
          medicationAdherent=True, symptomaticFractureLast12m=True, twoOrMoreFractures=True, T_score=-3.4,
          historyMiOrStroke=False)
# Column names as they come out of the questionnaire export
CSV_ROW = {
    "eGFR": 70, "hipTscore": -2.4, "lifeExpectancy": 15, "testAvailability": True, "femoralNeckTscore": -2.8,
    "lumbarSpineTscore": -2.6, "clinicalRiskFactors": True, "cognitiveImpairment": False, "clinicalFrailtyScore": 3,
    "liveInResidentialCare": False, "recentFractureWithin2Y": True, "historyOf2orMoreFractures": True,
    "osteoporosisTreatmentStatus": False, "knownPoorMedicationAdherence": False,
    "FRAX10YmajorHipFractureRiskPercent": 4.0, "hipVertebralOrMultipleFracturesInLast24M": True,
    "FRAX10YmajorOsteoporoticFractureRiskPercent": 25.0,
}


def p1(**kw) -> Facts:
    """
    :param kw: facts to override on the Pathway 1 baseline
    :rtype: Facts
    """
    return Facts(**{**P1, **kw})


def p2(**kw) -> Facts:
    """
    :param kw: facts to override on the Pathway 2 baseline
    :rtype: Facts
    """
    return Facts(**{**P2, **kw})


def _csv(rows) -> io.StringIO:
    """
    :param rows: list of row dicts
    :return: the rows as an in-memory CSV
    :rtype: io.StringIO
    """
    return io.StringIO(pd.DataFrame(rows).to_csv(index=False))


@pytest.mark.parametrize("kw, expected", [
    ({}, "P1_STANDARD_ANTIRESORPTIVE"),
    ({"liveInResidentialCare": True}, "P1_DENOSUMAB_FRAILTY"),
    ({"clinicalFrailtyScore": 6}, "P1_DENOSUMAB_FRAILTY"),
    ({"lifeExpectancy": 5.0}, "P1_DENOSUMAB_FRAILTY"),
    ({"cognitiveImpairment": True}, "P1_ZOLEDRONIC_ACID_ADHERENCE"),
    ({"testAvailable": False}, "P1_STANDARD_ANTIRESORPTIVE"),
    ({"testWithinLast2Years": False}, "P1_DXA_REFERRAL"),
    ({"T_score": -2.7, "hipVertebralOrMultipleFracturesInLast24M": True}, "P1_OSTEOANABOLIC_SPECIALIST"),
    ({"T_score": -3.2}, "P1_CONSIDER_PRIVATE_OSTEOANABOLIC"),
    ({"T_score": -2.7, "highRisk": True}, "P1_CONSIDER_PRIVATE_OSTEOANABOLIC"),
    ({"T_score": -2.7}, "P1_STANDARD_ANTIRESORPTIVE"),
    ({"minimalTraumaFracture": False}, "NOT_ELIGIBLE_NO_MINIMAL_TRAUMA"),
    ({"fractureSite": "left ankle"}, "NOT_ELIGIBLE_EXCLUDED_SITE"),
    ({"postmenopausal": False}, "SPECIALIST_OUT_OF_SCOPE"),
    ({"sex": "male", "postmenopausal": None, "age": 45}, "SPECIALIST_OUT_OF_SCOPE"),
    ({"eGFR": 34.9}, "SPECIALIST_RENAL"),
    ({"eGFR": 20.0, "liveInResidentialCare": True}, "SPECIALIST_RENAL"),
])
def test_pathway_1(kw, expected):
    assert evaluate(p1(**kw)).endpoint == expected


@pytest.mark.parametrize("kw, expected", [
    ({}, "P2_ROMOSOZUMAB"),
    ({"historyMiOrStroke": True}, "P2_TERIPARATIDE"),
    ({"medicationAdherent": False}, "P2_CONTINUE_ANTIRESORPTIVE"),
    ({"twoOrMoreFractures": False}, "P2_CONTINUE_ANTIRESORPTIVE"),
    ({"T_score": -2.8}, "P2_CONTINUE_ANTIRESORPTIVE"),
    ({"T_score": None, "lowBMD": True}, "P2_ROMOSOZUMAB"),
    ({"T_score": None, "lowBMD": False}, "P2_CONTINUE_ANTIRESORPTIVE"),
    ({"eGFR": 30.0}, "SPECIALIST_RENAL"),
])
def test_pathway_2(kw, expected):
    assert evaluate(p2(**kw)).endpoint == expected


def test_unknown_stops_and_names_the_fact():
    result = evaluate(p1(T_score=None))
    assert (result.endpoint, result.missing) == ("NEEDS_MORE_INFORMATION", ["T_score"])


def test_known_true_decides_despite_unknowns():
    assert evaluate(p1(liveInResidentialCare=True, clinicalFrailtyScore=None)).endpoint == "P1_DENOSUMAB_FRAILTY"


def test_unknown_blocks_a_no():
    assert evaluate(p1(clinicalFrailtyScore=None)).missing == ["clinicalFrailtyScore"]


def test_unknown_sex_asks_only_for_sex():
    assert evaluate(p1(sex=None)).missing == ["sex"]


def test_trace_follows_the_path():
    ids = [rid for rid, _, _ in evaluate(p1(T_score=-2.7)).trace]
    assert ids[:3] == ["G_ROUTING", "G_MTF", "G_SITE"] and ids[-1] == "P1_DEFAULT"


@pytest.mark.parametrize("values, expected", [((True, None), True), ((False, None), None), ((False, False), False)])
def test_kleene_or(values, expected):
    assert any_of(*values) is expected


@pytest.mark.parametrize("site, expected", [("hip", False), ("Right foot", True), (None, None)])
def test_excluded_site(site, expected):
    assert excluded_site(site) is expected


def test_screened_patient_skips_entry_gates():
    assert evaluate(p1(minimalTraumaFracture=None, sex=None, entryCriteriaMet=True)).endpoint \
        == "P1_STANDARD_ANTIRESORPTIVE"


def test_aliases_and_lowest_site_t_score():
    f = Facts(**CSV_ROW)
    assert (f.T_score, f.testAvailable, f.twoOrMoreFractures) == (-2.8, True, True)


def test_questionnaire_names_reach_pathway_2():
    f = Facts(osteoporosisTreatmentStatus=True, eGFR=40, antiresorptiveTreatmentStatus=True,
              antiresorptiveTreatmentDuration=True, adheredToTheTreatment=True, symptomaticFractureInLast12M=True,
              multipleFractures=True, lowBMD=True, priorMIorStroke=True)
    assert evaluate(f).endpoint == "P2_TERIPARATIDE"


def test_blank_alias_does_not_erase_a_recorded_answer():
    assert Facts(historyOf2orMoreFractures=False, multipleFractures=math.nan).twoOrMoreFractures is False


def test_patients_csv_decides_pathway_2_rows():
    _, y, info = load_csv(PATIENTS_PATH)
    assert "P2_ROMOSOZUMAB" in set(y) and "P2_TERIPARATIDE" in set(y)
    assert info["unused_columns"] == []


def test_feature_width_and_nan_for_unknowns():
    frame = to_frame([p1(T_score=None)])
    assert frame.shape == (1, len(FEATURES)) == (1, 32)
    assert math.isnan(frame.loc[0, "T_score"])


def test_csv_needs_assumptions_to_reach_a_decision():
    _, y, info = load_csv(_csv([CSV_ROW]))
    assert list(y) == ["NEEDS_MORE_INFORMATION"] and "minimalTraumaFracture" in info["facts_not_in_csv"]
    _, y, _ = load_csv(_csv([CSV_ROW]), entry_criteria_met=True, dxa_recent=True)
    assert list(y) == ["P1_OSTEOANABOLIC_SPECIALIST"]


def test_frax_thresholds_set_high_risk_only_when_supplied():
    row = {**CSV_ROW, "hipVertebralOrMultipleFracturesInLast24M": False}
    _, y, _ = load_csv(_csv([row]), entry_criteria_met=True, dxa_recent=True)
    assert list(y) == ["NEEDS_MORE_INFORMATION"]
    _, y, _ = load_csv(_csv([row]), entry_criteria_met=True, dxa_recent=True, frax_high_risk=(20.0, 3.0))
    assert list(y) == ["P1_CONSIDER_PRIVATE_OSTEOANABOLIC"]


def test_invalid_rows_are_rejected_not_defaulted():
    _, y, info = load_csv(_csv([P1, {**P1, "clinicalFrailtyScore": 12}]))
    assert (len(y), info["rows_rejected"]) == (1, 1)


def test_unrecognised_csv_is_rejected():
    with pytest.raises(ValueError, match="No recognised columns"):
        load_csv(_csv([{"Osteoporosis": 1}]))


class NoModel:
    """Stand-in for TreatmentModel when no model is trained."""

    loaded, card = False, {}

    def opinion(self, *_):
        return None


class FakeSupabase:
    """Answers every query with `rows`, or with rows[table] when given a dict of tables."""

    def __init__(self, rows):
        self.rows, self.current = rows, rows

    def table(self, name):
        self.current = self.rows.get(name, []) if isinstance(self.rows, dict) else self.rows
        return self

    def __getattr__(self, _):
        return lambda *a, **k: self

    def execute(self):
        return type("Response", (), {"data": self.current})()


@pytest.fixture
def client():
    """Test client with no model loaded; dependency overrides are cleared afterwards."""
    app.dependency_overrides[recommendations.get_model] = NoModel
    yield TestClient(app)
    app.dependency_overrides.clear()


def test_healthz(client):
    assert client.get("/healthz").json() == {"status": "ok"}


def test_post_facts_returns_the_guideline_endpoint(client):
    assert client.post("/api/recommendations", json=P2).json()["endpoint"] == "P2_ROMOSOZUMAB"


def test_case_lookup_reads_supabase(client):
    app.dependency_overrides[recommendations.require_supabase] = \
        lambda: FakeSupabase({"clinical_cases": [{"id": "c1", "patient_id": "p1", "clinician_facts": P2}]})
    body = client.get("/api/cases/c1/recommendation").json()
    assert (body["endpoint"], body["patient_id"]) == ("P2_ROMOSOZUMAB", "p1")


def test_case_facts_merge_sources_in_order():
    case = {"minimalTraumaFracture": None, "clinician_facts": {"eGFR": 70, "testAvailability": False, "lowBMD": None}}
    facts = recommendations.case_facts(
        case, profile={"gender": "male", "date_of_birth": "1950-06-15"},
        answers={"sex": "Female", "postmenopausal": "Yes", "minimalTraumaFracture": "Yes",
                 "excludedFractureSite": "No", "smoking": "Yes"},
        investigation={"t_score": "-2.7", "test_date": "2023-01-01"}, today=date(2026, 6, 14))
    assert facts == {"sex": "female", "age": 75, "postmenopausal": True, "minimalTraumaFracture": True,
                     "fractureSite": "eligible site (patient-reported)", "T_score": -2.7, "testAvailable": False,
                     "testWithinLast2Years": False, "eGFR": 70}
    assert Facts.model_validate(facts).testAvailable is False


def test_case_facts_excluded_site_is_not_eligible():
    facts = recommendations.case_facts({}, answers={"excludedFractureSite": "Yes"})
    assert excluded_site(facts["fractureSite"]) is True


def test_unknown_case_is_404(client):
    app.dependency_overrides[recommendations.require_supabase] = lambda: FakeSupabase([])
    assert client.get("/api/cases/missing/recommendation").status_code == 404


def test_every_questionnaire_row_gets_a_recommendation(client):
    for row in pd.read_csv(PATIENTS_PATH).to_dict(orient="records"):
        body = client.post("/api/recommendations", json={k: v for k, v in row.items() if pd.notna(v)}).json()
        assert body["endpoint"] != "NEEDS_MORE_INFORMATION", row


def test_assumptions_fill_only_blanks_and_are_reported():
    f, notes = fill_gaps(Facts(**{**CSV_ROW, "hipVertebralOrMultipleFracturesInLast24M": False}))
    assert (f.entryCriteriaMet, f.testWithinLast2Years, f.highRisk) == (True, True, True) and len(notes) == 3
    f, notes = fill_gaps(Facts(**CSV_ROW, highRisk=False, entryCriteriaMet=False))
    assert (f.entryCriteriaMet, f.highRisk) == (False, False) and len(notes) == 1


def test_low_egfr_refers_even_without_treatment_status():
    f, _ = fill_gaps(Facts(eGFR=20))
    assert evaluate(f).endpoint == "SPECIALIST_RENAL"
    assert evaluate(Facts(eGFR=20)).endpoint == "NEEDS_MORE_INFORMATION"


def test_health_reports_model_and_database(client):
    body = client.get("/health").json()
    assert body["status"] == "ok" and body["model_loaded"] is False and "supabase_connected" in body


def test_list_cases(client):
    app.dependency_overrides[recommendations.require_supabase] = lambda: FakeSupabase([{"id": "c1"}])
    assert client.get("/api/cases").json() == [{"id": "c1"}]


def test_model_card_is_503_without_a_model(client):
    assert client.get("/api/model").status_code == 503
