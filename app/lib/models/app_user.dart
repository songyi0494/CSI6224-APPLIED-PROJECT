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
  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
    id: json['id'] as String,
    displayName: json['full_name'] as String,
    email: json['email'] as String,
    role: UserRole.values.byName(json['role'] as String),
    approvalStatus: json['approval_status'] == null
        ? null
        : ClinicianApprovalStatus.values.byName(
            json['approval_status'] as String,
          ),
    dateOfBirth: DateTime.tryParse(json['date_of_birth']?.toString() ?? ''),
    sexAtBirth: json['sex_at_birth'] as String?,
  );
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
