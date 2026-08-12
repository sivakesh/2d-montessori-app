import 'package:core_contracts/core_contracts.dart';

// Re-exported for backward compatibility: PermissionFailure and
// ValidationFailure used to be defined in this file, but moved to
// core_contracts at the Phase 1 — CMS Core milestone once
// feature_publishing needed the same two shapes (see
// core_contracts/lib/src/common_failures.dart's doc comment). Anything
// importing feature_identity's barrel still sees these names.
export 'package:core_contracts/core_contracts.dart'
    show PermissionFailure, ValidationFailure;

/// Auth-specific failures. Data-layer adapters (Firebase Auth, Cloud
/// Functions) map SDK exceptions to these so presentation code never has
/// to inspect `FirebaseAuthException.code` strings directly.
sealed class AuthFailure extends Failure {
  const AuthFailure(super.message, {super.code});
}

final class InvalidCredentialsFailure extends AuthFailure {
  const InvalidCredentialsFailure()
    : super('Incorrect email or password.', code: 'invalid-credentials');
}

final class AccountDisabledFailure extends AuthFailure {
  const AccountDisabledFailure()
    : super('This account has been suspended.', code: 'account-disabled');
}

final class TooManyRequestsFailure extends AuthFailure {
  const TooManyRequestsFailure()
    : super(
        'Too many attempts. Please wait a moment and try again.',
        code: 'too-many-requests',
      );
}

final class RequiresRecentLoginFailure extends AuthFailure {
  const RequiresRecentLoginFailure()
    : super(
        'For security, please sign in again before changing your password.',
        code: 'requires-recent-login',
      );
}

final class WeakPasswordFailure extends AuthFailure {
  const WeakPasswordFailure(this.violations)
    : super(
        'Password does not meet the minimum requirements.',
        code: 'weak-password',
      );

  final List<String> violations;
}

final class NetworkFailure extends AuthFailure {
  const NetworkFailure()
    : super(
        'Network error. Please check your connection and try again.',
        code: 'network',
      );
}

final class InvalidResetCodeFailure extends AuthFailure {
  const InvalidResetCodeFailure()
    : super(
        'This password reset link is invalid or has expired.',
        code: 'invalid-reset-code',
      );
}

final class UnknownAuthFailure extends AuthFailure {
  const UnknownAuthFailure([
    super.message = 'Something went wrong. Please try again.',
  ]) : super(code: 'unknown');
}

/// The server rejected an operation that would have left zero active
/// Super Admins (see functions/src/auth/lastSuperAdminGuard.ts).
final class LastSuperAdminFailure extends Failure {
  const LastSuperAdminFailure()
    : super(
        'This is the last active Super Admin — demoting, suspending or deleting this account is blocked.',
        code: 'last-super-admin',
      );
}
