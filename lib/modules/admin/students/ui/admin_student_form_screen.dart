// ignore_for_file: camel_case_types
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../data/admin_student_service.dart';
import '../models/admin_student_model.dart';

class AdminStudentFormScreen extends StatefulWidget {
  const AdminStudentFormScreen({
    super.key,
    this.studentId,
    this.initialData,
  });

  final String? studentId;
  final Map<String, dynamic>? initialData;

  @override
  State<AdminStudentFormScreen> createState() => _AdminStudentFormScreenState();
}

class _AdminStudentFormScreenState extends State<AdminStudentFormScreen> {
  final GlobalKey<AdminStudentFormBodyState> _bodyKey =
      GlobalKey<AdminStudentFormBodyState>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.studentId == null ? 'Add Student' : 'Edit Student')),
      body: AdminStudentFormBody(
        key: _bodyKey,
        studentId: widget.studentId,
        initialData: widget.initialData,
        onSaved: () {
          if (mounted) Navigator.pop(context);
        },
      ),
    );
  }
}

class admin_student_form_screen extends AdminStudentFormScreen {
  const admin_student_form_screen({super.key, super.studentId, super.initialData});
}

class AdminStudentFormBody extends StatefulWidget {
  const AdminStudentFormBody({
    super.key,
    required this.onSaved,
    this.studentId,
    this.initialData,
    this.showSaveButton = true,
  });

  final String? studentId;
  final Map<String, dynamic>? initialData;
  final VoidCallback onSaved;
  final bool showSaveButton;

  @override
  State<AdminStudentFormBody> createState() => AdminStudentFormBodyState();
}

class AdminStudentFormBodyState extends State<AdminStudentFormBody> {
  final _formKey = GlobalKey<FormState>();
  final _service = AdminStudentService();
  final _nameController = TextEditingController();
  final _admissionController = TextEditingController();
  final _dobController = TextEditingController();
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _classes = [];
  bool _loading = true;
  String? _classId;
  String _gender = 'Male';
  bool _isActive = true;

  @override
  void initState() {
    super.initState();
    final data = widget.initialData ?? const {};
    _nameController.text = data['name']?.toString() ?? '';
    _admissionController.text = data['admissionNo']?.toString() ?? '';
    _dobController.text = data['dateOfBirth']?.toString() ?? '';
    _classId = data['classId']?.toString();
    _gender = data['gender']?.toString() ?? 'Male';
    _isActive = data['isActive'] != false;
    _loadClasses();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _admissionController.dispose();
    _dobController.dispose();
    super.dispose();
  }

  Future<void> _loadClasses() async {
    final classes = await _service.getClasses();
    if (!mounted) return;
    setState(() {
      _classes = classes;
      _classId ??= classes.isNotEmpty ? classes.first.id : null;
      _loading = false;
    });
  }

  Future<void> _pickDob() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(1950),
      lastDate: DateTime.now(),
      initialDate: DateTime.tryParse(_dobController.text) ?? DateTime.now(),
    );
    if (picked == null) return;
    setState(() {
      _dobController.text = picked.toIso8601String().split('T').first;
    });
  }

  Future<void> saveStudent() async {
    if (!_formKey.currentState!.validate()) return;
    if (_classId == null || _classId!.isEmpty) return;

    final admissionNo = _admissionController.text.trim();
    final isDuplicate = await _service.isAdmissionNoTaken(
      admissionNo,
      ignoreId: widget.studentId,
    );
    if (isDuplicate) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Admission number already exists')),
      );
      return;
    }

    final model = AdminStudentModel(
      id: widget.studentId ?? '',
      name: _nameController.text.trim(),
      admissionNo: admissionNo,
      classId: _classId ?? '',
      dateOfBirth: _dobController.text.trim(),
      gender: _gender,
      isActive: _isActive,
      isApproved: widget.initialData?['isApproved'] == true,
      createdAt: null,
      createdBy: widget.initialData?['createdBy']?.toString(),
      parentLinks:
          (widget.initialData?['parentLinks'] as List<dynamic>? ?? const [])
              .whereType<Map>()
              .map((e) => AdminStudentParentLink.fromMap(
                    Map<String, dynamic>.from(e),
                  ))
              .toList(),
      documents: (widget.initialData?['documents'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((e) => AdminStudentDocument.fromMap(Map<String, dynamic>.from(e)))
          .toList(),
    );

    if (widget.studentId == null) {
      await _service.createStudent(student: model, createdBy: 'admin');
    } else {
      await _service.updateStudent(studentId: widget.studentId!, student: model);
    }

    widget.onSaved();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: ListView(
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Name'),
              validator: (value) =>
                  value == null || value.trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _admissionController,
              decoration: const InputDecoration(labelText: 'Admission No'),
              validator: (value) =>
                  value == null || value.trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _classId,
              items: [
                for (final c in _classes)
                  DropdownMenuItem(
                    value: c.id,
                    child: Text(c.data()['name']?.toString() ?? ''),
                  ),
              ],
              onChanged: (value) => setState(() => _classId = value),
              decoration: const InputDecoration(labelText: 'Class'),
              validator: (value) =>
                  value == null || value.isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _dobController,
              readOnly: true,
              onTap: _pickDob,
              decoration: const InputDecoration(
                labelText: 'Date of Birth',
                suffixIcon: Icon(Icons.calendar_month),
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _gender,
              items: const [
                DropdownMenuItem(value: 'Male', child: Text('Male')),
                DropdownMenuItem(value: 'Female', child: Text('Female')),
                DropdownMenuItem(value: 'Other', child: Text('Other')),
              ],
              onChanged: (value) => setState(() => _gender = value ?? 'Male'),
              decoration: const InputDecoration(labelText: 'Gender'),
            ),
            const SizedBox(height: 10),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _isActive,
              onChanged: (value) => setState(() => _isActive = value),
              title: const Text('Active'),
            ),
            if (widget.showSaveButton) ...[
              const SizedBox(height: 12),
              FilledButton(
                onPressed: saveStudent,
                child: const Text('Save'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
