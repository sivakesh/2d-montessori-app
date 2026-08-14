/// The processing lifecycle a media asset moves through after upload
/// (SRS MED-01..MED-06). Distinct from [archived] on [MediaAsset], which
/// is a separate axis (recycle-bin state) only meaningful once an asset
/// is [ready] — see that type's doc comment.
enum MediaStatus {
  uploading('uploading'),
  processing('processing'),
  ready('ready'),
  failed('failed');

  const MediaStatus(this.storageValue);

  /// Persisted in `media/{mediaId}.status` — must match
  /// `functions/src/media/onMediaUploaded.ts`'s status strings exactly.
  final String storageValue;

  static MediaStatus? fromStorageValue(String? value) {
    for (final status in MediaStatus.values) {
      if (status.storageValue == value) return status;
    }
    return null;
  }
}
