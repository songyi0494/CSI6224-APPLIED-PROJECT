import os
import joblib
import pandas as pd
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import OneHotEncoder
from sklearn.compose import ColumnTransformer
from sklearn.pipeline import Pipeline
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import classification_report, roc_auc_score

DATA_PATH = os.path.join(os.path.dirname(__file__), "..", "data", "osteoporosis.csv")
MODEL_OUT = os.path.join(os.path.dirname(__file__), "osteoporosis_rf_v1.joblib")

def train():
    if not os.path.exists(DATA_PATH):
        raise FileNotFoundError(f"Dataset missing at {DATA_PATH}. Place your CSV there first.")

    df = pd.read_csv(DATA_PATH)
    
    # Target variable
    y = df["Osteoporosis"].astype(int)
    
    # Features (drop ID and target)
    X = df.drop(columns=["Id", "Osteoporosis"])

    numeric_cols = ["Age"]
    categorical_cols = [c for c in X.columns if c not in numeric_cols]

    preprocessor = ColumnTransformer(
        transformers=[
            ("num", "passthrough", numeric_cols),
            ("cat", OneHotEncoder(handle_unknown="ignore", sparse_output=False), categorical_cols)
        ]
    )

    clf = Pipeline(steps=[
        ("preprocessor", preprocessor),
        ("classifier", RandomForestClassifier(n_estimators=150, max_depth=8, random_state=42))
    ])

    X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42, stratify=y)
    
    clf.fit(X_train, y_train)
    y_pred = clf.predict(X_test)
    y_prob = clf.predict_proba(X_test)[:, 1]

    print("\n--- Pipeline 2: Exploratory ML Benchmark ---")
    print(classification_report(y_test, y_pred))
    print(f"ROC-AUC Score: {roc_auc_score(y_test, y_prob):.4f}")

    joblib.dump(clf, MODEL_OUT)
    print(f"Shadow model artifacts successfully saved -> {MODEL_OUT}\n")

if __name__ == "__main__":
    train()