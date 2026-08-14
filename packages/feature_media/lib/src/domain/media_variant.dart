import 'package:meta/meta.dart';

/// One generated, publicly-servable derivative of a media asset — a
/// responsive WebP width for an image, or the untransformed original for
/// a video/document (SRS "Responsive image variants and image
/// optimisation" / "WebP generation where suitable" / video/document
/// thumbnail generation deferred in Phase 1). Always lives under
/// `public/**` in Storage — see `firebase/storage.rules`.
@immutable
class MediaVariant {
  const MediaVariant({
    required this.storagePath,
    required this.url,
    required this.format,
    this.width,
    this.height,
  });

  final String storagePath;
  final String url;

  /// `webp` for generated image variants, or the original file
  /// extension (`pdf`, `mp4`, ...) for the untransformed video/document
  /// passthrough.
  final String format;

  final int? width;
  final int? height;

  Map<String, Object?> toMap() => {
    'storagePath': storagePath,
    'url': url,
    'format': format,
    'width': width,
    'height': height,
  };

  factory MediaVariant.fromMap(Map<String, Object?> map) => MediaVariant(
    storagePath: map['storagePath'] as String? ?? '',
    url: map['url'] as String? ?? '',
    format: map['format'] as String? ?? '',
    width: map['width'] as int?,
    height: map['height'] as int?,
  );

  @override
  bool operator ==(Object other) =>
      other is MediaVariant &&
      other.storagePath == storagePath &&
      other.url == url &&
      other.format == format &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(storagePath, url, format, width, height);
}
