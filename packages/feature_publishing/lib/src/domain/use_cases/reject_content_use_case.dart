import 'package:core_contracts/core_contracts.dart';

import '../publishing_action.dart';
import '../publishing_record.dart';
import '../publishing_status.dart';
import 'transition_content_use_case.dart';

/// InReview or Approved → Draft ("reject/return"). SRS CMS-03:
/// "rejection requires a comment" — [comment] is a required parameter
/// here (not optional), so a caller cannot construct a valid call
/// without one; `TransitionContentUseCase` still validates it is
/// non-blank, and the server re-validates regardless.
class RejectContentUseCase {
  const RejectContentUseCase(this._transition);

  final TransitionContentUseCase _transition;

  Future<Result<PublishingRecord>> call({
    required String contentId,
    required PublishingStatus currentStatus,
    required UserRole actingRole,
    required String actorId,
    required String comment,
  }) => _transition(
    contentId: contentId,
    action: PublishingAction.reject,
    currentStatus: currentStatus,
    actingRole: actingRole,
    actorId: actorId,
    comment: comment,
  );
}
