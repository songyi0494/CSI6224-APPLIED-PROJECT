# OsteoCare Pathway Flutter app

See [core workflow setup and acceptance](../docs/core_workflow.md). Local debug runs default to MockAppRepository when APP_MODE is omitted; mock mode is self-contained and uses a local Dart evaluator. Set APP_MODE explicitly to mock or supabase for deterministic demonstrations and integration checks. Production/release builds require an explicit APP_MODE and must not rely on an implicit mock repository.
