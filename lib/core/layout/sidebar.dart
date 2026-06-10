import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:montessori_app/modules/admin/ui/admin_dashboard.dart';
import 'package:montessori_app/modules/auth/providers/auth_provider.dart';

class AppSidebar extends ConsumerWidget {
  final int selectedIndex;
  final Function(int) onItemTapped;

  const AppSidebar({
    super.key,
    required this.selectedIndex,
    required this.onItemTapped,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(currentUserProvider)?.role ?? 'parent';
    final destinations = <NavigationRailDestination>[
      const NavigationRailDestination(
        icon: Icon(Icons.dashboard_outlined),
        selectedIcon: Icon(Icons.dashboard),
        label: Text('Dashboard'),
      ),
      if (role != 'parent') ...[
        const NavigationRailDestination(
          icon: Icon(Icons.class_outlined),
          selectedIcon: Icon(Icons.class_),
          label: Text('Classes'),
        ),
        const NavigationRailDestination(
          icon: Icon(Icons.people_outline),
          selectedIcon: Icon(Icons.people),
          label: Text('Students'),
        ),
      ],
      if (role != 'parent') ...[
        const NavigationRailDestination(
          icon: Icon(Icons.check_circle_outline),
          selectedIcon: Icon(Icons.check_circle),
          label: Text('Attendance'),
        ),
      ],
      if (role == 'staff') ...[
        const NavigationRailDestination(
          icon: Icon(Icons.badge_outlined),
          selectedIcon: Icon(Icons.badge),
          label: Text('Staff'),
        ),
      ],
      if (role == 'admin') ...[
        const NavigationRailDestination(
          icon: Icon(Icons.admin_panel_settings_outlined),
          selectedIcon: Icon(Icons.admin_panel_settings),
          label: Text('Admin'),
        ),
      ],
    ];
    final adminDestinationIndex = role == 'admin' ? destinations.length - 1 : -1;

    return Container(
      width: 220,
      padding: const EdgeInsets.symmetric(vertical: 16),
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        children: [
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                Image.asset('assets/logo.png', height: 64),
                const SizedBox(height: 8),
                Text(
                  '2D Montessori',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),
          Expanded(
            child: NavigationRail(
              selectedIndex: selectedIndex,
              onDestinationSelected: (index) {
                if (index == adminDestinationIndex) {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AdminDashboard()),
                  );
                  return;
                }

                onItemTapped(index);
              },
              labelType: NavigationRailLabelType.all,
              groupAlignment: -1,
              backgroundColor: Theme.of(context).colorScheme.surface,
              destinations: destinations,
            ),
          ),
        ],
      ),
    );
  }
}
