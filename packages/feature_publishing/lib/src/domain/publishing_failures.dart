import 'package:core_contracts/core_contracts.dart';

import 'publishing_action.dart';
import 'publishing_status.dart';

/// Raised when [action] has no edge out of [from] in
/// `PublishingStateMachine.transitions` at all — as opposed to
/// [PermissionFailure], which means the edge exists but the caller lacks
/// the capability for it.
final class InvalidTransitionFailure extends Failure {
  InvalidTransitionFailure({required this.from, required this.action})
    : super(
        '${action.storageValue} is not valid from ${from.storageValue}.',
        code: 'invalid-transition',
      );

  final PublishingStatus from;
  final PublishingAction action;
}

/// SRS CMS-03: rejection requires a comment.
final class CommentRequiredFailure extends Failure {
  const CommentRequiredFailure()
    : super('A comment is required for this action.', code: 'comment-required');
}

/// SRS CMS-08: schedules must be logical — `scheduledAt` must be a future
/// timestamp.
final class InvalidScheduleFailure extends Failure {
  const InvalidScheduleFailure()
    : super(
        'Scheduled publish time must be in the future.',
        code: 'invalid-schedule',
      );
}

final class ContentNotFoundFailure extends Failure {
  const ContentNotFoundFailure()
    : super('Content not found.', code: 'not-found');
}

final class UnknownPublishingFailure extends Failure {
  const UnknownPublishingFailure([
    super.message = 'Something went wrong. Please try again.',
  ]) : super(code: 'unknown');
}
