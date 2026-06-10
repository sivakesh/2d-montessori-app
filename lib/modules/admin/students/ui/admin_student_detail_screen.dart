// ignore_for_file: camel_case_types
import 'package:flutter/material.dart';
import '../../documents/data/admin_documents_service.dart';

class admin_student_detail_screen extends StatefulWidget {
  const admin_student_detail_screen({super.key, required this.studentId});

  final String studentId;

  @override
  State<admin_student_detail_screen> createState() => _admin_student_detail_screenState();
}

class _admin_student_detail_screenState extends State<admin_student_detail_screen> {
  final _documentsService = AdminDocumentsService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Student Details')),
      body: FutureBuilder(
        future: _documentsService.getDocuments(widget.studentId),
        builder: (context, snapshot) {
          final docs = snapshot.data ?? [];
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const CircleAvatar(radius: 44),
              const SizedBox(height: 16),
              const Text('Basic Info'),
              const SizedBox(height: 8),
              const Text('Personal Info'),
              const SizedBox(height: 8),
              const Text('Parent Info'),
              const SizedBox(height: 8),
              const Text('Address'),
              const SizedBox(height: 16),
              const Text('Documents'),
              const SizedBox(height: 8),
              if (docs.isEmpty)
                const Text('No documents uploaded')
              else
                for (final doc in docs)
                  Card(
                    child: ListTile(
                      title: Text(doc.documentType),
                      subtitle: Text(doc.fileName),
                      trailing: Wrap(
                        spacing: 8,
                        children: [
                          TextButton(
                            onPressed: () {},
                            child: const Text('View'),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete),
                            onPressed: () async {
                              await _documentsService.deleteDocument(doc.id);
                              if (mounted) setState(() {});
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
              ElevatedButton(
                onPressed: () async {
                  await _documentsService.uploadDocument(
                    studentId: widget.studentId,
                    documentType: 'aadhaar',
                  );
                  if (mounted) setState(() {});
                },
                child: const Text('Add Document'),
              ),
            ],
          );
        },
      ),
    );
  }
}
