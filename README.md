# OsteoCare Pathway

CSI6224 Applied Project — Flutter patient assessment and clinician review, backed by Supabase and a deterministic JSON rule engine.

- `app/`: Flutter UI, typed domain models, independent mock and Supabase repositories.
- `code/supabase/`: versioned baseline schema, RLS, guarded workflow RPCs and the authoritative Pathway 1 engine.
- `code/tests/`: executable rule, Edge-handler and PostgreSQL/RLS tests.
- `docs/core_workflow.md`: setup, migration boundaries, contracts, limitations and acceptance steps.

Read [the core workflow guide](docs/core_workflow.md) before running or deploying. The baseline is for a reviewed fresh schema and deliberately refuses existing core tables. Pathway 2 routes to manual review; its clinical rules are not integrated.

This implementation is a prototype requiring clinical contract validation and live environment acceptance. Local PostgreSQL and backend tests do not certify clinical correctness or demonstrate a deployed Flutter/Supabase workflow.
