"""
FastAPI application entry point: app setup, CORS, case listing, model card and health check.

The recommendation endpoints live in ``routes/recommendations.py``; this module
wires them in and logs at startup if the model or Supabase is unavailable.

    uvicorn cdss.api.main:app --env-file .env

:author: Jonathan Gurusinghe
ECU ID: 10658547

References:
    - FastAPI docs, lifespan events, CORS, dependencies and APIRouter:
      https://fastapi.tiangolo.com/advanced/events/
      https://fastapi.tiangolo.com/tutorial/cors/
      https://fastapi.tiangolo.com/tutorial/dependencies/
      https://fastapi.tiangolo.com/tutorial/bigger-applications/
    - Supabase Python client docs: https://supabase.com/docs/reference/python/select

"""

import logging
from contextlib import asynccontextmanager
from typing import Any, Dict, List

from fastapi import APIRouter, Depends, FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware

from cdss import __version__
from cdss.api.routes import recommendations
from cdss.api.routes.recommendations import get_model, get_supabase, require_supabase
from cdss.core.config import GUIDELINE_VERSION, get_settings
from cdss.ml.model import TreatmentModel

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
logger = logging.getLogger("cdss.api")


@asynccontextmanager
async def lifespan(_: FastAPI):
    """
    Startup hook: warn (but keep serving) if the model or Supabase is missing.

    :param _: the application (unused)
    """
    settings = get_settings()
    if not get_model().loaded:
        logger.warning("No model at %s; run scripts/train.py. Guideline output is unaffected.", settings.model_path)
    if get_supabase() is None:
        logger.warning("Supabase not configured; case lookups return 503.")
    yield


app = FastAPI(title="Osteocare", version=__version__, lifespan=lifespan)
app.add_middleware(
    CORSMiddleware,
    allow_origins=get_settings().cors_origins,
    allow_origin_regex=r"^https?://(localhost|127\.0\.0\.1)(:\d+)?$",
    allow_methods=["GET", "POST"],
    allow_headers=["Content-Type"],
)

# /api/cases/{id}/recommendation and /api/recommendations live in routes/recommendations.py
api = APIRouter(prefix="/api", tags=["Clinical Decision Support"])


@api.get("/cases", response_model=List[Dict[str, Any]])
def list_cases(client: Any = Depends(require_supabase)) -> List[Dict[str, Any]]:
    """
    GET /api/cases: every row of ``clinical_cases``.

    :param client: Supabase client
    :return: case rows
    :rtype: list[dict]
    :raises HTTPException: 502 if the query fails
    """
    try:
        return client.table("clinical_cases").select("*").execute().data
    except Exception:
        logger.exception("Failed to list clinical cases")
        raise HTTPException(502, "Could not load cases.")


@api.get("/model")
def model_card(model: TreatmentModel = Depends(get_model)) -> Dict[str, Any]:
    """
    GET /api/model: the loaded model's card.

    :param model: the treatment model
    :type model: TreatmentModel
    :rtype: dict
    :raises HTTPException: 503 if no model is loaded
    """
    if not model.loaded:
        raise HTTPException(503, "Model not loaded.")
    return model.card


app.include_router(api)
app.include_router(recommendations.router)


@app.get("/health")
def health(model: TreatmentModel = Depends(get_model)) -> Dict[str, Any]:
    """
    GET /health: guideline version plus model and Supabase status.

    :param model: the treatment model
    :type model: TreatmentModel
    :rtype: dict
    """
    return {
        "status": "ok",
        "guideline_version": GUIDELINE_VERSION,
        "supabase_connected": get_supabase() is not None,
        "model_loaded": model.loaded,
        "model_version": model.card.get("model_version"),
    }



