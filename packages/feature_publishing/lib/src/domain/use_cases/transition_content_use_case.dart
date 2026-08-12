import 'package:core_contracts/core_contracts.dart';

import '../publishing_action.dart';
import '../publishing_failures.dart';
import '../publishing_record.dart';
import '../publishing_repository.dart';
import '../publishing_state_machine.dart';
import '../publishing_status.dart';

/// The shared engine every named action use case in this directory wraps
/// (`SubmitForReviewUseCase`, `ApproveContentUseCase`, ...). Runs the same
/// three checks `PublishingStateMachine` and the Cloud Functions layer
/// agree on — edge exists, caller has full capability, comment/schedule
/// requirements are met — client-side, before ever calling the
/// repository. This is defense-in-depth only: the callable behind
/// [PublishingRepository.transition] re-validates all of this
/// server-side (functions/src/publishing/applyTransition.ts) and is the
/// actual authority.
class TransitionContentUseCase {
  const TransitionContentUseCase(this._repository);

  final PublishingRepository _repository;

  Future<Result<PublishingRecord>> call({
    required String contentId,
    required PublishingAction action,
    required PublishingStatus currentStatus,
    required UserRole actingRole,
    required String actorId,
    String? comment,
    DateTime? scheduledAt,
  }) async {
    final rule = PublishingStateMachine.resolve(currentStatus, action);
    if (rule == null) {
      return Result.failure(
        InvalidTransitionFailure(from: currentStatus, action: action),
      );
    }
    if (!RolePermissionMatrix.hasFull(actingRole, rule.requiredCapability)) {
      return const Result.failure(PermissionFailure());
    }
    if (rule.requiresComment && (comment == null || comment.trim().isEmpty)) {
      return const Result.failure(CommentRequiredFailure());
    }
    if (rule.requiresFutureScheduledAt) {
      if (scheduledAt == null || !scheduledAt.isAfter(DateTime.now())) {
        return const Result.failure(InvalidScheduleFailure());
      }
    }
    return _repository.transition(
      contentId: contentId,
      action: action,
      actorId: actorId,
      comment: comment,
      scheduledAt: scheduledAt,
    );
  }
}
