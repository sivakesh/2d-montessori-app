import 'package:core_contracts/core_contracts.dart';
import 'package:feature_publishing/feature_publishing.dart';
import 'package:firebase_adapters/firebase_adapters.dart';

import '../domain/page_failures.dart';

/// Maps a `FirebaseFunctionsException` thrown by any `pagesFns-*`
/// callable to a domain [Failure]. Mirrors
/// `feature_publishing`'s `PublishingFailureMapper` (same code→failure
/// shape for the transition-related codes/reasons, since
/// `pagesFns-transitionPage` delegates to the same
/// `applyTransition` engine and can surface the same errors) plus the
/// Pages-specific codes `functions/src/pages/*.ts` adds.
abstract final class PageFailureMapper {
  static Failure fromFunctionsException(FirebaseFunctionsException exception) {
    switch (exception.code) {
      case 'permission-denied':
        return const PermissionFailure();
      case 'unauthenticated':
        return const PermissionFailure('Sign in required.');
      case 'invalid-argument':
        return ValidationFailure(exception.message ?? 'Invalid request.');
      case 'not-found':
        return const PageRevisionNotFoundFailure();
      case 'already-exists':
        return const SlugConflictFailure();
      case 'failed-precondition':
        return _mapFailedPrecondition(exception);
      default:
        return UnknownPublishingFailure(
          exception.message ?? 'Something went wrong. Please try again.',
        );
    }
  }

  static Failure _mapFailedPrecondition(FirebaseFunctionsException exception) {
    final details = exception.details;
    final reason = details is Map ? details['reason'] as String? : null;
    switch (reason) {
      case 'comment-required':
        return const CommentRequiredFailure();
      case 'invalid-schedule':
        return const InvalidScheduleFailure();
      case 'slug-conflict':
        return const SlugConflictFailure();
      case 'invalid-slug':
        return const InvalidSlugFailure();
      case 'page-not-editable':
        return const PageNotEditableFailure();
      case 'page-incomplete':
        final violations = details is Map
            ? (details['violations'] as List?)?.cast<String>()
            : null;
        return PageIncompleteFailure(
          violations ?? const ['This page is missing required fields.'],
        );
      default:
        return UnknownPublishingFailure(
          exception.message ?? 'Something went wrong. Please try again.',
        );
    }
  }
}
