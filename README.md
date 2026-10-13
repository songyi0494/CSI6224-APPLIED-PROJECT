# FSFHG Osteoporosis CDSS

FastAPI service that applies the WA FSFHG osteoporosis pathways to a Supabase case and adds a random forest second opinion behind a contraindication guardrail. The guideline result is authoritative; the model can only add review reasons. Every response requires clinician review.

## Layout

```
data/cohort.csv                    synthetic training cohort (generated)
data/patients.csv                  Supabase questionnaire export
artifacts/treatment_rf.joblib      trained pipeline
artifacts/model_card.json          metrics, parameters, data report
artifacts/figures/                 confusion_matrix.png, feature_importance.png
scripts/export_dataset.py          generates and labels the synthetic cohort
scripts/train.py                   trains the forest and writes the artifacts
src/cdss/core/config.py            paths, thresholds, env settings
src/cdss/core/guidelines.py        Facts schema and the FSFHG rule tables
src/cdss/ml/model.py               feature encoding, CSV loader, forest pipeline
src/cdss/ml/safety_wrapper.py      eGFR and MI/stroke overrides
src/cdss/ml/explainability.py      SHAP feature importance
src/cdss/api/main.py               app, CORS, /api/cases, /api/model, health checks
src/cdss/api/routes/recommendations.py
tests/test_rules.py                guideline rules, CSV loading, API
tests/test_safety.py               guardrail, missing-value sentinel, review flags
```

## Setup

Python 3.9+.

```bash
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt          # editable install with test extras
cp .env.example .env
```

## Run

```bash
python scripts/export_dataset.py
python scripts/train.py
uvicorn cdss.api.main:app --env-file .env
pytest
```

`train.py` stops if any label breaks an FSFHG safety invariant (anabolic without fracture or T ≤ −3.0, romosozumab after MI or stroke, zoledronic acid with eGFR < 35).

## Training on your own CSV

Columns are matched to `Facts` (`src/cdss/core/guidelines.py`) by name or alias:

| CSV column | Used as |
|---|---|
| `hipTscore`, `femoralNeckTscore`, `lumbarSpineTscore` | Lowest becomes `T_score` |
| `testAvailability` | `testAvailable` |
| `historyOf2orMoreFractures`, `multipleFractures` | `twoOrMoreFractures` |
| `antiresorptiveTreatmentStatus` | `onAntiresorptiveTherapy` |
| `antiresorptiveTreatmentDuration` | `onAntiresorptiveGt12m` |
| `adheredToTheTreatment` | `medicationAdherent` |
| `symptomaticFractureInLast12M` | `symptomaticFractureLast12m` |
| `lowBMD` | Pathway 2 "T-score −3.0 or lower?" when no T-score is recorded |
| `priorMIorStroke` | `historyMiOrStroke` |
| `FRAX10Y…Percent`, `clinicalRiskFactors`, `recentFractureWithin2Y` | Model features; no FSFHG rule reads them |

`sequencingFromDenosumab` is not used by any rule or by the model; when it is true and the endpoint is anabolic, a review note about rebound bone loss is added.

Labels come from an `endpoint` column if present, otherwise from the guideline engine. Facts missing from the CSV make the rules stop at `NEEDS_MORE_INFORMATION`; three opt-in settings at the top of `scripts/train.py` fill Pathway 1 gaps and are written to the model card:

| Setting | Fills | Valid when |
|---|---|---|
| `ENTRY_CRITERIA_MET = True` | Minimal trauma fracture, eligible site, postmenopausal woman or man ≥ 50 | The cohort was screened into the general pathway |
| `ASSUME_DXA_RECENT = True` | `testWithinLast2Years` for rows with a T-score | T-scores come from a DXA within 2 years |
| `FRAX_HIGH_RISK = (MOF, HIP)` | `highRisk` from FRAX (%) | Thresholds come from your local guideline |

Endpoints with fewer than 10 rows are dropped. A small export like `patients.csv` needs `MIN_ROWS` lowered, and the result is a smoke test, not a model. Set these in `scripts/train.py`, then run `python scripts/train.py`:

```python
CSV = PATIENTS_PATH
ENTRY_CRITERIA_MET = True
ASSUME_DXA_RECENT = True
MIN_ROWS = 2
```

## Getting a recommendation

Post the questionnaire columns as they are; blanks can be left out.

```bash
curl -s localhost:8000/api/recommendations -H 'Content-Type: application/json' -d '{
  "eGFR": 40, "hipTscore": -3.0, "femoralNeckTscore": -2.0, "lumbarSpineTscore": -2.0,
  "lifeExpectancy": 8, "clinicalFrailtyScore": 5, "testAvailability": true,
  "osteoporosisTreatmentStatus": false, "liveInResidentialCare": false,
  "knownPoorMedicationAdherence": false, "cognitiveImpairment": false,
  "hipVertebralOrMultipleFracturesInLast24M": false,
  "FRAX10YmajorOsteoporoticFractureRiskPercent": 20.0, "FRAX10YmajorHipFractureRiskPercent": 4.0
}'
```

The questionnaire never asks the Pathway 1 entry questions, the DXA date or clinician-assessed risk, so blanks in those are filled before the rules run (`ASSUME_SCREENED`, `ASSUME_DXA_RECENT`, `FRAX_HIGH_RISK` in `core/config.py`):

- untreated patients are taken as screened into the general pathway;
- recorded T-scores are taken as from a DXA within 2 years;
- `highRisk` is set when FRAX major osteoporotic ≥ 20% or hip ≥ 3%.

Every assumption applied is listed in the response's `assumptions` and adds a review reason. A recorded answer is never overwritten. If treatment status is blank but eGFR < 35, both pathways agree on renal referral, so that is returned.

## API

| Method | Path | Notes |
|---|---|---|
| GET | `/health` | Status, guideline version, model and Supabase state |
| GET | `/healthz` | Process is up |
| GET | `/readyz` | 503 unless the model is loaded and Supabase answers |
| GET | `/api/cases/{id}/recommendation` | Builds facts from the case's Supabase rows |
| POST | `/api/recommendations` | Evaluates a `Facts` body |
| GET | `/api/cases` | Rows of `clinical_cases` |
| GET | `/api/model` | Model card; 503 if no model is loaded |

## Case facts

The case route reads the case's rows and merges them into `Facts` (`case_facts` in `api/routes/recommendations.py`), later sources winning:

1. `profiles`: `sex` from `gender`, `age` from `date_of_birth`;
2. `questionnaire_responses.answers`: `sex`, `postmenopausal`, `minimalTraumaFracture`, and `excludedFractureSite` as a `fractureSite` description, with Yes/No mapped to booleans;
3. `clinical_cases.minimalTraumaFracture`;
4. the case's latest `investigations` row: `T_score`, `testAvailable`, and `testWithinLast2Years` from `test_date`;
5. `clinical_cases.clinician_facts`, whose keys are already `Facts` names or aliases.

## Safety guardrail

| Model predicts | Condition | Replaced with |
|---|---|---|
| Zoledronic-first endpoint | eGFR < 35 or unknown | `SPECIALIST_RENAL` |
| `P2_TERIPARATIDE` | eGFR < 30 or unknown | `SPECIALIST_RENAL` |
| `P2_ROMOSOZUMAB` | MI or stroke, eGFR ≥ 30 | `P2_TERIPARATIDE` |
| `P2_ROMOSOZUMAB` | MI or stroke with eGFR < 30, or history unknown | `SPECIALIST_SAFETY_REVIEW` |
| `P1_OSTEOANABOLIC_SPECIALIST` | MI or stroke recorded | `SPECIALIST_SAFETY_REVIEW` |

## Limits

- Rule-derived labels make the model's scores a measure of fidelity to the rules; clinician-recorded `endpoint` labels give it independent value.
- The cohort priors in `export_dataset.py` are assumed values, not audit or registry data.
- Software that recommends treatment may be regulated by the TGA as a medical device.
