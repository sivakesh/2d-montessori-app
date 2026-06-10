import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/providers/auth_provider.dart';
import '../../classes/providers/class_provider.dart';
import '../providers/student_provider.dart';

class CreateStudentScreen extends ConsumerStatefulWidget {
  const CreateStudentScreen({super.key, this.studentId, this.initialData});

  final String? studentId;
  final Map<String, dynamic>? initialData;

  @override
  ConsumerState<CreateStudentScreen> createState() =>
      _CreateStudentScreenState();
}

class _CreateStudentScreenState extends ConsumerState<CreateStudentScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _admissionController;
  late final TextEditingController _dobController;
  String? _classId;
  String _gender = 'Male';
  bool _isLoadingClasses = true;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _classes = [];

  @override
  void initState() {
    super.initState();
    final data = widget.initialData ?? {};
    _nameController = TextEditingController(
      text: data['name']?.toString() ?? '',
    );
    _admissionController = TextEditingController(
      text: data['admissionNo']?.toString() ?? '',
    );
    _dobController = TextEditingController(
      text: data['dateOfBirth']?.toString() ?? '',
    );
    _classId = data['classId']?.toString();
    _gender = data['gender']?.toString() ?? 'Male';
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
    final classService = ref.read(classServiceProvider);
    final classes = await classService.getAllClasses();
    if (!mounted) return;
    setState(() {
      _classes = classes;
      _isLoadingClasses = false;
      if (_classId == null && classes.isNotEmpty) {
        _classId = classes.first.id;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final studentService = ref.watch(studentServiceProvider);
    final currentUser = ref.watch(currentUserProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.studentId == null ? 'Create Student' : 'Edit Student',
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              TextFormField(
                controller: _admissionController,
                decoration: const InputDecoration(
                  labelText: 'Admission Number',
                ),
              ),
              _isLoadingClasses
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : DropdownButtonFormField<String>(
                      initialValue: _classId,
                      items: _classes
                          .map(
                            (doc) => DropdownMenuItem(
                              value: doc.id,
                              child: Text(doc.data()['name']?.toString() ?? ''),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => _classId = v),
                      decoration: const InputDecoration(labelText: 'Class'),
                      validator: (value) =>
                          value == null || value.isEmpty ? 'Required' : null,
                    ),
              DropdownButtonFormField<String>(
                initialValue: _gender,
                items: const [
                  DropdownMenuItem(value: 'Male', child: Text('Male')),
                  DropdownMenuItem(value: 'Female', child: Text('Female')),
                ],
                onChanged: (v) => setState(() => _gender = v ?? 'Male'),
                decoration: const InputDecoration(labelText: 'Gender'),
              ),
              TextFormField(
                controller: _dobController,
                decoration: const InputDecoration(labelText: 'Date of Birth'),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    if (!_formKey.currentState!.validate()) return;
                    final data = {
                      'name': _nameController.text.trim(),
                      'admissionNo': _admissionController.text.trim(),
                      'classId': _classId ?? '',
                      'gender': _gender,
                      'dateOfBirth': _dobController.text.trim(),
                      'isActive': true,
                      'isApproved': false,
                      'createdBy': currentUser?.id,
                      'createdAt': FieldValue.serverTimestamp(),
                    };
                    if (widget.studentId == null) {
                      await studentService.createStudent(data);
                    } else {
                      await studentService.updateStudent(
                        studentId: widget.studentId!,
                        data: data,
                      );
                    }
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
