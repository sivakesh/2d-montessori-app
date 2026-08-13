import 'package:feature_publishing/feature_publishing.dart';
import 'package:meta/meta.dart';

import 'media_reference.dart';
import 'page_section.dart';
import 'page_type.dart';
import 'seo_metadata.dart';

/// The Pages content type — a `content/{contentId}` document with
/// `contentType == 'page'` (see decisions.md "Pages storage: `content`
/// collection, not a separate `pages` collection" for why). Named
/// `CmsPage`, not `Page`, because `core_contracts` already exports a
/// generic `Page<T>` cursor-pagination type; importing both into the same
/// file (as `apps/admin_web` will need to) would otherwise collide.
///
/// Embeds every `feature_publishing` envelope field verbatim (status,
/// owner, submitted/reviewed/published/archived timestamps and actors) —
/// see [toPublishingRecord] — so this single document is both "the page"
/// and "the thing `feature_publishing`'s workflow engine operates on",
/// with no separate synced copy.
@immutable
class CmsPage {
  const CmsPage({
    required this.pageId,
    required this.title,
    required this.slug,
    this.summary = '',
    this.pageType = PageType.standard,
    this.sections = const [],
    this.featuredImage,
    this.seo = SeoMetadata.empty,
    this.navigationLabel,
    this.showInNavigation = false,
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
    this.restoredAt,
    this.restoredBy,
    required this.createdAt,
    required this.createdBy,
    required this.updatedAt,
    required this.updatedBy,
  });

  /// Stable page ID — the `content/{contentId}` document id. Immutable
  /// once created.
  final String pageId;

  final String title;

  /// Unique URL slug, lowercase ASCII with hyphens (PRD §5 "Slugs are
  /// lowercase ASCII with hyphens and are unique within their route
  /// namespace"). Uniqueness is enforced server-side across all pages
  /// regardless of status — see `functions/src/pages/slug.ts`.
  final String slug;

  final String summary;
  final PageType pageType;

  /// Ordered, typed content blocks. Order is authoritative via each
  /// section's own `sortOrder` (not list position) so reordering is a
  /// pure metadata update, not a rewrite of the whole array's identity.
  final List<PageSection> sections;

  final MediaReference? featuredImage;
  final SeoMetadata seo;

  /// SRS WEB-02 navigation requirements — optional short label distinct
  /// from [title] for header/footer links (e.g. "Our Way" for a page
  /// titled "The Montessori Way — Our Educational Philosophy").
  final String? navigationLabel;

  /// Whether this page should appear in site navigation once published.
  /// Defaults to false — most CMS-created pages are linked contextually,
  /// not automatically added to primary navigation.
  final bool showInNavigation;

  final PublishingStatus status;
  final String ownerId;

  final DateTime? submittedAt;
  final String? submittedBy;
  final DateTime? reviewedAt;
  final String? reviewedBy;
  final DateTime? scheduledAt;
  final DateTime? publishedAt;
  final String? publishedBy;
  final DateTime? archivedAt;
  final String? archivedBy;

  /// Archive/restoration metadata (SRS CMS-02's `Archived` state plus the
  /// `restore` action `feature_publishing` already models) — set the last
  /// time this page was restored from Archived back to Draft.
  final DateTime? restoredAt;
  final String? restoredBy;

  final DateTime createdAt;
  final String createdBy;
  final DateTime updatedAt;
  final String updatedBy;

  /// Bridges to `feature_publishing`'s envelope type so this page can be
  /// driven through the *unmodified* `TransitionContentUseCase` and all
  /// nine named workflow use cases — see
  /// `PagesAsPublishingRepository` in `data/`.
  PublishingRecord toPublishingRecord() => PublishingRecord(
    contentId: pageId,
    contentType: 'page',
    title: title,
    status: status,
    ownerId: ownerId,
    submittedAt: submittedAt,
    submittedBy: submittedBy,
    reviewedAt: reviewedAt,
    reviewedBy: reviewedBy,
    scheduledAt: scheduledAt,
    publishedAt: publishedAt,
    publishedBy: publishedBy,
    archivedAt: archivedAt,
    archivedBy: archivedBy,
    createdAt: createdAt,
    createdBy: createdBy,
    updatedAt: updatedAt,
    updatedBy: updatedBy,
  );

  CmsPage copyWith({
    String? title,
    String? slug,
    String? summary,
    PageType? pageType,
    List<PageSection>? sections,
    MediaReference? featuredImage,
    bool clearFeaturedImage = false,
    SeoMetadata? seo,
    String? navigationLabel,
    bool? showInNavigation,
    PublishingStatus? status,
    DateTime? submittedAt,
    String? submittedBy,
    DateTime? reviewedAt,
    String? reviewedBy,
    DateTime? scheduledAt,
    bool clearScheduledAt = false,
    DateTime? publishedAt,
    String? publishedBy,
    DateTime? archivedAt,
    String? archivedBy,
    DateTime? restoredAt,
    String? restoredBy,
    DateTime? updatedAt,
    String? updatedBy,
  }) => CmsPage(
    pageId: pageId,
    title: title ?? this.title,
    slug: slug ?? this.slug,
    summary: summary ?? this.summary,
    pageType: pageType ?? this.pageType,
    sections: sections ?? this.sections,
    featuredImage: clearFeaturedImage
        ? null
        : (featuredImage ?? this.featuredImage),
    seo: seo ?? this.seo,
    navigationLabel: navigationLabel ?? this.navigationLabel,
    showInNavigation: showInNavigation ?? this.showInNavigation,
    status: status ?? this.status,
    ownerId: ownerId,
    submittedAt: submittedAt ?? this.submittedAt,
    submittedBy: submittedBy ?? this.submittedBy,
    reviewedAt: reviewedAt ?? this.reviewedAt,
    reviewedBy: reviewedBy ?? this.reviewedBy,
    scheduledAt: clearScheduledAt ? null : (scheduledAt ?? this.scheduledAt),
    publishedAt: publishedAt ?? this.publishedAt,
    publishedBy: publishedBy ?? this.publishedBy,
    archivedAt: archivedAt ?? this.archivedAt,
    archivedBy: archivedBy ?? this.archivedBy,
    restoredAt: restoredAt ?? this.restoredAt,
    restoredBy: restoredBy ?? this.restoredBy,
    createdAt: createdAt,
    createdBy: createdBy,
    updatedAt: updatedAt ?? this.updatedAt,
    updatedBy: updatedBy ?? this.updatedBy,
  );
}
