import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/widgets/responsive_dialog_shell.dart';
import '../../admin/models/admin_class_model.dart';
import '../data/class_service.dart';

class ClassViewDialog extends StatefulWidget {
  const ClassViewDialog({super.key, required this.classId});

  final String classId;

  @override
  State<ClassViewDialog> createState() => _ClassViewDialogState();
}

class _ClassViewDialogState extends State<ClassViewDialog> {
  final _service = ClassService();
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return ResponsiveDialogShell(
      desktopWidth: 820,
      desktopHeight: 680,
      child: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          future: FirebaseFirestore.instance.collection('classes').doc(widget.classId).get(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
            final data = snapshot.data!.data() ?? const <String, dynamic>{};
            final model = AdminClassModel.fromMap(widget.classId, data);
            return Column(
              children: [
                ListTile(
                  title: Text(model.name),
                  subtitle: Text(model.academicYear.isEmpty ? '-' : model.academicYear),
                  trailing: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(label: const Text('Overview'), selected: _tab == 0, onSelected: (_) => setState(() => _tab = 0)),
                      ChoiceChip(label: const Text('Students'), selected: _tab == 1, onSelected: (_) => setState(() => _tab = 1)),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: switch (_tab) {
                      0 => _buildOverview(model),
                      _ => _buildStudents(),
                    },
                  ),
                ),
              ],
            );
          },
        ),
    );
  }

  Widget _buildOverview(AdminClassModel model) {
    return ListView(
      children: [
        _row('Class Name', model.name),
        _row('Section', model.section.isEmpty ? '-' : model.section),
        _row('Academic Year', model.academicYear.isEmpty ? '-' : model.academicYear),
        _row('Capacity', model.capacity?.toString() ?? '-'),
        FutureBuilder<int>(
          future: _service.getStudentCountByClassId(widget.classId),
          builder: (context, snap) => _row('Student Count', snap.data?.toString() ?? '...'),
        ),
        _row('Class Teacher', model.teacherName.isEmpty ? '-' : model.teacherName),
        _row('Status', model.isActive ? 'Active' : 'Inactive'),
        _row('Approval Status', model.approvalStatus),
        _row('Notes', model.description.isEmpty ? '-' : model.description),
      ],
    );
  }

  Widget _buildStudents() {
    return FutureBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
      future: _service.getStudentsByClassId(widget.classId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final students = snapshot.data!;
        if (students.isEmpty) {
          return const Center(child: Text('No students assigned'));
        }
        return ListView.separated(
          itemCount: students.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final data = students[index].data();
            return ListTile(
              tileColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Text(data['name']?.toString() ?? 'Student'),
              subtitle: Text('Admission No: ${data['admissionNo']?.toString() ?? '-'}'),
              trailing: Text(data['isActive'] == false ? 'Inactive' : 'Active'),
            );
          },
        );
      },
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 150, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
