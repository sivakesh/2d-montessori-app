// ignore_for_file: camel_case_types
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../core/config/app_env.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../finance/widgets/finance_status_chip.dart';
import '../data/admin_student_service.dart';
import '../models/admin_student_model.dart';
import 'admin_student_view_dialog.dart';
import '../../ui/admin_fab.dart';
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
    if (!await _confirmDelete()) return;
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
      floatingActionButton: AdminFab(
        icon: Icons.add,
        onPressed: () => _openForm(),
      ),
      body: SingleChildScrollView(
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
                        'Manage student records, admissions, and class assignments.',
                        style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                if (currentEnvironment == AppEnvironment.dev)
                  TextButton.icon(
                    onPressed: _classes.isEmpty
                        ? null
                        : () => _openForm(initialData: _sampleStudentData()),
                    icon: const Icon(Icons.auto_awesome),
                    label: const Text('Seed Sample'),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                labelText: 'Search by name or admission no',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            const Text(
              'Filter by Class',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 8),
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
            const SizedBox(height: 20),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (filtered.isEmpty)
              const _StudentsEmptyState()
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final doc = filtered[index];
                  final data = doc.data();
                  final student = AdminStudentModel.fromMap(doc.id, data);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _StudentRow(
                      name: student.name,
                      admissionNo: student.admissionNo,
                      className: _classNameFor(student.classId),
                      isActive: student.isActive,
                      onView: () => _openView(doc.id),
                      onEdit: () => _openForm(studentId: doc.id, initialData: data),
                      onDelete: () => _deleteStudent(doc.id),
                    ),
                  );
                },
              ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

/// Compact student row matching the shared card style established for
/// Finance/Attendance/Users. Presentation only — callbacks are the
/// screen's existing view/edit/delete handlers, unchanged.
class _StudentRow extends StatelessWidget {
  const _StudentRow({
    required this.name,
    required this.admissionNo,
    required this.className,
    required this.isActive,
    required this.onView,
    required this.onEdit,
    required this.onDelete,
  });

  final String name;
  final String admissionNo;
  final String className;
  final bool isActive;
  final VoidCallback onView;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final subtitle = [admissionNo, className].where((v) => v.isNotEmpty && v != '-').join(' • ');
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
              name.isNotEmpty ? name[0].toUpperCase() : '?',
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
                  name.isEmpty ? 'Student' : name,
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
                FinanceStatusChip(label: isActive ? 'ACTIVE' : 'INACTIVE', color: isActive ? AppColors.primary : Colors.grey),
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

class admin_students_screen extends AdminStudentsScreen {
  const admin_students_screen({super.key});
}
