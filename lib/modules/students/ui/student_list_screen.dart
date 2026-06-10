import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/student_provider.dart';
import 'create_student_screen.dart';

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
    return Padding(
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
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const CreateStudentScreen(),
                  ),
                ),
                child: const Text('Add Student'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _searchController,
            decoration: const InputDecoration(labelText: 'Search by name'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
            future: FirebaseFirestore.instance.collection('classes').get(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const SizedBox.shrink();
              }
              final classes = snapshot.data!.docs;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final doc in classes)
                    FilterChip(
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
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          Expanded(
            child:
                FutureBuilder<
                  List<QueryDocumentSnapshot<Map<String, dynamic>>>
                >(
                  future: service.getAllStudents(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final docs = snapshot.data ?? [];
                    final filteredDocs = docs.where((doc) {
                      final name = (doc.data()['name'] ?? '')
                          .toString()
                          .toLowerCase();
                      final classId = doc.data()['classId']?.toString() ?? '';
                      final matchesClass =
                          _selectedClassIds.isEmpty ||
                          _selectedClassIds.contains(classId);
                      return matchesClass &&
                          name.contains(_searchController.text.toLowerCase());
                    }).toList();
                    if (filteredDocs.isEmpty) {
                      return const Center(child: Text('No students found.'));
                    }
                    return ListView.separated(
                      itemCount: filteredDocs.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final doc = filteredDocs[index];
                        final data = doc.data();
                        return Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: ListTile(
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(data['name']?.toString() ?? ''),
                                ),
                                if (data['isApproved'] != true) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.orange.shade100,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Text('Pending Approval'),
                                  ),
                                ],
                              ],
                            ),
                            subtitle: Text(
                              data['admissionNo']?.toString() ?? '',
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.edit),
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => CreateStudentScreen(
                                    studentId: doc.id,
                                    initialData: data,
                                  ),
                                ),
                              ),
                            ),
                          ),
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
