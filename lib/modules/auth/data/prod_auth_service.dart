import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:montessori_app/core/services/auth_interface.dart';
import 'package:montessori_app/modules/auth/data/user_service.dart';
import 'package:montessori_app/modules/auth/models/app_user.dart';
import 'package:montessori_app/modules/auth/providers/auth_provider.dart';

class ProdAuthService implements AuthService {
  ProdAuthService({FirebaseAuth? firebaseAuth, UserService? userService})
    : _firebaseAuth = firebaseAuth,
      _userService = userService ?? UserService();

  final FirebaseAuth? _firebaseAuth;
  final UserService _userService;

  FirebaseAuth get firebaseAuth => _firebaseAuth ?? FirebaseAuth.instance;

  String? _verificationId;
  String? _pendingPhone;

  Future<void> startPhoneVerification(String phoneNumber) async {
    _pendingPhone = phoneNumber;
    await firebaseAuth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      verificationCompleted: (credential) async {
        await firebaseAuth.signInWithCredential(credential);
      },
      verificationFailed: (_) {},
      codeSent: (verificationId, _) {
        _verificationId = verificationId;
      },
      codeAutoRetrievalTimeout: (verificationId) {
        _verificationId = verificationId;
      },
    );
  }

  Future<AppUser?> verifyOtp(String smsCode) async {
    final verificationId = _verificationId;
    final phone = _pendingPhone;
    if (verificationId == null || phone == null) {
      return null;
    }

    final credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode,
    );
    final result = await firebaseAuth.signInWithCredential(credential);
    final firebaseUid = result.user?.uid;
    if (firebaseUid == null) {
      return null;
    }

    debugPrint('PROD auth started');
    debugPrint('Firebase Auth UID: $firebaseUid');
    debugPrint('Raw phone: $phone');
    debugPrint('Normalized phone: ${_userService.normalizePhone(phone)}');
    final resolvedData = await _userService.getOrCreateProdUser(
      firebaseAuthUid: firebaseUid,
      phoneNumber: phone,
    );
    return AppUser(
      id: resolvedData['id']?.toString() ?? _userService.normalizePhone(phone),
      phone:
          resolvedData['phoneNumber']?.toString() ??
          _userService.normalizePhone(phone),
      name: resolvedData['name']?.toString(),
      role: resolvedData['role']?.toString() ?? 'user',
      isActive: resolvedData['isActive'] ?? true,
    );
  }

  @override
  Future<AppUser?> signIn() async {
    throw UnimplementedError(
      'Use startPhoneVerification and verifyOtp in ProdAuthService.',
    );
  }

  @override
  Future<void> signOut() async {
    await firebaseAuth.signOut();
  }

  @override
  Future<void> logout(WidgetRef ref, BuildContext context) async {
    await firebaseAuth.signOut();
    ref.read(currentUserProvider.notifier).state = null;
    ref.invalidate(currentUserProvider);
  }
}
