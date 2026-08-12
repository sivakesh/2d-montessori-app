import 'package:core_contracts/core_contracts.dart';

import '../publishing_action.dart';
import '../publishing_record.dart';
import '../publishing_status.dart';
import 'transition_content_use_case.dart';

/// InReview → Approved. SRS §3: requires full `approveRejectPublish` (Publisher/Super Admin only).
///
/// [currentStatus] must be the status the caller actually observed for
/// this content — see SubmitForReviewUseCase's doc comment for why.
class ApproveContentUseCase {
  const ApproveContentUseCase(this._transition);

  final TransitionContentUseCase _transition;

  Future<Result<PublishingRecord>> call({
    required String contentId,
    required PublishingStatus currentStatus,
    required UserRole actingRole,
    required String actorId,
  }) => _transition(
    contentId: contentId,
    action: PublishingAction.approve,
    currentStatus: currentStatus,
    actingRole: actingRole,
    actorId: actorId,
  );
}
