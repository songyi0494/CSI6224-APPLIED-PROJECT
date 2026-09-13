import logging
import os
from typing import Any, Dict, Optional
import joblib
import pandas as pd
from cdss.schemas import PatientClinicalInput

logger = logging.getLogger("CDSS.ShadowModel")

MODEL_PATH = os.path.join(os.path.dirname(__file__), "osteoporosis_rf_v1.joblib")


class ShadowClassifier:
    """Exploratory ML Shadow Model for risk screening and telemetry concordance."""

    def __init__(self, model_path: str = MODEL_PATH):
        self.model_path = model_path
        self.model = self._load_model()

    def _load_model(self) -> Optional[Any]:
        if os.path.exists(self.model_path):
            try:
                clf = joblib.load(self.model_path)
                logger.info(f"Loaded shadow ML artifact from {self.model_path}")
                return clf
            except Exception as e:
                logger.warning(f"Failed to load shadow ML artifact: {e}")
                return None
        logger.info(f"Shadow ML artifact not found at {self.model_path}. Operating in safe telemetry fallback mode.")
        return None

    def _map_patient_to_training_df(self, patient: PatientClinicalInput) -> pd.DataFrame:
        gender_val = "Female" if str(patient.sex).lower() == "female" else "Male"
        hormonal_changes = "Postmenopausal" if (gender_val == "Female" and patient.postmenopausal) else "Normal"
        has_prior_fx = "Yes" if (patient.minimal_trauma_fracture or patient.fractures_in_last_24_months > 0) else "No"

        features = {
            "Age": [patient.age],
            "Gender": [gender_val],
            "Hormonal Changes": [hormonal_changes],
            "Family History": ["No"],
            "Race/Ethnicity": ["Caucasian"],
            "Body Weight": ["Normal"],
            "Calcium Intake": ["Adequate"],
            "Vitamin D Intake": ["Adequate"],
            "Physical Activity": ["Sedentary" if patient.clinical_frailty_score >= 5 else "Active"],
            "Smoking": ["No"],
            "Alcohol Consumption": ["Moderate"],
            "Medical Conditions": ["None"],
            "Medications": ["None"],
            "Prior Fractures": [has_prior_fx],
        }
        return pd.DataFrame(features)

    def evaluate_shadow(
        self, patient: PatientClinicalInput, deterministic_action: Optional[str] = None
    ) -> Dict[str, Any]:
        if self.model is None:
            return {
                "shadow_pipeline_active": False,
                "model_version": "unavailable",
                "predicted_risk_score": None,
                "predicted_risk_tier": "UNAVAILABLE",
                "concordant_with_rules": None,
                "telemetry_note": "Shadow model binary not loaded. Deterministic evaluation unaffected.",
            }

        try:
            input_df = self._map_patient_to_training_df(patient)
            probs = self.model.predict_proba(input_df)
            prob_positive = float(probs[0, 1])

            if prob_positive >= 0.65:
                risk_tier = "HIGH_RISK"
            elif prob_positive >= 0.35:
                risk_tier = "MODERATE_RISK"
            else:
                risk_tier = "LOW_RISK"

            concordance = None
            if deterministic_action:
                high_intervention_actions = [
                    "INITIATE_THERAPY",
                    "INITIATE_DENOSUMAB",
                    "ESCALATE_ANABOLIC",
                ]
                rules_intervene = deterministic_action in high_intervention_actions
                ml_flags_high_risk = prob_positive >= 0.50
                concordance = rules_intervene == ml_flags_high_risk

            return {
                "shadow_pipeline_active": True,
                "model_version": "random_forest_v1",
                "predicted_risk_score": round(prob_positive, 4),
                "predicted_risk_tier": risk_tier,
                "concordant_with_rules": concordance,
                "telemetry_note": "Logged for shadow telemetry audit.",
            }
        except Exception as exc:
            logger.error(f"Error during shadow inference: {exc}")
            return {
                "shadow_pipeline_active": False,
                "model_version": "random_forest_v1_error",
                "predicted_risk_score": None,
                "predicted_risk_tier": "ERROR",
                "concordant_with_rules": None,
                "telemetry_note": f"Inference failure: {str(exc)}",
            }