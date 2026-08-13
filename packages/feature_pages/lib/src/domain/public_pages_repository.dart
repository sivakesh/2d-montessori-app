import 'package:core_contracts/core_contracts.dart';

import 'public_page_view.dart';

/// The public-site read path — deliberately a *separate* interface from
/// [PagesRepository], not a filtered view of it: it reads a different
/// collection (`publishedPages`, not `content`) under different Firestore
/// Rules (public read, no auth required), returns a different, reduced
/// type ([PublicPageView], not [CmsPage]), and can never see a draft,
/// scheduled, in-review or archived page — there is no status parameter
/// to accidentally request one with. This type-level separation is the
/// mechanism behind "render only published and currently valid content"
/// and "do not expose administrative fields", not a runtime check that
/// could be forgotten.
abstract class PublicPagesRepository {
  /// Returns [ContentNotFoundFailure] for any slug that isn't currently
  /// published — including a slug that exists but is a draft, is
  /// scheduled, or was unpublished/archived. The repository cannot
  /// distinguish "never existed" from "not currently public" and must
  /// not try to (doing so would itself leak information about
  /// unpublished content's existence).
  Future<Result<PublicPageView>> getBySlug(String slug);

  /// Published pages with `showInNavigation == true`, for header/footer
  /// navigation (SRS WEB-02).
  Future<Result<List<PublicPageView>>> listNavigationPages();
}
