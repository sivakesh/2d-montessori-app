import 'package:meta/meta.dart';

import 'media_reference.dart';
import 'page_section.dart';
import 'page_type.dart';
import 'seo_metadata.dart';

/// SRS CMS-06: "Persist meaningful revisions, author, timestamp and
/// action. Authorised roles can compare and restore an earlier version
/// without erasing the audit trail." A revision is a full content-field
/// snapshot written every time `updatePageContent` successfully changes a
/// page's content — restoring one copies its fields onto the *current*
/// draft (see `RestorePageRevisionUseCase`), it never deletes or rewrites
/// prior revisions, so the history itself is append-only exactly as the
/// SRS requires.
///
/// Deliberately holds only the content fields a revision needs to
/// restore — not the workflow envelope (status/owner/timestamps), which
/// `feature_publishing` already tracks separately via
/// `content/{contentId}/transitions/`.
@immutable
class PageRevision {
  const PageRevision({
    required this.revisionId,
    required this.pageId,
    required this.title,
    required this.slug,
    required this.summary,
    required this.pageType,
    required this.sections,
    this.featuredImage,
    required this.seo,
    this.navigationLabel,
    required this.showInNavigation,
    required this.actorId,
    required this.createdAt,
  });

  final String revisionId;
  final String pageId;

  final String title;
  final String slug;
  final String summary;
  final PageType pageType;
  final List<PageSection> sections;
  final MediaReference? featuredImage;
  final SeoMetadata seo;
  final String? navigationLabel;
  final bool showInNavigation;

  /// Who made the content change this revision captures.
  final String actorId;

  final DateTime createdAt;
}
