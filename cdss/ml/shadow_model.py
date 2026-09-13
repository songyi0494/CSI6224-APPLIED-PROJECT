import os
import joblib
import pandas as pd
from typing import Dict, Any
from cdss.schemas import PatientClinicalInput

MODEL_PATH = os.path.join(os.path.dirname(__file__), "osteoporosis_rf_v1.joblib")


class ShadowClassifier:
    def __init__(self):
        self.model = None
        if os.path.exists(MODEL_PATH):
            try:
                self.model = joblib.load(MODEL_PATH)
            except Exception as e:
                print(f"Failed to load shadow ML artifact: {e}")

    def evaluate_shadow(self, patient: PatientClinicalInput) -> Dict[str, Any]:
        if not self.model:
            return {
                "status": "UNAVAILABLE",
                "note": "Model artifact not trained yet. Run train_shadow.py."
            }

        # Build inference frame aligned with training column layout
        inference_row = {
            "Age": patient.age,
            "Gender": "Female" if patient.gender == "F" else "Male",
            "Hormonal Changes": "Postmenopausal" if (patient.gender == "F" and patient.age >= 50) else "Normal",
            "Family History": "Yes",
            "Race/Ethnicity": "Caucasian",
            "Body Weight": "Normal",
            "Calcium Intake": "Low",
            "Vitamin D Intake": "Insufficient",
            "Physical Activity": "Sedentary",
            "Smoking": "No",
            "Alcohol Consumption": "Moderate",
            "Medical Conditions": "None",
            "Medications": "None" if patient.treatment_history.is_treatment_naive else "Bisphosphonates",
            "Prior Fractures": "Yes" if patient.fracture_history.has_minimal_trauma_fracture else "No"
        }

        df_inf = pd.DataFrame([inference_row])
        prob = float(self.model.predict_proba(df_inf)[0][1])
        prediction = int(self.model.predict(df_inf)[0])

        return {
            "status": "ACTIVE_SHADOW",
            "ml_predicted_osteoporosis": bool(prediction == 1),
            "ml_risk_probability": round(prob, 4),
            "telemetry_role": "Exploratory shadow benchmarking only (does not override deterministic rules)"
        }