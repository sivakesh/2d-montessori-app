/// Publishing & Versions
///
/// Editorial workflow states, transitions, scheduling foundation and
/// audit trail — the reusable engine every content feature
/// (feature_pages, feature_programs, ...) applies to its own documents.
///
/// Traceability: SRS CMS-02, CMS-03, CMS-05, CMS-08; PRD Section 9
/// (Editorial Workflow and Versioning)
///
/// Public API barrel — see docs/architecture/repository-structure.md for
/// why only this file (never lib/src/**) may be imported by other
/// packages.
library;

export 'src/data/firestore_publishing_repository.dart';
export 'src/domain/publishing_action.dart';
export 'src/domain/publishing_failures.dart';
export 'src/domain/publishing_record.dart';
export 'src/domain/publishing_repository.dart';
export 'src/domain/publishing_state_machine.dart';
export 'src/domain/publishing_status.dart';
export 'src/domain/publishing_transition_event.dart';
export 'src/domain/use_cases/approve_content_use_case.dart';
export 'src/domain/use_cases/archive_content_use_case.dart';
export 'src/domain/use_cases/publish_content_use_case.dart';
export 'src/domain/use_cases/reject_content_use_case.dart';
export 'src/domain/use_cases/restore_content_use_case.dart';
export 'src/domain/use_cases/schedule_content_use_case.dart';
export 'src/domain/use_cases/submit_for_review_use_case.dart';
export 'src/domain/use_cases/transition_content_use_case.dart';
export 'src/domain/use_cases/unpublish_content_use_case.dart';
export 'src/domain/use_cases/unschedule_content_use_case.dart';
