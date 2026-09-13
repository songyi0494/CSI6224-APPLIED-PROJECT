import os
import uuid
from datetime import datetime
from typing import Any, Dict, List
import firebase_admin
from firebase_admin import auth, credentials
from fastapi import Depends, FastAPI, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel

from engine import ClinicalInputPayload, DecisionResult, run_fsfhg_engine

# --- Initialize Firebase Admin SDK ---
cred_path = os.getenv("FIREBASE_CREDENTIALS_PATH", "serviceAccountKey.json")
if not firebase_admin._apps:
    cred = credentials.Certificate(cred_path)
    firebase_admin.initialize_app(cred)

security = HTTPBearer()

app = FastAPI(
    title="FSFHG Decision Support API (Firebase Auth)",
    description="Clinical guideline engine secured by Firebase ID tokens.",
    version="2.1.0"
)

# In-memory store (keyed by Firebase UID)
db = {
    "questionnaires": {},
    "responses": {},
    "recommendations": {},
    "feedbacks": {},
}

# --- Generic Schemas ---
class QuestionnaireSchema(BaseModel):
    title: str
    questions: List[Dict[str, Any]]

class ResponseSchema(BaseModel):
    questionnaire_id: str
    answers: Dict[str, Any]

class FeedbackSchema(BaseModel):
    recommendation_id: str
    rating: int
    comment: str = ""

# --- Firebase Token Verification Dependency ---
def get_current_user(res: HTTPAuthorizationCredentials = Depends(security)) -> Dict[str, Any]:
    """
    Verifies the Firebase ID token sent in the Authorization header (Bearer <token>).
    Returns the decoded Firebase token claims (including 'uid' and 'email').
    """
    token = res.credentials
    try:
        decoded_token = auth.verify_id_token(token)
        return decoded_token
    except auth.ExpiredIdTokenError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Firebase ID token has expired."
        )
    except auth.InvalidIdTokenError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid Firebase ID token."
        )
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"Authentication failed: {str(e)}"
        )

# 1. Identity / User Info Endpoint
@app.get("/auth/me")
def get_user_profile(current_user: Dict[str, Any] = Depends(get_current_user)):
    """Returns the authenticated Firebase user profile details."""
    return {
        "uid": current_user.get("uid"),
        "email": current_user.get("email"),
        "email_verified": current_user.get("email_verified", False)
    }

# 2. Questionnaire Endpoints (Create / Edit / View / Delete)
@app.post("/questionnaires")
def create_questionnaire(data: QuestionnaireSchema, user: Dict[str, Any] = Depends(get_current_user)):
    q_id = str(uuid.uuid4())
    record = {"id": q_id, "user_id": user["uid"], **data.model_dump()}
    db["questionnaires"][q_id] = record
    return record

@app.get("/questionnaires/{q_id}")
def get_questionnaire(q_id: str, user: Dict[str, Any] = Depends(get_current_user)):
    item = db["questionnaires"].get(q_id)
    if not item or item["user_id"] != user["uid"]:
        raise HTTPException(status_code=404, detail="Questionnaire not found")
    return item

@app.put("/questionnaires/{q_id}")
def edit_questionnaire(q_id: str, data: QuestionnaireSchema, user: Dict[str, Any] = Depends(get_current_user)):
    item = db["questionnaires"].get(q_id)
    if not item or item["user_id"] != user["uid"]:
        raise HTTPException(status_code=404, detail="Questionnaire not found")
    item.update(data.model_dump())
    return item

@app.delete("/questionnaires/{q_id}")
def delete_questionnaire(q_id: str, user: Dict[str, Any] = Depends(get_current_user)):
    item = db["questionnaires"].get(q_id)
    if not item or item["user_id"] != user["uid"]:
        raise HTTPException(status_code=404, detail="Questionnaire not found")
    del db["questionnaires"][q_id]
    return {"status": "deleted"}

# 3. Response Endpoints (Save / View)
@app.post("/responses")
def save_response(data: ResponseSchema, user: Dict[str, Any] = Depends(get_current_user)):
    r_id = str(uuid.uuid4())
    record = {"id": r_id, "user_id": user["uid"], **data.model_dump()}
    db["responses"][r_id] = record
    return record

@app.get("/responses/{r_id}")
def get_response(r_id: str, user: Dict[str, Any] = Depends(get_current_user)):
    res = db["responses"].get(r_id)
    if not res or res["user_id"] != user["uid"]:
        raise HTTPException(status_code=404, detail="Response not found")
    return res

# 4. JSON Import / Export Endpoints
@app.get("/export/{resource_type}")
def export_json(resource_type: str, user: Dict[str, Any] = Depends(get_current_user)):
    if resource_type not in ["questionnaires", "responses"]:
        raise HTTPException(status_code=400, detail="Invalid resource type")
    return [v for v in db[resource_type].values() if v["user_id"] == user["uid"]]

@app.post("/import/{resource_type}")
def import_json(resource_type: str, items: List[Dict[str, Any]], user: Dict[str, Any] = Depends(get_current_user)):
    if resource_type not in ["questionnaires", "responses"]:
        raise HTTPException(status_code=400, detail="Invalid resource type")
    for item in items:
        new_id = str(uuid.uuid4())
        db[resource_type][new_id] = {"id": new_id, "user_id": user["uid"], **item}
    return {"imported": len(items)}

# 5. Decision Support Endpoint
@app.post("/decision-support/recommendation", response_model=DecisionResult)
def create_recommendation(payload: ClinicalInputPayload, user: Dict[str, Any] = Depends(get_current_user)):
    rec_id = str(uuid.uuid4())
    result = run_fsfhg_engine(payload)
    
    record = {
        "recommendation_id": rec_id,
        "response_id": payload.response_id,
        "user_id": user["uid"],
        "pathway_evaluated": result["pathway"],
        "recommendation_text": result["text"],
        "action_type": result["action_type"],
        "safety_fallback": result["safety_fallback"],
        "reasoning_trace": result["trace"],
        "evaluated_at": datetime.utcnow()
    }
    db["recommendations"][rec_id] = record
    return record

# 6. Feedback Endpoint
@app.post("/feedback")
def save_feedback(data: FeedbackSchema, user: Dict[str, Any] = Depends(get_current_user)):
    fb_id = str(uuid.uuid4())
    record = {"id": fb_id, "user_id": user["uid"], **data.model_dump()}
    db["feedbacks"][fb_id] = record
    return record