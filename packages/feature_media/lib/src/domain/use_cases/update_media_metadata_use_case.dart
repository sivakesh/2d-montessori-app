import 'package:core_contracts/core_contracts.dart';

import '../media_asset.dart';
import '../media_failures.dart';
import '../media_repository.dart';
import '../media_status.dart';

/// SRS §3: Editor may edit only assets they uploaded; Publisher/Super
/// Admin may edit any asset — the same "own vs. all" split
/// `UpdatePageContentUseCase` already established for `editAllContent`,
/// applied here to `manageMediaLibrary`.
class UpdateMediaMetadataUseCase {
  const UpdateMediaMetadataUseCase(this._repository);

  final MediaRepository _repository;

  Future<Result<MediaAsset>> call({
    required MediaAsset currentAsset,
    required String title,
    required String altText,
    String description = '',
    required UserRole actingRole,
    required String actorId,
  }) async {
    if (currentAsset.status != MediaStatus.ready &&
        currentAsset.status != MediaStatus.failed) {
      return const Result.failure(MediaNotEditableFailure());
    }

    final canManageAll = RolePermissionMatrix.hasFull(
      actingRole,
      Capability.manageMediaLibrary,
    );
    if (!canManageAll && currentAsset.uploadedBy != actorId) {
      return const Result.failure(PermissionFailure());
    }

    if (title.trim().isEmpty) {
      return const Result.failure(ValidationFailure('A title is required.'));
    }
    if (altText.trim().isEmpty) {
      return const Result.failure(
        ValidationFailure('Accessible alt text is required.'),
      );
    }

    return _repository.updateMetadata(
      mediaId: currentAsset.mediaId,
      title: title.trim(),
      altText: altText.trim(),
      description: description.trim(),
    );
  }
}
