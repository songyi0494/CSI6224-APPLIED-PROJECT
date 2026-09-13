from typing import Any, Dict
from fastapi import FastAPI, HTTPException, WebSocket, WebSocketDisconnect, status
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

from cdss.adapter.pathway_adapter import PathwayCompatibilityAdapter
from cdss.engine.pipeline import FSFHGPipeline
from cdss.ml.shadow_model import ShadowClassifier
from cdss.schemas import CDSSRecommendationOutput, PatientClinicalInput

app = FastAPI(
    title="FSFHG Osteoporosis Clinical Decision Support System",
    version="1.1.0",
    description="Dual-pipeline CDSS: Primary deterministic FSFHG rule engine with isolated Flutter P1 compatibility adapter.",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

pipeline_engine = FSFHGPipeline()
shadow_engine = ShadowClassifier()


class FlutterFactsRequest(BaseModel):
    facts: Dict[str, Any]


@app.get("/health", tags=["System"])
def health_check():
    return {
        "status": "OPERATIONAL",
        "primary_engine": "FSFHG_RULE_BASED_DETERMINISTIC_V1",
        "shadow_ml_pipeline": shadow_engine.model is not None,
    }


@app.post(
    "/api/v1/evaluate",
    response_model=CDSSRecommendationOutput,
    status_code=status.HTTP_200_OK,
    tags=["Clinical Decision Support"],
)
def evaluate_case(patient: PatientClinicalInput):
    """Internal evaluation endpoint returning rich domain models and shadow telemetry."""
    try:
        recommendation = pipeline_engine.evaluate(patient)
        recommendation.shadow_ml_metrics = shadow_engine.evaluate_shadow(
            patient, deterministic_action=recommendation.action_type.value
        )
        return recommendation
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Deterministic CDSS evaluation failed: {str(e)}",
        )


@app.post(
    "/api/v1/evaluate_pathway_1",
    status_code=status.HTTP_200_OK,
    tags=["Frontend Integration Contract"],
)
def evaluate_pathway_1_contract(request: FlutterFactsRequest):
    """
    Contract-compatible endpoint for Flutter UI integration.
    Consumes camelCase 'facts' dictionary and returns the frozen 4-key JSON envelope.
    """
    try:
        patient_input = PathwayCompatibilityAdapter.flutter_facts_to_patient_input(request.facts)
        domain_output = pipeline_engine.evaluate(patient_input)
        return PathwayCompatibilityAdapter.cdss_output_to_flutter_envelope(domain_output)
    except Exception as exc:
        return PathwayCompatibilityAdapter.safe_error_fallback(str(exc))