import 'package:core_contracts/core_contracts.dart';
import 'package:feature_publishing/feature_publishing.dart';

import '../cms_page.dart';
import '../page_content_update.dart';
import '../page_failures.dart';
import '../page_repository.dart';
import '../slug_format.dart';

/// SRS §3: Editor may edit only pages they own ("Edit all content:
/// Assigned/permitted"); Publisher/Super Admin may edit any page ("Edit
/// all content: Yes") — the same interpretation `feature_publishing`
/// already established for this exact SRS ambiguity (see
/// `SubmitForReviewUseCase`'s doc comment there). Content edits are only
/// ever allowed while the page is a Draft — see [PageNotEditableFailure].
class UpdatePageContentUseCase {
  const UpdatePageContentUseCase(this._repository);

  final PagesRepository _repository;

  Future<Result<CmsPage>> call({
    required CmsPage currentPage,
    required PageContentUpdate content,
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

    if (content.title.trim().isEmpty) {
      return const Result.failure(ValidationFailure('Title is required.'));
    }
    if (content.slug.trim().isEmpty) {
      return const Result.failure(ValidationFailure('A URL slug is required.'));
    }
    if (!isValidSlugFormat(content.slug)) {
      return const Result.failure(
        ValidationFailure(
          'The URL slug must be lowercase letters, numbers and hyphens only.',
        ),
      );
    }

    return _repository.updateContent(
      pageId: currentPage.pageId,
      content: content,
    );
  }
}
