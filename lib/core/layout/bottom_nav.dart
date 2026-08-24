import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:montessori_app/modules/auth/providers/auth_provider.dart';
import 'package:montessori_app/modules/admin/ui/admin_dashboard.dart';
import '../theme/app_colors.dart';

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
    // Same operational-relevance order as AppSidebar (see its comment) —
    // Dashboard, then the daily-use destinations, then the lower-frequency
    // roster/setup screens, then Parent's own read-only Fees. For Parent
    // this yields exactly [Dashboard, Calendar, Leave, Fees] — four direct
    // NavigationBar items, matching the desktop sidebar one-for-one rather
    // than folding any of them behind a "More" affordance.
    final destinations = <NavigationDestination>[
      const NavigationDestination(
        icon: Icon(Icons.dashboard_outlined),
        selectedIcon: Icon(Icons.dashboard),
        label: 'Dashboard',
      ),
      if (role != 'parent') ...[
        const NavigationDestination(
          icon: Icon(Icons.check_circle_outline),
          selectedIcon: Icon(Icons.check_circle),
          label: 'Attendance',
        ),
      ],
      const NavigationDestination(
        icon: Icon(Icons.calendar_month_outlined),
        selectedIcon: Icon(Icons.calendar_month),
        label: 'Calendar',
      ),
      const NavigationDestination(
        icon: Icon(Icons.event_available_outlined),
        selectedIcon: Icon(Icons.event_available),
        label: 'Leave',
      ),
      if (role != 'parent') ...[
        const NavigationDestination(
          icon: Icon(Icons.people_outline),
          selectedIcon: Icon(Icons.people),
          label: 'Students',
        ),
        const NavigationDestination(
          icon: Icon(Icons.class_outlined),
          selectedIcon: Icon(Icons.class_),
          label: 'Classes',
        ),
      ],
      if (role == 'parent')
        const NavigationDestination(
          icon: Icon(Icons.receipt_long_outlined),
          selectedIcon: Icon(Icons.receipt_long),
          label: 'Fees',
        ),
      if (role == 'admin')
        const NavigationDestination(
          icon: Icon(Icons.admin_panel_settings_outlined),
          selectedIcon: Icon(Icons.admin_panel_settings),
          label: 'Admin',
        ),
    ];

    final safeIndex = selectedIndex.clamp(0, destinations.length - 1);

    // Material's NavigationBar hard-asserts destinations.length >= 2 (it's
    // built for switching between multiple views), so a role with exactly
    // one destination — today only Parent — would crash it. Every role with
    // 2+ destinations (Staff, Admin) keeps using NavigationBar exactly as
    // before; this branch only ever engages for the single-destination case.
    if (destinations.length < 2) {
      return _SingleDestinationNavBar(
        destination: destinations.single,
        onTap: () => onItemTapped(0),
      );
    }

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

/// Bottom navigation for a role with exactly one destination. Not a second
/// widget system — it mirrors NavigationBar's own selected-pill treatment
/// (using the same AppColors tokens the app's ThemeData actually resolves
/// NavigationBar's Material 3 colors from) for the one destination it's
/// given, which is always shown selected since there is nothing else to
/// select. This is not a placeholder/fake destination: it renders the real
/// single destination it's handed, just without going through a widget that
/// refuses to render fewer than two.
class _SingleDestinationNavBar extends StatelessWidget {
  const _SingleDestinationNavBar({
    required this.destination,
    required this.onTap,
  });

  final NavigationDestination destination;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      elevation: 3,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 80,
          width: double.infinity,
          child: InkWell(
            onTap: onTap,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.secondary,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: IconTheme(
                    data: const IconThemeData(color: Colors.white, size: 22),
                    child: destination.selectedIcon ?? destination.icon,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  destination.label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.secondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
