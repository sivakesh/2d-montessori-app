import 'package:core_contracts/core_contracts.dart';

import 'media_asset.dart';
import 'media_mime_category.dart';
import 'media_upload_event.dart';
import 'media_upload_request.dart';
import 'media_usage_reference.dart';

/// Filters for [MediaRepository.list] — SRS "Search and filtering".
class MediaFilter {
  const MediaFilter({
    this.searchText,
    this.category,
    this.includeArchived = false,
  });

  final String? searchText;
  final MediaMimeCategory? category;

  /// `false` (the default) excludes archived assets — the ordinary
  /// library/picker view. The recycle-bin view passes `true` and filters
  /// to archived-only itself.
  final bool includeArchived;
}

/// The Media Library repository (SRS MED-01..MED-06). `feature_pages`
/// depends on this package (not the reverse) so its picker can select a
/// [MediaAsset] and turn it into a `MediaReference` without this package
/// needing to know Pages exist — see `MediaAsset`'s own doc comment.
abstract class MediaRepository {
  /// Uploads directly to Cloud Storage (authorized by `storage.rules`,
  /// not a callable — see `functions/src/media/index.ts`'s doc comment
  /// for why) and returns a stream of lifecycle events ending in
  /// [MediaUploadFinished] once server-side processing completes.
  /// [actorId] must be the caller's own uid — `storage.rules` requires
  /// the uploaded object's `uploadedBy` custom metadata to match
  /// `request.auth.uid` exactly, so a client cannot upload attributed to
  /// anyone else.
  Stream<MediaUploadEvent> upload(
    MediaUploadRequest request, {
    required String actorId,
  });

  Future<Result<MediaAsset>> get(String mediaId);

  Stream<Result<MediaAsset>> observe(String mediaId);

  Future<Result<Page<MediaAsset>>> list({
    MediaFilter query = const MediaFilter(),
    PageRequest request = const PageRequest(),
  });

  Future<Result<MediaAsset>> updateMetadata({
    required String mediaId,
    required String title,
    required String altText,
    String description = '',
  });

  /// Soft-delete (recycle bin) — reversible via [restore].
  Future<Result<void>> archive(String mediaId);

  Future<Result<void>> restore(String mediaId);

  /// Permanent delete. Only valid for an already-[archive]d asset with
  /// zero live usage references (SRS "Protection against deleting media
  /// currently in use") — see [MediaNotArchivedFailure]/[MediaInUseFailure].
  Future<Result<void>> delete(String mediaId);

  /// SRS "Usage references showing where an asset is used".
  Future<Result<List<MediaUsageReference>>> listUsages(String mediaId);
}
