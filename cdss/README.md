# CDSS Pipeline — Implementation Documentation

**Repository:** `songyi0494/CSI6224-APPLIED-PROJECT`  
**Branch reviewed:** `feature/cdss-pipeline`  
**Scope:** the Python/FastAPI clinical decision-support implementation under `cdss/`, plus the separate root-level API.

## 1. Purpose and scope

This branch provides a Python clinical decision-support system (CDSS) for osteoporosis management. Its primary evaluator is a deterministic, rule-based pipeline with two treatment routes:

- **Pathway 1:** treatment-naïve patients after minimal-trauma fracture.
- **Pathway 2:** patients previously treated for osteoporosis who present with a subsequent fracture.

The branch also contains a random-forest **shadow model**. The model produces risk telemetry and does not control the deterministic recommendation.

The code includes a compatibility endpoint intended to consume the Flutter application's historical `facts` payload and return its four-key recommendation envelope. It is a prototype and not suitable for clinical deployment in its reviewed state.

## 2. Architecture

```text
Flutter-compatible facts payload
  └─ PathwayCompatibilityAdapter
       └─ PatientClinicalInput (Pydantic validation)
            └─ FSFHGPipeline
                 ├─ global renal safety gate
                 ├─ Pathway 1 deterministic rules
                 └─ Pathway 2 deterministic rules
            └─ CDSSRecommendationOutput
                 ├─ Flutter four-key envelope
                 └─ optional shadow-model telemetry
```

`cdss/main.py` exposes the intended FastAPI service:

| Endpoint | Purpose |
| --- | --- |
| `GET /health` | Returns service and shadow-model availability. |
| `POST /api/v1/evaluate` | Accepts the internal typed request and returns rich domain output plus shadow metrics. |
| `POST /api/v1/evaluate_pathway_1` | Accepts `{"facts": {...}}` and returns the Flutter-compatible envelope. |

There is also a separate root-level `main.py` that attempts to expose Firebase-authenticated questionnaire, response, recommendation, and feedback endpoints using an in-memory dictionary. It is not integrated with the `cdss/` service and imports an `engine` module that is not present at the repository root. Treat it as an incomplete/legacy API, not the deployable CDSS entry point.

## 3. Input model and safety gate

`PatientClinicalInput` validates basic fields including age (18–120), sex, treatment status, renal markers, frailty score, T-score, and fracture counts. The pipeline runs the renal gate before either pathway:

- Missing renal data → `NO_DECISION`, safety fallback, clinician review required.
- eGFR below 30 → specialist/nephrology referral and clinician review required.
- eGFR 30 or above → routing to Pathway 1 or Pathway 2.

The code aliases eGFR and creatinine clearance: when only one is supplied, it copies its value to the other. This avoids a missing-field error but is not a clinically valid conversion and must be replaced by an approved data contract.

## 4. Deterministic rule behaviour

### Pathway 1

After the renal gate, the current Pathway 1 rule sequence is:

1. Exclude fracture sites: hand, foot, face, ankle.
2. For residential aged care, Clinical Frailty Score ≥6, or life expectancy below 7 years: recommend denosumab.
3. For adherence/cognitive concerns: recommend parenteral/oral antiresorptive options.
4. For T-score ≤−2.5 plus a hip/vertebral fracture or at least two fractures in 24 months: consider osteoanabolic therapy and specialist review.
5. If DXA is impractical or T-score ≤−2.5: recommend standard antiresorptive options.
6. Otherwise: request DXA / no decision, with a safety fallback.

### Pathway 2

For previously treated patients, escalation requires all five conditions:

- antiresorptive treatment longer than 12 months;
- patient adherent;
- symptomatic fracture in the last 12 months;
- two or more lifetime fractures; and
- T-score ≤−3.0.

If all apply, the engine recommends specialist-referred anabolic escalation. A prior MI or stroke switches the stated option from romosozumab to teriparatide. If not all criteria apply, it recommends continuing or switching parenteral antiresorptive therapy.

Every output includes a structured rule trace, action classification, recommendation text, safety-fallback flag, and clinician-review flag.

## 5. Flutter compatibility adapter

`PathwayCompatibilityAdapter` maps camelCase Flutter facts to the typed Python input and translates a rich output to:

```json
{
  "pathway": "PATHWAY1",
  "decision": "action_taken",
  "actions": [{"type": "treatment", "recommendation": "…", "requireReview": false}],
  "trace": ["RULE_ID"]
}
```

It accepts string/numeric boolean values and derives `dxa_impractical` from `testAvailable` and `testWithinLast2Years`. On an exception, it returns a successful-looking fallback envelope directing the case to clinician review.

## 6. Shadow ML model

`ShadowClassifier` loads `osteoporosis_rf_v1.joblib`, a Random Forest trained from `cdss/data/osteoporosis.csv`. It maps the clinical input to a fixed set of training features, predicts a probability, groups it as low/moderate/high risk, and records whether that tier agrees with an intervention-oriented deterministic action.

The model is appropriately non-authoritative in the current design: its unavailable or failing state does not alter the deterministic recommendation. However, model provenance, clinical validation, bias evaluation, calibration evidence, version governance, and a telemetry/privacy policy are not documented.

## 7. Tests and developer setup

The repository contains two adapter-focused pytest tests:

- a frozen Flutter Pathway 1 example mapping to an osteoanabolic consideration;
- missing renal data returning a safety fallback.

No dependency manifest (`requirements.txt`, `pyproject.toml`, or lockfile), container configuration, runbook, or CI workflow is present. As a result, the exact reproducible environment and command to run tests/service are not defined in the repository. Expected direct dependencies include FastAPI, Uvicorn, Pydantic v2, Pandas, scikit-learn, joblib, and—only for the root API—Firebase Admin SDK.

## 8. Security and production gaps

| Finding | Why it matters |
| --- | --- |
| Intended CDSS API has no authentication or authorisation. | Any caller can invoke clinical recommendations and receive trace/output data. |
| CORS permits all origins, methods, and headers. | This is inappropriate for a clinical API; restrict to trusted client origins. |
| No persistence, audit trail, patient ownership, or clinician approval workflow exists in `cdss/`. | Recommendations cannot be associated securely with patients, reviewers, source facts, rule version, or a final clinician decision. |
| Adapter silently supplies defaults such as age 65, female sex, treatment-naïve status, and minimal-trauma fracture. | Missing data can become a substantive clinical assumption rather than a request for information. |
| Pathway 1 marks entry as passed without enforcing sex/age/postmenopausal/minimal-trauma eligibility. | Ineligible patients can reach treatment recommendations. |
| Adapter ignores `highRisk`, does not use a confirmed treatment-pathway decision, and collapses several missing/negative states. | The historical Flutter contract is not faithfully represented. |
| Error fallback returns HTTP 200 and includes exception text in the recommendation. | Clients cannot distinguish evaluation failure from a valid result; internal errors may be disclosed. |
| eGFR and creatinine clearance are copied between fields. | These measures are not interchangeable without an approved clinical method. |
| Root API is separate, in-memory, and appears non-runnable due to its unresolved `engine` import. | It provides no durable or reliable backend path. |
| ML training/artifact controls are absent. | The model cannot be safely governed, reproduced, or used beyond exploratory telemetry. |

## 9. Recommended remediation order

1. **Block clinical use** until a clinician validates all pathway definitions, thresholds, contraindications, drug wording, inputs, and units.
2. Remove silent adapter defaults. Require missing eligibility/clinical facts explicitly and return a typed `needs_more_information` result.
3. Implement and test Pathway 1 entry conditions before any treatment branch; formalise Pathway 2 entry/contraindications as well.
4. Add authenticated, authorised, server-side persistence with patient ownership, clinician review/approval, revision checks, and immutable audit records.
5. Restrict CORS, return meaningful 4xx/5xx responses, and ensure fallback messages never expose internal exceptions.
6. Select one API entry point and remove or repair the unintegrated root-level service.
7. Add a pinned dependency manifest, test command, lint/type checks, CI, and endpoint integration tests—including adverse, missing-data, and authorisation cases.
8. Keep the ML model isolated from treatment decisions until its dataset provenance, performance, calibration, bias, privacy, monitoring, and clinical governance are independently approved.

## 10. Review conclusion

The deterministic pipeline is clear, traceable, and sensibly keeps the ML component non-authoritative. It is a useful proof of concept for discussion and controlled development. However, the absent clinical eligibility checks, default-filled adapter inputs, unprotected API, lack of persistence/auditing, and incomplete developer packaging are critical blockers. This branch should not issue patient-specific recommendations or be deployed in a clinical environment until those issues are resolved and clinically validated.

## Key source locations

- `cdss/main.py`
- `cdss/schemas.py`
- `cdss/engine/pipeline.py`
- `cdss/engine/pathway_1.py`
- `cdss/engine/pathway_2.py`
- `cdss/adapter/pathway_adapter.py`
- `cdss/ml/shadow_model.py`
- `cdss/ml/train_shadow.py`
- `cdss/tests/test_p1_adapter.py`
- `main.py`
