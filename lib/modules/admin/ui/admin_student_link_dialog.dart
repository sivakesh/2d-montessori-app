import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../data/admin_profile_service.dart';

class AdminStudentLinkDialog extends StatelessWidget {
  const AdminStudentLinkDialog({
    super.key,
    required this.userId,
    required this.service,
  });

  final String userId;
  final AdminProfileService service;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Link Student'),
      content: SizedBox(
        width: 520,
        height: 420,
        child: FutureBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
          future: service.getAllStudents(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final docs = snapshot.data!;
            return ListView.builder(
              itemCount: docs.length,
              itemBuilder: (context, index) {
                final doc = docs[index];
                final data = doc.data();
                return ListTile(
                  title: Text(data['name']?.toString() ?? 'Student'),
                  subtitle: Text('Class: ${data['classId']?.toString() ?? '-'}'),
                  trailing: ElevatedButton(
                    onPressed: () async {
                      await service.linkStudent(
                        userId: userId,
                        studentId: doc.id,
                        studentName: data['name']?.toString() ?? 'Student',
                        classId: data['classId']?.toString() ?? '',
                      );
                      if (context.mounted) Navigator.pop(context);
                    },
                    child: const Text('Link'),
                  ),
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
