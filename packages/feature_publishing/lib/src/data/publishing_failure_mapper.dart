import 'package:core_contracts/core_contracts.dart';
import 'package:firebase_adapters/firebase_adapters.dart';

import '../domain/publishing_failures.dart';

/// Translates `FirebaseFunctionsException`s from the publishing callables
/// into domain [Failure]s — mirrors
/// feature_identity/lib/src/data/firebase_failure_mapper.dart's role for
/// auth, kept separate rather than shared because the `details.reason`
/// codes differ per feature.
abstract final class PublishingFailureMapper {
  static Failure fromFunctionsException(FirebaseFunctionsException exception) {
    switch (exception.code) {
      case 'permission-denied':
        return const PermissionFailure();
      case 'invalid-argument':
        return ValidationFailure(exception.message ?? 'Invalid request.');
      case 'unauthenticated':
        return const PermissionFailure('Sign in required.');
      case 'not-found':
        return const ContentNotFoundFailure();
      case 'failed-precondition':
        return _fromReason(exception);
      default:
        return UnknownPublishingFailure(
          exception.message ?? 'Server error (${exception.code}).',
        );
    }
  }

  static Failure _fromReason(FirebaseFunctionsException exception) {
    final details = exception.details;
    final reason = details is Map ? details['reason'] as String? : null;
    switch (reason) {
      case 'comment-required':
        return const CommentRequiredFailure();
      case 'invalid-schedule':
        return const InvalidScheduleFailure();
      default:
        return UnknownPublishingFailure(
          exception.message ?? 'Request could not be completed.',
        );
    }
  }
}
