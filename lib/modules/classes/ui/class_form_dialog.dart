import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/widgets/responsive_dialog_shell.dart';
import '../data/class_service.dart';

class ClassFormDialog extends StatefulWidget {
  const ClassFormDialog({super.key, this.classId, this.initialData});

  final String? classId;
  final Map<String, dynamic>? initialData;

  @override
  State<ClassFormDialog> createState() => _ClassFormDialogState();
}

class _ClassFormDialogState extends State<ClassFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _service = ClassService();
  late final TextEditingController _name;
  late final TextEditingController _section;
  late final TextEditingController _year;
  late final TextEditingController _capacity;
  late final TextEditingController _teacherName;
  late final TextEditingController _notes;
  bool _isActive = true;
  String _approvalStatus = 'Approved';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final data = widget.initialData ?? const {};
    _name = TextEditingController(text: data['name']?.toString() ?? '');
    _section = TextEditingController(text: data['section']?.toString() ?? '');
    _year = TextEditingController(text: data['academicYear']?.toString() ?? '');
    _capacity = TextEditingController(text: data['capacity']?.toString() ?? '');
    _teacherName = TextEditingController(text: data['teacherName']?.toString() ?? '');
    _notes = TextEditingController(text: data['description']?.toString() ?? '');
    _isActive = data['isActive'] != false;
    _approvalStatus = data['approvalStatus']?.toString() ??
        (data['isApproved'] == true ? 'Approved' : 'Pending Approval');
  }

  @override
  void dispose() {
    _name.dispose();
    _section.dispose();
    _year.dispose();
    _capacity.dispose();
    _teacherName.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final payload = {
        'name': _name.text.trim(),
        'section': _section.text.trim(),
        'academicYear': _year.text.trim(),
        'capacity': _capacity.text.trim().isEmpty ? null : int.parse(_capacity.text.trim()),
        'teacherName': _teacherName.text.trim(),
        'description': _notes.text.trim(),
        'isActive': _isActive,
        'approvalStatus': _approvalStatus,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (widget.classId == null) {
        payload['createdAt'] = FieldValue.serverTimestamp();
        payload['createdBy'] = 'admin';
        await _service.createClass(payload);
      } else {
        await _service.updateClass(classId: widget.classId!, data: payload);
      }
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.classId == null ? 'Class created' : 'Class updated')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save class: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveDialogShell.form(
      desktopWidth: 600,
      desktopHeight: 620,
      title: widget.classId == null ? 'Add Class' : 'Edit Class',
      content: Form(
          key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Class Name *'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                TextFormField(controller: _section, decoration: const InputDecoration(labelText: 'Section')),
                TextFormField(
                  controller: _year,
                  decoration: const InputDecoration(labelText: 'Academic Year *'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                TextFormField(
                  controller: _capacity,
                  decoration: const InputDecoration(labelText: 'Capacity'),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return null;
                    return int.tryParse(v.trim()) == null ? 'Enter a valid number' : null;
                  },
                ),
                TextFormField(controller: _teacherName, decoration: const InputDecoration(labelText: 'Class Teacher / Staff in charge')),
                TextFormField(
                  controller: _notes,
                  decoration: const InputDecoration(labelText: 'Description / Notes'),
                  maxLines: 3,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Active'),
                  value: _isActive,
                  onChanged: (value) => setState(() => _isActive = value),
                ),
                DropdownButtonFormField<String>(
                  initialValue: _approvalStatus,
                  decoration: const InputDecoration(labelText: 'Approval Status'),
                  items: const [
                    DropdownMenuItem(value: 'Approved', child: Text('Approved')),
                    DropdownMenuItem(value: 'Pending Approval', child: Text('Pending Approval')),
                    DropdownMenuItem(value: 'Rejected', child: Text('Rejected')),
                  ],
                  onChanged: (value) => setState(() => _approvalStatus = value ?? 'Approved'),
                ),
              ],
            ),
          ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _saving ? null : _save, child: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save')),
      ],
    );
  }
}
