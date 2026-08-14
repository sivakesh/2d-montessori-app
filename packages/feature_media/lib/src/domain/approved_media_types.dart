import 'media_mime_category.dart';

/// SRS "approved file-type and size limits" — the Dart mirror of
/// `functions/src/media/validators.ts`'s `APPROVED_MEDIA_TYPES` (hand-
/// synced, not code-shared, the same established convention
/// `publishing_state_machine.dart`/`stateMachine.ts` already use). This
/// is a fast, local pre-upload check only — `storage.rules` and
/// `onMediaUploaded.ts` are the actual, non-spoofable security boundary;
/// keep both lists in sync when either changes.
class ApprovedMediaType {
  const ApprovedMediaType({
    required this.mimeType,
    required this.category,
    required this.maxSizeBytes,
  });

  final String mimeType;
  final MediaMimeCategory category;
  final int maxSizeBytes;
}

const _mb = 1024 * 1024;

const List<ApprovedMediaType> approvedMediaTypes = [
  ApprovedMediaType(
    mimeType: 'image/jpeg',
    category: MediaMimeCategory.image,
    maxSizeBytes: 10 * _mb,
  ),
  ApprovedMediaType(
    mimeType: 'image/png',
    category: MediaMimeCategory.image,
    maxSizeBytes: 10 * _mb,
  ),
  ApprovedMediaType(
    mimeType: 'image/webp',
    category: MediaMimeCategory.image,
    maxSizeBytes: 10 * _mb,
  ),
  ApprovedMediaType(
    mimeType: 'image/gif',
    category: MediaMimeCategory.image,
    maxSizeBytes: 10 * _mb,
  ),
  ApprovedMediaType(
    mimeType: 'video/mp4',
    category: MediaMimeCategory.video,
    maxSizeBytes: 200 * _mb,
  ),
  ApprovedMediaType(
    mimeType: 'video/webm',
    category: MediaMimeCategory.video,
    maxSizeBytes: 200 * _mb,
  ),
  ApprovedMediaType(
    mimeType: 'application/pdf',
    category: MediaMimeCategory.document,
    maxSizeBytes: 25 * _mb,
  ),
];

ApprovedMediaType? approvedMediaTypeFor(String mimeType) {
  for (final type in approvedMediaTypes) {
    if (type.mimeType == mimeType) return type;
  }
  return null;
}
