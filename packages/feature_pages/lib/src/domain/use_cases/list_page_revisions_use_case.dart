import 'package:core_contracts/core_contracts.dart';

import '../page_repository.dart';
import '../page_revision.dart';

class ListPageRevisionsUseCase {
  const ListPageRevisionsUseCase(this._repository);

  final PagesRepository _repository;

  Future<Result<List<PageRevision>>> call(String pageId) =>
      _repository.listRevisions(pageId);
}
