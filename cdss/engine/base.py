from abc import ABC, abstractmethod
from typing import Optional
from cdss.schemas import PatientClinicalInput, RuleTrace

class BaseRule(ABC):
    def __init__(self, rule_id: str, pathway: str, priority: int, description: str):
        self.rule_id = rule_id
        self.pathway = pathway
        self.priority = priority  # Higher number indicates higher priority
        self.description = description

    @abstractmethod
    def evaluate(self, patient: PatientClinicalInput) -> Optional[RuleTrace]:
        pass