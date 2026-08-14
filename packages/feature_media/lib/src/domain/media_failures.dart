import 'package:core_contracts/core_contracts.dart';

/// SRS "approved file-type and size limits" — raised client-side before
/// ever attempting an upload; the authoritative, non-spoofable check is
/// still `storage.rules` + `functions/src/media/onMediaUploaded.ts`
/// server-side (this is a fast local rejection, not the security
/// boundary).
final class UnapprovedMediaTypeFailure extends Failure {
  const UnapprovedMediaTypeFailure(String mimeType)
    : super(
        '"$mimeType" is not an approved file type.',
        code: 'unapproved-media-type',
      );
}

final class MediaTooLargeFailure extends Failure {
  const MediaTooLargeFailure(int maxSizeBytes)
    : super(
        'This file exceeds the maximum allowed size (${maxSizeBytes ~/ (1024 * 1024)}MB).',
        code: 'media-too-large',
      );
}

final class MediaNotFoundFailure extends Failure {
  const MediaNotFoundFailure([super.message = 'Media asset not found.'])
    : super(code: 'not-found');
}

/// SRS "Protection against deleting media currently in use" — raised
/// when attempting to permanently delete an asset `mediaUsages` still
/// references.
final class MediaInUseFailure extends Failure {
  const MediaInUseFailure([
    super.message =
        'This asset is still in use and cannot be permanently deleted.',
  ]) : super(code: 'media-in-use');
}

/// SRS "Archive/recycle-bin behaviour" — permanent delete is only valid
/// from within the recycle bin (an already-archived asset).
final class MediaNotArchivedFailure extends Failure {
  const MediaNotArchivedFailure([
    super.message =
        'Only an archived asset can be permanently deleted — archive it first.',
  ]) : super(code: 'media-not-archived');
}

/// Raised when editing metadata on an asset still mid-pipeline
/// (Uploading/Processing) — wait for Ready or Failed first.
final class MediaNotEditableFailure extends Failure {
  const MediaNotEditableFailure([
    super.message = 'This asset cannot be edited while it is still processing.',
  ]) : super(code: 'media-not-editable');
}

/// Upload failed on the transport layer itself (network error, Storage
/// rules rejection, etc.) — distinct from [UnapprovedMediaTypeFailure]/
/// [MediaTooLargeFailure], which are pre-flight client-side rejections
/// before any network call is even attempted.
final class MediaUploadFailure extends Failure {
  const MediaUploadFailure([
    super.message = 'The upload failed. Please try again.',
  ]) : super(code: 'media-upload-failed');
}
