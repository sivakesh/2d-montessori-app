import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/config/app_env.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_sizes.dart';
import '../../admin/models/admin_class_model.dart';
import '../../finance/widgets/finance_status_chip.dart';
import '../data/class_service.dart';
import 'class_form_dialog.dart';
import 'class_view_dialog.dart';

class ClassListScreen extends StatefulWidget {
  const ClassListScreen({
    super.key,
    this.readOnly = false,
    this.service,
  });

  final bool readOnly;

  /// Overridable only so tests can inject a fake-Firestore-backed
  /// ClassService — the same DI seam every service here already exposes
  /// on its own constructor. Production callers never pass this.
  final ClassService? service;

  @override
  State<ClassListScreen> createState() => ClassListScreenState();
}

class ClassListScreenState extends State<ClassListScreen> {
  late final _service = widget.service ?? ClassService();
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> openAddClass() async {
    if (widget.readOnly) return;
    await _openForm();
  }

  Future<void> _openForm({String? classId, Map<String, dynamic>? initialData}) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => ClassFormDialog(classId: classId, initialData: initialData),
    );
    if (mounted) setState(() {});
  }

  Future<bool> _confirmDelete() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete class?'),
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

  Future<void> _deleteClass(String classId) async {
    if (!await _confirmDelete()) return;
    await _service.deleteClass(classId);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
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
                      'Classes',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Manage classes, sections, capacity, and academic year.',
                      style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              if (!widget.readOnly && currentEnvironment == AppEnvironment.dev)
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
          const SizedBox(height: 20),
          TextField(
            controller: _searchController,
            decoration: const InputDecoration(
              labelText: 'Search by class name or section',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 20),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _service.watchClasses(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                      child: Text('Failed to load classes: ${snapshot.error}'),
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                final docs = snapshot.data!.docs.where((doc) {
                  final model = AdminClassModel.fromMap(doc.id, doc.data());
                  final matchesSearch = query.isEmpty ||
                      model.name.toLowerCase().contains(query) ||
                      model.section.toLowerCase().contains(query);
                  return matchesSearch && model.isActive;
                }).toList();

                if (docs.isEmpty) {
                  return const _ClassesEmptyState();
                }

                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: docs.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final model = AdminClassModel.fromMap(doc.id, doc.data());
                    return _ClassRow(
                      model: model,
                      showDetails: !widget.readOnly,
                      showActions: !widget.readOnly,
                      onView: () => showDialog(
                        context: context,
                        barrierDismissible: false,
                        builder: (_) => ClassViewDialog(classId: doc.id),
                      ),
                      onEdit: () => _openForm(classId: doc.id, initialData: doc.data()),
                      onDelete: () => _deleteClass(doc.id),
                    );
                  },
                );
              },
            ),
          // Reserves clearance so the last class's actions can scroll
          // fully clear of the floating "Add class" FAB (Admin only).
          const SizedBox(height: 24 + AppSizes.fabScrollClearance),
        ],
      ),
    );
  }
}

/// Compact class row matching the shared card style established for
/// Finance/Attendance/Users/Students. [showDetails]/[showActions] preserve
/// the screen's existing readOnly behavior (used embedded, read-only, in
/// the staff Dashboard). Presentation only.
class _ClassRow extends StatelessWidget {
  const _ClassRow({
    required this.model,
    required this.showDetails,
    required this.showActions,
    required this.onView,
    required this.onEdit,
    required this.onDelete,
  });

  final AdminClassModel model;
  final bool showDetails;
  final bool showActions;
  final VoidCallback onView;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
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
                  model.name.isEmpty ? 'Class' : model.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textPrimary),
                ),
                if (model.section.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    'Section ${model.section}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
                if (showDetails) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 16,
                    runSpacing: 4,
                    children: [
                      Text('Academic Year ${model.academicYear.isEmpty ? '-' : model.academicYear}', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      Text('Capacity ${model.capacity?.toString() ?? '-'}', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    ],
                  ),
                ],
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    FinanceStatusChip(label: model.isActive ? 'ACTIVE' : 'INACTIVE', color: model.isActive ? AppColors.primary : Colors.grey),
                    if (showDetails)
                      FinanceStatusChip(
                        label: model.approvalStatus.toUpperCase(),
                        color: model.approvalStatus.toLowerCase() == 'approved' ? AppColors.secondary : const Color(0xFFB26A00),
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (showActions) ...[
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
        ],
      ),
    );
  }
}

class _ClassesEmptyState extends StatelessWidget {
  const _ClassesEmptyState();

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
          Icon(Icons.class_outlined, size: 36, color: AppColors.textSecondary.withValues(alpha: 0.6)),
          const SizedBox(height: 12),
          const Text(
            'No classes found',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 4),
          const Text(
            'No classes match your current search.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
