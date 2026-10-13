"""
Random forest pipeline, the dense feature encoding it shares between training
and inference, and the CSV loader.

CSV columns are matched to Facts by field name or alias. Labels come from an
`endpoint` column when present, otherwise from the guideline engine. Facts the
CSV lacks stay unknown unless an assumption is switched on; each assumption is
recorded in the load report.

The model is advisory only: its opinion is passed through the safety guardrail
and can add review reasons, but never replaces the guideline endpoint.

:author: Jonathan Gurusinghe
ECU ID: 10658547

References:
    - Breiman, L. (2001). Random Forests. Machine Learning, 45(1), 5-32.
    - scikit-learn docs: Pipeline, SimpleImputer (add_indicator) and RandomForestClassifier:
      https://scikit-learn.org/stable/modules/compose.html#pipeline
      https://scikit-learn.org/stable/modules/impute.html#marking-imputed-values
      https://scikit-learn.org/stable/modules/generated/sklearn.ensemble.RandomForestClassifier.html
    - joblib persistence: https://joblib.readthedocs.io/en/stable/persistence.html
    - Mitchell, M. et al. (2019). Model Cards for Model Reporting. FAT* '19
      (the model card the training script writes and this class reads).


"""

import json
import math
from pathlib import Path
from typing import Dict, List, Optional, Tuple

import joblib
import numpy as np
import pandas as pd
from pydantic import ValidationError
from sklearn.ensemble import RandomForestClassifier
from sklearn.impute import SimpleImputer
from sklearn.pipeline import Pipeline

from cdss.core.config import RENAL_EGFR_MIN, SEED, SEVERE_T, UNDERTREATMENT_COST
from cdss.core.guidelines import (ANABOLIC, ANTIRESORPTIVE_ONLY, FIELD_BY_NAME, SITE_T_SCORES, ZOLEDRONIC_FIRST,
                                  Facts, canonical, clean, evaluate, excluded_site, fill_gaps)
from cdss.ml.safety_wrapper import intercept

TARGET = "endpoint"
NUMERIC = ["age", "eGFR", "clinicalFrailtyScore", "lifeExpectancy", "T_score", *SITE_T_SCORES,
           "FRAX10YmajorOsteoporoticFractureRiskPercent", "FRAX10YmajorHipFractureRiskPercent"]
# sequencingFromDenosumab only adds a review note, so the model never sees it
BOOLEAN = [n for n in Facts.model_fields if n not in NUMERIC
           and n not in ("sex", "fractureSite", "sequencingFromDenosumab")]
FEATURES: List[str] = NUMERIC + BOOLEAN + ["sex_female", "site_excluded"]

# -99 is outside every feature's range; a -1 sentinel would collide with a real T-score of -1.0
MISSING_SENTINEL = -99.0


def _num(value) -> float:
    return math.nan if value is None else float(value)


def to_row(f: Facts) -> Dict[str, float]:
    """
    Encode one patient as a dense numeric feature row; unknowns become NaN.

    :param f: patient facts
    :type f: Facts
    :return: feature name to value
    :rtype: dict
    """
    row ={name: _num(getattr(f, name)) for name in NUMERIC + BOOLEAN}
    row["sex_female"] = math.nan if f.sex is None else float(f.sex == "female")
    row["site_excluded"] = _num(excluded_site(f.fractureSite))
    return row


def to_frame(facts: List[Facts]) -> pd.DataFrame:
    """
    :param facts: patients to encode
    :type facts: list[Facts]
    :return: feature matrix with columns in ``FEATURES`` order
    :rtype: pandas.DataFrame
    """
    return pd.DataFrame([to_row(f) for f in facts], columns=FEATURES)


def invariant_violations(X: pd.DataFrame, y: np.ndarray) -> Dict[str, int]:
    """
    Count labels that break an FSFHG safety invariant; always 0 for rule-derived labels.

    :param X: encoded features
    :type X: pandas.DataFrame
    :param y: endpoint labels
    :type y: numpy.ndarray
    :return: violation name to row count
    :rtype: dict
    """
    tx = pd.Series(y, index=X.index)
    fractured = (X["hipVertebralOrMultipleFracturesInLast24M"] == 1) | (X["twoOrMoreFractures"] == 1)
    return {
        "anabolic_without_fracture_or_severe_op":
            int((tx.isin(ANABOLIC) & ~fractured & ~(X["T_score"] <= SEVERE_T)).sum()),
        "romosozumab_with_mi_stroke": int(((tx == "P2_ROMOSOZUMAB") & (X["historyMiOrStroke"] == 1)).sum()),
        "zoledronic_with_low_egfr": int((tx.isin(ZOLEDRONIC_FIRST) & (X["eGFR"] < RENAL_EGFR_MIN)).sum()),
    }


def load_csv(source, entry_criteria_met: bool = False, dxa_recent: bool = False,
             frax_high_risk: Optional[Tuple[float, float]] = None) -> Tuple[pd.DataFrame, np.ndarray, Dict]:
    """
    Load a cohort CSV into features and endpoint labels.

    :param source: path or file-like object for the CSV
    :param entry_criteria_met: assume rows were screened into the general pathway
    :type entry_criteria_met: bool
    :param dxa_recent: assume recorded T-scores come from a DXA within 2 years
    :type dxa_recent: bool
    :param frax_high_risk: FRAX thresholds that set a blank ``highRisk``, or None
    :type frax_high_risk: tuple or None
    :return: features, labels and a load report (rejections, assumptions, label counts)
    :rtype: tuple[pandas.DataFrame, numpy.ndarray, dict]
    :raises ValueError: if no column matches a Facts field or alias
    """
    df =pd.read_csv(source)
    mapped = {FIELD_BY_NAME[c] for c in df.columns if c in FIELD_BY_NAME}
    if not mapped:
        raise ValueError(f"No recognised columns; found {list(df.columns)}.")
    info: Dict = {
        "rows_read": len(df),
        "unused_columns": [c for c in df.columns if c not in FIELD_BY_NAME and c != TARGET],
        "facts_not_in_csv": [f for f in Facts.model_fields if f not in mapped
                             and not (f == "T_score" and mapped & set(SITE_T_SCORES))],
        "assumptions": {"entry_criteria_met": entry_criteria_met, "dxa_recent": dxa_recent,
                        "frax_high_risk_thresholds": frax_high_risk},
        "label_source": "csv" if TARGET in df.columns else "rules",
    }

    rows, labels, rejected = [], [], 0
    for record in df.to_dict(orient="records"):
        try:
            facts = Facts(**canonical(record))
        except ValidationError:
            rejected += 1
            continue
        facts, _ = fill_gaps(facts, entry_criteria_met, dxa_recent, frax_high_risk)
        label = clean(record[TARGET]) if TARGET in df.columns else evaluate(facts).endpoint
        if label is None:
            rejected += 1
            continue
        rows.append(to_row(facts))
        labels.append(str(label))

    X, y = pd.DataFrame(rows, columns=FEATURES), np.array(labels, dtype=object)
    counts = pd.Series(y).value_counts()
    info.update(rows_rejected=rejected, rows_used=len(y), label_counts=counts.to_dict(),
                invariant_violations=invariant_violations(X, y))
    undecided = counts.get("NEEDS_MORE_INFORMATION", 0) / max(len(y), 1)
    if undecided > 0.5:
        info["warning"] = f"{undecided:.0%} of rows are NEEDS_MORE_INFORMATION; see facts_not_in_csv."
    return X, y, info


def build_pipeline(n_estimators: int = 200, seed: int = SEED, oob_score: bool = False) -> Pipeline:
    """
    Sentinel imputer (with missing-value indicators) followed by a balanced random forest.

    :param n_estimators: number of trees
    :type n_estimators: int
    :param seed: random state
    :type seed: int
    :param oob_score: compute the out-of-bag score while fitting
    :type oob_score: bool
    :return: an unfitted pipeline
    :rtype: sklearn.pipeline.Pipeline
    """
    return Pipeline([
        ("imputer", SimpleImputer(strategy="constant", fill_value=MISSING_SENTINEL, add_indicator=True,
                                  keep_empty_features=True)),
        ("forest", RandomForestClassifier(
            n_estimators=n_estimators, max_depth=18, min_samples_leaf=3, class_weight="balanced",
            oob_score=oob_score, random_state=seed, n_jobs=-1)),
    ])


def wrec(y_true, y_pred) -> float:
    """
    Weighted Risk-Error Cost: mean per-patient penalty. An anabolic-eligible patient
    given an antiresorptive-only endpoint costs 5.0; any other error costs 1.0.

    :param y_true: guideline endpoints
    :param y_pred: predicted endpoints
    :return: mean cost per patient (0.0 is perfect)
    :rtype: float
    """
    y_true, y_pred = np.asarray(y_true), np.asarray(y_pred)
    under = np.isin(y_true, list(ANABOLIC)) & np.isin(y_pred, list(ANTIRESORPTIVE_ONLY))
    return float(np.where(y_true == y_pred, 0.0, np.where(under, UNDERTREATMENT_COST, 1.0)).mean())


class TreatmentModel:
    """Trained forest plus model card; both are optional so the API runs without a model."""

    def __init__(self, model_path: Path, card_path: Path):
        """
        :param model_path: joblib pipeline file; ignored if it doesn't exist
        :type model_path: pathlib.Path
        :param card_path: model card JSON; ignored if it doesn't exist
        :type card_path: pathlib.Path
        """
        model_path, card_path = Path(model_path), Path(card_path)
        self.pipeline = joblib.load(model_path) if model_path.exists() else None
        self.card = json.loads(card_path.read_text()) if card_path.exists() else {}

    @property
    def loaded(self) -> bool:
        """
        :return: True when a pipeline was loaded
        :rtype: bool
        """
        return self.pipeline is not None

    def opinion(self, facts: Facts, guideline_endpoint: str) -> Optional[dict]:
        """
        Predict an endpoint, pass it through the safety guardrail and compare it with the guideline.

        :param facts: patient facts (after gap filling)
        :type facts: Facts
        :param guideline_endpoint: the rule engine's endpoint
        :type guideline_endpoint: str
        :return: the model opinion, or None when no model is loaded
        :rtype: dict or None
        """
        if self.pipeline is None:
            return None
        proba = self.pipeline.predict_proba(to_frame([facts]))[0]
        k = int(np.argmax(proba))
        raw = str(self.pipeline.classes_[k])
        final, reason = intercept(raw, facts.eGFR, facts.historyMiOrStroke)
        return {"endpoint": final, "raw_endpoint": raw, "confidence": round(float(proba[k]), 4),
                "agrees_with_guideline": final == guideline_endpoint, "safety_override": reason,
                "model_version": self.card.get("model_version")}
