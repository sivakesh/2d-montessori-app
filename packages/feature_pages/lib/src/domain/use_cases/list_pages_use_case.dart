import 'package:core_contracts/core_contracts.dart';

import '../cms_page.dart';
import '../page_repository.dart';

/// SRS CMS-10: "Search/filter by title, type, status, owner, ..."
class ListPagesUseCase {
  const ListPagesUseCase(this._repository);

  final PagesRepository _repository;

  Future<Result<Page<CmsPage>>> call({
    PagesQuery query = const PagesQuery(),
    PageRequest request = const PageRequest(),
  }) => _repository.list(query: query, request: request);
}
