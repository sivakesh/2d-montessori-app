import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../admin/models/admin_class_model.dart';
import '../data/class_service.dart';
import 'class_form_dialog.dart';
import 'class_view_dialog.dart';

class ClassListScreen extends StatefulWidget {
  const ClassListScreen({super.key});

  @override
  State<ClassListScreen> createState() => ClassListScreenState();
}

class ClassListScreenState extends State<ClassListScreen> {
  final _service = ClassService();
  final _searchController = TextEditingController();
  String _filter = 'All';

  Future<void> openAddClass() => _openForm();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openForm({String? classId, Map<String, dynamic>? initialData}) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => ClassFormDialog(classId: classId, initialData: initialData),
    );
    if (mounted) setState(() {});
  }

  Future<void> _deleteClass(String classId) async {
    await _service.deleteClass(classId);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Classes', style: Theme.of(context).textTheme.headlineSmall),
                const Spacer(),
                TextButton.icon(
                  onPressed: () async {
                    await _service.seedSampleClasses();
                    if (mounted) setState(() {});
                  },
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('Seed Sample'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                labelText: 'Search by class name or section',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ['All', 'Active', 'Inactive', 'Pending Approval']
                  .map(
                    (value) => FilterChip(
                      selected: _filter == value,
                      label: Text(value),
                      onSelected: (_) => setState(() => _filter = value),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _service.watchClasses(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: Text('Failed to load classes: ${snapshot.error}'),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final docs = snapshot.data!.docs.where((doc) {
                    final data = doc.data();
                    final model = AdminClassModel.fromMap(doc.id, data);
                    final matchesSearch = query.isEmpty ||
                        model.name.toLowerCase().contains(query) ||
                        model.section.toLowerCase().contains(query);
                    final approval = model.approvalStatus.toLowerCase();
                    final matchesFilter = switch (_filter) {
                      'Active' => model.isActive,
                      'Inactive' => !model.isActive,
                      'Pending Approval' => approval == 'pending approval',
                      _ => true,
                    };
                    return matchesSearch && matchesFilter;
                  }).toList();

                  if (docs.isEmpty) {
                    return const Center(child: Text('No classes found'));
                  }

                  return ListView.builder(
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final doc = docs[index];
                      final data = doc.data();
                      final model = AdminClassModel.fromMap(doc.id, data);
                      return FutureBuilder<int>(
                        future: _service.getStudentCountByClassId(doc.id),
                        builder: (context, countSnapshot) {
                          final studentCount = countSnapshot.data ?? 0;
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
                                        model.name.isNotEmpty ? model.name[0].toUpperCase() : '?',
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(model.name, style: Theme.of(context).textTheme.titleMedium),
                                          const SizedBox(height: 4),
                                          Text('Section: ${model.section.isEmpty ? '-' : model.section}'),
                                          const SizedBox(height: 2),
                                          Text('Academic Year: ${model.academicYear.isEmpty ? '-' : model.academicYear}'),
                                          const SizedBox(height: 2),
                                          Text('Capacity: ${model.capacity?.toString() ?? '-'}'),
                                          const SizedBox(height: 2),
                                          Text('Students: $studentCount'),
                                          const SizedBox(height: 2),
                                          Text('Status: ${model.isActive ? 'Active' : 'Inactive'}'),
                                          const SizedBox(height: 2),
                                          Text('Approval: ${model.approvalStatus}'),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.visibility),
                                          onPressed: () => showDialog(
                                            context: context,
                                            barrierDismissible: false,
                                            builder: (_) => ClassViewDialog(classId: doc.id),
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.edit),
                                          onPressed: () => _openForm(classId: doc.id, initialData: data),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.delete),
                                          onPressed: () => _deleteClass(doc.id),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
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
