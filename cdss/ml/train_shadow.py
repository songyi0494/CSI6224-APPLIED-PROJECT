import os
import joblib
import numpy as np
import pandas as pd
from sklearn.compose import ColumnTransformer
from sklearn.ensemble import RandomForestClassifier
from sklearn.impute import SimpleImputer
from sklearn.metrics import (
    brier_score_loss,
    classification_report,
    confusion_matrix,
    roc_auc_score,
)
from sklearn.model_selection import train_test_split
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder

# Resolve canonical paths relative to current script
CURRENT_DIR = os.path.dirname(os.path.abspath(__file__))
DATA_PATH = os.path.abspath(os.path.join(CURRENT_DIR, "..", "data", "osteoporosis.csv"))
MODEL_OUT = os.path.join(CURRENT_DIR, "osteoporosis_rf_v1.joblib")


def load_and_prep_data(data_path: str):
    """Loads CSV and separates target and features safely."""
    if not os.path.exists(data_path):
        raise FileNotFoundError(
            f"Dataset missing at: {data_path}. Ensure 'osteoporosis.csv' is placed under 'cdss/data/'."
        )

    df = pd.read_csv(data_path)

    # Identify target column (case-insensitive search)
    target_col = None
    for col in df.columns:
        if col.strip().lower() == "osteoporosis":
            target_col = col
            break

    if not target_col:
        raise KeyError("Could not find 'Osteoporosis' target column in CSV dataset.")

    y = df[target_col].astype(int)

    # Remove non-predictive identifiers or target column
    cols_to_drop = [target_col]
    for id_candidate in ["Id", "id", "ID", "PatientID", "patient_id"]:
        if id_candidate in df.columns:
            cols_to_drop.append(id_candidate)

    X = df.drop(columns=cols_to_drop)
    return X, y


def train():
    print(f"Loading clinical dataset from: {DATA_PATH}")
    X, y = load_and_prep_data(DATA_PATH)

    print(f"Dataset summary: {X.shape[0]} patient samples across {X.shape[1]} features.")
    print(f"Osteoporosis class balance: {np.mean(y):.2%} positive prevalence.")

    # Identify numerical vs categorical columns
    numeric_cols = [c for c in X.columns if pd.api.types.is_numeric_dtype(X[c])]
    categorical_cols = [c for c in X.columns if c not in numeric_cols]

    print(f"Numerical features ({len(numeric_cols)}): {numeric_cols}")
    print(f"Categorical features ({len(categorical_cols)}): {categorical_cols}")

    # Robust preprocessor with imputers to guarantee zero runtime NaN crashes
    num_pipeline = Pipeline(steps=[
        ("imputer", SimpleImputer(strategy="median")),
    ])

    cat_pipeline = Pipeline(steps=[
        ("imputer", SimpleImputer(strategy="most_frequent")),
        ("encoder", OneHotEncoder(handle_unknown="ignore", sparse_output=False)),
    ])

    preprocessor = ColumnTransformer(
        transformers=[
            ("num", num_pipeline, numeric_cols),
            ("cat", cat_pipeline, categorical_cols),
        ]
    )

    # Classifier pipeline with balanced weights for clinical stratification
    clf = Pipeline(steps=[
        ("preprocessor", preprocessor),
        (
            "classifier",
            RandomForestClassifier(
                n_estimators=200,
                max_depth=8,
                min_samples_split=5,
                min_samples_leaf=2,
                class_weight="balanced",
                random_state=42,
                n_jobs=-1,
            ),
        ),
    ])

    # Stratified 80/20 train/test split
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42, stratify=y
    )

    print("\nTraining Shadow Random Forest classifier...")
    clf.fit(X_train, y_train)

    # Evaluate predictions
    y_pred = clf.predict(X_test)
    y_prob = clf.predict_proba(X_test)[:, 1]

    roc_auc = roc_auc_score(y_test, y_prob)
    brier = brier_score_loss(y_test, y_prob)

    print("\n=======================================================")
    print("      Pipeline 2: Exploratory ML Shadow Benchmark     ")
    print("=======================================================")
    print(f"ROC-AUC Score: {roc_auc:.4f}")
    print(f"Brier Loss:    {brier:.4f}")
    print("\nConfusion Matrix:")
    print(confusion_matrix(y_test, y_pred))
    print("\nClassification Report:")
    print(classification_report(y_test, y_pred, digits=4))

    # Top Feature Importance Diagnostics
    try:
        classifier = clf.named_steps["classifier"]
        feature_names = clf.named_steps["preprocessor"].get_feature_names_out()
        importances = classifier.feature_importances_
        sorted_indices = np.argsort(importances)[::-1][:10]

        print("Top 10 Influential Clinical Features in Model:")
        for rank, idx in enumerate(sorted_indices, start=1):
            clean_name = feature_names[idx].replace("cat__", "").replace("num__", "")
            print(f"  {rank:2d}. {clean_name:30s} : {importances[idx]:.4f}")
    except Exception as exc:
        print(f"Note: Could not compute feature importances: {exc}")

    # Persist artifact
    os.makedirs(os.path.dirname(MODEL_OUT), exist_ok=True)
    joblib.dump(clf, MODEL_OUT)
    print(f"\n[OK] Model successfully serialized to:\n  -> {MODEL_OUT}\n")


if __name__ == "__main__":
    train()