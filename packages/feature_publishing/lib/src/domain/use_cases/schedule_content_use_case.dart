import 'package:core_contracts/core_contracts.dart';

import '../publishing_action.dart';
import '../publishing_record.dart';
import '../publishing_status.dart';
import 'transition_content_use_case.dart';

/// Approved → Scheduled. SRS CMS-05/CMS-08: schedules are Publisher/Super
/// Admin only (Editor may only "suggest" — not implemented as a
/// transition in this milestone, see PublishingRecord's doc comment) and
/// must be a future timestamp — [scheduledAt] is required here (not
/// optional); `TransitionContentUseCase` still validates it is actually
/// in the future, and the server re-validates regardless.
class ScheduleContentUseCase {
  const ScheduleContentUseCase(this._transition);

  final TransitionContentUseCase _transition;

  Future<Result<PublishingRecord>> call({
    required String contentId,
    required PublishingStatus currentStatus,
    required UserRole actingRole,
    required String actorId,
    required DateTime scheduledAt,
  }) => _transition(
    contentId: contentId,
    action: PublishingAction.schedule,
    currentStatus: currentStatus,
    actingRole: actingRole,
    actorId: actorId,
    scheduledAt: scheduledAt,
  );
}
