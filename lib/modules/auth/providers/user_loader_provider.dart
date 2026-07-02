import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:montessori_app/core/config/app_env.dart';
import 'package:montessori_app/modules/auth/data/user_service.dart';
import 'package:montessori_app/modules/auth/models/app_user.dart';

final userLoaderProvider = FutureProvider<AppUser?>((ref) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null) return null;

  final uid = firebaseUser.uid;
  final phone = firebaseUser.phoneNumber ?? '';

  final userService = UserService();
  if (currentEnvironment == AppEnvironment.prod) {
    final userData =
        await userService.getUserByPhone(phone) ??
        await userService.getUserByFirebaseAuthUid(uid);
    if (userData == null) return null;

    return AppUser(
      id: userData['id']?.toString() ?? userService.normalizePhone(phone),
      phone:
          userData['phoneNumber']?.toString() ??
          userService.normalizePhone(phone),
      role: userData['role']?.toString() ?? 'user',
      isActive: userData['isActive'] ?? true,
      name: userData['name'] as String?,
    );
  }

  var userData = await userService.getUserByPhone(phone);
  userData ??= await userService.getUserByFirebaseAuthUid(uid);

  if (userData == null) return null;

  return AppUser(
    id: userData['id']?.toString() ?? userService.normalizePhone(phone),
    phone: userData['phoneNumber']?.toString() ?? '',
    role: userData['role']?.toString() ?? 'parent',
    isActive: userData['isActive'] ?? true,
    name: userData['name'] as String?,
  );
});
