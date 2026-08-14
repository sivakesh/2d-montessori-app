import 'package:meta/meta.dart';

import 'media_mime_category.dart';
import 'media_status.dart';
import 'media_variant.dart';

/// A Media Library asset (SRS MED-01..MED-06) — the admin-side entity
/// covering the full upload/processing/archive lifecycle. Distinct from
/// `feature_pages`' `MediaReference`, a lightweight embedded pointer a
/// page stores once an asset has been *selected*; this is the library's
/// own record. `feature_pages` depends on this package (not the other
/// way around) precisely so its picker can produce a `MediaReference`
/// from a [MediaAsset] without this package needing to know Pages exist.
@immutable
class MediaAsset {
  const MediaAsset({
    required this.mediaId,
    required this.fileName,
    required this.title,
    required this.altText,
    required this.status,
    required this.archived,
    required this.storagePath,
    required this.uploadedBy,
    this.description = '',
    this.mimeType = '',
    this.mimeCategory,
    this.fileSizeBytes = 0,
    this.width,
    this.height,
    this.orientation,
    this.failureReason,
    this.variants = const {},
    this.usageCount = 0,
    this.uploadedAt,
    this.updatedAt,
    this.archivedAt,
    this.archivedBy,
  });

  final String mediaId;
  final String fileName;
  final String title;
  final String description;

  /// Accessible alternative text (SRS "accessible alt text") — required
  /// non-empty at upload time (`storage.rules`' `hasRequiredAccessibilityMetadata()`).
  final String altText;

  final String mimeType;
  final MediaMimeCategory? mimeCategory;
  final int fileSizeBytes;

  /// Real pixel dimensions, confirmed server-side during processing —
  /// `null` for non-image assets or before processing completes.
  final int? width;
  final int? height;
  final MediaOrientation? orientation;

  final MediaStatus status;
  final String? failureReason;

  /// Recycle-bin state — a separate axis from [status]: an archived
  /// asset can still be [MediaStatus.ready] underneath (its files are
  /// untouched), it is just hidden from the default library/picker view.
  final bool archived;

  /// The *original's* Cloud Storage path — never a derivative's. Also
  /// what `feature_pages`' `MediaReference.storagePath` is set to when a
  /// picker selection is turned into a reference, so usage tracking can
  /// always recover a [mediaId] from any `MediaReference` it later sees.
  final String storagePath;

  /// Every generated public derivative, keyed by a variant name (e.g.
  /// `w640` for a 640px-wide WebP image variant, or `original` for a
  /// video/document passthrough) — see
  /// `functions/src/media/onMediaUploaded.ts`.
  final Map<String, MediaVariant> variants;

  /// Denormalized count of pages currently referencing this asset
  /// (SRS "usage references" / "protection against deleting media
  /// currently in use") — a fast display value only; the actual
  /// deletion-blocking check server-side queries `mediaUsages` directly,
  /// never trusts this counter alone.
  final int usageCount;

  final String uploadedBy;
  final DateTime? uploadedAt;
  final DateTime? updatedAt;
  final DateTime? archivedAt;
  final String? archivedBy;

  /// The variant to render when a single "best" representative image is
  /// needed (e.g. a picker thumbnail) — the smallest generated variant,
  /// since it is the cheapest to load and still recognizable; falls back
  /// to the largest if no small one was generated (a source image
  /// narrower than the smallest configured responsive width).
  MediaVariant? get thumbnailVariant {
    if (variants.isEmpty) return null;
    final sorted = variants.values.toList()
      ..sort((a, b) => (a.width ?? 0).compareTo(b.width ?? 0));
    return sorted.first;
  }

  /// The largest available variant — used when a page needs the
  /// highest-quality rendering (e.g. a hero/featured image).
  MediaVariant? get largestVariant {
    if (variants.isEmpty) return null;
    final sorted = variants.values.toList()
      ..sort((a, b) => (b.width ?? 0).compareTo(a.width ?? 0));
    return sorted.first;
  }

  MediaAsset copyWith({
    String? title,
    String? description,
    String? altText,
    MediaStatus? status,
    String? failureReason,
    bool? archived,
    Map<String, MediaVariant>? variants,
    int? usageCount,
    int? width,
    int? height,
    MediaOrientation? orientation,
    DateTime? updatedAt,
    DateTime? archivedAt,
    String? archivedBy,
  }) => MediaAsset(
    mediaId: mediaId,
    fileName: fileName,
    title: title ?? this.title,
    description: description ?? this.description,
    altText: altText ?? this.altText,
    mimeType: mimeType,
    mimeCategory: mimeCategory,
    fileSizeBytes: fileSizeBytes,
    width: width ?? this.width,
    height: height ?? this.height,
    orientation: orientation ?? this.orientation,
    status: status ?? this.status,
    failureReason: failureReason ?? this.failureReason,
    archived: archived ?? this.archived,
    storagePath: storagePath,
    variants: variants ?? this.variants,
    usageCount: usageCount ?? this.usageCount,
    uploadedBy: uploadedBy,
    uploadedAt: uploadedAt,
    updatedAt: updatedAt ?? this.updatedAt,
    archivedAt: archivedAt ?? this.archivedAt,
    archivedBy: archivedBy ?? this.archivedBy,
  );

  @override
  bool operator ==(Object other) =>
      other is MediaAsset &&
      other.mediaId == mediaId &&
      other.title == title &&
      other.altText == altText &&
      other.status == status &&
      other.archived == archived &&
      other.usageCount == usageCount;

  @override
  int get hashCode =>
      Object.hash(mediaId, title, altText, status, archived, usageCount);
}
