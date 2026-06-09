import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/widgets.dart';
import 'package:montessori_app/modules/auth/models/app_user.dart';

abstract class AuthService {
  Future<AppUser?> signIn();
  Future<void> signOut();
  Future<void> logout(WidgetRef ref, BuildContext context);
}
