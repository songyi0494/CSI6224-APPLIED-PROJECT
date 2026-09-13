import json
from fastapi import FastAPI, WebSocket, WebSocketDisconnect, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware

from cdss.schemas import PatientClinicalInput, CDSSRecommendationOutput
from cdss.engine.pipeline import FSFHGPipeline
from cdss.ml.shadow_model import ShadowClassifier

app = FastAPI(
    title="FSFHG Osteoporosis Clinical Decision Support System",
    version="1.0.0",
    description="Dual-pipeline CDSS: Primary deterministic FSFHG rule engine with exploratory ML shadow telemetry."
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


@app.get("/health", tags=["System"])
def health_check():
    return {
        "status": "OPERATIONAL",
        "primary_engine": "FSFHG_RULE_BASED_DETERMINISTIC_V1",
        "shadow_ml_pipeline": shadow_engine.model is not None
    }


@app.post(
    "/api/v1/evaluate",
    response_model=CDSSRecommendationOutput,
    status_code=status.HTTP_200_OK,
    tags=["Clinical Decision Support"]
)
def evaluate_case(patient: PatientClinicalInput):
    """
    Primary clinical decision endpoint.
    Evaluates patient parameters against FSFHG pathway rules and computes shadow ML metrics.
    """
    try:
        recommendation = pipeline_engine.evaluate(patient)
        # Compute secondary shadow ML metrics
        recommendation.shadow_ml_metrics = shadow_engine.evaluate_shadow(patient)
        return recommendation
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Deterministic CDSS evaluation failed: {str(e)}"
        )


@app.websocket("/ws/clinical-stream")
async def clinical_decision_socket(websocket: WebSocket):
    """
    Duplex WebSocket connection for real-time clinician dashboard updates
    and step-by-step reasoning trace logging.
    """
    await websocket.accept()
    try:
        while True:
            raw_data = await websocket.receive_text()
            payload = json.loads(raw_data)

            # Validate input against schema
            patient = PatientClinicalInput(**payload)

            # Evaluate deterministic rules
            rec = pipeline_engine.evaluate(patient)
            rec.shadow_ml_metrics = shadow_engine.evaluate_shadow(patient)

            # Emit structured recommendation trace
            await websocket.send_text(rec.model_dump_json())
    except WebSocketDisconnect:
        pass
    except Exception as exc:
        await websocket.send_text(json.dumps({"error": f"Socket processing failure: {str(exc)}"}))
        await websocket.close()