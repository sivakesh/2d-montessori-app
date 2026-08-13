import 'package:core_contracts/core_contracts.dart';

/// SRS CMS-08 "unique slug" — raised when the requested slug is already
/// in use by another page (any status, not just published — a Draft can
/// still reserve a slug it plans to publish under).
final class SlugConflictFailure extends Failure {
  const SlugConflictFailure([
    super.message = 'That URL slug is already in use by another page.',
  ]) : super(code: 'slug-conflict');
}

/// Raised when a slug fails format validation (lowercase ASCII + hyphens,
/// PRD §5) before a uniqueness check is even attempted.
final class InvalidSlugFailure extends Failure {
  const InvalidSlugFailure([
    super.message =
        'Slugs must be lowercase letters, numbers and hyphens only.',
  ]) : super(code: 'invalid-slug');
}

/// SRS CMS-08: "Publishing checks required fields, alt text, ... unique
/// slug, logical schedules/expiry, ... Errors block." Raised when a page
/// fails the completeness gate on submit-for-review/publish/schedule.
/// [violations] lists every failed check (not just the first) so a
/// caller can show all errors at once rather than one at a time.
final class PageIncompleteFailure extends Failure {
  PageIncompleteFailure(this.violations)
    : super(
        'This page is not ready: ${violations.join(' ')}',
        code: 'page-incomplete',
      );

  final List<String> violations;
}

/// A page-specific edit was attempted while the page is not in a status
/// that allows content edits (see decisions.md — content fields are only
/// editable while a page is in Draft; editing already-published content
/// goes through `unpublish` then `restore`, reusing the existing
/// `feature_publishing` transitions rather than adding a parallel
/// "live draft copy" mechanism).
final class PageNotEditableFailure extends Failure {
  const PageNotEditableFailure([
    super.message = 'This page can only be edited while it is a draft.',
  ]) : super(code: 'page-not-editable');
}

final class PageRevisionNotFoundFailure extends Failure {
  const PageRevisionNotFoundFailure([
    super.message = 'That revision could not be found.',
  ]) : super(code: 'revision-not-found');
}
