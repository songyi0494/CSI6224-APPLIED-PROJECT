"""
Unified CDSS Routing Pipeline.
Directs incoming patient-reported facts and clinical investigations
to the appropriate deterministic pathway.
"""

from typing import Dict, Any
from cdss.schemas import Pathway1Facts, Pathway2Facts, EvaluationEnvelope
from cdss.engine.pathway_1 import evaluate_pathway_1
from cdss.engine.pathway_2 import evaluate_pathway_2


def run_cdss_pipeline(payload: Dict[str, Any]) -> EvaluationEnvelope:
    """
    Parses facts payload and executes the deterministic clinical engine.
    """
    is_pre_treated = payload.get("osteoporosisTreatmentStatus", False)

    if is_pre_treated:
        p2_facts = Pathway2Facts(**payload)
        return evaluate_pathway_2(p2_facts)
    else:
        p1_facts = Pathway1Facts(**payload)
        return evaluate_pathway_1(p1_facts)