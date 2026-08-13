import 'package:core_contracts/core_contracts.dart';
import 'package:feature_publishing/feature_publishing.dart';

import 'cms_page.dart';
import 'page_content_update.dart';
import 'page_revision.dart';

/// Filters for [PagesRepository.list] — SRS CMS-10 "Search/filter by
/// title, type, status, owner, ... and featured flag" (the subset that
/// applies to Pages; "fixed classification"/"featured flag" belong to
/// other content types).
class PagesQuery {
  const PagesQuery({this.status, this.ownerId, this.searchText});

  final PublishingStatus? status;
  final String? ownerId;
  final String? searchText;
}

/// The Pages content-management repository (admin-side: every status,
/// full field set, workflow transitions). Distinct from
/// [PublicPagesRepository], which is a completely different read path
/// against a different, publicly-readable collection with a reduced
/// field set — see that type's doc comment for why they're not one
/// interface.
abstract class PagesRepository {
  /// Creates a new Draft with a server-derived initial slug (from
  /// [title]) and empty content — SRS CMS-07 autosave then fills the rest
  /// in via [updateContent] as the editor works.
  Future<Result<CmsPage>> createPage({
    required String title,
    required String ownerId,
  });

  /// Replaces this page's editable content fields. Only valid while the
  /// page is a Draft (see [PageNotEditableFailure]). Every successful
  /// call appends a new [PageRevision] server-side (SRS CMS-06).
  Future<Result<CmsPage>> updateContent({
    required String pageId,
    required PageContentUpdate content,
  });

  Future<Result<CmsPage>> get(String pageId);

  Stream<Result<CmsPage>> observe(String pageId);

  Future<Result<Page<CmsPage>>> list({
    PagesQuery query = const PagesQuery(),
    PageRequest request = const PageRequest(),
  });

  Future<Result<List<PageRevision>>> listRevisions(String pageId);

  /// Copies a prior [PageRevision]'s content fields onto the current
  /// draft. Never deletes or rewrites the revision history itself (SRS
  /// CMS-06 "without erasing the audit trail") — restoring creates a
  /// fresh revision entry the same way any other content edit does.
  Future<Result<CmsPage>> restoreRevision({
    required String pageId,
    required String revisionId,
    required String actorId,
  });

  /// Every workflow action (submit/approve/reject/publish/...) — routed
  /// through `functions/src/pages/transitionPage.ts`, which adds the
  /// SRS CMS-08 completeness gate on submit/publish/schedule and then
  /// delegates to the *same, unmodified*
  /// `functions/src/publishing/applyTransition.ts` engine every other
  /// content type uses. See `PagesAsPublishingRepository` in `data/` for
  /// how this single method backs all nine `feature_publishing` use
  /// cases without duplicating any of their logic.
  Future<Result<CmsPage>> transition({
    required String pageId,
    required PublishingAction action,
    required String actorId,
    String? comment,
    DateTime? scheduledAt,
  });
}
