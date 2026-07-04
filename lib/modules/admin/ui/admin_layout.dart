import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'admin_classes_screen.dart';
import 'admin_dashboard_screen.dart';
import 'admin_documents_screen.dart';
import 'admin_notifications_screen.dart';
import 'admin_users_screen.dart';
import '../../fees/ui/admin_fees_screen.dart';
import '../../finance/ui/admin_finance_screen.dart';
import 'admin_attendance_management_screen.dart';
import '../students/ui/admin_students_screen.dart';
import 'mobile_nav_item.dart';
import 'admin_sidebar.dart';

class AdminLayout extends ConsumerWidget {
  const AdminLayout({
    super.key,
    required this.selectedIndex,
    required this.title,
    required this.body,
    this.floatingActionButton,
  });

  final int selectedIndex;
  final String title;
  final Widget body;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isMobile = MediaQuery.of(context).size.width < 800;
    final mobileNavItems = <MobileNavItem>[
      MobileNavItem(
        label: 'Dashboard',
        icon: Icons.dashboard_outlined,
        route: 'dashboard',
        screenIndex: 0,
        builder: (_) => const AdminDashboardScreen(),
      ),
      MobileNavItem(
        label: 'Notifications',
        icon: Icons.notifications_outlined,
        route: 'notifications',
        screenIndex: 5,
        builder: (_) => const AdminNotificationsScreen(),
      ),
      MobileNavItem(
        label: 'Students',
        icon: Icons.school_outlined,
        route: 'students',
        screenIndex: 2,
        builder: (_) => const admin_students_screen(),
      ),
      MobileNavItem(
        label: 'Fees',
        icon: Icons.payments_outlined,
        route: 'fees',
        screenIndex: 6,
        builder: (_) => const AdminFeesScreen(),
      ),
      MobileNavItem(label: 'More', icon: Icons.more_horiz, route: 'more'),
    ];

    final secondaryItems = <MobileNavItem>[
      MobileNavItem(
        label: 'Users',
        icon: Icons.people_outline,
        route: 'users',
        screenIndex: 1,
        builder: (_) => const AdminUsersScreen(),
      ),
      MobileNavItem(
        label: 'Classes',
        icon: Icons.class_outlined,
        route: 'classes',
        screenIndex: 3,
        builder: (_) => const AdminClassesScreen(),
      ),
      MobileNavItem(
        label: 'Documents',
        icon: Icons.description_outlined,
        route: 'documents',
        screenIndex: 4,
        builder: (_) => const AdminDocumentsScreen(),
      ),
      MobileNavItem(
        label: 'Finance',
        icon: Icons.account_balance_wallet_outlined,
        route: 'finance',
        screenIndex: 7,
        builder: (_) => const AdminFinanceScreen(),
      ),
      MobileNavItem(
        label: 'Attendance',
        icon: Icons.fact_check_outlined,
        route: 'attendance',
        screenIndex: 8,
        builder: (_) => const AdminAttendanceManagementScreen(),
      ),
      MobileNavItem(
        label: 'Reports',
        icon: Icons.bar_chart_outlined,
        route: 'reports',
      ),
      MobileNavItem(
        label: 'Settings',
        icon: Icons.settings_outlined,
        route: 'settings',
      ),
    ];

    int mobileSelectedIndex() {
      if (selectedIndex == 0) return 0;
      if (selectedIndex == 5) return 1;
      if (selectedIndex == 2) return 2;
      if (selectedIndex == 6) return 3;
      return 4;
    }

    Future<void> openDestination(WidgetBuilder builder) async {
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: builder));
    }

    Future<void> openMoreSheet() async {
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        useSafeArea: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (sheetContext) {
          return SafeArea(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text(
                    'More Modules',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
                ...secondaryItems.map(
                  (item) => ListTile(
                    leading: Icon(item.icon),
                    title: Text(item.label),
                    onTap: item.builder == null
                        ? () {
                            Navigator.pop(sheetContext);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('${item.label} is coming soon'),
                              ),
                            );
                          }
                        : () {
                            Navigator.pop(sheetContext);
                            openDestination(item.builder!);
                          },
                  ),
                ),
              ],
            ),
          );
        },
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey[50],
      floatingActionButton: floatingActionButton,
      body: isMobile
          ? Column(
              children: [
                AppBar(title: Text(title)),
                Expanded(child: body),
              ],
            )
          : Row(
              children: [
                AdminSidebar(
                  selectedIndex: selectedIndex,
                  onDestinationSelected: (index) {
                    if (index == selectedIndex) return;
                    final Widget destination = switch (index) {
                      0 => const AdminDashboardScreen(),
                      1 => const AdminUsersScreen(),
                      2 => const admin_students_screen(),
                      3 => const AdminClassesScreen(),
                      4 => const AdminDocumentsScreen(),
                      5 => const AdminNotificationsScreen(),
                      6 => const AdminFeesScreen(),
                      7 => const AdminFinanceScreen(),
                      8 => const AdminAttendanceManagementScreen(),
                      _ => body,
                    };
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => destination),
                    );
                  },
                ),
                Expanded(
                  child: Column(
                    children: [
                      AppBar(title: Text(title)),
                      Expanded(child: body),
                    ],
                  ),
                ),
              ],
            ),
      bottomNavigationBar: isMobile
          ? NavigationBar(
              selectedIndex: mobileSelectedIndex(),
              onDestinationSelected: (index) {
                if (index == 4) {
                  openMoreSheet();
                  return;
                }
                if (index == mobileSelectedIndex()) return;
                final item = mobileNavItems[index];
                if (item.builder != null) {
                  openDestination(item.builder!);
                }
              },
              destinations: mobileNavItems
                  .map(
                    (item) => NavigationDestination(
                      icon: Icon(item.icon),
                      selectedIcon: Icon(item.icon),
                      label: item.label,
                    ),
                  )
                  .toList(),
            )
          : null,
    );
  }
}
