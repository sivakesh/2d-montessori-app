import 'package:core_contracts/core_contracts.dart';

import '../media_asset.dart';
import '../media_repository.dart';

/// Same own-vs-all split as [UpdateMediaMetadataUseCase]. Archiving is
/// reversible (see [RestoreMediaUseCase]) — never blocked by usage,
/// unlike permanent delete (see [DeleteMediaUseCase]).
class ArchiveMediaUseCase {
  const ArchiveMediaUseCase(this._repository);

  final MediaRepository _repository;

  Future<Result<void>> call({
    required MediaAsset currentAsset,
    required UserRole actingRole,
    required String actorId,
  }) {
    final canManageAll = RolePermissionMatrix.hasFull(
      actingRole,
      Capability.manageMediaLibrary,
    );
    if (!canManageAll && currentAsset.uploadedBy != actorId) {
      return Future.value(const Result.failure(PermissionFailure()));
    }
    return _repository.archive(currentAsset.mediaId);
  }
}

class RestoreMediaUseCase {
  const RestoreMediaUseCase(this._repository);

  final MediaRepository _repository;

  Future<Result<void>> call({
    required MediaAsset currentAsset,
    required UserRole actingRole,
    required String actorId,
  }) {
    final canManageAll = RolePermissionMatrix.hasFull(
      actingRole,
      Capability.manageMediaLibrary,
    );
    if (!canManageAll && currentAsset.uploadedBy != actorId) {
      return Future.value(const Result.failure(PermissionFailure()));
    }
    return _repository.restore(currentAsset.mediaId);
  }
}
