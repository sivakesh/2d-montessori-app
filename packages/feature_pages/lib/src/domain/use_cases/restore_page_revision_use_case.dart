import 'package:core_contracts/core_contracts.dart';
import 'package:feature_publishing/feature_publishing.dart';

import '../cms_page.dart';
import '../page_failures.dart';
import '../page_repository.dart';

/// SRS CMS-06: "Authorised roles can compare and restore an earlier
/// version without erasing the audit trail." Same edit-authorization
/// rule as [UpdatePageContentUseCase] — restoring a revision is a content
/// edit, just one whose new values happen to come from history instead
/// of the current form.
class RestorePageRevisionUseCase {
  const RestorePageRevisionUseCase(this._repository);

  final PagesRepository _repository;

  Future<Result<CmsPage>> call({
    required CmsPage currentPage,
    required String revisionId,
    required UserRole actingRole,
    required String actorId,
  }) async {
    if (currentPage.status != PublishingStatus.draft) {
      return const Result.failure(PageNotEditableFailure());
    }

    final canEditAll = RolePermissionMatrix.hasFull(
      actingRole,
      Capability.editAllContent,
    );
    if (!canEditAll && currentPage.ownerId != actorId) {
      return const Result.failure(PermissionFailure());
    }

    return _repository.restoreRevision(
      pageId: currentPage.pageId,
      revisionId: revisionId,
      actorId: actorId,
    );
  }
}
