import 'package:csi6224_patient_feedback/data/supabase_app_repository.dart';
import 'package:csi6224_patient_feedback/models/app_user.dart';
import 'package:csi6224_patient_feedback/screens/auth_signup.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('live profile contract', () {
    test('maps gender, date of birth, approval, and Auth email', () {
      final user = AppUser.fromJson({
        'id': 'patient-id',
        'role': 'patient',
        'full_name': 'Monica Test',
        'date_of_birth': '1970-02-03',
        'gender': 'female',
        'approval_status': 'approved',
      }, authenticatedEmail: 'monica@example.test');

      expect(user.email, 'monica@example.test');
      expect(user.dateOfBirth, DateTime(1970, 2, 3));
      expect(user.sexAtBirth, 'female');
      expect(user.approvalStatus, ClinicianApprovalStatus.approved);
    });

    test('legacy patient with null gender still parses', () {
      final user = AppUser.fromJson({
        'id': 'legacy-patient-id',
        'role': 'patient',
        'full_name': 'Legacy Patient',
        'date_of_birth': '1980-04-05',
        'gender': null,
        'approval_status': 'approved',
      }, authenticatedEmail: 'legacy@example.test');

      expect(user.sexAtBirth, isNull);
      expect(user.email, 'legacy@example.test');
    });

    test('clinician pending approval parses without demographics', () {
      final user = AppUser.fromJson({
        'id': 'clinician-id',
        'role': 'clinician',
        'full_name': 'Clinician Test',
        'date_of_birth': null,
        'gender': null,
        'approval_status': 'pending',
      }, authenticatedEmail: 'clinician@example.test');

      expect(user.approvalStatus, ClinicianApprovalStatus.pending);
      expect(user.isClinician, isFalse);
    });
  });

  group('live registration metadata', () {
    test('uses only the trigger-approved patient demographic keys', () {
      final metadata = SupabaseAppRepository.registrationMetadata(
        RegistrationInput(
          name: 'New Patient',
          email: 'new@example.test',
          password: 'SecretPass123!',
          role: UserRole.patient,
          dateOfBirth: DateTime(1990, 6, 7),
          sexAtBirth: 'female',
        ),
      );

      expect(metadata, {
        'full_name': 'New Patient',
        'role': 'patient',
        'date_of_birth': '1990-06-07',
        'gender': 'female',
      });
      expect(metadata, isNot(contains('sex_at_birth')));
      expect(metadata, isNot(contains('email')));
      expect(metadata, isNot(contains('password')));
    });
  });

  group('safe sign-in error classification', () {
    test(
      'distinguishes credentials, additional auth, profile, and service',
      () {
        expect(
          safeSignInFailureMessage(
            const AuthException('raw detail', code: 'invalid_credentials'),
          ),
          'Email or password is incorrect.',
        );
        expect(
          safeSignInFailureMessage(
            const AuthException('raw detail', code: 'email_not_confirmed'),
          ),
          contains('Additional authentication'),
        );
        expect(
          profileLoadFailureMessage,
          contains('profile could not be loaded'),
        );
        expect(
          safeSignInFailureMessage(const AuthException('internal raw detail')),
          signInServiceFailureMessage,
        );
      },
    );
  });

  testWidgets('registration review shows details but never the password', (
    tester,
  ) async {
    var backPressed = false;
    var createPressed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RegistrationReview(
            input: RegistrationInput(
              name: 'New Patient',
              email: 'new@example.test',
              password: 'SecretPass123!',
              role: UserRole.patient,
              dateOfBirth: DateTime(1990, 6, 7),
              sexAtBirth: 'female',
            ),
            saving: false,
            onBack: () => backPressed = true,
            onCreateAccount: () => createPressed = true,
          ),
        ),
      ),
    );

    expect(find.text('Review your details'), findsOneWidget);
    expect(find.text('New Patient'), findsOneWidget);
    expect(find.text('Patient'), findsOneWidget);
    expect(find.text('Female'), findsOneWidget);
    expect(find.text('new@example.test'), findsOneWidget);
    expect(find.text('SecretPass123!'), findsNothing);
    expect(find.text('Password'), findsNothing);

    await tester.tap(find.byKey(const Key('registration-back-button')));
    await tester.tap(find.byKey(const Key('registration-create-button')));
    expect(backPressed, isTrue);
    expect(createPressed, isTrue);
  });
}
