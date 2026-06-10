import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:montessori_app/modules/auth/providers/auth_provider.dart';
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
