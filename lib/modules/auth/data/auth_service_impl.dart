import 'package:montessori_app/core/config/app_env.dart';
import 'package:montessori_app/core/services/auth_interface.dart';
import 'package:montessori_app/modules/auth/data/dev_auth_service.dart';
import 'package:montessori_app/modules/auth/data/prod_auth_service.dart';

AuthService getAuthService() {
  if (currentEnvironment == AppEnvironment.dev) {
    return DevAuthService();
  }
  return ProdAuthService();
}
