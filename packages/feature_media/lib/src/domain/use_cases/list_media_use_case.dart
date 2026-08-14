import 'package:core_contracts/core_contracts.dart';

import '../media_asset.dart';
import '../media_repository.dart';
import '../media_usage_reference.dart';

/// SRS "Search and filtering" / "Media selection/reuse from Pages".
class ListMediaUseCase {
  const ListMediaUseCase(this._repository);

  final MediaRepository _repository;

  Future<Result<Page<MediaAsset>>> call({
    MediaFilter query = const MediaFilter(),
    PageRequest request = const PageRequest(),
  }) => _repository.list(query: query, request: request);
}

/// SRS "Usage references showing where an asset is used".
class ListMediaUsagesUseCase {
  const ListMediaUsagesUseCase(this._repository);

  final MediaRepository _repository;

  Future<Result<List<MediaUsageReference>>> call(String mediaId) =>
      _repository.listUsages(mediaId);
}
