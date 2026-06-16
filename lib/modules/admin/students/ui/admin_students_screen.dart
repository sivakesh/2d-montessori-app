// ignore_for_file: camel_case_types
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../data/admin_student_service.dart';
import '../models/admin_student_model.dart';
import 'admin_student_view_dialog.dart';
import '../../ui/admin_layout.dart';
import '../../ui/admin_student_form.dart';

class AdminStudentsScreen extends StatefulWidget {
  const AdminStudentsScreen({super.key});

  @override
  State<AdminStudentsScreen> createState() => _AdminStudentsScreenState();
}

class _AdminStudentsScreenState extends State<AdminStudentsScreen> {
  final AdminStudentService _service = AdminStudentService();
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _selectedClassIds = <String>{};
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _students = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _classes = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final students = await _service.getStudents();
    final classes = await _service.getClasses();
    if (!mounted) return;
    setState(() {
      _students = students;
      _classes = classes;
      _loading = false;
    });
  }

  String _classNameFor(String classId) {
    for (final doc in _classes) {
      if (doc.id == classId) {
        return doc.data()['name']?.toString() ?? '-';
      }
    }
    return '-';
  }

  Future<void> _openForm({
    String? studentId,
    Map<String, dynamic>? initialData,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AdminStudentForm(
          studentId: studentId,
          initialData: initialData,
        ),
      ),
    );
    await _loadData();
  }

  Map<String, dynamic> _sampleStudentData() {
    final classId = _classes.isNotEmpty ? _classes.first.id : null;
    return {
      'name': 'Aarav Kumar',
      'admissionNo': 'ADM2026001',
      'classId': classId,
      'section': 'A',
      'rollNumber': '12',
      'dateOfBirth': '2019-06-15',
      'gender': 'Male',
      'bloodGroup': 'O+',
      'nationality': 'Indian',
      'motherTongue': 'Tamil',
      'addressLine1': '12, Gandhi Street',
      'addressLine2': 'Near Temple Road',
      'city': 'Coimbatore',
      'state': 'Tamil Nadu',
      'pincode': '641001',
      'isActive': true,
      'profileImageUrl': '',
    };
  }

  Future<void> _openView(String studentId) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AdminStudentViewDialog(studentId: studentId),
    );
    await _loadData();
  }

  Future<void> _deleteStudent(String studentId) async {
    await _service.deleteStudent(studentId);
    await _loadData();
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final filtered = _students.where((doc) {
      final data = doc.data();
      final name = data['name']?.toString().toLowerCase() ?? '';
      final admissionNo = data['admissionNo']?.toString().toLowerCase() ?? '';
      final classId = data['classId']?.toString() ?? '';
      final matchesSearch =
          query.isEmpty || name.contains(query) || admissionNo.contains(query);
      final matchesClass =
          _selectedClassIds.isEmpty || _selectedClassIds.contains(classId);
      return matchesSearch && matchesClass;
    }).toList();

    return AdminLayout(
      selectedIndex: 2,
      title: 'Students',
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF2E7D32),
        elevation: 4,
        onPressed: () => _openForm(),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Students', style: Theme.of(context).textTheme.headlineSmall),
                const Spacer(),
                TextButton.icon(
                  onPressed: _classes.isEmpty
                      ? null
                      : () => _openForm(initialData: _sampleStudentData()),
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('Seed Sample'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                labelText: 'Search by name or admission no',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final doc in _classes)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        selected: _selectedClassIds.contains(doc.id),
                        label: Text(doc.data()['name']?.toString() ?? ''),
                        onSelected: (selected) {
                          setState(() {
                            if (selected) {
                              _selectedClassIds.add(doc.id);
                            } else {
                              _selectedClassIds.remove(doc.id);
                            }
                          });
                        },
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : filtered.isEmpty
                      ? const Center(child: Text('No students found'))
                      : ListView.builder(
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final doc = filtered[index];
                            final data = doc.data();
                            final student = AdminStudentModel.fromMap(doc.id, data);
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      CircleAvatar(
                                        radius: 24,
                                        child: Text(
                                          student.name.isNotEmpty
                                              ? student.name[0].toUpperCase()
                                              : '?',
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              student.name,
                                              style: Theme.of(context).textTheme.titleMedium,
                                            ),
                                            const SizedBox(height: 4),
                                            Text('Admission No: ${student.admissionNo}'),
                                            const SizedBox(height: 2),
                                            Text('Class: ${_classNameFor(student.classId)}'),
                                            const SizedBox(height: 2),
                                            Text(
                                              student.isActive ? 'Status: Active' : 'Status: Inactive',
                                            ),
                                          ],
                                        ),
                                      ),
                                      Column(
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.visibility),
                                            onPressed: () => _openView(doc.id),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.edit),
                                            onPressed: () => _openForm(
                                              studentId: doc.id,
                                              initialData: data,
                                            ),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.delete),
                                            onPressed: () => _deleteStudent(doc.id),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class admin_students_screen extends AdminStudentsScreen {
  const admin_students_screen({super.key});
}
