/// Media Library
///
/// Uploads, processing status, responsive/WebP derivatives, usage
/// tracking and archive/recycle-bin lifecycle for the CMS's shared media
/// library.
///
/// Traceability: SRS MED-01..MED-06; PRD Section 7 (Media Library)
///
/// Public API barrel. This feature owns lib/src/domain (entities, use
/// cases, repository interfaces), lib/src/data (DTOs, mappers,
/// Firestore/Storage/Functions repository implementations) and
/// lib/src/presentation (Flutter screens/widgets/state) per PRD Section
/// 11.1. No other feature package may import lib/src/** directly — only
/// this barrel. `feature_pages` depends on this package (not the
/// reverse) so its own picker/editor screens can select a [MediaAsset]
/// and turn it into a `MediaReference` — see [MediaAsset]'s own doc
/// comment.
library;

export 'src/data/firestore_media_repository.dart';
export 'src/domain/approved_media_types.dart';
export 'src/domain/media_asset.dart';
export 'src/domain/media_failures.dart';
export 'src/domain/media_mime_category.dart';
export 'src/domain/media_repository.dart';
export 'src/domain/media_status.dart';
export 'src/domain/media_upload_event.dart';
export 'src/domain/media_upload_request.dart';
export 'src/domain/media_usage_reference.dart';
export 'src/domain/media_variant.dart';
export 'src/domain/use_cases/archive_media_use_case.dart';
export 'src/domain/use_cases/delete_media_use_case.dart';
export 'src/domain/use_cases/get_media_use_case.dart';
export 'src/domain/use_cases/list_media_use_case.dart';
export 'src/domain/use_cases/update_media_metadata_use_case.dart';
export 'src/domain/use_cases/upload_media_use_case.dart';
export 'src/presentation/media_library_controller.dart';
export 'src/presentation/media_library_screen.dart';
export 'src/presentation/media_picker_dialog.dart';
