import 'package:flutter/material.dart';
import 'documents_management_screen.dart';
import 'admin_layout.dart';

class AdminDocumentsScreen extends StatelessWidget {
  const AdminDocumentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdminLayout(
      selectedIndex: 4,
      title: 'Documents',
      body: DocumentsManagementScreen(),
    );
  }
}
