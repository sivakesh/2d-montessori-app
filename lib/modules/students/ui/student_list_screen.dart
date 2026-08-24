import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_env.dart';
import '../../../core/theme/app_colors.dart';
import '../../admin/models/admin_class_model.dart';
import '../../admin/students/data/admin_student_service.dart';
import '../../admin/students/models/admin_student_model.dart';
import '../../admin/students/ui/admin_student_view_dialog.dart';
import '../../admin/ui/admin_student_form.dart';
import '../../auth/providers/auth_provider.dart';
import '../../finance/widgets/finance_status_chip.dart';
import '../providers/student_provider.dart';

class StudentListScreen extends ConsumerStatefulWidget {
  const StudentListScreen({super.key, this.adminService});

  /// Overridable only so tests can inject a fake-Firestore-backed
  /// AdminStudentService — the same DI seam every service here already
  /// exposes on its own constructor. Production callers never pass this.
  final AdminStudentService? adminService;

  @override
  ConsumerState<StudentListScreen> createState() => StudentListScreenState();
}

class StudentListScreenState extends ConsumerState<StudentListScreen> {
  final _searchController = TextEditingController();
  final Set<String> _selectedClassIds = {};
  late final _adminService = widget.adminService ?? AdminStudentService();

  bool get _isAdmin =>
      (ref.read(currentUserProvider)?.role ?? '').toLowerCase() == 'admin';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> openAddStudent() async {
    if (!_isAdmin) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AdminStudentForm()),
    );
    if (mounted) setState(() {});
  }

  Future<void> _editStudent(String studentId, Map<String, dynamic> data) async {
    if (!_isAdmin) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AdminStudentForm(studentId: studentId, initialData: data),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _viewStudent(String studentId) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AdminStudentViewDialog(
        studentId: studentId,
        readOnly: !_isAdmin,
      ),
    );
    if (mounted) setState(() {});
  }

  Future<bool> _confirmDelete() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete student?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _deleteStudent(String studentId) async {
    if (!_isAdmin) return;
    if (!await _confirmDelete()) return;
    await _adminService.deleteStudent(studentId);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final service = ref.watch(studentServiceProvider);
    final isAdmin = _isAdmin;
    final query = _searchController.text.trim().toLowerCase();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Students',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Search, filter, and view student profiles.',
                      style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              if (isAdmin && currentEnvironment == AppEnvironment.dev)
                TextButton.icon(
                  onPressed: () async {
                    await _adminService.seedSampleStudents();
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
          FutureBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
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
                  return const _StudentsEmptyState();
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
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: filteredDocs.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final doc = filteredDocs[index];
                        final data = doc.data();
                        final student = AdminStudentModel.fromMap(doc.id, data);
                        return _StudentRow(
                          model: student,
                          className: classMap[student.classId] ?? '-',
                          showActions: isAdmin,
                          onView: () => _viewStudent(doc.id),
                          onEdit: () => _editStudent(doc.id, data),
                          onDelete: () => _deleteStudent(doc.id),
                        );
                      },
                    );
                  },
                );
              },
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// Compact student row matching the shared card style established for
/// Classes/Finance/Attendance/Users. [showActions] hides Edit/Delete for
/// Staff while View remains available to everyone.
class _StudentRow extends StatelessWidget {
  const _StudentRow({
    required this.model,
    required this.className,
    required this.showActions,
    required this.onView,
    required this.onEdit,
    required this.onDelete,
  });

  final AdminStudentModel model;
  final String className;
  final bool showActions;
  final VoidCallback onView;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final subtitle = [model.admissionNo, className]
        .where((v) => v.isNotEmpty && v != '-')
        .join(' • ');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: AppColors.primary.withValues(alpha: 0.1),
            child: Text(
              model.name.isNotEmpty ? model.name[0].toUpperCase() : '?',
              style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  model.name.isEmpty ? 'Student' : model.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textPrimary),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
                const SizedBox(height: 6),
                FinanceStatusChip(
                  label: model.isActive ? 'ACTIVE' : 'INACTIVE',
                  color: model.isActive ? AppColors.primary : Colors.grey,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Wrap(
            spacing: 2,
            children: [
              IconButton(
                tooltip: 'View',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.visibility_outlined, size: 20),
                onPressed: onView,
              ),
              if (showActions) ...[
                IconButton(
                  tooltip: 'Edit',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  onPressed: onEdit,
                ),
                IconButton(
                  tooltip: 'Delete',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.delete_outline, size: 20, color: Color(0xFFD32F2F)),
                  onPressed: onDelete,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _StudentsEmptyState extends StatelessWidget {
  const _StudentsEmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Column(
        children: [
          Icon(Icons.school_outlined, size: 36, color: AppColors.textSecondary.withValues(alpha: 0.6)),
          const SizedBox(height: 12),
          const Text(
            'No students found',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 4),
          const Text(
            'No students match your current search or filters.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
