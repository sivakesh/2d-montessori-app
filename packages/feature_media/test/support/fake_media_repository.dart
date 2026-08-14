import 'package:core_contracts/core_contracts.dart';
import 'package:feature_media/feature_media.dart';

/// Records the last call to each method and returns a pre-set
/// [Result] — mirrors `feature_pages`' `FakePagesRepository` convention.
class FakeMediaRepository implements MediaRepository {
  MediaUploadRequest? lastUploadRequest;
  String? lastUploadActorId;
  Stream<MediaUploadEvent> uploadResponse = const Stream.empty();

  String? lastGetMediaId;
  Result<MediaAsset> getResponse = const Result.failure(MediaNotFoundFailure());

  MediaFilter? lastListQuery;
  Result<Page<MediaAsset>> listResponse = const Result.ok(
    Page(items: [], nextCursor: null, hasMore: false),
  );

  String? lastUpdateMediaId;
  String? lastUpdateTitle;
  String? lastUpdateAltText;
  Result<MediaAsset> updateMetadataResponse = const Result.failure(
    MediaNotFoundFailure(),
  );

  String? lastArchivedMediaId;
  Result<void> archiveResponse = const Result.ok(null);

  String? lastRestoredMediaId;
  Result<void> restoreResponse = const Result.ok(null);

  String? lastDeletedMediaId;
  Result<void> deleteResponse = const Result.ok(null);

  Result<List<MediaUsageReference>> listUsagesResponse = const Result.ok([]);

  @override
  Stream<MediaUploadEvent> upload(
    MediaUploadRequest request, {
    required String actorId,
  }) {
    lastUploadRequest = request;
    lastUploadActorId = actorId;
    return uploadResponse;
  }

  @override
  Future<Result<MediaAsset>> get(String mediaId) async {
    lastGetMediaId = mediaId;
    return getResponse;
  }

  @override
  Stream<Result<MediaAsset>> observe(String mediaId) =>
      Stream.value(getResponse);

  @override
  Future<Result<Page<MediaAsset>>> list({
    MediaFilter query = const MediaFilter(),
    PageRequest request = const PageRequest(),
  }) async {
    lastListQuery = query;
    return listResponse;
  }

  @override
  Future<Result<MediaAsset>> updateMetadata({
    required String mediaId,
    required String title,
    required String altText,
    String description = '',
  }) async {
    lastUpdateMediaId = mediaId;
    lastUpdateTitle = title;
    lastUpdateAltText = altText;
    return updateMetadataResponse;
  }

  @override
  Future<Result<void>> archive(String mediaId) async {
    lastArchivedMediaId = mediaId;
    return archiveResponse;
  }

  @override
  Future<Result<void>> restore(String mediaId) async {
    lastRestoredMediaId = mediaId;
    return restoreResponse;
  }

  @override
  Future<Result<void>> delete(String mediaId) async {
    lastDeletedMediaId = mediaId;
    return deleteResponse;
  }

  @override
  Future<Result<List<MediaUsageReference>>> listUsages(String mediaId) async =>
      listUsagesResponse;
}
