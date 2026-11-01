import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:montessori_app/modules/auth/providers/auth_provider.dart';
import 'package:montessori_app/modules/auth/ui/auth_gate.dart';
import 'package:montessori_app/modules/dashboard/ui/dashboard_screen.dart';
import 'package:montessori_app/modules/parent/ui/parent_dashboard.dart';

class RoleBasedHome extends ConsumerWidget {
  const RoleBasedHome({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final role = user?.role ?? 'parent';

    if (role == 'admin' || role == 'staff') {
      return const DashboardScreen();
    }

    return const ParentDashboard();
  }
}

/// The `/dashboard` route. A session user already in currentUserProvider
/// (set by the login/OTP flows, including dev login) goes straight to
/// [RoleBasedHome]. With no session user — a browser refresh on
/// /#/dashboard, where the public homepage rather than AuthGate is the root
/// route, or a signed-out visitor typing the address — it shows [AuthGate]:
/// splash while the session is restored, login when signed out. AuthGate's
/// session sync then sets the user and this rebuilds into RoleBasedHome.
class DashboardRoute extends ConsumerWidget {
  const DashboardRoute({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(currentUserProvider) == null ? const AuthGate() : const RoleBasedHome();
  }
}
