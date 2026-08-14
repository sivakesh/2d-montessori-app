import 'package:core_contracts/core_contracts.dart';

import '../media_asset.dart';
import '../media_failures.dart';
import '../media_repository.dart';

/// Permanent delete (SRS "Archive/recycle-bin behaviour" +
/// "Protection against deleting media currently in use"). Two client-
/// side pre-checks mirror the server's authoritative ones exactly (see
/// `functions/src/media/deleteMedia.ts`) purely for fast UI feedback —
/// the server re-checks both regardless, since a client check can never
/// be trusted as the actual security boundary.
class DeleteMediaUseCase {
  const DeleteMediaUseCase(this._repository);

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
    if (!currentAsset.archived) {
      return Future.value(const Result.failure(MediaNotArchivedFailure()));
    }
    if (currentAsset.usageCount > 0) {
      return Future.value(const Result.failure(MediaInUseFailure()));
    }
    return _repository.delete(currentAsset.mediaId);
  }
}
