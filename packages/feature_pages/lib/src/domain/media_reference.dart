import 'package:meta/meta.dart';

/// A typed pointer to an already-uploaded media asset, plus the fields a
/// page needs to render it accessibly. This is deliberately the entire
/// surface `feature_pages` needs from media — not a media library. Per
/// this milestone's boundary, `feature_media` (upload pipeline,
/// processing status, derivatives, consent workflow) is not built yet;
/// [storagePath]/[url] are assumed already-hosted URLs a caller supplies
/// (e.g. pasted, or from a future media picker), and there is no
/// [MED-05](../../../../docs/architecture/decisions.md) "Ready" gating
/// here because there is no processing pipeline to gate on yet.
@immutable
class MediaReference {
  const MediaReference({
    required this.url,
    required this.altText,
    this.storagePath,
    this.caption,
  });

  /// Publicly resolvable URL for this media. Required — a reference with
  /// no URL cannot render anything.
  final String url;

  /// Accessible alternative text. Required and non-empty by construction
  /// (see [PageValidators]/[PageCompletenessValidator]) — WCAG 2.2 AA
  /// (NFR-02) and SRS CMS-08 ("validation checks... alt text") both
  /// require every content image to carry one.
  final String altText;

  /// Cloud Storage path, if this asset was uploaded through Firebase
  /// Storage rather than referenced by external URL. Optional — not
  /// every reference need come from Storage in this milestone.
  final String? storagePath;

  /// Optional visible caption, distinct from [altText] (which is for
  /// assistive technology, not necessarily shown on screen).
  final String? caption;

  MediaReference copyWith({
    String? url,
    String? altText,
    String? storagePath,
    String? caption,
  }) => MediaReference(
    url: url ?? this.url,
    altText: altText ?? this.altText,
    storagePath: storagePath ?? this.storagePath,
    caption: caption ?? this.caption,
  );

  Map<String, Object?> toMap() => {
    'url': url,
    'altText': altText,
    'storagePath': storagePath,
    'caption': caption,
  };

  factory MediaReference.fromMap(Map<String, Object?> map) => MediaReference(
    url: map['url'] as String? ?? '',
    altText: map['altText'] as String? ?? '',
    storagePath: map['storagePath'] as String?,
    caption: map['caption'] as String?,
  );

  @override
  bool operator ==(Object other) =>
      other is MediaReference &&
      other.url == url &&
      other.altText == altText &&
      other.storagePath == storagePath &&
      other.caption == caption;

  @override
  int get hashCode => Object.hash(url, altText, storagePath, caption);
}
