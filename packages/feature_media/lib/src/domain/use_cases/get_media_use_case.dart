import 'package:core_contracts/core_contracts.dart';

import '../media_asset.dart';
import '../media_repository.dart';

class GetMediaUseCase {
  const GetMediaUseCase(this._repository);

  final MediaRepository _repository;

  Future<Result<MediaAsset>> call(String mediaId) => _repository.get(mediaId);
}
