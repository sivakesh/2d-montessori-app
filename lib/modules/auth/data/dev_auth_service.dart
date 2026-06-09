import 'package:montessori_app/core/services/auth_interface.dart';
import 'package:montessori_app/modules/auth/data/user_service.dart';
import 'package:montessori_app/modules/auth/models/app_user.dart';

class DevAuthService implements AuthService {
  DevAuthService({UserService? userService}) : _userService = userService ?? UserService();

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
    if (userData == null) {
      return null;
    }

    return AppUser.fromMap(
      phone,
      userData,
    );
  }

  @override
  Future<void> signOut() async {
  }
}
