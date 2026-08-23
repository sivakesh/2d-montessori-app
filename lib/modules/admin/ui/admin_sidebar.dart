import 'package:flutter/material.dart';

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

  static const _destinations = <_SidebarDestination>[
    _SidebarDestination(
      icon: Icons.dashboard_outlined,
      selectedIcon: Icons.dashboard,
      label: 'Dashboard',
    ),
    _SidebarDestination(
      icon: Icons.people_outline,
      selectedIcon: Icons.people,
      label: 'Users',
    ),
    _SidebarDestination(
      icon: Icons.school_outlined,
      selectedIcon: Icons.school,
      label: 'Students',
    ),
    _SidebarDestination(
      icon: Icons.class_outlined,
      selectedIcon: Icons.class_,
      label: 'Classes',
    ),
    _SidebarDestination(
      icon: Icons.description_outlined,
      selectedIcon: Icons.description,
      label: 'Documents',
    ),
    _SidebarDestination(
      icon: Icons.notifications_outlined,
      selectedIcon: Icons.notifications,
      label: 'Notifications',
    ),
    _SidebarDestination(
      icon: Icons.payments_outlined,
      selectedIcon: Icons.payments,
      label: 'Fees',
    ),
    _SidebarDestination(
      icon: Icons.account_balance_wallet_outlined,
      selectedIcon: Icons.account_balance_wallet,
      label: 'Finance',
    ),
    _SidebarDestination(
      icon: Icons.fact_check_outlined,
      selectedIcon: Icons.fact_check,
      label: 'Attendance',
    ),
    _SidebarDestination(
      icon: Icons.login_outlined,
      selectedIcon: Icons.login,
      label: 'Login Logs',
    ),
    _SidebarDestination(
      icon: Icons.bar_chart_outlined,
      selectedIcon: Icons.bar_chart,
      label: 'Reports',
    ),
    _SidebarDestination(
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  Image.asset('assets/logo.png', height: 56),
                  const SizedBox(height: 6),
                  Text(
                    '2D Montessori',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ],
              ),
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
                      final isSelected = widget.selectedIndex == index;
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
                            onTap: () => widget.onDestinationSelected(index),
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
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}
