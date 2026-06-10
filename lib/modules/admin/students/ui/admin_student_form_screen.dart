// ignore_for_file: camel_case_types, deprecated_member_use
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../data/admin_students_service.dart';
import '../models/admin_student_model.dart';

class admin_student_form_screen extends StatefulWidget {
  const admin_student_form_screen({super.key, this.studentId, this.initialData});

  final String? studentId;
  final Map<String, dynamic>? initialData;

  @override
  State<admin_student_form_screen> createState() => _admin_student_form_screenState();
}

class _admin_student_form_screenState extends State<admin_student_form_screen> {
  final _formKey = GlobalKey<FormState>();
  final _service = AdminStudentsService();
  final _picker = ImagePicker();
  late final TextEditingController _nameController;
  late final TextEditingController _admissionController;
  late final TextEditingController _dobController;
  late final TextEditingController _bloodGroupController;
  late final TextEditingController _fatherNameController;
  late final TextEditingController _motherNameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _addressController;
  String _gender = 'Male';
  String? _classId;
  String? _profileImage;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _classes = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final data = widget.initialData ?? {};
    _nameController = TextEditingController(text: data['name']?.toString() ?? '');
    _admissionController = TextEditingController(text: data['admissionNo']?.toString() ?? '');
    _dobController = TextEditingController(text: data['dateOfBirth']?.toString() ?? '');
    _bloodGroupController = TextEditingController(text: data['bloodGroup']?.toString() ?? '');
    _fatherNameController = TextEditingController(text: data['fatherName']?.toString() ?? '');
    _motherNameController = TextEditingController(text: data['motherName']?.toString() ?? '');
    _phoneController = TextEditingController(text: data['phone']?.toString() ?? '');
    _addressController = TextEditingController(text: data['address']?.toString() ?? '');
    _gender = data['gender']?.toString() ?? 'Male';
    _classId = data['classId']?.toString();
    _profileImage = data['profileImage']?.toString();
    _loadClasses();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _admissionController.dispose();
    _dobController.dispose();
    _bloodGroupController.dispose();
    _fatherNameController.dispose();
    _motherNameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _loadClasses() async {
    final classes = await _service.getClasses();
    if (!mounted) return;
    setState(() {
      _classes = classes;
      _loading = false;
      _classId ??= classes.isNotEmpty ? classes.first.id : null;
    });
  }

  Future<void> _pickProfileImage(String studentId) async {
    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final url = await _service.uploadProfileImage(studentId);
    if (!mounted) return;
    setState(() => _profileImage = url);
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.studentId != null;
    return Scaffold(
      appBar: AppBar(title: Text(isEditing ? 'Edit Student' : 'Create Student')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: ListView(
                  children: [
                    if (_profileImage != null && _profileImage!.isNotEmpty)
                      CircleAvatar(radius: 40, backgroundImage: NetworkImage(_profileImage!)),
                    TextButton(
                      onPressed: widget.studentId == null ? null : () => _pickProfileImage(widget.studentId!),
                      child: const Text('Upload Profile Image'),
                    ),
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(labelText: 'Name'),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                    TextFormField(
                      controller: _admissionController,
                      decoration: const InputDecoration(labelText: 'Admission Number'),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                    DropdownButtonFormField<String>(
                      value: _classId,
                      items: [
                        for (final c in _classes)
                          DropdownMenuItem(value: c.id, child: Text(c.data()['name']?.toString() ?? '')),
                      ],
                      onChanged: (v) => setState(() => _classId = v),
                      decoration: const InputDecoration(labelText: 'Class'),
                    ),
                    DropdownButtonFormField<String>(
                      value: _gender,
                      items: const [
                        DropdownMenuItem(value: 'Male', child: Text('Male')),
                        DropdownMenuItem(value: 'Female', child: Text('Female')),
                      ],
                      onChanged: (v) => setState(() => _gender = v ?? 'Male'),
                      decoration: const InputDecoration(labelText: 'Gender'),
                    ),
                    TextFormField(controller: _dobController, decoration: const InputDecoration(labelText: 'Date of Birth')),
                    TextFormField(controller: _bloodGroupController, decoration: const InputDecoration(labelText: 'Blood Group')),
                    TextFormField(controller: _fatherNameController, decoration: const InputDecoration(labelText: 'Father Name')),
                    TextFormField(controller: _motherNameController, decoration: const InputDecoration(labelText: 'Mother Name')),
                    TextFormField(controller: _phoneController, decoration: const InputDecoration(labelText: 'Phone')),
                    TextFormField(controller: _addressController, decoration: const InputDecoration(labelText: 'Address')),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () async {
                        if (!_formKey.currentState!.validate()) return;
                        final model = AdminStudentModel(
                          id: widget.studentId ?? '',
                          name: _nameController.text.trim(),
                          admissionNo: _admissionController.text.trim(),
                          classId: _classId ?? '',
                          gender: _gender,
                          dateOfBirth: _dobController.text.trim(),
                          bloodGroup: _bloodGroupController.text.trim(),
                          fatherName: _fatherNameController.text.trim(),
                          motherName: _motherNameController.text.trim(),
                          phone: _phoneController.text.trim(),
                          address: _addressController.text.trim(),
                          profileImage: _profileImage ?? '',
                          isActive: true,
                          isApproved: false,
                        );
                        if (isEditing) {
                          await _service.updateStudent(studentId: widget.studentId!, student: model);
                        } else {
                          await _service.addStudent(model);
                        }
                        if (context.mounted) Navigator.pop(context);
                      },
                      child: const Text('Save'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
