import 'package:flutter/material.dart';
import '../../documents/data/document_service.dart';

class DocumentsManagementScreen extends StatelessWidget {
  const DocumentsManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final service = DocumentService();
    return Scaffold(
      appBar: AppBar(title: const Text('Documents')),
      body: FutureBuilder(
        future: service.getDocuments(entityType: 'user', entityId: ''),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return const Center(child: Text('No documents uploaded'));
        },
      ),
    );
  }
}
