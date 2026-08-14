import 'package:core_contracts/core_contracts.dart';

import '../approved_media_types.dart';
import '../media_failures.dart';
import '../media_repository.dart';
import '../media_upload_event.dart';
import '../media_upload_request.dart';

/// SRS §3: every role has at least `limited` (own uploads) access to the
/// media library — there is no role that cannot upload at all, only a
/// difference in what they may later archive/delete (see
/// [ArchiveMediaUseCase]/[DeleteMediaUseCase]).
class UploadMediaUseCase {
  const UploadMediaUseCase(this._repository);

  final MediaRepository _repository;

  Stream<MediaUploadEvent> call({
    required MediaUploadRequest request,
    required UserRole actingRole,
    required String actorId,
  }) {
    if (!RolePermissionMatrix.hasAny(
      actingRole,
      Capability.manageMediaLibrary,
    )) {
      return Stream.value(
        const MediaUploadFinished(Result.failure(PermissionFailure())),
      );
    }
    if (request.title.trim().isEmpty) {
      return Stream.value(
        const MediaUploadFinished(
          Result.failure(ValidationFailure('A title is required.')),
        ),
      );
    }
    if (request.altText.trim().isEmpty) {
      return Stream.value(
        const MediaUploadFinished(
          Result.failure(ValidationFailure('Accessible alt text is required.')),
        ),
      );
    }
    final approvedType = approvedMediaTypeFor(request.mimeType);
    if (approvedType == null) {
      return Stream.value(
        MediaUploadFinished(
          Result.failure(UnapprovedMediaTypeFailure(request.mimeType)),
        ),
      );
    }
    if (request.bytes.lengthInBytes > approvedType.maxSizeBytes) {
      return Stream.value(
        MediaUploadFinished(
          Result.failure(MediaTooLargeFailure(approvedType.maxSizeBytes)),
        ),
      );
    }

    return _repository.upload(request, actorId: actorId);
  }
}
