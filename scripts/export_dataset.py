"""
Generate the synthetic training cohort and label it with the guideline engine.

Continuous facts come from a Gaussian copula (as in SDV's GaussianCopula),
binary facts from prior rates. Every row is marked as screened into the
pathway so all branches are reachable.

    python scripts/export_dataset.py

Change SAMPLES, SEED or OUT below to generate a different cohort.

:author: Jonathan Gurusinghe
ECU ID: 10658547

References:
    - Patki, N., Wedge, R. & Veeramachaneni, K. (2016). The Synthetic Data Vault.
      IEEE DSAA, 399-410; GaussianCopula approach in SDV:
      https://github.com/sdv-dev/SDV (the method was followed; no SDV code is used)
    - SciPy docs, truncnorm and norm:
      https://docs.scipy.org/doc/scipy/reference/generated/scipy.stats.truncnorm.html
    - NumPy docs, Generator.multivariate_normal:
      https://numpy.org/doc/stable/reference/random/generated/numpy.random.Generator.multivariate_normal.html

AI assistance: generated initial code from gemini for synethetic dataset /Users/jonathangurusinghe/Desktop/Personal/Education/ECU/CSI6224/Project/osteoporosis-cdss/artifacts/figures/Screenshot 2026-10-13 at 08.40.36.png
"""

from pathlib import Path

import numpy as np
import pandas as pd
from scipy.stats import norm, truncnorm

from cdss.core.config import COHORT_PATH, SEED
from cdss.core.guidelines import Facts, evaluate
from cdss.ml.model import TARGET

SAMPLES = 30000
OUT = COHORT_PATH

# Assumed values for a WA minimal-trauma fracture cohort. Replace with fracture
# liaison audit or registry data before reading anything into the distributions.
CONTINUOUS = {
    "eGFR": dict(mean=62.0, sd=20.0, low=8.0, high=120.0),
    "femoralNeckTscore": dict(mean=-2.7, sd=0.9, low=-5.5, high=1.5),
    "clinicalFrailtyScore": dict(mean=4.0, sd=1.7, low=1.0, high=9.0, integer=True),
    "lifeExpectancy": dict(mean=11.0, sd=5.0, low=0.5, high=30.0),
    "FRAX10YmajorOsteoporoticFractureRiskPercent": dict(mean=18.0, sd=10.0, low=1.0, high=80.0),
}
CORRELATION = [
    [1.0, 0.1, -0.25, 0.3, -0.15],
    [0.1, 1.0, -0.15, 0.1, -0.55],
    [-0.25, -0.15, 1.0, -0.6, 0.3],
    [0.3, 0.1, -0.6, 1.0, -0.25],
    [-0.15, -0.55, 0.3, -0.25, 1.0],
]
BINARY = {
    "osteoporosisTreatmentStatus": 0.4,
    "testAvailability": 0.85,
    "testWithinLast2Years": 0.6,
    "clinicalRiskFactors": 0.5,
    "cognitiveImpairment": 0.12,
    "knownPoorMedicationAdherence": 0.12,
    "recentFractureWithin2Y": 0.6,
    "historyOf2orMoreFractures": 0.3,
    "hipVertebralOrMultipleFracturesInLast24M": 0.4,
    "historyMiOrStroke": 0.25,
    "highRisk": 0.2,
}
# Pathway 2 cascade answers, only filled for treated patients
TREATED = {
    "onAntiresorptiveTherapy": 0.92,
    "onAntiresorptiveGt12m": 0.8,
    "medicationAdherent": 0.8,
    "symptomaticFractureLast12m": 0.85,
}
MISSING_RATE = 0.015


def _marginal(spec: dict):
    """
    Truncated normal for one continuous fact.

    :param spec: mean, sd, low and high for the fact
    :type spec: dict
    :return: frozen scipy distribution
    """
    a, b = (spec["low"] - spec["mean"]) / spec["sd"], (spec["high"] - spec["mean"]) / spec["sd"]
    return truncnorm(a, b, loc=spec["mean"], scale=spec["sd"])


def generate(n: int, seed: int = SEED) -> pd.DataFrame:
    """
    Sample an unlabelled synthetic cohort.

    :param n: number of patients
    :type n: int
    :param seed: random seed
    :type seed: int
    :return: one row per patient, with about 1.5% of cells blanked
    :rtype: pandas.DataFrame
    """
    rng =np.random.default_rng(seed)
    u = norm.cdf(rng.multivariate_normal(np.zeros(len(CONTINUOUS)), np.array(CORRELATION), size=n))
    df = pd.DataFrame({col: _marginal(spec).ppf(u[:, j]) for j, (col, spec) in enumerate(CONTINUOUS.items())})
    for col, spec in CONTINUOUS.items():
        if spec.get("integer"):
            df[col] = df[col].round().astype(int)

    fn = df["femoralNeckTscore"]
    df["hipTscore"] = np.clip(fn + rng.normal(0.3, 0.3, n), -5.5, 1.5)
    df["lumbarSpineTscore"] = np.clip(fn + rng.normal(0.2, 0.4, n), -5.5, 1.5)
    mof = df["FRAX10YmajorOsteoporoticFractureRiskPercent"]
    df["FRAX10YmajorHipFractureRiskPercent"] = np.clip(0.25 * mof + rng.normal(0, 1.0, n), 0.1, 60)
    df = df.round({"eGFR": 1, "femoralNeckTscore": 1, "hipTscore": 1, "lumbarSpineTscore": 1,
                   "lifeExpectancy": 1, "FRAX10YmajorOsteoporoticFractureRiskPercent": 1,
                   "FRAX10YmajorHipFractureRiskPercent": 1})

    for col, p in BINARY.items():
        df[col] = rng.random(n) < p
    df["liveInResidentialCare"] = rng.random(n) < np.where(df["clinicalFrailtyScore"] >= 7, 0.35, 0.05)
    df["entryCriteriaMet"] = True
    treated = df["osteoporosisTreatmentStatus"].to_numpy()
    for col, p in TREATED.items():
        df[col] = np.where(treated, rng.random(n) < p, None)
    df["historyMiOrStroke"] = np.where(treated, df["historyMiOrStroke"], None)

    df = df.astype(object)
    return df.mask(rng.random(df.shape) < MISSING_RATE)


def main(samples: int = SAMPLES, seed: int = SEED, out: Path = OUT) -> None:
    """
    Generate, label with the guideline engine and write the cohort CSV.

    :param samples: number of patients
    :type samples: int
    :param seed: random seed
    :type seed: int
    :param out: output CSV path
    :type out: pathlib.Path
    """
    df = generate(samples, seed)
    df[TARGET] = [evaluate(Facts.model_validate(row)).endpoint for row in df.to_dict(orient="records")]
    out = Path(out)
    out.parent.mkdir(parents=True, exist_ok=True)
    df.to_csv(out, index=False)
    print(f"{len(df)} rows -> {out}")
    print(df[TARGET].value_counts().to_string())


if __name__ == "__main__":
    main()
