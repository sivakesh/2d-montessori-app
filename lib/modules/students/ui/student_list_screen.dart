import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../admin/models/admin_class_model.dart';
import '../../admin/models/admin_student_model.dart';
import '../providers/student_provider.dart';

class StudentListScreen extends ConsumerStatefulWidget {
  const StudentListScreen({super.key});

  @override
  ConsumerState<StudentListScreen> createState() => _StudentListScreenState();
}

class _StudentListScreenState extends ConsumerState<StudentListScreen> {
  final _searchController = TextEditingController();
  final Set<String> _selectedClassIds = {};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final service = ref.watch(studentServiceProvider);
    final query = _searchController.text.trim().toLowerCase();
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Students', style: Theme.of(context).textTheme.headlineSmall),
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
          FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
            future: FirebaseFirestore.instance
                .collection('classes')
                .where('isActive', isEqualTo: true)
                .get(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const SizedBox.shrink();
              }
              final classes = snapshot.data!.docs
                  .map((doc) => AdminClassModel.fromMap(doc.id, doc.data()))
                  .where((model) => model.isActive)
                  .toList();
              if (classes.isEmpty) {
                return const SizedBox.shrink();
              }
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final model in classes)
                    FilterChip(
                      selected: _selectedClassIds.contains(model.id),
                      label: Text(model.name),
                      onSelected: (selected) {
                        setState(() {
                          if (selected) {
                            _selectedClassIds.add(model.id);
                          } else {
                            _selectedClassIds.remove(model.id);
                          }
                        });
                      },
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          Expanded(
            child: FutureBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
              future: service.getAllStudents(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Text('Failed to load students: ${snapshot.error}'),
                  );
                }

                final docs = snapshot.data ?? [];
                final filteredDocs = docs.where((doc) {
                  final data = doc.data();
                  final student = AdminStudentModel.fromMap(doc.id, data);
                  final name = student.name.toLowerCase();
                  final admissionNo = data['admissionNo']?.toString().toLowerCase() ?? '';
                  final matchesSearch =
                      query.isEmpty || name.contains(query) || admissionNo.contains(query);
                  final matchesClass =
                      _selectedClassIds.isEmpty || _selectedClassIds.contains(student.classId);
                  return matchesSearch && matchesClass && student.isActive;
                }).toList();

                if (filteredDocs.isEmpty) {
                  return const Center(child: Text('No students available.'));
                }

                return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  future: FirebaseFirestore.instance.collection('classes').get(),
                  builder: (context, classSnapshot) {
                    final classMap = <String, String>{};
                    if (classSnapshot.hasData) {
                      for (final doc in classSnapshot.data!.docs) {
                        classMap[doc.id] = doc.data()['name']?.toString() ?? '-';
                      }
                    }

                    return ListView.separated(
                      itemCount: filteredDocs.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final doc = filteredDocs[index];
                        final data = doc.data();
                        final student = AdminStudentModel.fromMap(doc.id, data);
                        final gender = data['gender']?.toString() ?? '-';
                        final age = data['age']?.toString() ?? data['studentAge']?.toString() ?? '';
                        return Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              child: Text(
                                student.name.isNotEmpty ? student.name[0].toUpperCase() : '?',
                              ),
                            ),
                            title: Text(student.name),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('Admission No: ${data['admissionNo']?.toString() ?? '-'}'),
                                Text('Class: ${classMap[student.classId] ?? '-'}'),
                                Text('Gender: $gender'),
                                if (age.isNotEmpty) Text('Age: $age'),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
