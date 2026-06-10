// ignore_for_file: camel_case_types
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../data/admin_students_service.dart';
import '../models/admin_student_model.dart';
import 'admin_student_detail_screen.dart';
import 'admin_student_form_screen.dart';

class admin_students_screen extends StatefulWidget {
  const admin_students_screen({super.key});

  @override
  State<admin_students_screen> createState() => _admin_students_screenState();
}

class _admin_students_screenState extends State<admin_students_screen> {
  final AdminStudentsService _service = AdminStudentsService();
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _selectedClassIds = <String>{};

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _students = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _classes = [];
  bool _isLoading = true;

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
      _isLoading = false;
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

  void _refresh() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final filteredStudents = _students.where((doc) {
      final data = doc.data();
      final name = (data['name']?.toString() ?? '').toLowerCase();
      final classId = data['classId']?.toString() ?? '';
      final matchesSearch = query.isEmpty || name.contains(query);
      final matchesClass = _selectedClassIds.isEmpty || _selectedClassIds.contains(classId);
      return matchesSearch && matchesClass;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Students'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Students',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const Spacer(),
                ElevatedButton(
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const admin_student_form_screen(),
                      ),
                    );
                    await _loadData();
                  },
                  child: const Text('Add Student'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                labelText: 'Search by name',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (_) => _refresh(),
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final doc in _classes) ...[
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
                ],
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : filteredStudents.isEmpty
                      ? _buildEmptyState(context)
                      : ListView.builder(
                          itemCount: filteredStudents.length,
                          itemBuilder: (context, index) {
                            final doc = filteredStudents[index];
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
                                        backgroundImage: student.profileImage.isNotEmpty
                                            ? NetworkImage(student.profileImage)
                                            : null,
                                        child: student.profileImage.isEmpty
                                            ? Text(
                                                student.name.isNotEmpty
                                                    ? student.name[0].toUpperCase()
                                                    : '?',
                                              )
                                            : null,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              student.name,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleMedium,
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              'Admission No: ${student.admissionNo}',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodyMedium,
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              'Class: ${_classNameFor(student.classId)}',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodyMedium,
                                            ),
                                            const SizedBox(height: 8),
                                            Wrap(
                                              spacing: 8,
                                              runSpacing: 8,
                                              children: [
                                                Chip(
                                                  label: Text(
                                                    student.isApproved
                                                        ? 'Approved'
                                                        : 'Pending',
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      Column(
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.visibility),
                                            onPressed: () async {
                                              await Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (_) =>
                                                      admin_student_detail_screen(
                                                    studentId: doc.id,
                                                  ),
                                                ),
                                              );
                                              await _loadData();
                                            },
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.edit),
                                            onPressed: () async {
                                              await Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (_) =>
                                                      admin_student_form_screen(
                                                    studentId: doc.id,
                                                    initialData: data,
                                                  ),
                                                ),
                                              );
                                              await _loadData();
                                            },
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.delete),
                                            onPressed: () async {
                                              await _service.deleteStudent(doc.id);
                                              await _loadData();
                                            },
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

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('No students found'),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const admin_student_form_screen(),
                ),
              );
              await _loadData();
            },
            child: const Text('+ Add Student'),
          ),
        ],
      ),
    );
  }
}
