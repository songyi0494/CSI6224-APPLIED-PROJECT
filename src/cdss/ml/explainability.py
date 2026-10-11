"""SHAP TreeExplainer on the forest inside the pipeline, ranked into a feature importance chart."""

from pathlib import Path

import matplotlib

matplotlib.use("Agg")

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import shap
from sklearn.pipeline import Pipeline


def explain(pipeline: Pipeline, X: pd.DataFrame, out_path: Path, top: int = 15) -> pd.DataFrame:
    imputer, forest = pipeline.named_steps["imputer"], pipeline.named_steps["forest"]
    names = imputer.get_feature_names_out(X.columns)
    values = shap.TreeExplainer(forest)(imputer.transform(X)).values
    # Multi-class SHAP is (rows, features, classes); average |impact| over rows and classes
    impact = np.abs(values).mean(axis=(0, 2) if values.ndim == 3 else 0)
    ranked = (pd.DataFrame({"feature": names, "mean_abs_shap": impact.round(4)})
              .sort_values("mean_abs_shap", ascending=False).head(top).reset_index(drop=True))

    fig, ax = plt.subplots(figsize=(8, 0.4 * len(ranked) + 1.5))
    ax.barh(ranked["feature"][::-1], ranked["mean_abs_shap"][::-1], color="#3b6ea8")
    ax.set_xlabel("Mean |SHAP value| across endpoints")
    ax.set_title("Top clinical features")
    fig.tight_layout()
    fig.savefig(out_path, dpi=150)
    plt.close(fig)
    return ranked
