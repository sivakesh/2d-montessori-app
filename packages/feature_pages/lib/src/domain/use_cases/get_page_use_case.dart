import 'package:core_contracts/core_contracts.dart';

import '../cms_page.dart';
import '../page_repository.dart';

class GetPageUseCase {
  const GetPageUseCase(this._repository);

  final PagesRepository _repository;

  Future<Result<CmsPage>> call(String pageId) => _repository.get(pageId);
}
