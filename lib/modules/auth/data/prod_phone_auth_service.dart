import 'package:firebase_auth/firebase_auth.dart';
// ignore: depend_on_referenced_packages
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:montessori_app/modules/auth/data/user_service.dart';
import 'package:montessori_app/modules/auth/models/app_user.dart';

class ProdPhoneAuthService {
  ProdPhoneAuthService({
    FirebaseAuth? firebaseAuth,
    UserService? userService,
  })  : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
        _userService = userService ?? UserService();

  final FirebaseAuth _firebaseAuth;
  final UserService _userService;

  ConfirmationResult? _webConfirmationResult;
  RecaptchaVerifier? _recaptchaVerifier;
  String? _mobileVerificationId;
  String? _pendingPhone;

  String buildE164Phone(String countryCode, String phone) {
    final code = countryCode.replaceAll(RegExp(r'[^0-9]'), '');
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');

    if (code.isEmpty || digits.isEmpty) {
      throw FirebaseAuthException(
        code: 'invalid-phone-number',
        message: 'Phone number is required.',
      );
    }

    if (digits.startsWith(code) && digits.length > 10) {
      return '+$digits';
    }

    return '+$code$digits';
  }

  Future<void> sendOtp({
    required String countryCode,
    required String phone,
  }) async {
    final fullPhone = buildE164Phone(countryCode, phone);
    _pendingPhone = fullPhone;

    debugPrint('PROD Send OTP to: $fullPhone');
    debugPrint('kIsWeb: $kIsWeb');

    if (kIsWeb) {
      _recaptchaVerifier?.clear();
      _recaptchaVerifier = null;
      _webConfirmationResult = null;

      _recaptchaVerifier = RecaptchaVerifier(
        container: 'recaptcha-container',
        auth: FirebaseAuthPlatform.instance,
      );

      try {
        _webConfirmationResult = await _firebaseAuth.signInWithPhoneNumber(
          fullPhone,
          _recaptchaVerifier!,
        );
      } on FirebaseAuthException {
        rethrow;
      } catch (e) {
        throw FirebaseAuthException(
          code: 'otp-send-failed',
          message: e.toString(),
        );
      }

      return;
    }

    await _firebaseAuth.verifyPhoneNumber(
      phoneNumber: fullPhone,
      verificationCompleted: (credential) async {
        await _firebaseAuth.signInWithCredential(credential);
      },
      verificationFailed: (FirebaseAuthException e) {
        debugPrint('PROD OTP failed: ${e.code} - ${e.message}');
        throw e;
      },
      codeSent: (verificationId, _) {
        _mobileVerificationId = verificationId;
      },
      codeAutoRetrievalTimeout: (verificationId) {
        _mobileVerificationId = verificationId;
      },
    );
  }

  Future<AppUser> verifyOtp(String otp) async {
    if (otp.trim().length != 6) {
      throw FirebaseAuthException(
        code: 'invalid-verification-code',
        message: 'Enter a valid 6-digit OTP.',
      );
    }

    UserCredential credential;

    if (kIsWeb) {
      final confirmationResult = _webConfirmationResult;
      if (confirmationResult == null) {
        throw FirebaseAuthException(
          code: 'code-expired',
          message: 'Please request a new OTP.',
        );
      }

      credential = await confirmationResult.confirm(otp.trim());
    } else {
      final verificationId = _mobileVerificationId;
      if (verificationId == null) {
        throw FirebaseAuthException(
          code: 'code-expired',
          message: 'Please request a new OTP.',
        );
      }

      final phoneCredential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: otp.trim(),
      );

      credential = await _firebaseAuth.signInWithCredential(phoneCredential);
    }

    final firebaseUser = credential.user;
    if (firebaseUser == null) {
      throw FirebaseAuthException(
        code: 'login-failed',
        message: 'Login failed. Please try again.',
      );
    }

    final phoneNumber = firebaseUser.phoneNumber ?? _pendingPhone;
    if (phoneNumber == null || phoneNumber.isEmpty) {
      throw FirebaseAuthException(
        code: 'missing-phone-number',
        message: 'Phone number missing from authenticated user.',
      );
    }

    final userData = await _userService.loginOrCreateUser(firebaseUser);

    await _cleanup();

    return AppUser(
      id: userData['id']?.toString() ?? _userService.normalizePhone(phoneNumber),
      phone:
          userData['phoneNumber']?.toString() ??
          _userService.normalizePhone(phoneNumber),
      name: userData['name']?.toString(),
      role: userData['role']?.toString() ?? 'parent',
      isActive: userData['isActive'] ?? true,
    );
  }

  Future<void> _cleanup() async {
    if (kIsWeb) {
      _recaptchaVerifier?.clear();
    }

    _recaptchaVerifier = null;
    _webConfirmationResult = null;
    _mobileVerificationId = null;
    _pendingPhone = null;
  }

  Future<void> signOut() async {
    await _firebaseAuth.signOut();
    await _cleanup();
  }
}
