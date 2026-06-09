import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:montessori_app/core/config/app_env.dart';
import 'package:montessori_app/core/services/auth_interface.dart';
import 'package:montessori_app/modules/auth/data/auth_service_impl.dart';
import 'package:montessori_app/modules/auth/data/firebase_phone_auth_service.dart';
import 'package:montessori_app/modules/auth/models/app_user.dart';

final authServiceProvider = Provider<AuthService>((ref) => getAuthService());
final firebasePhoneAuthServiceProvider =
    Provider<FirebasePhoneAuthService>((ref) => FirebasePhoneAuthService());

final currentUserProvider = StateProvider<AppUser?>((ref) => null);

final environmentProvider = Provider<AppEnvironment>((ref) => currentEnvironment);
