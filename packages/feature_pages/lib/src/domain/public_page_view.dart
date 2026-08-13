import 'package:meta/meta.dart';

import 'media_reference.dart';
import 'page_section.dart';
import 'page_type.dart';
import 'seo_metadata.dart';

/// A minimal summary of a related page, resolved server-side at publish
/// time — see [PublicPageView.resolvedRelatedPages] doc comment.
@immutable
class RelatedPageSummary {
  const RelatedPageSummary({
    required this.pageId,
    required this.slug,
    required this.title,
    required this.summary,
    this.featuredImage,
  });

  final String pageId;
  final String slug;
  final String title;
  final String summary;
  final MediaReference? featuredImage;

  factory RelatedPageSummary.fromMap(Map<String, Object?> map) =>
      RelatedPageSummary(
        pageId: map['pageId'] as String? ?? '',
        slug: map['slug'] as String? ?? '',
        title: map['title'] as String? ?? '',
        summary: map['summary'] as String? ?? '',
        featuredImage: map['featuredImage'] == null
            ? null
            : MediaReference.fromMap(
                Map<String, Object?>.from(map['featuredImage']! as Map),
              ),
      );
}

/// The public read model for a published page — everything
/// `publishedPages/{slug}` exposes to unauthenticated visitors.
/// Deliberately excludes every field an admin-only [CmsPage] carries that
/// isn't safe or meaningful to publish: `status` (always implicitly
/// "published" — that's the only reason this document exists at all),
/// `ownerId`, `submittedAt/By`, `reviewedAt/By`, `archivedAt/By`,
/// `restoredAt/By`, `createdBy`/`updatedBy` (actor identities), and
/// anything about revision history. This is the enforcement point for
/// "do not expose administrative fields or unpublished revisions" — the
/// type itself has no field to leak them through.
@immutable
class PublicPageView {
  const PublicPageView({
    required this.pageId,
    required this.slug,
    required this.title,
    required this.summary,
    required this.pageType,
    required this.sections,
    this.featuredImage,
    required this.seo,
    this.navigationLabel,
    required this.showInNavigation,
    required this.publishedAt,
    this.resolvedRelatedPages = const {},
  });

  final String pageId;
  final String slug;
  final String title;
  final String summary;
  final PageType pageType;
  final List<PageSection> sections;
  final MediaReference? featuredImage;
  final SeoMetadata seo;
  final String? navigationLabel;
  final bool showInNavigation;
  final DateTime? publishedAt;

  /// Every `RelatedContentSection.relatedPageIds` reference this page
  /// currently carries, resolved to a display-ready summary — but only
  /// for related pages that were themselves published at the moment
  /// *this* page was last synced to `publishedPages`. A related page id
  /// with no entry here means it either isn't published, or this page
  /// hasn't been republished since the related page's status last
  /// changed (a known, documented staleness window — see decisions.md
  /// "Related-content resolution is denormalized at sync time").
  final Map<String, RelatedPageSummary> resolvedRelatedPages;
}
