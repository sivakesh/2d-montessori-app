import 'package:core_contracts/core_contracts.dart';

import 'auth_session.dart';

/// Everything a signed-in (or signing-in) user can do to their own
/// session. Implemented by the Firebase Auth adapter in
/// lib/src/data/firebase_auth_repository.dart; every other layer depends
/// only on this interface (see docs/architecture/repository-structure.md).
abstract class AuthRepository {
  /// Emits the current [AuthState] immediately on listen and again
  /// whenever the underlying ID token changes (sign-in, sign-out, or a
  /// forced/periodic token refresh — which is also how a role/status
  /// change made by an admin eventually reaches this session).
  Stream<AuthState> observeAuthState();

  Future<Result<void>> signInWithEmailAndPassword({
    required String email,
    required String password,
  });

  Future<Result<void>> signOut();

  /// Self-service reset (SRS does not forbid this — it is a standard
  /// Firebase Auth security email, distinct from the "invitation email"
  /// AUTH-01 explicitly excludes from Phase 1 account creation). Always
  /// succeeds from the caller's point of view regardless of whether the
  /// email exists, to avoid leaking account existence.
  Future<Result<void>> sendPasswordResetEmail(String email);

  /// Completes a reset started by [sendPasswordResetEmail]. [oobCode]
  /// comes from the reset link's `oobCode` query parameter.
  Future<Result<void>> confirmPasswordReset({
    required String oobCode,
    required String newPassword,
  });

  /// Changes the password of the *currently signed-in* user (used for the
  /// forced first-login flow, SRS AUTH-03, and voluntary changes from My
  /// Profile). Requires a recent sign-in per Firebase Auth's own
  /// re-authentication rules; callers should surface
  /// [RequiresRecentLoginFailure] by asking the user to sign in again.
  Future<Result<void>> changeOwnPassword(String newPassword);

  /// Clears the `mustChangePassword` flag once the password has actually
  /// been changed. A trusted Cloud Function, not a direct Firestore write
  /// — see AUTH-04 ("must-change-password status remain system-controlled").
  Future<Result<void>> completeFirstLogin();

  /// Forces the client's cached ID token to refresh so a role/status
  /// change this session just made to *another* user (or, after
  /// re-authenticating, to itself) is reflected without waiting for the
  /// natural ~1 hour refresh cycle.
  Future<Result<void>> refreshOwnClaims();
}
