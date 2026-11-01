import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:montessori_app/modules/auth/providers/auth_session_provider.dart';
import 'package:montessori_app/modules/auth/providers/auth_state_provider.dart';
import 'package:montessori_app/modules/auth/providers/user_loader_provider.dart';
import 'package:montessori_app/modules/auth/ui/login_screen.dart';
import 'package:montessori_app/modules/auth/ui/splash_screen.dart';
import 'package:montessori_app/modules/dashboard/ui/dashboard_screen.dart';
import 'package:montessori_app/modules/parent/ui/parent_dashboard.dart';

/// Shows login, a splash while loading, or the signed-in user's dashboard.
/// It only reads state while building; currentUserProvider is kept in step
/// by [authSessionSyncProvider] (watched here to keep it alive), never by a
/// write during build.
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(authSessionSyncProvider);
    final view = resolveAuthGateView(ref.watch(authStateProvider), () => ref.watch(userLoaderProvider));
    return switch (view) {
      AuthGateView.splash => const SplashScreen(),
      AuthGateView.login => const LoginScreen(),
      AuthGateView.staffDashboard => const DashboardScreen(),
      AuthGateView.parentDashboard => const ParentDashboard(),
    };
  }
}
