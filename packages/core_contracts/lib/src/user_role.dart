/// The three Phase 1 human roles (SRS §3). Deliberately just these three —
/// "Public visitor" is not an account, and the PRD's "System service"
/// identity is a non-interactive Cloud Functions principal, not a
/// selectable role (see docs/architecture/decisions.md).
///
/// The string values match exactly what is stored in Firebase Auth custom
/// claims (`token.role`) and in `users/{uid}.role` — every layer (client,
/// Firestore rules, Cloud Functions) must agree on this encoding.
enum UserRole {
  editor('editor'),
  publisher('publisher'),
  superAdmin('superAdmin');

  const UserRole(this.claimValue);

  final String claimValue;

  static UserRole? fromClaimValue(String? value) {
    for (final role in UserRole.values) {
      if (role.claimValue == value) return role;
    }
    return null;
  }
}

/// Account lifecycle state (SRS AUTH-05 "suspend/reactivate accounts").
/// Mirrors Firebase Auth's `disabled` flag but is also carried in the
/// custom claims and the `users/{uid}` Firestore doc so both client code
/// and security rules can check it without an extra Admin SDK call.
enum AccountStatus {
  active('active'),
  suspended('suspended');

  const AccountStatus(this.claimValue);

  final String claimValue;

  static AccountStatus? fromClaimValue(String? value) {
    for (final status in AccountStatus.values) {
      if (status.claimValue == value) return status;
    }
    return null;
  }
}
