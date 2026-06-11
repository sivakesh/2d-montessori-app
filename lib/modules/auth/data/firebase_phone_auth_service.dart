import 'package:firebase_auth/firebase_auth.dart';
// ignore: depend_on_referenced_packages
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:montessori_app/core/config/app_env.dart';

class FirebasePhoneAuthService {
  FirebasePhoneAuthService({FirebaseAuth? firebaseAuth})
      : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance;

  final FirebaseAuth _firebaseAuth;

  ConfirmationResult? _webConfirmationResult;
  RecaptchaVerifier? _recaptchaVerifier;
  String? _verificationId;

  Future<void> sendOtp(String phoneNumber) async {
    if (currentEnvironment == AppEnvironment.dev) {
      // DEV MODE: skip Firebase completely
      // ignore: avoid_print
      print('DEV MODE: Skipping OTP');
      return;
    }

    if (kIsWeb) {
      _recaptchaVerifier ??= RecaptchaVerifier(
        container: 'recaptcha-container',
        auth: FirebaseAuthPlatform.instance,
      );
      _webConfirmationResult = await _firebaseAuth.signInWithPhoneNumber(
        phoneNumber,
        _recaptchaVerifier!,
      );
      return;
    }

    await _firebaseAuth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      verificationCompleted: (credential) async {
        await _firebaseAuth.signInWithCredential(credential);
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

  Future<UserCredential?> verifyOtp(String otp) async {
    if (currentEnvironment == AppEnvironment.dev) {
      // ignore: avoid_print
      print('DEV MODE: Auto login');
      return null;
    }

    if (kIsWeb) {
      final confirmationResult = _webConfirmationResult;
      if (confirmationResult == null) {
        throw FirebaseAuthException(
          code: 'code-expired',
          message: 'Please request a new OTP.',
        );
      }
      final result = await confirmationResult.confirm(otp);
      _recaptchaVerifier?.clear();
      _recaptchaVerifier = null;
      _webConfirmationResult = null;
      return result;
    }

    final verificationId = _verificationId;
    if (verificationId == null) {
      throw FirebaseAuthException(
        code: 'code-expired',
        message: 'Please request a new OTP.',
      );
    }

    final credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: otp,
    );
    final result = await _firebaseAuth.signInWithCredential(credential);
    _recaptchaVerifier?.clear();
    _recaptchaVerifier = null;
    _webConfirmationResult = null;
    return result;
  }

  Future<void> signOut() async {
    await _firebaseAuth.signOut();
  }
}
