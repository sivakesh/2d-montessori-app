import 'package:core_contracts/core_contracts.dart';

import '../cms_page.dart';
import '../page_repository.dart';

/// SRS §3: "Create/edit own drafts" is full for all three roles — any
/// signed-in CMS user may start a new page draft.
class CreatePageUseCase {
  const CreatePageUseCase(this._repository);

  final PagesRepository _repository;

  Future<Result<CmsPage>> call({
    required String title,
    required String ownerId,
  }) {
    if (title.trim().isEmpty) {
      return Future.value(
        const Result.failure(ValidationFailure('Title is required.')),
      );
    }
    return _repository.createPage(title: title.trim(), ownerId: ownerId);
  }
}
