import 'package:core_contracts/core_contracts.dart';
import 'package:firebase_adapters/firebase_adapters.dart';

import '../domain/media_failures.dart';

/// Maps a `FirebaseFunctionsException` thrown by any `mediaFns-*`
/// callable to a domain [Failure]. Mirrors `feature_pages`'
/// `PageFailureMapper` convention exactly.
abstract final class MediaFailureMapper {
  static Failure fromFunctionsException(FirebaseFunctionsException exception) {
    switch (exception.code) {
      case 'permission-denied':
        return const PermissionFailure();
      case 'unauthenticated':
        return const PermissionFailure('Sign in required.');
      case 'invalid-argument':
        return ValidationFailure(exception.message ?? 'Invalid request.');
      case 'not-found':
        return const MediaNotFoundFailure();
      case 'failed-precondition':
        return _mapFailedPrecondition(exception);
      default:
        return ValidationFailure(
          exception.message ?? 'Something went wrong. Please try again.',
        );
    }
  }

  static Failure _mapFailedPrecondition(FirebaseFunctionsException exception) {
    final details = exception.details;
    final reason = details is Map ? details['reason'] as String? : null;
    switch (reason) {
      case 'media-not-editable':
        return const MediaNotEditableFailure();
      case 'media-not-archived':
        return const MediaNotArchivedFailure();
      case 'media-in-use':
        return const MediaInUseFailure();
      default:
        return ValidationFailure(
          exception.message ?? 'Something went wrong. Please try again.',
        );
    }
  }
}
