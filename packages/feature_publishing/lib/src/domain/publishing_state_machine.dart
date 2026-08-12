import 'package:core_contracts/core_contracts.dart';
import 'package:meta/meta.dart';

import 'publishing_action.dart';
import 'publishing_status.dart';

/// One legal edge in the workflow graph. [requiredCapability] is checked
/// against the SRS §3 role matrix (`RolePermissionMatrix`) — see
/// docs/architecture/decisions.md "Publishing workflow: role/capability
/// enforcement" for how `approveRejectPublish`/`schedulePublishing` map
/// onto these actions.
@immutable
class PublishingTransitionRule {
  const PublishingTransitionRule({
    required this.from,
    required this.action,
    required this.to,
    required this.requiredCapability,
    this.requiresComment = false,
    this.requiresFutureScheduledAt = false,
  });

  final PublishingStatus from;
  final PublishingAction action;
  final PublishingStatus to;

  /// Full access to this capability is required — `limited` (e.g.
  /// Editor's "suggest only" on `schedulePublishing`) never satisfies a
  /// transition; see `PublishingStateMachine.isAllowed`.
  final Capability requiredCapability;

  /// SRS CMS-03: "rejection requires a comment."
  final bool requiresComment;

  /// SRS CMS-08: "logical schedules" — a `schedule` transition's
  /// `scheduledAt` must be in the future.
  final bool requiresFutureScheduledAt;
}

/// Pure, Firestore-free workflow logic — the "reusable contract" every
/// future content feature (feature_pages, feature_programs, ...) applies
/// to its own documents. Deliberately has zero knowledge of what a
/// "page" or "program" is: callers pass a [PublishingStatus] and
/// [PublishingAction] and get back whether/where the transition goes.
///
/// Ported line-for-line in intent (not code — Dart vs TypeScript) to
/// functions/src/publishing/stateMachine.ts, which is the actual
/// enforcement point; this copy exists so client UIs can show/hide
/// actions correctly without a round trip, and so the workflow shape has
/// one designed, tested source of truth on each side.
abstract final class PublishingStateMachine {
  static const List<PublishingTransitionRule> transitions = [
    PublishingTransitionRule(
      from: PublishingStatus.draft,
      action: PublishingAction.submitForReview,
      to: PublishingStatus.inReview,
      requiredCapability: Capability.submitForReview,
    ),
    PublishingTransitionRule(
      from: PublishingStatus.draft,
      action: PublishingAction.archive,
      to: PublishingStatus.archived,
      requiredCapability: Capability.approveRejectPublish,
    ),
    PublishingTransitionRule(
      from: PublishingStatus.inReview,
      action: PublishingAction.reject,
      to: PublishingStatus.draft,
      requiredCapability: Capability.approveRejectPublish,
      requiresComment: true,
    ),
    PublishingTransitionRule(
      from: PublishingStatus.inReview,
      action: PublishingAction.approve,
      to: PublishingStatus.approved,
      requiredCapability: Capability.approveRejectPublish,
    ),
    PublishingTransitionRule(
      from: PublishingStatus.inReview,
      action: PublishingAction.archive,
      to: PublishingStatus.archived,
      requiredCapability: Capability.approveRejectPublish,
    ),
    PublishingTransitionRule(
      from: PublishingStatus.approved,
      action: PublishingAction.reject,
      to: PublishingStatus.draft,
      requiredCapability: Capability.approveRejectPublish,
      requiresComment: true,
    ),
    PublishingTransitionRule(
      from: PublishingStatus.approved,
      action: PublishingAction.schedule,
      to: PublishingStatus.scheduled,
      requiredCapability: Capability.schedulePublishing,
      requiresFutureScheduledAt: true,
    ),
    PublishingTransitionRule(
      from: PublishingStatus.approved,
      action: PublishingAction.publish,
      to: PublishingStatus.published,
      requiredCapability: Capability.approveRejectPublish,
    ),
    PublishingTransitionRule(
      from: PublishingStatus.approved,
      action: PublishingAction.archive,
      to: PublishingStatus.archived,
      requiredCapability: Capability.approveRejectPublish,
    ),
    PublishingTransitionRule(
      from: PublishingStatus.scheduled,
      action: PublishingAction.unschedule,
      to: PublishingStatus.approved,
      requiredCapability: Capability.schedulePublishing,
    ),
    PublishingTransitionRule(
      from: PublishingStatus.scheduled,
      action: PublishingAction.publish,
      to: PublishingStatus.published,
      requiredCapability: Capability.approveRejectPublish,
    ),
    PublishingTransitionRule(
      from: PublishingStatus.scheduled,
      action: PublishingAction.archive,
      to: PublishingStatus.archived,
      requiredCapability: Capability.approveRejectPublish,
    ),
    PublishingTransitionRule(
      from: PublishingStatus.published,
      action: PublishingAction.unpublish,
      to: PublishingStatus.archived,
      requiredCapability: Capability.approveRejectPublish,
    ),
    PublishingTransitionRule(
      from: PublishingStatus.archived,
      action: PublishingAction.restore,
      to: PublishingStatus.draft,
      requiredCapability: Capability.approveRejectPublish,
    ),
  ];

  static PublishingTransitionRule? resolve(
    PublishingStatus from,
    PublishingAction action,
  ) {
    for (final rule in transitions) {
      if (rule.from == from && rule.action == action) return rule;
    }
    return null;
  }

  /// True only if the edge exists AND [role] has *full* (not `limited`)
  /// access to its required capability — an Editor's "suggest only" on
  /// `schedulePublishing` never authorizes an actual `schedule` call.
  static bool isAllowed(
    PublishingStatus from,
    PublishingAction action,
    UserRole role,
  ) {
    final rule = resolve(from, action);
    if (rule == null) return false;
    return RolePermissionMatrix.hasFull(role, rule.requiredCapability);
  }
}
