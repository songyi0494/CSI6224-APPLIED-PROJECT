"""
FastAPI application for FSFHG Osteoporosis CDSS.
Fetches assessment facts from Supabase, evaluates rules in-memory, 
and returns the result without writing anything back to the database.
"""

import os
import logging
from typing import Dict, Any, Optional
from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException, status
from supabase import create_client, Client

from cdss.schemas import EvaluationEnvelope, Pathway1Facts, Pathway2Facts
from cdss.engine.pathway_1 import evaluate_pathway_1
from cdss.engine.pathway_2 import evaluate_pathway_2
from cdss.engine.pipeline import run_cdss_pipeline

load_dotenv()

SUPABASE_URL = os.getenv("SUPABASE_URL")
# You can use either the anon key or service role key; 
# the code below ONLY executes SELECT queries.
SUPABASE_KEY = os.getenv("SUPABASE_SERVICE_ROLE_KEY") or os.getenv("SUPABASE_ANON_KEY")

logger = logging.getLogger("cdss.readonly")

supabase: Optional[Client] = None
if SUPABASE_URL and SUPABASE_KEY:
    supabase = create_client(SUPABASE_URL, SUPABASE_KEY)
else:
    logger.warning("Supabase credentials missing. Supabase fetch endpoint will be disabled.")

app = FastAPI(
    title="FSFHG Osteoporosis CDSS Engine (Read-Only Mode)",
    version="2.2.0",
    description="Deterministic evaluation engine. Zero database writes."
)


@app.get("/health", status_code=status.HTTP_200_OK)
def health_check() -> Dict[str, Any]:
    return {
        "status": "healthy",
        "mode": "STRICTLY_READ_ONLY",
        "supabase_connected": supabase is not None
    }


# 1. Direct In-Memory Evaluation (No Database Connection Used)
@app.post("/evaluate/pathway1", response_model=EvaluationEnvelope)
def api_evaluate_pathway_1(facts: Pathway1Facts) -> EvaluationEnvelope:
    try:
        return evaluate_pathway_1(facts)
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"Rule evaluation error: {str(e)}"
        )


@app.post("/evaluate/pathway2", response_model=EvaluationEnvelope)
def api_evaluate_pathway_2(facts: Pathway2Facts) -> EvaluationEnvelope:
    try:
        return evaluate_pathway_2(facts)
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"Rule evaluation error: {str(e)}"
        )


@app.post("/evaluate", response_model=EvaluationEnvelope)
def api_evaluate_unified(payload: Dict[str, Any]) -> EvaluationEnvelope:
    try:
        return run_cdss_pipeline(payload)
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Pipeline processing failed: {str(e)}"
        )


# 2. Read-Only Fetch & Evaluate (Fetches from Supabase, does NOT save back)
@app.get("/evaluate/from-supabase/{assessment_id}", response_model=EvaluationEnvelope)
def evaluate_from_supabase_readonly(assessment_id: str) -> EvaluationEnvelope:
    if not supabase:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Supabase client is not configured."
        )

    try:
        # READ ONLY: Fetch facts and clinician_facts from public.assessments
        asm_response = supabase.table("assessments").select(
            "id, patient_id, revision, facts, clinician_facts"
        ).eq("id", assessment_id).single().execute()

        if not asm_response.data:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Assessment {assessment_id} not found."
            )

        assessment = asm_response.data
        patient_id = assessment.get("patient_id")

        # READ ONLY: Fetch sex and demographics from public.profiles
        profile_data = {}
        if patient_id:
            prof_response = supabase.table("profiles").select(
                "sex_at_birth, date_of_birth"
            ).eq("id", patient_id).single().execute()
            if prof_response.data:
                profile_data = prof_response.data

        # Merge fields in memory
        patient_facts = assessment.get("facts") or {}
        clinician_facts = assessment.get("clinician_facts") or {}

        payload: Dict[str, Any] = {
            **patient_facts,
            **clinician_facts,
        }

        if "sex" not in payload and "sex_at_birth" in profile_data:
            payload["sex"] = "female" if profile_data["sex_at_birth"] == "F" else "male"

        # Execute pure Python deterministic rule engine (Zero DB writes)
        return run_cdss_pipeline(payload)

    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to fetch assessment: {str(exc)}"
        )