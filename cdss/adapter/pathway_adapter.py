"""
PostgreSQL & Supabase Adapter for CDSS Evaluations.
Bridges incoming Flutter facts to database entity records in 'pathway_evaluations'.
"""

import uuid
from datetime import datetime, timezone
from typing import Dict, Any
from cdss.schemas import EvaluationEnvelope


def format_evaluation_for_database(
    assessment_id: str,
    assessment_revision: int,
    envelope: EvaluationEnvelope,
    rule_version: str = "FSFHG-v2.2"
) -> Dict[str, Any]:
    """
    Transforms EvaluationEnvelope into a record matching the pathway_evaluations table schema:
    id (uuid), assessment_id (text), assessment_revision (int4), pathway (text),
    decision (text), rule_version (text), actions (jsonb), reasoning_trace (jsonb),
    missing_inputs (jsonb), warnings (jsonb), created_at (timestamptz).
    """
    return {
        "id": str(uuid.uuid4()),
        "assessment_id": assessment_id,
        "assessment_revision": assessment_revision,
        "pathway": envelope.pathway,
        "decision": envelope.decision,
        "rule_version": rule_version,
        "routing_reason": f"Evaluated under deterministic {envelope.pathway} rules",
        "actions": [action.model_dump() for action in envelope.actions],
        "reasoning_trace": envelope.trace,
        "missing_inputs": {},
        "warnings": [],
        "created_at": datetime.now(timezone.utc).isoformat()
    }