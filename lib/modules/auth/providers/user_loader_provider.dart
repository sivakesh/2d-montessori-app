import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:montessori_app/modules/auth/data/user_service.dart';
import 'package:montessori_app/modules/auth/models/app_user.dart';

final userLoaderProvider = FutureProvider<AppUser?>((ref) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null) return null;

  final uid = firebaseUser.uid;
  final phone = firebaseUser.phoneNumber?.replaceAll('+91', '') ?? '';

  final userService = UserService();

  var userData = await userService.getUserByUid(uid);
  userData ??= await userService.getUserByPhone(phone);

  if (userData == null) return null;

  return AppUser(
    id: uid,
    phone: userData['phone'] ?? '',
    role: userData['role'] ?? 'staff',
    isActive: userData['isActive'] ?? true,
    name: userData['name'] as String?,
  );
});
