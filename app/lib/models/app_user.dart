enum UserRole { patient, clinician, admin }

enum ClinicianApprovalStatus { pending, approved, rejected }

class AppUser {
  const AppUser({
    required this.id,
    required this.displayName,
    required this.email,
    required this.role,
    this.approvalStatus,
    this.dateOfBirth,
    this.sexAtBirth,
  });
  final String id;
  final String displayName;
  final String email;
  final UserRole role;
  final ClinicianApprovalStatus? approvalStatus;
  final DateTime? dateOfBirth;
  final String? sexAtBirth;
  bool get isClinician =>
      role == UserRole.clinician &&
      approvalStatus == ClinicianApprovalStatus.approved;
  String get sessionKey => '$id/${role.name}/${approvalStatus?.name}';
  factory AppUser.fromJson(
    Map<String, dynamic> json, {
    String? authenticatedEmail,
  }) {
    final fullName = json['full_name']?.toString().trim();
    final profileEmail = json['email']?.toString().trim();
    final approval = json['approval_status']?.toString();
    return AppUser(
      id: json['id'] as String,
      displayName: fullName == null || fullName.isEmpty ? 'User' : fullName,
      // The live profiles table has no email column. Auth remains the source
      // of truth for the signed-in user's email at the repository boundary.
      email: profileEmail == null || profileEmail.isEmpty
          ? (authenticatedEmail ?? '')
          : profileEmail,
      role: UserRole.values.byName(json['role'] as String),
      approvalStatus: approval == null
          ? null
          : ClinicianApprovalStatus.values.byName(approval),
      dateOfBirth: DateTime.tryParse(json['date_of_birth']?.toString() ?? ''),
      // Songyi's live profile contract names this column `gender`.
      sexAtBirth: json['gender']?.toString(),
    );
  }
  AppUser withApproval(ClinicianApprovalStatus value) => AppUser(
    id: id,
    displayName: displayName,
    email: email,
    role: role,
    approvalStatus: value,
  );
}

class RegistrationInput {
  const RegistrationInput({
    required this.name,
    required this.email,
    required this.password,
    required this.role,
    this.dateOfBirth,
    this.sexAtBirth,
  });
  final String name, email, password;
  final UserRole role;
  final DateTime? dateOfBirth;
  final String? sexAtBirth;
}
