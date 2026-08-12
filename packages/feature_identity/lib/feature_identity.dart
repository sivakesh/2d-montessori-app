/// Identity & Access
///
/// Authentication session, user profile, custom-claim role display and
/// authorization gates.
///
/// Traceability: SRS AUTH-01..AUTH-05; PRD Section 2 (Users, Roles and
/// Permissions)
///
/// Public API barrel. This feature owns lib/src/domain (entities, use
/// cases, repository interfaces), lib/src/data (DTOs, mappers, Firestore/
/// Storage/Functions repository implementations) and lib/src/presentation
/// (Flutter screens/widgets/state) per PRD Section 11.1. No other feature
/// package may import lib/src/** directly — only this barrel.
library;

export 'src/data/firebase_auth_repository.dart';
export 'src/data/user_admin_functions_repository.dart';
export 'src/domain/auth_failures.dart';
export 'src/domain/auth_repository.dart';
export 'src/domain/auth_session.dart';
export 'src/domain/password_policy.dart';
export 'src/domain/use_cases/admin/create_user_use_case.dart';
export 'src/domain/use_cases/admin/reset_user_password_use_case.dart';
export 'src/domain/use_cases/admin/set_user_role_use_case.dart';
export 'src/domain/use_cases/admin/set_user_status_use_case.dart';
export 'src/domain/use_cases/change_own_password_use_case.dart';
export 'src/domain/use_cases/complete_forced_password_change_use_case.dart';
export 'src/domain/use_cases/confirm_password_reset_use_case.dart';
export 'src/domain/use_cases/send_password_reset_use_case.dart';
export 'src/domain/use_cases/sign_in_use_case.dart';
export 'src/domain/use_cases/sign_out_use_case.dart';
export 'src/domain/user_account.dart';
export 'src/domain/user_admin_repository.dart';
export 'src/presentation/auth_controller.dart';
export 'src/presentation/auth_gate.dart';
export 'src/presentation/identity_scope.dart';
export 'src/presentation/screens/reset_password_screen.dart';
