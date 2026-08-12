import 'package:feature_identity/feature_identity.dart';
import 'package:firebase_adapters/firebase_adapters.dart';
import 'package:flutter/material.dart';

/// Admin/CMS entrypoint. Bootstraps against the local Firebase Emulator
/// Suite via [demoEmulatorFirebaseOptions] until the real dev/staging/prod
/// projects exist — see docs/architecture/environments.md.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await bootstrapFirebase(
    options: demoEmulatorFirebaseOptions,
    useEmulators: true,
  );

  final authRepository = FirebaseAuthRepository(
    auth: FirebaseAuth.instance,
    firestore: FirebaseFirestore.instance,
    functions: FirebaseFunctions.instance,
  );
  final userAdminRepository = UserAdminFunctionsRepository(
    firestore: FirebaseFirestore.instance,
    functions: FirebaseFunctions.instance,
  );
  final authController = AuthController(authRepository);

  runApp(
    AdminWebApp(
      authController: authController,
      authRepository: authRepository,
      userAdminRepository: userAdminRepository,
    ),
  );
}

class AdminWebApp extends StatelessWidget {
  const AdminWebApp({
    super.key,
    required this.authController,
    required this.authRepository,
    required this.userAdminRepository,
  });

  final AuthController authController;
  final AuthRepository authRepository;
  final UserAdminRepository userAdminRepository;

  /// The standard Firebase password-reset action link is
  /// `?mode=resetPassword&oobCode=...`. Detected here (once, at startup)
  /// from the browser URL rather than through a routing package — see
  /// docs/architecture/decisions.md "Admin routing" for why Phase 1
  /// Foundation doesn't introduce one yet.
  static String? _resetPasswordOobCodeFromUrl() {
    final params = Uri.base.queryParameters;
    if (params['mode'] != 'resetPassword') return null;
    return params['oobCode'];
  }

  @override
  Widget build(BuildContext context) {
    return IdentityScope(
      controller: authController,
      authRepository: authRepository,
      userAdminRepository: userAdminRepository,
      child: MaterialApp(
        title: '2D Montessori — Admin',
        debugShowCheckedModeBanner: false,
        home: Builder(
          builder: (context) {
            final oobCode = _resetPasswordOobCodeFromUrl();
            return oobCode != null
                ? ResetPasswordScreen(oobCode: oobCode)
                : const AuthGate();
          },
        ),
      ),
    );
  }
}
