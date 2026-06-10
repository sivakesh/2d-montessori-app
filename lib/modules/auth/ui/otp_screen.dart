import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:montessori_app/core/theme/app_colors.dart';
import 'package:montessori_app/modules/auth/data/user_service.dart';
import 'package:montessori_app/modules/auth/models/app_user.dart';
import 'package:montessori_app/modules/auth/providers/auth_provider.dart';

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

      final userCredential = await FirebaseAuth.instance.signInWithCredential(
        credential,
      );

      final firebaseUser = userCredential.user;

      if (firebaseUser != null) {
        final uid = firebaseUser.uid;
        final phone = firebaseUser.phoneNumber?.replaceAll('+91', '') ?? '';

        final userService = UserService();

        var userData = await userService.getUserByUid(uid);

        if (userData == null) {
          userData = await userService.getUserByPhone(phone);

          if (userData != null) {
            await FirebaseFirestore.instance
                .collection('users')
                .doc(uid)
                .set(userData);
          } else {
            await userService.createUser(uid, phone);
            userData = {'phone': phone, 'role': 'parent'};
          }
        }

        final appUser = AppUser(
          id: uid,
          phone: userData['phone'] ?? phone,
          name: userData['name'],
          role: userData['role'] ?? 'parent',
          isActive: userData['isActive'] ?? true,
        );

        ref.read(currentUserProvider.notifier).state = appUser;

        if (mounted) {
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
