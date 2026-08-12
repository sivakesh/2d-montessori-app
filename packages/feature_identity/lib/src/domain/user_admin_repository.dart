import 'package:core_contracts/core_contracts.dart';
import 'package:meta/meta.dart';

import 'user_account.dart';

@immutable
class CreateUserResult {
  const CreateUserResult({required this.uid, required this.temporaryPassword});

  final String uid;

  /// Returned once, to be communicated to the new user out-of-band (SRS
  /// AUTH-01 — "No invitation or notification email is sent in Phase 1").
  /// Never persisted anywhere; the caller must not log it.
  final String temporaryPassword;
}

@immutable
class ResetPasswordResult {
  const ResetPasswordResult({required this.temporaryPassword});

  final String temporaryPassword;
}

/// Super-Admin-only user administration (SRS AUTH-01, AUTH-05). Every
/// method is backed by a callable Cloud Function that re-verifies the
/// caller's role and active status server-side — this interface's job is
/// to give the client a typed surface, not to be the security boundary.
abstract class UserAdminRepository {
  /// Live list for the User Management screen. Firestore rules restrict
  /// this read to Super Admins (see firebase/firestore.rules).
  Stream<Result<List<UserAccount>>> observeUsers();

  Future<Result<CreateUserResult>> createUser({
    required String email,
    required String displayName,
    required UserRole role,
  });

  Future<Result<void>> setUserRole({
    required String uid,
    required UserRole role,
  });

  Future<Result<void>> setUserStatus({
    required String uid,
    required AccountStatus status,
  });

  /// Sets a new server-generated temporary password and marks the account
  /// as requiring a change at next sign-in (SRS AUTH-05).
  Future<Result<ResetPasswordResult>> resetUserPassword(String uid);
}
