import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'firebase_options.dart';
import 'core/theme/app_theme.dart';
import 'modules/auth/ui/auth_gate.dart';
import 'modules/auth/ui/login_screen.dart';
import 'modules/auth/ui/otp_screen.dart';
import 'modules/dashboard/ui/dashboard_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  // ignore: avoid_print
  print('Firebase initialized');
  runApp(
    const ProviderScope(
      child: MontessoriApp(),
    ),
  );
}

class MontessoriApp extends StatelessWidget {
  const MontessoriApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '2D Montessori',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const AuthGate(),
      routes: {
        '/login': (context) => const LoginScreen(),
        '/dashboard': (context) => const DashboardScreen(),
      },
      onGenerateRoute: (settings) {
        if (settings.name == '/otp') {
          final arguments = settings.arguments as Map<String, dynamic>;
          return MaterialPageRoute(
            builder: (_) => OtpScreen(
              phoneNumber: arguments['phone'] as String,
              verificationId: arguments['verificationId'] as String,
            ),
          );
        }
        return null;
      },
    );
  }
}
