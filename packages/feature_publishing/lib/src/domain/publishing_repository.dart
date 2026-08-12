import 'package:core_contracts/core_contracts.dart';

import 'publishing_action.dart';
import 'publishing_record.dart';

/// Everything a use case needs to drive one content item through the
/// workflow. Implemented by `FirestorePublishingRepository`
/// (lib/src/data/) for this milestone's reference `content` collection —
/// feature_pages/feature_programs/etc. later either implement this same
/// interface against their own collection, or the interface is
/// parameterized further once a second real content type exists to prove
/// the right generalization; see docs/architecture/decisions.md
/// "Publishing workflow: reusable contracts."
abstract class PublishingRepository {
  /// Creates a new Draft. Minimal — full content-field creation (title,
  /// body, SEO, ...) is each content feature's own concern; this exists
  /// only so the workflow has something to exercise, per this milestone's
  /// boundary ("do not begin the full page builder... until the
  /// publishing workflow has been implemented and verified").
  Future<Result<PublishingRecord>> createDraft({
    required String contentType,
    required String title,
    required String ownerId,
  });

  Future<Result<PublishingRecord>> get(String contentId);

  Stream<Result<PublishingRecord>> observe(String contentId);

  /// Applies one workflow transition. [comment] is required by the
  /// `reject` action and ignored otherwise; [scheduledAt] is required by
  /// `schedule` and ignored otherwise — see
  /// `PublishingStateMachine.transitions` for exactly which action needs
  /// which optional argument.
  Future<Result<PublishingRecord>> transition({
    required String contentId,
    required PublishingAction action,
    required String actorId,
    String? comment,
    DateTime? scheduledAt,
  });
}
