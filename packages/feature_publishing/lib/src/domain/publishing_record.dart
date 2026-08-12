import 'package:meta/meta.dart';

import 'publishing_status.dart';

/// The workflow envelope for one piece of publishable content. This
/// milestone's reference content type is generic (`contentType` +
/// `title` only) — feature_pages/feature_programs/etc. later either
/// store their own fields alongside these same envelope fields in their
/// own collection, or compose with this one; see
/// docs/architecture/decisions.md "Publishing workflow: reusable
/// contracts" for the intended reuse shape.
@immutable
class PublishingRecord {
  const PublishingRecord({
    required this.contentId,
    required this.contentType,
    required this.title,
    required this.status,
    required this.ownerId,
    this.submittedAt,
    this.submittedBy,
    this.reviewedAt,
    this.reviewedBy,
    this.scheduledAt,
    this.publishedAt,
    this.publishedBy,
    this.archivedAt,
    this.archivedBy,
    required this.createdAt,
    required this.createdBy,
    required this.updatedAt,
    required this.updatedBy,
  });

  final String contentId;
  final String contentType;
  final String title;
  final PublishingStatus status;

  /// Creator of the draft. SRS §3's Editor "editAllContent: Assigned/
  /// permitted" nuance is approximated in this milestone as "owner or a
  /// role with full `approveRejectPublish`" — see
  /// `SubmitForReviewUseCase`'s doc comment for why a full assignment
  /// system is out of scope here.
  final String ownerId;

  final DateTime? submittedAt;
  final String? submittedBy;
  final DateTime? reviewedAt;
  final String? reviewedBy;

  /// Set by `schedule`, cleared by `unschedule`/`publish`.
  final DateTime? scheduledAt;

  final DateTime? publishedAt;
  final String? publishedBy;
  final DateTime? archivedAt;
  final String? archivedBy;

  final DateTime createdAt;
  final String createdBy;
  final DateTime updatedAt;
  final String updatedBy;
}
