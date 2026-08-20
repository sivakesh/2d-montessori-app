import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../../core/widgets/responsive_dialog_shell.dart';
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
    return ResponsiveDialogShell(
      desktopWidth: 520,
      desktopHeight: 480,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Link Student',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ],
            ),
          ),
          Expanded(
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
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
