/// Approved upload categories (SRS "approved file-type and size limits").
/// Mirrors `functions/src/media/validators.ts`'s `MediaMimeCategory`.
enum MediaMimeCategory {
  image('image'),
  video('video'),
  document('document');

  const MediaMimeCategory(this.storageValue);

  final String storageValue;

  static MediaMimeCategory? fromStorageValue(String? value) {
    for (final category in MediaMimeCategory.values) {
      if (category.storageValue == value) return category;
    }
    return null;
  }
}

/// Server-confirmed image orientation, derived from real pixel
/// dimensions once processing finishes — never guessed client-side.
enum MediaOrientation {
  landscape('landscape'),
  portrait('portrait'),
  square('square');

  const MediaOrientation(this.storageValue);

  final String storageValue;

  static MediaOrientation? fromStorageValue(String? value) {
    for (final orientation in MediaOrientation.values) {
      if (orientation.storageValue == value) return orientation;
    }
    return null;
  }
}
