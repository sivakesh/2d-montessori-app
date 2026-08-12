import 'package:core_contracts/core_contracts.dart';
import 'package:meta/meta.dart';

/// The signed-in user's identity plus the two claims Firestore rules and
/// the admin UI both need: [role] and [status]. Both come from the ID
/// token's custom claims (set only by trusted Cloud Functions — see
/// functions/src/auth), never from a client-writable source.
@immutable
class AuthSession {
  const AuthSession({
    required this.uid,
    required this.email,
    required this.displayName,
    this.photoUrl,
    required this.role,
    required this.status,
    required this.mustChangePassword,
  });

  final String uid;
  final String email;
  final String displayName;
  final String? photoUrl;
  final UserRole role;
  final AccountStatus status;

  /// Firestore-sourced (not claims — see docs/architecture/decisions.md).
  /// True until the user completes the forced first-login password change
  /// (SRS AUTH-03) or an admin-triggered reset (SRS AUTH-05).
  final bool mustChangePassword;

  bool get isActive => status == AccountStatus.active;
}

/// The full space of authentication states the presentation layer's
/// `AuthGate` must render distinctly (see feature_identity presentation
/// layer). Modeled as a sealed class rather than booleans so a missing
/// `switch` arm is a compile error, not a runtime gap in route protection.
@immutable
sealed class AuthState {
  const AuthState();
}

/// Initial state while the first auth check is in flight (app just
/// launched, persisted session not yet confirmed either way).
final class AuthStateUnknown extends AuthState {
  const AuthStateUnknown();
}

final class AuthStateSignedOut extends AuthState {
  const AuthStateSignedOut();
}

/// Signed in, provisioned (has a valid role claim) and active.
final class AuthStateSignedIn extends AuthState {
  const AuthStateSignedIn(this.session);

  final AuthSession session;
}

/// Signed in and provisioned, but the account's status claim is
/// `suspended` (SRS AUTH-05). Kept distinct from [AuthStateSignedOut] so
/// the UI can explain *why* access is blocked instead of silently
/// bouncing to the login screen.
final class AuthStateSuspended extends AuthState {
  const AuthStateSuspended(this.session);

  final AuthSession session;
}

/// Signed in to Firebase Auth but has no valid `role` custom claim yet —
/// e.g. an account created directly in the Auth emulator without going
/// through `createUser`, or a claims-propagation race. Treated as a hard
/// stop, not a crash: only Cloud Functions ever set claims, so this
/// account needs a Super Admin's attention, not a client-side retry.
final class AuthStateUnprovisioned extends AuthState {
  const AuthStateUnprovisioned({required this.uid, required this.email});

  final String uid;
  final String email;
}

/// Something failed while resolving the session (e.g. the Firestore
/// profile read was denied, or a network error). Distinct from
/// [AuthStateSignedOut] so the UI shows a retry affordance instead of a
/// login form that will just fail again for the same reason.
final class AuthStateError extends AuthState {
  const AuthStateError(this.failure);

  final Failure failure;
}
