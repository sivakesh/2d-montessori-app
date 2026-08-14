import 'package:meta/meta.dart';

/// One page's usage of a media asset (SRS "usage references showing
/// where an asset is used") — mirrors a `mediaUsages/{mediaId}__{contentId}`
/// Firestore document, maintained server-side by
/// `functions/src/media/usageTracking.ts` alongside every page content
/// save.
@immutable
class MediaUsageReference {
  const MediaUsageReference({
    required this.mediaId,
    required this.contentId,
    required this.contentTitle,
    required this.fieldPaths,
  });

  final String mediaId;
  final String contentId;
  final String contentTitle;

  /// Every field within [contentId]'s content that currently references
  /// this asset (e.g. `featuredImage`, `sections[2].image`) — more than
  /// one entry means the same page uses this asset in multiple places.
  final List<String> fieldPaths;

  factory MediaUsageReference.fromMap(Map<String, Object?> map) =>
      MediaUsageReference(
        mediaId: map['mediaId'] as String? ?? '',
        contentId: map['contentId'] as String? ?? '',
        contentTitle: map['contentTitle'] as String? ?? '',
        fieldPaths:
            (map['fieldPaths'] as List<Object?>?)?.cast<String>() ?? const [],
      );

  @override
  bool operator ==(Object other) =>
      other is MediaUsageReference &&
      other.mediaId == mediaId &&
      other.contentId == contentId;

  @override
  int get hashCode => Object.hash(mediaId, contentId);
}
