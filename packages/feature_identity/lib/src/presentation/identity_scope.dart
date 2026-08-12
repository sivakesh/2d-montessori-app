import 'package:flutter/widgets.dart';

import '../domain/auth_repository.dart';
import '../domain/use_cases/admin/create_user_use_case.dart';
import '../domain/use_cases/admin/reset_user_password_use_case.dart';
import '../domain/use_cases/admin/set_user_role_use_case.dart';
import '../domain/use_cases/admin/set_user_status_use_case.dart';
import '../domain/use_cases/complete_forced_password_change_use_case.dart';
import '../domain/use_cases/confirm_password_reset_use_case.dart';
import '../domain/use_cases/send_password_reset_use_case.dart';
import '../domain/use_cases/sign_in_use_case.dart';
import '../domain/use_cases/sign_out_use_case.dart';
import '../domain/user_admin_repository.dart';
import 'auth_controller.dart';

/// The composition root's single injection point for everything
/// `feature_identity` exposes. Built once in `apps/admin_web/lib/main.dart`
/// and made available to the whole widget tree via
/// `IdentityScope.of(context)`; screens never construct a repository or
/// use case themselves; this keeps every screen testable by wrapping it
/// in a test-only `IdentityScope` built from fakes.
class IdentityScope extends InheritedNotifier<AuthController> {
  IdentityScope({
    super.key,
    required AuthController controller,
    required AuthRepository authRepository,
    required this.userAdminRepository,
    required super.child,
  }) : signIn = SignInUseCase(authRepository),
       signOut = SignOutUseCase(authRepository),
       sendPasswordReset = SendPasswordResetUseCase(authRepository),
       confirmPasswordReset = ConfirmPasswordResetUseCase(authRepository),
       completeForcedPasswordChange = CompleteForcedPasswordChangeUseCase(
         authRepository,
       ),
       createUser = CreateUserUseCase(userAdminRepository),
       setUserRole = SetUserRoleUseCase(userAdminRepository),
       setUserStatus = SetUserStatusUseCase(userAdminRepository),
       resetUserPassword = ResetUserPasswordUseCase(userAdminRepository),
       super(notifier: controller);

  final UserAdminRepository userAdminRepository;

  final SignInUseCase signIn;
  final SignOutUseCase signOut;
  final SendPasswordResetUseCase sendPasswordReset;
  final ConfirmPasswordResetUseCase confirmPasswordReset;
  final CompleteForcedPasswordChangeUseCase completeForcedPasswordChange;
  final CreateUserUseCase createUser;
  final SetUserRoleUseCase setUserRole;
  final SetUserStatusUseCase setUserStatus;
  final ResetUserPasswordUseCase resetUserPassword;

  AuthController get controller => notifier!;

  static IdentityScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<IdentityScope>();
    assert(
      scope != null,
      'No IdentityScope found in context — wrap the app in one from main().',
    );
    return scope!;
  }
}
