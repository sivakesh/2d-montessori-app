import 'package:core_contracts/core_contracts.dart';
import 'package:firebase_adapters/firebase_adapters.dart';

import '../domain/auth_failures.dart';

/// Translates Firebase SDK exceptions into the domain's [Failure] types so
/// no other layer needs to know about `FirebaseAuthException`/
/// `FirebaseFunctionsException` codes.
abstract final class FirebaseFailureMapper {
  static AuthFailure fromAuthException(FirebaseAuthException exception) {
    switch (exception.code) {
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
      case 'invalid-email':
        return const InvalidCredentialsFailure();
      case 'user-disabled':
        return const AccountDisabledFailure();
      case 'too-many-requests':
        return const TooManyRequestsFailure();
      case 'requires-recent-login':
        return const RequiresRecentLoginFailure();
      case 'weak-password':
        return const WeakPasswordFailure(['Password is too weak.']);
      case 'invalid-action-code':
      case 'expired-action-code':
        return const InvalidResetCodeFailure();
      case 'network-request-failed':
        return const NetworkFailure();
      default:
        return UnknownAuthFailure(
          exception.message ?? 'Authentication error (${exception.code}).',
        );
    }
  }

  static Failure fromFunctionsException(FirebaseFunctionsException exception) {
    switch (exception.code) {
      case 'permission-denied':
        return const PermissionFailure();
      case 'invalid-argument':
      case 'failed-precondition':
        return ValidationFailure(exception.message ?? 'Invalid request.');
      case 'unauthenticated':
        return const InvalidCredentialsFailure();
      case 'resource-exhausted':
        return const TooManyRequestsFailure();
      default:
        if (exception.details is Map &&
            (exception.details as Map)['reason'] == 'last-super-admin') {
          return const LastSuperAdminFailure();
        }
        return UnknownAuthFailure(
          exception.message ?? 'Server error (${exception.code}).',
        );
    }
  }
}
