import 'package:flutter/material.dart';
import '../../classes/ui/class_list_screen.dart';
import 'admin_layout.dart';

class AdminClassesScreen extends StatelessWidget {
  const AdminClassesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdminLayout(
      selectedIndex: 3,
      title: 'Classes',
      body: ClassListScreen(),
    );
  }
}
