import 'package:flutter/material.dart';
import '../../classes/ui/class_list_screen.dart';
import 'admin_layout.dart';

class AdminClassesScreen extends StatefulWidget {
  const AdminClassesScreen({super.key});

  @override
  State<AdminClassesScreen> createState() => _AdminClassesScreenState();
}

class _AdminClassesScreenState extends State<AdminClassesScreen> {
  final _listKey = GlobalKey<ClassListScreenState>();

  @override
  Widget build(BuildContext context) {
    return AdminLayout(
      selectedIndex: 3,
      title: 'Classes',
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF2E7D32),
        elevation: 4,
        onPressed: () => _listKey.currentState?.openAddClass(),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: ClassListScreen(key: _listKey),
    );
  }
}
