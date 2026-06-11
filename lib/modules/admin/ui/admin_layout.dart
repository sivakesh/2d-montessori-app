import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'admin_classes_screen.dart';
import 'admin_dashboard_screen.dart';
import 'admin_documents_screen.dart';
import 'admin_users_screen.dart';
import '../students/ui/admin_students_screen.dart';
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
              selectedIndex: selectedIndex,
              onDestinationSelected: (index) {
                if (index == selectedIndex) return;
                final Widget destination = switch (index) {
                  0 => const AdminDashboardScreen(),
                  1 => const AdminUsersScreen(),
                  2 => const admin_students_screen(),
                  3 => const AdminClassesScreen(),
                  4 => const AdminDocumentsScreen(),
                  _ => body,
                };
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => destination),
                );
              },
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.dashboard_outlined),
                  selectedIcon: Icon(Icons.dashboard),
                  label: 'Dashboard',
                ),
                NavigationDestination(
                  icon: Icon(Icons.people_outline),
                  selectedIcon: Icon(Icons.people),
                  label: 'Users',
                ),
                NavigationDestination(
                  icon: Icon(Icons.school_outlined),
                  selectedIcon: Icon(Icons.school),
                  label: 'Students',
                ),
                NavigationDestination(
                  icon: Icon(Icons.class_outlined),
                  selectedIcon: Icon(Icons.class_),
                  label: 'Classes',
                ),
                NavigationDestination(
                  icon: Icon(Icons.description_outlined),
                  selectedIcon: Icon(Icons.description),
                  label: 'Documents',
                ),
              ],
            )
          : null,
    );
  }
}
