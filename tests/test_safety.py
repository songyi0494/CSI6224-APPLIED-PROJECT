"""
Tests for the safety guardrail, the missing-value sentinel and the rule that the
model can flag a recommendation but never change its endpoint.

:author: Jonathan Gurusinghe
ECU ID: 10658547

References:
    - pytest docs, parametrize: https://docs.pytest.org/en/stable/how-to/parametrize.html
    - scikit-learn docs, DummyClassifier:
      https://scikit-learn.org/stable/modules/generated/sklearn.dummy.DummyClassifier.html
    - FastAPI docs, overriding dependencies in tests:
      https://fastapi.tiangolo.com/advanced/testing-dependencies/


"""

import math

import pandas as pd
import pytest
from fastapi.testclient import TestClient
from sklearn.dummy import DummyClassifier

from cdss.api.main import app
from cdss.api.routes import recommendations
from cdss.ml.model import FEATURES, MISSING_SENTINEL, build_pipeline, to_frame, wrec
from cdss.ml.safety_wrapper import ClinicalSafetyWrapper, intercept
from tests.test_rules import P2, NoModel, p1

ZOL = "P1_STANDARD_ANTIRESORPTIVE"


@pytest.mark.parametrize("endpoint, egfr, mi, final", [
    (ZOL, 34.0, 0, "SPECIALIST_RENAL"),
    (ZOL, math.nan, 0, "SPECIALIST_RENAL"),
    (ZOL, 35.0, 0, ZOL),
    ("P2_ROMOSOZUMAB", 60.0, 1, "P2_TERIPARATIDE"),
    ("P2_ROMOSOZUMAB", 25.0, 1, "SPECIALIST_SAFETY_REVIEW"),
    ("P2_ROMOSOZUMAB", 60.0, math.nan, "SPECIALIST_SAFETY_REVIEW"),
    ("P2_ROMOSOZUMAB", 60.0, 0, "P2_ROMOSOZUMAB"),
    ("P2_TERIPARATIDE", 25.0, 1, "SPECIALIST_RENAL"),
    ("P2_TERIPARATIDE", None, 1, "SPECIALIST_RENAL"),
    ("P2_TERIPARATIDE", 30.0, 1, "P2_TERIPARATIDE"),
    ("P1_OSTEOANABOLIC_SPECIALIST", 60.0, math.nan, "P1_OSTEOANABOLIC_SPECIALIST"),
    ("P1_OSTEOANABOLIC_SPECIALIST", 60.0, 1, "SPECIALIST_SAFETY_REVIEW"),
    ("P1_DENOSUMAB_FRAILTY", 20.0, 1, "P1_DENOSUMAB_FRAILTY"),
])
def test_intercept(endpoint, egfr, mi, final):
    assert intercept(endpoint, egfr, mi)[0] == final


def test_wrec_weights_undertreatment():
    assert wrec(["P2_ROMOSOZUMAB", "P1_DXA_REFERRAL"], [ZOL, "P1_DXA_REFERRAL"]) == 2.5


def test_wrapper_rewrites_and_records_overrides():
    X = pd.DataFrame({"eGFR": [30.0, 80.0], "historyMiOrStroke": [0.0, 0.0]})
    model = ClinicalSafetyWrapper(DummyClassifier(strategy="constant", constant=ZOL)).fit(X, [ZOL, ZOL])
    assert list(model.predict(X)) == ["SPECIALIST_RENAL", ZOL]
    assert len(model.overrides_) == 1


def test_missing_sentinel_cannot_pass_for_a_real_t_score():
    frame = to_frame([p1(T_score=None), p1(T_score=-1.0)])
    out = build_pipeline().named_steps["imputer"].fit(frame).transform(frame)
    t = FEATURES.index("T_score")
    assert out[0, t] == MISSING_SENTINEL and out[1, t] == -1.0
    assert out.shape[1] > len(FEATURES)


class DisagreeingModel(NoModel):
    """Model stub that always disagrees with the guideline."""

    loaded = True

    def opinion(self, facts, guideline_endpoint):
        return {"endpoint": ZOL, "raw_endpoint": ZOL, "confidence": 0.9, "agrees_with_guideline": False,
                "safety_override": None, "model_version": "test"}


@pytest.fixture
def client():
    """Test client; dependency overrides are cleared afterwards."""
    yield TestClient(app)
    app.dependency_overrides.clear()


def test_model_can_flag_but_never_change_the_endpoint(client):
    app.dependency_overrides[recommendations.get_model] = DisagreeingModel
    body = client.post("/api/recommendations", json={**P2, "historyMiOrStroke": True}).json()
    assert body["endpoint"] == "P2_TERIPARATIDE" and body["requires_clinician_review"] is True
    assert any(ZOL in r for r in body["review_reasons"])

