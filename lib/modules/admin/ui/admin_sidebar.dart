import 'package:flutter/material.dart';

import '../../../core/widgets/school_brand_mark.dart';

class AdminSidebar extends StatefulWidget {
  const AdminSidebar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  State<AdminSidebar> createState() => _AdminSidebarState();
}

class _AdminSidebarState extends State<AdminSidebar> {
  final ScrollController _sidebarScrollController = ScrollController();
  static const Color _primaryGreen = Color(0xFF2E7D32);

  // Each destination's `id` is the stable index every other screen's
  // `AdminLayout(selectedIndex: ...)` and this file's own tap/highlight
  // logic have always used (Dashboard=0 ... Leave Requests=13) — it is
  // NOT the position in this list. Reordering navigation therefore only
  // ever means reordering this list; no `id` value changes, so no other
  // file (including Fees'/Finance's own screens, which hardcode their own
  // id) needs to change. Display order below is by operational relevance:
  // Dashboard, then the destinations used daily (Attendance, Calendar,
  // Leave Requests), then Notifications/Fees/Finance, then the
  // roster/setup screens, then the least-frequently-used admin-config
  // items (Login Logs, Reports, Settings) at the end — the same relative
  // ordering AppSidebar/AppBottomNav use for their own daily-use items,
  // per "a consistent logical order across platforms".
  static const _destinations = <_SidebarDestination>[
    _SidebarDestination(
      id: 0,
      icon: Icons.dashboard_outlined,
      selectedIcon: Icons.dashboard,
      label: 'Dashboard',
    ),
    _SidebarDestination(
      id: 8,
      icon: Icons.fact_check_outlined,
      selectedIcon: Icons.fact_check,
      label: 'Attendance',
    ),
    _SidebarDestination(
      id: 12,
      icon: Icons.calendar_month_outlined,
      selectedIcon: Icons.calendar_month,
      label: 'Calendar',
    ),
    _SidebarDestination(
      id: 13,
      icon: Icons.event_available_outlined,
      selectedIcon: Icons.event_available,
      label: 'Leave Requests',
    ),
    _SidebarDestination(
      id: 5,
      icon: Icons.notifications_outlined,
      selectedIcon: Icons.notifications,
      label: 'Notifications',
    ),
    _SidebarDestination(
      id: 6,
      icon: Icons.payments_outlined,
      selectedIcon: Icons.payments,
      label: 'Fees',
    ),
    _SidebarDestination(
      id: 7,
      icon: Icons.account_balance_wallet_outlined,
      selectedIcon: Icons.account_balance_wallet,
      label: 'Finance',
    ),
    _SidebarDestination(
      id: 2,
      icon: Icons.school_outlined,
      selectedIcon: Icons.school,
      label: 'Students',
    ),
    _SidebarDestination(
      id: 3,
      icon: Icons.class_outlined,
      selectedIcon: Icons.class_,
      label: 'Classes',
    ),
    _SidebarDestination(
      id: 1,
      icon: Icons.people_outline,
      selectedIcon: Icons.people,
      label: 'Users',
    ),
    _SidebarDestination(
      id: 4,
      icon: Icons.description_outlined,
      selectedIcon: Icons.description,
      label: 'Documents',
    ),
    _SidebarDestination(
      id: 9,
      icon: Icons.login_outlined,
      selectedIcon: Icons.login,
      label: 'Login Logs',
    ),
    _SidebarDestination(
      id: 10,
      icon: Icons.bar_chart_outlined,
      selectedIcon: Icons.bar_chart,
      label: 'Reports',
    ),
    _SidebarDestination(
      id: 11,
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings,
      label: 'Settings',
    ),
  ];

  @override
  void dispose() {
    _sidebarScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        width: 220,
        color: Theme.of(context).colorScheme.surface,
        child: Column(
          children: [
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: SchoolBrandMark(logoHeight: 56, spacing: 6),
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            Expanded(
              child: Scrollbar(
                controller: _sidebarScrollController,
                thumbVisibility: true,
                interactive: true,
                child: SingleChildScrollView(
                  controller: _sidebarScrollController,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    children: List.generate(_destinations.length, (index) {
                      final destination = _destinations[index];
                      final isSelected = widget.selectedIndex == destination.id;
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        child: Material(
                          color: isSelected
                              ? _primaryGreen
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(16),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => widget.onDestinationSelected(destination.id),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    isSelected
                                        ? destination.selectedIcon
                                        : destination.icon,
                                    color: isSelected
                                        ? Colors.white
                                        : Colors.black87,
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Text(
                                      destination.label,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            fontWeight: isSelected
                                                ? FontWeight.w600
                                                : FontWeight.w500,
                                            color: isSelected
                                                ? Colors.white
                                                : Colors.black87,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarDestination {
  const _SidebarDestination({
    required this.id,
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  /// The stable selectedIndex/screen identifier — see the doc comment on
  /// `_destinations` for why this is distinct from list position.
  final int id;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
}
