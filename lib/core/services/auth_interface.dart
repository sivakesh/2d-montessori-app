import 'package:montessori_app/modules/auth/models/app_user.dart';

abstract class AuthService {
  Future<AppUser?> signIn();
  Future<void> signOut();
}
