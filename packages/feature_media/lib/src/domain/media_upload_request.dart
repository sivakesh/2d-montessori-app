import 'dart:typed_data';

import 'package:meta/meta.dart';

/// Client-side input to [MediaRepository.upload] — everything the
/// upload needs, gathered before any network call: `bytes` (Flutter
/// Web's `file_picker` returns file content as bytes directly, never a
/// filesystem path) plus the accessibility/descriptive fields SRS
/// requires up front, never added later.
@immutable
class MediaUploadRequest {
  const MediaUploadRequest({
    required this.bytes,
    required this.fileName,
    required this.mimeType,
    required this.title,
    required this.altText,
    this.description = '',
  });

  final Uint8List bytes;
  final String fileName;
  final String mimeType;
  final String title;

  /// Required, non-empty — SRS "accessible alt text".
  final String altText;

  final String description;
}
