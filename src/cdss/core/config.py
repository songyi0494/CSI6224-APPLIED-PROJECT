"""
Central configuration: file paths, clinical thresholds and environment settings.

Every clinical cut-off used by the guideline engine and the safety guardrail lives
here so a threshold change happens in one place. Runtime settings (Supabase
credentials, CORS origins, model paths) are read from environment variables once
and cached.

:author: Jonathan Gurusinghe
ECU ID: 10658547

References:
    - FSFHG osteoporosis treatment Pathways 1 and 2 (unit-supplied clinical
      guideline): renal gate, T-score and frailty thresholds.
    - Rockwood K. et al. (2005). A global clinical measure of fitness and frailty
      in elderly people. CMAJ, 173(5), 489-495 (Clinical Frailty Scale).
    - FRAX fracture risk assessment tool, University of Sheffield:
      https://frax.shef.ac.uk/FRAX/
    - Python docs, dataclasses and functools.lru_cache:
      https://docs.python.org/3/library/dataclasses.html
      https://docs.python.org/3/library/functools.html#functools.lru_cache


"""

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
    """
    Read an environment variable, tolerating stray whitespace and quotes from .env files.

    :param name: environment variable name
    :type name: str
    :param default: value used when the variable is unset
    :type default: str
    :return: the cleaned value
    :rtype: str
    """
    return os.getenv(name, default).strip().strip("'\"")


@dataclass(frozen=True)
class Settings:
    """
    Immutable runtime settings, populated from the environment at construction time.

    :ivar supabase_url: Supabase project URL
    :ivar supabase_key: Supabase service role key
    :ivar cors_origins: extra allowed CORS origins (localhost is always allowed)
    :ivar model_path: path to the trained joblib pipeline
    :ivar model_card_path: path to the model card JSON
    :ivar confidence_floor: model confidence below which a review reason is added
    """

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
        """
        :return: True when both the Supabase URL and key are set
        :rtype: bool
        """
        return bool(self.supabase_url and self.supabase_key)


@lru_cache
def get_settings() -> Settings:
    """
    Build the settings once per process.

    :return: the cached settings instance
    :rtype: Settings
    """
    return Settings()
