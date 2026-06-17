import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:montessori_app/modules/auth/providers/auth_provider.dart';
import 'package:montessori_app/modules/admin/ui/admin_dashboard.dart';

class AppBottomNav extends ConsumerWidget {
  final int selectedIndex;
  final Function(int) onItemTapped;

  const AppBottomNav({
    super.key,
    required this.selectedIndex,
    required this.onItemTapped,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(currentUserProvider)?.role ?? 'parent';
    final destinations = <NavigationDestination>[
      const NavigationDestination(
        icon: Icon(Icons.dashboard_outlined),
        selectedIcon: Icon(Icons.dashboard),
        label: 'Dashboard',
      ),
      if (role != 'parent') ...[
        const NavigationDestination(
          icon: Icon(Icons.class_outlined),
          selectedIcon: Icon(Icons.class_),
          label: 'Classes',
        ),
        const NavigationDestination(
          icon: Icon(Icons.people_outline),
          selectedIcon: Icon(Icons.people),
          label: 'Students',
        ),
        const NavigationDestination(
          icon: Icon(Icons.check_circle_outline),
          selectedIcon: Icon(Icons.check_circle),
          label: 'Attendance',
        ),
      ],
      if (role == 'admin')
        const NavigationDestination(
          icon: Icon(Icons.admin_panel_settings_outlined),
          selectedIcon: Icon(Icons.admin_panel_settings),
          label: 'Admin',
        ),
    ];

    final safeIndex = selectedIndex.clamp(0, destinations.length - 1);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: NavigationBar(
        selectedIndex: safeIndex,
        onDestinationSelected: (index) {
          if (role == 'admin' && index == destinations.length - 1) {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AdminDashboard()),
            );
            return;
          }
          onItemTapped(index);
        },
        destinations: destinations,
      ),
    );
  }
}
