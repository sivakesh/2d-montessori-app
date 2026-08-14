import 'package:feature_media/feature_media.dart';

MediaAsset sampleMediaAsset({
  String mediaId = 'media-1',
  String title = 'Logo',
  String altText = 'The school logo',
  MediaStatus status = MediaStatus.ready,
  bool archived = false,
  String uploadedBy = 'uploader-1',
  int usageCount = 0,
  Map<String, MediaVariant> variants = const {},
}) {
  return MediaAsset(
    mediaId: mediaId,
    fileName: 'logo.png',
    title: title,
    altText: altText,
    status: status,
    archived: archived,
    storagePath: 'private/media/$mediaId/original.png',
    uploadedBy: uploadedBy,
    usageCount: usageCount,
    variants: variants,
  );
}
