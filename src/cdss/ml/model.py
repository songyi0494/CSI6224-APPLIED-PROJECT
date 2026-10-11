"""
Random forest pipeline, the dense feature encoding it shares between training
and inference, and the CSV loader.

CSV columns are matched to Facts by field name or alias. Labels come from an
`endpoint` column when present, otherwise from the guideline engine. Facts the
CSV lacks stay unknown unless an assumption is switched on; each assumption is
recorded in the load report.
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
    row = {name: _num(getattr(f, name)) for name in NUMERIC + BOOLEAN}
    row["sex_female"] = math.nan if f.sex is None else float(f.sex == "female")
    row["site_excluded"] = _num(excluded_site(f.fractureSite))
    return row


def to_frame(facts: List[Facts]) -> pd.DataFrame:
    return pd.DataFrame([to_row(f) for f in facts], columns=FEATURES)


def invariant_violations(X: pd.DataFrame, y: np.ndarray) -> Dict[str, int]:
    """Labels that break an FSFHG safety invariant; always 0 for rule-derived labels."""
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
    df = pd.read_csv(source)
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
    """
    y_true, y_pred = np.asarray(y_true), np.asarray(y_pred)
    under = np.isin(y_true, list(ANABOLIC)) & np.isin(y_pred, list(ANTIRESORPTIVE_ONLY))
    return float(np.where(y_true == y_pred, 0.0, np.where(under, UNDERTREATMENT_COST, 1.0)).mean())


class TreatmentModel:
    def __init__(self, model_path: Path, card_path: Path):
        model_path, card_path = Path(model_path), Path(card_path)
        self.pipeline = joblib.load(model_path) if model_path.exists() else None
        self.card = json.loads(card_path.read_text()) if card_path.exists() else {}

    @property
    def loaded(self) -> bool:
        return self.pipeline is not None

    def opinion(self, facts: Facts, guideline_endpoint: str) -> Optional[dict]:
        if self.pipeline is None:
            return None
        proba = self.pipeline.predict_proba(to_frame([facts]))[0]
        k = int(np.argmax(proba))
        raw = str(self.pipeline.classes_[k])
        final, reason = intercept(raw, facts.eGFR, facts.historyMiOrStroke)
        return {"endpoint": final, "raw_endpoint": raw, "confidence": round(float(proba[k]), 4),
                "agrees_with_guideline": final == guideline_endpoint, "safety_override": reason,
                "model_version": self.card.get("model_version")}
