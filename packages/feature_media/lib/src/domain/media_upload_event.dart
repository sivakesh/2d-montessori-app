import 'package:core_contracts/core_contracts.dart';
import 'package:meta/meta.dart';

import 'media_asset.dart';

/// One event in an upload's lifecycle (SRS "Clear upload progress,
/// success and failure feedback") — [MediaRepository.upload] returns a
/// `Stream` of these rather than a single `Future` so a screen can show
/// the raw byte-transfer progress, then "processing...", then the final
/// Ready/Failed outcome, all from one subscription.
@immutable
sealed class MediaUploadEvent {
  const MediaUploadEvent();
}

/// Raw byte-transfer progress (0.0..1.0) — the Storage SDK's own
/// `UploadTask` progress, before the server has even started processing.
final class MediaUploadProgress extends MediaUploadEvent {
  const MediaUploadProgress(this.fraction);

  final double fraction;
}

/// The byte transfer itself finished; the asset now exists server-side
/// and is (or is about to be) [MediaStatus.processing]. [mediaId] is
/// known from the moment the upload started (client-generated), so this
/// event mainly signals "the transfer is done, processing has begun."
final class MediaUploadTransferComplete extends MediaUploadEvent {
  const MediaUploadTransferComplete(this.mediaId);

  final String mediaId;
}

/// The terminal event — processing finished, one way or the other.
/// [result] is `Ok` with the [MediaStatus.ready] asset, or `Err` with a
/// [MediaUploadFailure]-shaped [Failure] carrying the server's
/// `failureReason` (SRS "Uploading, Processing, Ready and Failed
/// statuses").
final class MediaUploadFinished extends MediaUploadEvent {
  const MediaUploadFinished(this.result);

  final Result<MediaAsset> result;
}
