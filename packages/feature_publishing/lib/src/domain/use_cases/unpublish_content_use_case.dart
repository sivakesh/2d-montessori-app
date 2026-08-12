import 'package:core_contracts/core_contracts.dart';

import '../publishing_action.dart';
import '../publishing_record.dart';
import '../publishing_status.dart';
import 'transition_content_use_case.dart';

/// Published → Archived. SRS §3: requires full `approveRejectPublish`.
///
/// [currentStatus] must be the status the caller actually observed for
/// this content — see SubmitForReviewUseCase's doc comment for why.
class UnpublishContentUseCase {
  const UnpublishContentUseCase(this._transition);

  final TransitionContentUseCase _transition;

  Future<Result<PublishingRecord>> call({
    required String contentId,
    required PublishingStatus currentStatus,
    required UserRole actingRole,
    required String actorId,
  }) => _transition(
    contentId: contentId,
    action: PublishingAction.unpublish,
    currentStatus: currentStatus,
    actingRole: actingRole,
    actorId: actorId,
  );
}
