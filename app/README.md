# OsteoCare Pathway Flutter app

See [core workflow setup and acceptance](../docs/core_workflow.md). Local debug runs default to MockAppRepository when APP_MODE is omitted; mock mode is self-contained and uses a local Dart evaluator. Set APP_MODE explicitly to mock or supabase for deterministic demonstrations and integration checks. Production/release builds require an explicit APP_MODE and must not rely on an implicit mock repository.

## Flutter UI Review

### Mock mode

```bash
cd app
flutter pub get
flutter run -d chrome --dart-define=APP_MODE=mock
```

Mock mode requires no Supabase credentials.

### Live mode configuration

Live mode targets the Songyi Supabase project `cwxxumfmvmspofouqxxh` and
requires configuration through compile-time dart-defines:

```text
APP_MODE=supabase
SUPABASE_URL
SUPABASE_PUBLISHABLE_KEY
```

Do not commit live credential values. Pre-review patient withdrawal is
intentionally unavailable in live mode until the backend provides an atomic
withdrawal/resubmission contract.
