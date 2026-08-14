import 'package:firebase_adapters/firebase_adapters.dart';

import '../domain/media_asset.dart';
import '../domain/media_mime_category.dart';
import '../domain/media_status.dart';
import '../domain/media_variant.dart';

/// Firestore document <-> [MediaAsset]. Internal to `data/` — mirrors
/// `feature_pages`' `CmsPageMapper` convention (not exported from the
/// package barrel).
abstract final class MediaAssetMapper {
  static MediaAsset fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) => fromMap(snapshot.id, snapshot.data() ?? const {});

  static MediaAsset fromMap(String mediaId, Map<String, dynamic> data) =>
      MediaAsset(
        mediaId: mediaId,
        fileName: data['fileName'] as String? ?? '',
        title: data['title'] as String? ?? '',
        description: data['description'] as String? ?? '',
        altText: data['altText'] as String? ?? '',
        mimeType: data['mimeType'] as String? ?? '',
        mimeCategory: MediaMimeCategory.fromStorageValue(
          data['mimeCategory'] as String?,
        ),
        fileSizeBytes: (data['fileSizeBytes'] as num?)?.toInt() ?? 0,
        width: (data['width'] as num?)?.toInt(),
        height: (data['height'] as num?)?.toInt(),
        orientation: MediaOrientation.fromStorageValue(
          data['orientation'] as String?,
        ),
        status:
            MediaStatus.fromStorageValue(data['status'] as String?) ??
            MediaStatus.processing,
        failureReason: data['failureReason'] as String?,
        archived: data['archived'] as bool? ?? false,
        storagePath: data['storagePath'] as String? ?? '',
        variants: _variantsFrom(data['variants']),
        usageCount: (data['usageCount'] as num?)?.toInt() ?? 0,
        uploadedBy: data['uploadedBy'] as String? ?? '',
        uploadedAt: (data['uploadedAt'] as Timestamp?)?.toDate(),
        updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
        archivedAt: (data['archivedAt'] as Timestamp?)?.toDate(),
        archivedBy: data['archivedBy'] as String?,
      );

  static Map<String, MediaVariant> _variantsFrom(Object? raw) {
    if (raw is! Map) return const {};
    return raw.map(
      (key, value) => MapEntry(
        key as String,
        MediaVariant.fromMap(Map<String, Object?>.from(value as Map)),
      ),
    );
  }
}
