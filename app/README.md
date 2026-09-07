# CSI6224 Flutter App

Cross-platform Flutter prototype for the Secure Cross-Platform Patient Feedback and Clinical Decision Support System.

## Current Scope

- Patient and clinician role selection.
- Patient dashboard for questionnaires and approved recommendations.
- Clinician dashboard for patient responses, questionnaire authoring, and Pathway 1/2 review.
- Pathway 1 clinical input form aligned with the current Supabase Edge Function field names.
- Mock repository for UI development before Supabase Auth/database integration is complete.
- HTTP client wrapper for the `evaluate_pathway_1` Supabase Edge Function.

## Run

```powershell
flutter pub get
flutter run -d chrome
flutter run -d android
```

## Test

```powershell
flutter test
flutter analyze
flutter build web
flutter build apk --debug
```

## Backend Switch

The app currently starts with `MockAppRepository` in `lib/app.dart`. Replace it with a Supabase-backed repository after the team finalises Auth, RLS, table names, and Edge Function deployment URL.
