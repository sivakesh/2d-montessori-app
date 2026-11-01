import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:montessori_app/core/config/app_env.dart';
import 'package:montessori_app/modules/auth/data/user_service.dart';
import 'package:montessori_app/modules/auth/models/app_user.dart';
import 'package:montessori_app/modules/auth/providers/auth_state_provider.dart';

/// The app user for the signed-in Firebase account. Watches
/// [authStateProvider], so it reloads whenever the account signs in, out or
/// changes, rather than keeping the first account's profile.
final userLoaderProvider = FutureProvider<AppUser?>((ref) async {
  final firebaseUser = await ref.watch(authStateProvider.future);

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
