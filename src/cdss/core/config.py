import os
from dataclasses import dataclass, field
from functools import lru_cache
from pathlib import Path
from typing import List

ROOT = Path(__file__).resolve().parents[3]
COHORT_PATH = ROOT / "data" / "cohort.csv"
PATIENTS_PATH = ROOT / "data" / "patients.csv"
ARTIFACTS = ROOT / "artifacts"
FIGURES = ARTIFACTS / "figures"
MODEL_PATH = ARTIFACTS / "treatment_rf.joblib"
MODEL_CARD_PATH = ARTIFACTS / "model_card.json"

SEED = 42
MODEL_VERSION = "treatment-rf-5.1.0"
GUIDELINE_VERSION = "fsfhg-pathways-1-2"

# FSFHG renal gate: CrCl/eGFR < 35 contraindicates zoledronic acid and oral bisphosphonates
RENAL_EGFR_MIN = 35.0
# Teriparatide is contraindicated in severe renal impairment (CrCl < 30)
TERIPARATIDE_EGFR_MIN = 30.0
OSTEOPOROTIC_T = -2.5
# PBS severe established osteoporosis
SEVERE_T = -3.0
# Rockwood CFS >= 6 routes to Branch A (denosumab, no BMD required)
FRAIL_CFS = 6
LIMITED_LIFE_YEARS = 7
MIN_MALE_AGE = 50

# The questionnaire only reaches patients already screened into the general pathway and never
# asks the entry questions, DXA date or clinician risk. These fill those gaps at recommendation
# time; every one applied is listed in the response.
ASSUME_SCREENED = True
ASSUME_DXA_RECENT = True
# FRAX 10-year risk (%) that sets a blank highRisk: (major osteoporotic, hip)
FRAX_HIGH_RISK = (20.0, 3.0)

CONFIDENCE_FLOOR = 0.70
UNDERTREATMENT_COST = 5.0
# Smallest forest whose mean OOB error and macro-F1 are both within this of the best
PLATEAU_TOL = 0.005
# StratifiedKFold(5) needs 5 rows per class; 10 leaves room for the hold-out split
MIN_CLASS_ROWS = 10


def _env(name: str, default: str = "") -> str:
    return os.getenv(name, default).strip().strip("'\"")


@dataclass(frozen=True)
class Settings:
    supabase_url: str = field(default_factory=lambda: _env("SUPABASE_URL"))
    supabase_key: str = field(default_factory=lambda: _env("SUPABASE_SERVICE_ROLE_KEY"))
    # Empty means only localhost origins are allowed
    cors_origins: List[str] = field(
        default_factory=lambda: [o.strip() for o in _env("CDSS_CORS_ORIGINS").split(",") if o.strip()])
    model_path: Path = field(default_factory=lambda: Path(_env("CDSS_MODEL_PATH", str(MODEL_PATH))))
    model_card_path: Path = field(default_factory=lambda: Path(_env("CDSS_MODEL_CARD_PATH", str(MODEL_CARD_PATH))))
    confidence_floor: float = field(default_factory=lambda: float(_env("CDSS_CONFIDENCE_FLOOR", str(CONFIDENCE_FLOOR))))

    @property
    def supabase_enabled(self) -> bool:
        return bool(self.supabase_url and self.supabase_key)


@lru_cache
def get_settings() -> Settings:
    return Settings()
