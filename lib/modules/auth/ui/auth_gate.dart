import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:montessori_app/modules/auth/providers/auth_provider.dart';
import 'package:montessori_app/modules/auth/providers/auth_state_provider.dart';
import 'package:montessori_app/modules/auth/providers/user_loader_provider.dart';
import 'package:montessori_app/modules/auth/ui/login_screen.dart';
import 'package:montessori_app/modules/auth/ui/splash_screen.dart';
import 'package:montessori_app/modules/dashboard/ui/dashboard_screen.dart';
import 'package:montessori_app/modules/parent/ui/parent_dashboard.dart';

class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);

    return authState.when(
      data: (User? user) {
        if (user == null) {
          ref.read(currentUserProvider.notifier).state = null;
          return const LoginScreen();
        }

        final userAsync = ref.watch(userLoaderProvider);

        return userAsync.when(
          data: (user) {
            if (user == null) {
              ref.read(currentUserProvider.notifier).state = null;
              return const LoginScreen();
            }

            ref.read(currentUserProvider.notifier).state = user;

            final role = user.role;
            if (role == 'admin' || role == 'staff') {
              return const DashboardScreen();
            }

            return const ParentDashboard();
          },
          loading: () => const SplashScreen(),
          error: (_, _) => const LoginScreen(),
        );
      },
      loading: () => const SplashScreen(),
      error: (_, _) => const LoginScreen(),
    );
  }
}
