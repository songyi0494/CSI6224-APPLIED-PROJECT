"""
Generate the synthetic training cohort and label it with the guideline engine.

Continuous facts come from a Gaussian copula (as in SDV's GaussianCopula),
binary facts from prior rates. Every row is marked as screened into the
pathway so all branches are reachable.

    python scripts/export_dataset.py --samples 30000 --seed 42
"""

import argparse
from pathlib import Path

import numpy as np
import pandas as pd
from scipy.stats import norm, truncnorm

from cdss.core.config import COHORT_PATH, SEED
from cdss.core.guidelines import Facts, evaluate
from cdss.ml.model import TARGET

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
    a, b = (spec["low"] - spec["mean"]) / spec["sd"], (spec["high"] - spec["mean"]) / spec["sd"]
    return truncnorm(a, b, loc=spec["mean"], scale=spec["sd"])


def generate(n: int, seed: int = SEED) -> pd.DataFrame:
    rng = np.random.default_rng(seed)
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


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--samples", type=int, default=30000)
    parser.add_argument("--seed", type=int, default=SEED)
    parser.add_argument("--out", type=Path, default=COHORT_PATH)
    args = parser.parse_args()

    df = generate(args.samples, args.seed)
    df[TARGET] = [evaluate(Facts.model_validate(row)).endpoint for row in df.to_dict(orient="records")]
    args.out.parent.mkdir(parents=True, exist_ok=True)
    df.to_csv(args.out, index=False)
    print(f"{len(df)} rows -> {args.out}")
    print(df[TARGET].value_counts().to_string())


if __name__ == "__main__":
    main()
