"""Contraindication guardrail applied to every model prediction before anyone sees it."""

import logging
import math
from typing import Optional, Tuple

import numpy as np
import pandas as pd
from sklearn.base import BaseEstimator, ClassifierMixin, clone
from sklearn.utils.validation import check_is_fitted

from cdss.core.config import RENAL_EGFR_MIN, TERIPARATIDE_EGFR_MIN
from cdss.core.guidelines import ROMOSOZUMAB_FIRST, ZOLEDRONIC_FIRST

logger = logging.getLogger("cdss.safety")


def _known(x) -> bool:
    return x is not None and not (isinstance(x, float) and math.isnan(x))


def _egfr_at_least(egfr, floor: float) -> bool:
    # Unknown eGFR fails closed
    return _known(egfr) and egfr >= floor


def intercept(endpoint: str, egfr, mi_stroke) -> Tuple[str, Optional[str]]:
    """Return (final endpoint, reason it was changed or None)."""
    if endpoint in ZOLEDRONIC_FIRST and not _egfr_at_least(egfr, RENAL_EGFR_MIN):
        return "SPECIALIST_RENAL", f"Zoledronic acid needs eGFR ≥ {RENAL_EGFR_MIN:.0f} (recorded: {egfr})."
    if endpoint == "P2_TERIPARATIDE" and not _egfr_at_least(egfr, TERIPARATIDE_EGFR_MIN):
        return "SPECIALIST_RENAL", f"Teriparatide needs eGFR ≥ {TERIPARATIDE_EGFR_MIN:.0f} (recorded: {egfr})."
    if endpoint not in ROMOSOZUMAB_FIRST:
        return endpoint, None

    if not _known(mi_stroke):
        # Pathway 1 referrals already tell the clinic to confirm no MI or stroke
        if endpoint == "P2_ROMOSOZUMAB":
            return "SPECIALIST_SAFETY_REVIEW", "MI or stroke history not recorded; romosozumab can't be cleared."
        return endpoint, None
    if not mi_stroke:
        return endpoint, None
    if endpoint == "P2_ROMOSOZUMAB" and _egfr_at_least(egfr, TERIPARATIDE_EGFR_MIN):
        return "P2_TERIPARATIDE", "Prior MI or stroke: romosozumab contraindicated, teriparatide substituted."
    return "SPECIALIST_SAFETY_REVIEW", "Prior MI or stroke: romosozumab contraindicated."


class ClinicalSafetyWrapper(BaseEstimator, ClassifierMixin):
    """Wraps a classifier; X must carry eGFR and historyMiOrStroke."""

    def __init__(self, estimator):
        self.estimator = estimator

    def fit(self, X, y):
        self.estimator_ = clone(self.estimator).fit(X, y)
        self.classes_ = np.union1d(self.estimator_.classes_, ["SPECIALIST_RENAL", "SPECIALIST_SAFETY_REVIEW"])
        return self

    def predict(self, X: pd.DataFrame) -> np.ndarray:
        check_is_fitted(self, "estimator_")
        raw = self.estimator_.predict(X).astype(object)
        final, records = raw.copy(), []
        for i, (p, egfr, mi) in enumerate(zip(raw, X["eGFR"], X["historyMiOrStroke"])):
            final[i], reason = intercept(p, egfr, mi)
            if reason:
                records.append({"row": X.index[i], "model": p, "final": final[i], "reason": reason})
                logger.warning("Safety override row=%s: %s -> %s (%s)", X.index[i], p, final[i], reason)
        self.overrides_ = pd.DataFrame(records, columns=["row", "model", "final", "reason"])
        return final
