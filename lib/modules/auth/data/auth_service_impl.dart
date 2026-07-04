import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:montessori_app/core/config/app_env.dart';
import 'package:montessori_app/core/services/auth_interface.dart';
import 'package:montessori_app/modules/auth/data/dev_auth_service.dart';
import 'package:montessori_app/modules/auth/models/app_user.dart';
import 'package:montessori_app/modules/auth/providers/auth_provider.dart';
import 'package:montessori_app/services/user_session_log_service.dart';

class _LogoutOnlyAuthService implements AuthService {
  @override
  Future<AppUser?> signIn() async {
    throw UnimplementedError('Use the dedicated auth flow.');
  }

  @override
  Future<void> signOut() async {
    await FirebaseAuth.instance.signOut();
  }

  @override
  Future<void> logout(WidgetRef ref, BuildContext context) async {
    await UserSessionLogService().logLogout(source: 'logout_button');
    await FirebaseAuth.instance.signOut();
    ref.read(currentUserProvider.notifier).state = null;
    ref.invalidate(currentUserProvider);
  }
}

AuthService getAuthService() {
  if (currentEnvironment == AppEnvironment.dev) {
    return DevAuthService();
  }
  return _LogoutOnlyAuthService();
}
