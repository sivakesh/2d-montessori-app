import 'package:core_contracts/core_contracts.dart';

import '../publishing_action.dart';
import '../publishing_record.dart';
import '../publishing_status.dart';
import 'transition_content_use_case.dart';

/// Draft → InReview. SRS §3: `submitForReview` is full for all three
/// roles — every content owner can submit their own draft.
///
/// [currentStatus] must be the status the caller actually observed for
/// this content (e.g. from the record currently displayed) — it is not
/// assumed to be `draft` just because that is the only status this
/// action is ever valid from. Passing the real, possibly-stale value
/// lets the client-side check in `TransitionContentUseCase` mean
/// something (it fails closed if the client's view is out of date);
/// the server re-reads the authoritative current status regardless.
class SubmitForReviewUseCase {
  const SubmitForReviewUseCase(this._transition);

  final TransitionContentUseCase _transition;

  Future<Result<PublishingRecord>> call({
    required String contentId,
    required PublishingStatus currentStatus,
    required UserRole actingRole,
    required String actorId,
  }) => _transition(
    contentId: contentId,
    action: PublishingAction.submitForReview,
    currentStatus: currentStatus,
    actingRole: actingRole,
    actorId: actorId,
  );
}
