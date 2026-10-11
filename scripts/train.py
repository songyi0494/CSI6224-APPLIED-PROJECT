"""
Train the advisory random forest on a cohort CSV and write the model card.

    python scripts/train.py
    python scripts/train.py --csv data/patients.csv --entry-criteria-met --assume-dxa-recent --min-class-rows 2
"""

import argparse
import json
from pathlib import Path

import joblib
import matplotlib

matplotlib.use("Agg")

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from sklearn.ensemble import RandomForestClassifier
from sklearn.impute import SimpleImputer
from sklearn.metrics import ConfusionMatrixDisplay, classification_report, f1_score, recall_score
from sklearn.model_selection import StratifiedKFold, train_test_split
from sklearn.pipeline import Pipeline

from cdss.core.config import (
    COHORT_PATH,
    FIGURES,
    GUIDELINE_VERSION,
    MIN_CLASS_ROWS,
    MODEL_CARD_PATH,
    MODEL_PATH,
    MODEL_VERSION,
    PLATEAU_TOL,
    SEED,
)
from cdss.core.guidelines import ANABOLIC, ANTIRESORPTIVE_ONLY
from cdss.ml.explainability import explain
from cdss.ml.model import FEATURES, MISSING_SENTINEL, load_csv, wrec
from cdss.ml.safety_wrapper import ClinicalSafetyWrapper

SHAP_ROWS = 500
N_ESTIMATORS_GRID = (50, 100, 200, 300, 500)


def build_rf_pipeline(n_estimators: int, seed: int = SEED, oob_score: bool = True) -> Pipeline:
    """Constructs an end-to-end clinical inference pipeline."""
    return Pipeline([
        ("imputer", SimpleImputer(
            strategy="constant",
            fill_value=MISSING_SENTINEL,
            add_indicator=True,
            keep_empty_features=True,  # Suppresses warning and preserves all-NaN clinical columns
        )),
        ("forest", RandomForestClassifier(
            n_estimators=n_estimators,
            max_depth=18,
            min_samples_leaf=3,
            class_weight="balanced_subsample",
            oob_score=oob_score,
            random_state=seed,
            n_jobs=-1,
        )),
    ])


def plot_comparison_curve(grid: dict, chosen_n: int, save_path: Path) -> None:
    """Plots and saves the OOB Error vs. Macro-F1 comparison curve across all n_estimators."""
    trees = sorted(grid.keys())
    oob_errors = [grid[n]["oob_error"] for n in trees]
    macro_f1s = [grid[n]["macro_f1"] for n in trees]

    fig, ax1 = plt.subplots(figsize=(8, 5))
    ax2 = ax1.twinx()

    line1 = ax1.plot(trees, oob_errors, marker="o", color="tab:red", lw=2, label="OOB Error")
    line2 = ax2.plot(trees, macro_f1s, marker="s", color="tab:blue", lw=2, label="CV Macro-F1")

    # Mark the chosen plateau size
    vline = ax1.axvline(chosen_n, color="gray", linestyle="--", label=f"Selected (n={chosen_n})")

    ax1.set_xlabel("n_estimators (Number of Trees)")
    ax1.set_ylabel("OOB Generalization Error", color="tab:red")
    ax2.set_ylabel("Cross-Validation Macro-F1", color="tab:blue")
    ax1.tick_params(axis="y", labelcolor="tab:red")
    ax2.tick_params(axis="y", labelcolor="tab:blue")

    lines = line1 + line2 + [vline]
    labels = [line.get_label() for line in lines]
    ax1.legend(lines, labels, loc="best")
    plt.title("Random Forest n_estimators Convergence & Performance Sweep")

    fig.tight_layout()
    fig.savefig(save_path, dpi=150)
    plt.close(fig)


def cross_validate(X: pd.DataFrame, y: np.ndarray):
    """Sweep N_ESTIMATORS_GRID with stratified CV and return the smallest forest on the plateau."""
    n_splits = max(2, min(5, pd.Series(y).value_counts().min()))
    splits = list(StratifiedKFold(n_splits=n_splits, shuffle=True, random_state=SEED).split(X, y))
    folds = np.zeros(len(y), dtype=int)
    for k, (_, val) in enumerate(splits):
        folds[val] = k

    grid = {}
    for n in N_ESTIMATORS_GRID:
        pred = np.empty(len(y), dtype=object)
        oob_errors, f1s = [], []
        for tr, val in splits:
            pipe = build_rf_pipeline(n, oob_score=True).fit(X.iloc[tr], y[tr])
            pred[val] = pipe.predict(X.iloc[val])

            # Explicit subtraction
            oob_val = getattr(pipe.named_steps["forest"], "oob_score_", np.nan)
            oob_errors.append(1.0 - oob_val if not np.isnan(oob_val) else 1.0)
            f1s.append(f1_score(y[val], pred[val], average="macro", zero_division=0))

        grid[n] = {
            "oob_error": float(np.nanmean(oob_errors)),
            "macro_f1": float(np.nanmean(f1s)),
            "pred": pred,
        }

    valid_oob = [g["oob_error"] for g in grid.values() if not np.isnan(g["oob_error"])]
    valid_f1 = [g["macro_f1"] for g in grid.values() if not np.isnan(g["macro_f1"])]
    best_oob = min(valid_oob) if valid_oob else 1.0
    best_f1 = max(valid_f1) if valid_f1 else 0.0

    plateau = [
        n for n, g in grid.items()
        if g["oob_error"] <= best_oob + PLATEAU_TOL and g["macro_f1"] >= best_f1 - PLATEAU_TOL
    ]
    chosen = min(plateau) if plateau else max(grid, key=lambda n: grid[n]["macro_f1"])

    # Terminal Comparison Output
    comparison_records = [
        {
            "n_estimators": n,
            "OOB Error": round(stats["oob_error"], 4),
            "Macro-F1": round(stats["macro_f1"], 4),
            "OOB Accuracy": round(1.0 - stats["oob_error"], 4),
            "Status": "<- SELECTED" if n == chosen else "",
        }
        for n, stats in sorted(grid.items())
    ]
    comparison_df = pd.DataFrame(comparison_records)
    print("\n" + "=" * 55)
    print("      n_estimators Model Hyperparameter Comparison")
    print("=" * 55)
    print(comparison_df.to_string(index=False))
    print("=" * 55 + "\n")

    return chosen, grid, folds


def fold_report(y: np.ndarray, pred: np.ndarray, folds: np.ndarray) -> list:
    rows = []
    for k in np.unique(folds):
        m = folds == k
        cost = wrec(y[m], pred[m])
        rows.append({
            "fold": int(k),
            "wrec": round(cost, 4),
            "risk_penalty": round(cost * m.sum(), 1),
            "weighted_recall": round(recall_score(y[m], pred[m], average="weighted", zero_division=0), 4),
            "anabolic_undertreated": int(
                (np.isin(y[m], list(ANABOLIC)) & np.isin(pred[m], list(ANTIRESORPTIVE_ONLY))).sum()
            ),
        })
    return rows


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--csv", type=Path, default=COHORT_PATH)
    parser.add_argument("--entry-criteria-met", action="store_true",
                        help="rows were screened into the general pathway")
    parser.add_argument("--assume-dxa-recent", action="store_true",
                        help="recorded T-scores come from a DXA within 2 years")
    parser.add_argument("--frax-high-risk", type=float, nargs=2, metavar=("MOF", "HIP"),
                        help="FRAX % thresholds that set highRisk when it is blank")
    parser.add_argument("--min-class-rows", type=int, default=MIN_CLASS_ROWS,
                        help="drop endpoints with fewer rows than this")
    args = parser.parse_args()

    X, y, info = load_csv(
        args.csv,
        args.entry_criteria_met,
        args.assume_dxa_recent,
        tuple(args.frax_high_risk) if args.frax_high_risk else None,
    )
    if "warning" in info:
        print(info["warning"])
    if any(info["invariant_violations"].values()):
        raise SystemExit(f"Labels break FSFHG safety invariants: {info['invariant_violations']}")

    counts = pd.Series(y).value_counts()
    dropped = counts[counts < args.min_class_rows].to_dict()
    keep = ~pd.Series(y).isin(list(dropped)).to_numpy()
    X, y = X[keep].reset_index(drop=True), y[keep]
    if pd.Series(y).nunique() < 2:
        raise SystemExit(f"Need 2+ endpoints with {args.min_class_rows}+ rows each; got {counts.to_dict()}")
    if dropped:
        print(f"Dropped sparse endpoints: {dropped}")

    # Explicit multiplication: 0.2 * len(y)
    test_size = max(int(round(0.2 * len(y))), pd.Series(y).nunique())
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=test_size, stratify=y, random_state=SEED
    )
    n_estimators, grid, folds = cross_validate(X_train, y_train)

    FIGURES.mkdir(parents=True, exist_ok=True)
    plot_comparison_curve(grid, n_estimators, FIGURES / "oob_convergence_curve.png")

    model = ClinicalSafetyWrapper(build_rf_pipeline(n_estimators, oob_score=True)).fit(X_train, y_train)
    pipeline = model.estimator_
    raw, final = pipeline.predict(X_test), model.predict(X_test)
    print(f"Final Model: n_estimators={n_estimators}, trained on {len(y_train)} rows\n")
    print(classification_report(y_test, raw, zero_division=0))

    disp = ConfusionMatrixDisplay.from_predictions(
        y_test, raw, normalize="true", values_format=".2f", xticks_rotation=45, cmap="Blues"
    )
    disp.figure_.set_size_inches(10, 9)
    disp.figure_.tight_layout()
    disp.figure_.savefig(FIGURES / "confusion_matrix.png", dpi=150)
    plt.close(disp.figure_)

    sample = X_test.sample(min(SHAP_ROWS, len(X_test)), random_state=SEED)
    top_features = explain(pipeline, sample, FIGURES / "feature_importance.png")

    MODEL_PATH.parent.mkdir(parents=True, exist_ok=True)
    joblib.dump(pipeline, MODEL_PATH, compress=3)

    forest_step = pipeline.named_steps["forest"]
    card = {
        "model_version": MODEL_VERSION,
        "guideline_version": GUIDELINE_VERSION,
        "data": {**info, "source": str(args.csv), "classes_dropped": dropped},
        "features": FEATURES,
        "classes": [str(c) for c in pipeline.classes_],
        "n_estimators": n_estimators,
        "oob_error": round(1.0 - forest_step.oob_score_, 4),
        "cv_comparison": {n: {k: round(v, 4) for k, v in g.items() if k != "pred"} for n, g in grid.items()},
        "cv_folds": fold_report(y_train, grid[n_estimators]["pred"], folds),
        "holdout": {
            "rows": len(y_test),
            "macro_f1": round(float(f1_score(y_test, raw, average="macro")), 4),
            "wrec": round(wrec(y_test, raw), 4),
            "wrec_after_guardrail": round(wrec(y_test, final), 4),
            "safety_overrides": len(model.overrides_),
        },
        "top_features": top_features.to_dict(orient="records"),
    }
    MODEL_CARD_PATH.write_text(json.dumps(card, indent=2))
    print(json.dumps(card["holdout"], indent=2))
    print(f"{MODEL_PATH}\n{MODEL_CARD_PATH}")


if __name__ == "__main__":
    main()