/// Pages & Sections
///
/// Managed pages, approved section-template registry, ordered sections
/// and previews.
///
/// Traceability: SRS WEB-01..WEB-03, CMS-01..CMS-15; PRD Section 4 (CMS
/// Page Builder), Section 5.1/5.2 (Page/SEO models)
///
/// Public API barrel. This feature owns lib/src/domain (entities, use
/// cases, repository interfaces), lib/src/data (DTOs, mappers, Firestore/
/// Functions repository implementations) and lib/src/presentation
/// (Flutter screens/widgets/state) per PRD Section 11.1. No other feature
/// package may import lib/src/** directly — only this barrel, and only
/// through core_contracts/design_system-typed public members.
///
/// Reuses `feature_publishing`'s workflow engine unmodified rather than
/// duplicating it — see `PagesAsPublishingRepository`'s doc comment.
library;

export 'src/data/firestore_pages_repository.dart';
export 'src/data/firestore_public_pages_repository.dart';
export 'src/domain/call_to_action.dart';
export 'src/domain/cms_page.dart';
export 'src/domain/media_reference.dart';
export 'src/domain/page_completeness_validator.dart';
export 'src/domain/page_content_update.dart';
export 'src/domain/page_failures.dart';
export 'src/domain/page_repository.dart';
export 'src/domain/page_revision.dart';
export 'src/domain/page_section.dart';
export 'src/domain/page_type.dart';
export 'src/domain/pages_as_publishing_repository.dart';
export 'src/domain/public_page_view.dart';
export 'src/domain/public_pages_repository.dart';
export 'src/domain/seo_metadata.dart';
export 'src/domain/slug_format.dart';
export 'src/domain/use_cases/create_page_use_case.dart';
export 'src/domain/use_cases/get_page_use_case.dart';
export 'src/domain/use_cases/list_page_revisions_use_case.dart';
export 'src/domain/use_cases/list_pages_use_case.dart';
export 'src/domain/use_cases/restore_page_revision_use_case.dart';
export 'src/domain/use_cases/update_page_content_use_case.dart';
export 'src/presentation/page_editor_controller.dart';
export 'src/presentation/page_editor_screen.dart';
export 'src/presentation/page_preview_screen.dart';
export 'src/presentation/page_section_renderer.dart';
export 'src/presentation/pages_list_screen.dart';
export 'src/presentation/pages_section.dart';
