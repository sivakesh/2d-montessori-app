import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:montessori_app/core/theme/app_colors.dart';
import 'package:montessori_app/modules/auth/data/user_service.dart';
import 'package:montessori_app/modules/auth/models/app_user.dart';
import 'package:montessori_app/modules/auth/providers/auth_provider.dart';
import 'package:montessori_app/modules/auth/utils/recaptcha_cleanup.dart';

class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({
    super.key,
    required this.phoneNumber,
    required this.verificationId,
  });

  final String phoneNumber;
  final String verificationId;

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  final TextEditingController _otpController = TextEditingController();
  bool _isLoading = false;
  String? _message;

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  Future<AppUser> loginDev(String phoneNumber) async {
    final userService = UserService();
    final appUser = await userService.getOrCreateDevUser(phoneNumber);

    return AppUser(
      id: appUser['id']?.toString() ?? userService.normalizePhone(phoneNumber),
      phone:
          appUser['phoneNumber']?.toString() ??
          userService.normalizePhone(phoneNumber),
      name: appUser['name']?.toString(),
      role: appUser['role']?.toString() ?? 'parent',
      isActive: appUser['isActive'] ?? true,
    );
  }

  Future<AppUser> loginProdWithOtpCredential(AuthCredential credential) async {
    final userCredential = await FirebaseAuth.instance.signInWithCredential(
      credential,
    );

    final firebaseUser =
        FirebaseAuth.instance.currentUser ?? userCredential.user;
    if (firebaseUser == null) {
      throw FirebaseAuthException(
        code: 'no-auth-user',
        message: 'Login failed. Please try again.',
      );
    }

    final phoneNumber = firebaseUser.phoneNumber;
    if (phoneNumber == null || phoneNumber.isEmpty) {
      throw FirebaseAuthException(
        code: 'missing-phone-number',
        message: 'Phone number missing from authenticated user.',
      );
    }

    final userService = UserService();
    final appUser = await userService.getOrCreateProdUser(
      phoneNumber: phoneNumber,
      firebaseAuthUid: firebaseUser.uid,
    );

    return AppUser(
      id: appUser['id']?.toString() ?? userService.normalizePhone(phoneNumber),
      phone:
          appUser['phoneNumber']?.toString() ??
          userService.normalizePhone(phoneNumber),
      name: appUser['name']?.toString(),
      role: appUser['role']?.toString() ?? 'parent',
      isActive: appUser['isActive'] ?? true,
    );
  }

  Future<void> _verifyOtp() async {
    final otp = _otpController.text.trim();
    if (otp.length != 6) {
      setState(() => _message = 'Enter the 6-digit code.');
      return;
    }

    setState(() {
      _isLoading = true;
      _message = null;
    });

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: widget.verificationId,
        smsCode: otp,
      );

      if (kReleaseMode) {
        final appUser = await loginProdWithOtpCredential(credential);
        ref.read(currentUserProvider.notifier).state = appUser;
        if (mounted) {
          cleanupRecaptcha();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            cleanupRecaptcha();
          });
          Navigator.pushReplacementNamed(context, '/dashboard');
        }
      } else {
        final appUser = await loginDev(widget.phoneNumber);
        ref.read(currentUserProvider.notifier).state = appUser;
        if (mounted) {
          cleanupRecaptcha();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            cleanupRecaptcha();
          });
          Navigator.pushReplacementNamed(context, '/dashboard');
        }
      }
    } on FirebaseAuthException catch (error) {
      if (mounted) {
        setState(() => _message = _readableAuthError(error.code));
      }
    } catch (error) {
      if (mounted) {
        setState(() => _message = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _resendOtp() async {
    final authService = ref.read(firebasePhoneAuthServiceProvider);
    try {
      await authService.sendOtp(widget.phoneNumber);
      if (mounted) {
        setState(() => _message = 'OTP resent.');
      }
    } catch (error) {
      if (mounted) {
        setState(() => _message = error.toString());
      }
    }
  }

  String _readableAuthError(String code) {
    switch (code) {
      case 'invalid-phone-number':
        return 'Please enter a valid phone number.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      case 'code-expired':
        return 'The code expired. Request a new OTP.';
      case 'invalid-verification-code':
        return 'The OTP is invalid. Please check and try again.';
      case 'network-request-failed':
        return 'Network error. Please check your connection.';
      case 'user-not-provisioned':
        return 'This phone number has not been invited yet. Please contact admin.';
      case 'user-disabled':
        return 'This account has been deactivated. Please contact admin.';
      default:
        return 'Authentication failed. Please try again.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Verify OTP')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Enter the 6-digit code sent to ${widget.phoneNumber}',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _otpController,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: const InputDecoration(
                      labelText: 'OTP',
                      border: OutlineInputBorder(),
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _isLoading ? null : _verifyOtp,
                    child: const Text('Verify OTP'),
                  ),
                  TextButton(
                    onPressed: _isLoading ? null : _resendOtp,
                    child: const Text('Resend OTP'),
                  ),
                  if (_message != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _message!,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
