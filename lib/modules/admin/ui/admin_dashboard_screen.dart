import 'package:flutter/material.dart';
import 'admin_users_screen.dart';
import 'admin_classes_screen.dart';
import 'admin_documents_screen.dart';
import 'admin_layout.dart';
import '../students/ui/admin_students_screen.dart';

class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AdminLayout(
      selectedIndex: 0,
      title: 'Admin Dashboard',
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            _Tile(
              title: 'Users',
              icon: Icons.manage_accounts,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AdminUsersScreen()),
              ),
            ),
            _Tile(
              title: 'Students',
              icon: Icons.school,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const admin_students_screen()),
              ),
            ),
            _Tile(
              title: 'Classes',
              icon: Icons.class_,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AdminClassesScreen()),
              ),
            ),
            _Tile(
              title: 'Documents',
              icon: Icons.description,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AdminDocumentsScreen()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.title,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: Card(
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 36),
                const SizedBox(height: 12),
                Text(title),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
