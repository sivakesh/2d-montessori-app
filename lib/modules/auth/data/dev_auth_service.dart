import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:montessori_app/core/services/auth_interface.dart';
import 'package:montessori_app/modules/auth/data/user_service.dart';
import 'package:montessori_app/modules/auth/models/app_user.dart';
import 'package:montessori_app/modules/auth/providers/auth_provider.dart';
import 'package:montessori_app/services/user_session_log_service.dart';

class DevAuthService implements AuthService {
  DevAuthService({UserService? userService})
    : _userService = userService ?? UserService();

  final UserService _userService;

  @override
  Future<AppUser?> signIn() async {
    throw UnimplementedError('Use signInWithPhone in DevAuthService.');
  }

  Future<AppUser?> signInWithPhone(String phone) async {
    if (phone.isEmpty) {
      return null;
    }

    final userData = await _userService.getUserByPhone(phone);
    if (userData != null) {
      return AppUser(
        id: userData['id']?.toString() ?? _userService.normalizePhone(phone),
        phone:
            userData['phoneNumber']?.toString() ??
            _userService.normalizePhone(phone),
        name: userData['name']?.toString(),
        role: userData['role']?.toString() ?? 'parent',
        isActive: userData['isActive'] ?? true,
      );
    }

    final created = await _userService.createDevUser(phone);
    return AppUser(
      id: created['id']?.toString() ?? _userService.normalizePhone(phone),
      phone:
          created['phoneNumber']?.toString() ??
          _userService.normalizePhone(phone),
      name: created['name']?.toString(),
      role: created['role']?.toString() ?? 'parent',
      isActive: created['isActive'] ?? true,
    );
  }

  @override
  Future<void> signOut() async {}

  @override
  Future<void> logout(WidgetRef ref, BuildContext context) async {
    await UserSessionLogService().logLogout(source: 'logout_button');
    await FirebaseAuth.instance.signOut();
    ref.read(currentUserProvider.notifier).state = null;
    ref.invalidate(currentUserProvider);
  }
}
