// ignore_for_file: camel_case_types
import 'package:flutter/material.dart';
import '../data/admin_documents_service.dart';

class admin_documents_screen extends StatefulWidget {
  const admin_documents_screen({super.key, required this.studentId});

  final String studentId;

  @override
  State<admin_documents_screen> createState() => _admin_documents_screenState();
}

class _admin_documents_screenState extends State<admin_documents_screen> {
  final _service = AdminDocumentsService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Documents')),
      body: FutureBuilder(
        future: _service.getDocuments(widget.studentId),
        builder: (context, snapshot) {
          final docs = snapshot.data ?? [];
          if (docs.isEmpty) {
            return const Center(child: Text('No documents uploaded'));
          }
          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              return ListTile(
                title: Text(doc.documentType),
                subtitle: Text(doc.fileName),
              );
            },
          );
        },
      ),
    );
  }
}
