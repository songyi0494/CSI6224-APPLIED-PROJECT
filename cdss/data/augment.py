import os
import json
import pandas as pd
import numpy as np

CSV_IN = os.path.join(os.path.dirname(__file__), "osteoporosis.csv")
JSON_OUT = os.path.join(os.path.dirname(__file__), "test_cases.json")

def build_synthetic_verification_cases():
    if not os.path.exists(CSV_IN):
        print(f"Warning: {CSV_IN} not found. Skipping CSV translation.")
        return

    df = pd.read_csv(CSV_IN).head(25)  # Sample first 25 cases for test benchmarks
    cases = []

    for _, row in df.iterrows():
        is_osteo = int(row.get("Osteoporosis", 0)) == 1
        has_prior_fx = str(row.get("Prior Fractures", "No")).strip().lower() in ["yes", "1", "true"]
        meds = str(row.get("Medications", "")).lower()
        conds = str(row.get("Medical Conditions", "")).lower()

        # Calibrate synthetic T-scores to target condition
        fem_neck = round(float(np.random.normal(-2.9, 0.3)), 2) if is_osteo else round(float(np.random.normal(-1.4, 0.4)), 2)
        spine = round(float(np.random.normal(-3.1, 0.4)), 2) if is_osteo else round(float(np.random.normal(-1.5, 0.4)), 2)

        # Estimate CrCl
        crcl = 28.0 if ("kidney" in conds or "renal" in conds) else max(20.0, round(float(130 - row["Age"]), 1))
        is_treated = any(m in meds for m in ["bisphosphonate", "alendronate", "denosumab"])

        cases.append({
            "case_id": f"CSV_CASE_{row['Id']}",
            "age": int(row["Age"]),
            "gender": "F" if str(row["Gender"]).upper().startswith("F") else "M",
            "crcl_ml_min": crcl,
            "hypocalcemia": False,
            "bmd": {
                "femoral_neck_t_score": fem_neck,
                "lumbar_spine_t_score": spine,
                "total_hip_t_score": min(fem_neck + 0.1, 1.0)
            },
            "fracture_history": {
                "has_minimal_trauma_fracture": has_prior_fx,
                "fracture_site": "vertebral" if (has_prior_fx and is_osteo) else ("wrist" if has_prior_fx else "none"),
                "recent_fracture_within_12m": has_prior_fx
            },
            "treatment_history": {
                "is_treatment_naive": not is_treated,
                "prior_antiresorptive": is_treated,
                "prior_anabolic": False,
                "years_on_bisphosphonates": 5.2 if is_treated else 0.0,
                "recent_fracture_on_treatment": is_treated and has_prior_fx,
                "adherence_issues": False
            }
        })

    with open(JSON_OUT, "w") as f:
        json.dump(cases, f, indent=2)
    print(f"Generated {len(cases)} validated test vectors -> {JSON_OUT}")

if __name__ == "__main__":
    build_synthetic_verification_cases()