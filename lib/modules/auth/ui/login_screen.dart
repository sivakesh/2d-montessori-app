import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:montessori_app/core/theme/app_colors.dart';
import 'package:montessori_app/core/widgets/app_logo.dart';
import 'package:montessori_app/modules/auth/data/user_service.dart';
import 'package:montessori_app/modules/auth/providers/auth_provider.dart';
import 'package:montessori_app/modules/auth/models/app_user.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final TextEditingController _countryCodeController =
      TextEditingController(text: '+91');
  final TextEditingController _phoneController = TextEditingController();
  bool _isLoading = false;
  String? _message;

  @override
  void dispose() {
    _countryCodeController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> handleDevLogin(WidgetRef ref, BuildContext context) async {
    final userService = UserService();
    var phone = _phoneController.text.trim();

    if (phone.startsWith('+91')) {
      phone = phone.substring(3);
    }

    phone = phone.replaceAll(' ', '');

    final userData = await userService.getUserByPhone(phone);

    if (userData != null) {
      final user = AppUser(
        id: phone,
        phone: userData['phone'] ?? phone,
        name: userData['name'],
        role: userData['role'] ?? 'staff',
        isActive: userData['isActive'] ?? true,
      );

      ref.read(currentUserProvider.notifier).state = user;

      if (context.mounted) {
        Navigator.pushReplacementNamed(context, '/dashboard');
      }
    } else {
      // ignore: avoid_print
      print('DEV: User not found');
    }
  }

  Future<void> handleProdLogin(BuildContext context) async {
    final rawPhone = _phoneController.text.trim();
    final fullPhone = '+91$rawPhone';

    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: fullPhone,
      verificationCompleted: (_) {},
      verificationFailed: (e) {
        // ignore: avoid_print
        print('OTP Error: $e');
      },
      codeSent: (verificationId, resendToken) {
        Navigator.pushNamed(
          context,
          '/otp',
          arguments: {
            'verificationId': verificationId,
            'phone': rawPhone,
          },
        );
      },
      codeAutoRetrievalTimeout: (_) {},
    );
  }

  Future<void> _handleLogin() async {
    final phone = _phoneController.text.trim();
    final digitsOnly = phone.replaceAll(RegExp(r'[^0-9]'), '');

    if (digitsOnly.length != 10) {
      setState(() => _message = 'Enter a valid 10-digit phone number.');
      return;
    }

    setState(() {
      _isLoading = true;
      _message = null;
    });

    try {
      // ignore: avoid_print
      print("kReleaseMode: $kReleaseMode");
      if (!kReleaseMode) {
        await handleDevLogin(ref, context);
        return;
      }

      await handleProdLogin(context);
    } catch (error) {
      if (mounted) {
        setState(() => _message = _readableAuthError(error));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _readableAuthError(Object error) {
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'invalid-phone-number':
          return 'Please enter a valid phone number.';
        case 'too-many-requests':
          return 'Too many attempts. Please try again later.';
        case 'network-request-failed':
          return 'Network error. Please check your connection.';
        default:
          return error.message ?? 'Authentication failed.';
      }
    }
    return error.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
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
                  const AppLogo(size: 120, padding: EdgeInsets.only(bottom: 24)),
                  Text(
                    'Welcome back',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Enter your phone number to continue',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                  const SizedBox(height: 32),
                  Row(
                    children: [
                      SizedBox(
                        width: 96,
                        child: TextField(
                          controller: _countryCodeController,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'Code',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'Phone number',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _isLoading ? null : _handleLogin,
                    child: const Text('Send OTP'),
                  ),
                  if (_message != null) ...[
                    const SizedBox(height: 16),
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
