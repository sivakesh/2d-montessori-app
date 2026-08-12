import 'package:meta/meta.dart';

import 'publishing_action.dart';
import 'publishing_status.dart';

/// One entry in a content item's transition history
/// (`content/{contentId}/transitions/{transitionId}` — see
/// docs/architecture/firestore-model.md). Immutable and append-only, same
/// posture as `auditLogs`; this is the content-specific counterpart SRS
/// CMS-03 requires ("comments and transitions stay in history").
@immutable
class PublishingTransitionEvent {
  const PublishingTransitionEvent({
    required this.action,
    required this.fromStatus,
    required this.toStatus,
    required this.actorId,
    required this.actorRole,
    this.comment,
    required this.occurredAt,
  });

  final PublishingAction action;
  final PublishingStatus fromStatus;
  final PublishingStatus toStatus;
  final String actorId;
  final String actorRole;

  /// Required by the state machine for `reject`; optional for every
  /// other action.
  final String? comment;

  final DateTime occurredAt;
}
