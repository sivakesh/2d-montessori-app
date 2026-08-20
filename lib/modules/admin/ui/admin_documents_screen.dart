import 'package:flutter/material.dart';

import '../../../core/config/app_env.dart';
import '../../../core/theme/app_colors.dart';
import '../../finance/widgets/finance_status_chip.dart';
import '../documents/data/admin_documents_service.dart';
import '../documents/models/admin_school_document.dart';
import 'admin_layout.dart';
import '../documents/ui/admin_document_form_dialog.dart';
import '../documents/ui/admin_document_view_dialog.dart';

class AdminDocumentsScreen extends StatefulWidget {
  const AdminDocumentsScreen({super.key});

  @override
  State<AdminDocumentsScreen> createState() => _AdminDocumentsScreenState();
}

class _AdminDocumentsScreenState extends State<AdminDocumentsScreen> {
  final _service = AdminDocumentsService();
  final _searchController = TextEditingController();
  String _filter = 'All';
  String _typeFilter = 'All';
  List<AdminSchoolDocument> _documents = [];
  bool _loading = true;

  static const _types = <String>[
    'All',
    'Circular',
    'Policy',
    'Consent Form',
    'Fee Structure',
    'Academic Calendar',
    'Holiday List',
    'Timetable',
    'Syllabus',
    'Admission Document',
    'Staff Document',
    'Parent Communication',
    'Government Compliance',
    'Medical / Safety',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final docs = await _service.getSchoolDocuments();
    if (!mounted) return;
    setState(() {
      _documents = docs;
      _loading = false;
    });
  }

  Future<void> _openForm({AdminSchoolDocument? doc}) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AdminDocumentFormDialog(document: doc),
    );
    await _load();
  }

  Future<void> _deleteDoc(AdminSchoolDocument doc) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Document'),
        content: const Text('Are you sure you want to delete this document?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    await _service.deleteDocument(doc.id, fileUrl: doc.fileUrl);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final q = _searchController.text.trim().toLowerCase();
    final filtered = _documents.where((doc) {
      final matchesSearch = q.isEmpty ||
          doc.title.toLowerCase().contains(q) ||
          doc.fileName.toLowerCase().contains(q) ||
          doc.documentType.toLowerCase().contains(q) ||
          doc.category.toLowerCase().contains(q) ||
          doc.tags.any((t) => t.toLowerCase().contains(q));
      final matchesStatus = switch (_filter) {
        'Published' => doc.status == 'Published',
        'Draft' => doc.status == 'Draft',
        'Archived' => doc.status == 'Archived',
        'Expiring Soon' => doc.expiryDate != null &&
            doc.expiryDate!.difference(DateTime.now()).inDays <= 30,
        _ => true,
      };
      final matchesType = _typeFilter == 'All' || doc.documentType == _typeFilter;
      return matchesSearch && matchesStatus && matchesType;
    }).toList();

    return AdminLayout(
      selectedIndex: 4,
      title: 'Documents',
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.primary,
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Documents',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Manage school documents, notices, circulars, and files.',
                        style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                if (currentEnvironment == AppEnvironment.dev)
                  TextButton.icon(
                    onPressed: () async {
                      await _service.seedSampleDocuments();
                      await _load();
                    },
                    icon: const Icon(Icons.auto_awesome),
                    label: const Text('Seed Sample'),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Search by title, file name, document type, category, tags',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Filters',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 12),
                  const Text('Status', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: ['All', 'Published', 'Draft', 'Archived', 'Expiring Soon']
                        .map((value) => FilterChip(
                              label: Text(value),
                              selected: _filter == value,
                              onSelected: (_) => setState(() => _filter = value),
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 16),
                  const Text('Document Type', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _typeFilter,
                    decoration: const InputDecoration(isDense: true),
                    items: _types.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                    onChanged: (value) => setState(() => _typeFilter = value ?? 'All'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : filtered.isEmpty
                      ? const _DocumentsEmptyState()
                      : ListView.builder(
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final doc = filtered[index];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _DocumentRow(
                                doc: doc,
                                onView: () => showDialog(
                                  context: context,
                                  barrierDismissible: false,
                                  builder: (_) => AdminDocumentViewDialog(documentId: doc.id),
                                ),
                                onEdit: () => _openForm(doc: doc),
                                onDelete: () => _deleteDoc(doc),
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

/// Compact document row matching the shared card style established for
/// Finance/Attendance/Users/Students/Classes. Every field the previous
/// card showed is still shown here — just laid out more compactly.
/// Presentation only.
class _DocumentRow extends StatelessWidget {
  const _DocumentRow({
    required this.doc,
    required this.onView,
    required this.onEdit,
    required this.onDelete,
  });

  final AdminSchoolDocument doc;
  final VoidCallback onView;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  Color get _statusColor => switch (doc.status) {
        'Published' => AppColors.primary,
        'Draft' => const Color(0xFFB26A00),
        'Archived' => Colors.grey,
        _ => AppColors.secondary,
      };

  @override
  Widget build(BuildContext context) {
    final metaLine = [doc.documentType, doc.category].where((v) => v.isNotEmpty).join(' • ');
    final classesLine = doc.appliesToAllClasses
        ? 'All Classes'
        : doc.applicableClassNames.isNotEmpty
            ? doc.applicableClassNames.join(', ')
            : '';
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
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.description_outlined, color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        doc.title.isEmpty ? 'Document' : doc.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textPrimary),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FinanceStatusChip(label: doc.status.toUpperCase(), color: _statusColor),
                  ],
                ),
                if (metaLine.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(metaLine, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                ],
                const SizedBox(height: 4),
                Text(
                  'Academic Year: ${doc.academicYear.isEmpty ? '-' : doc.academicYear}  •  Visibility: ${doc.visibility}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
                if (classesLine.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(classesLine, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                ],
                if (doc.issueDate != null || doc.expiryDate != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Issue/Expiry: ${doc.issueDate?.toIso8601String().split('T').first ?? '-'} / ${doc.expiryDate?.toIso8601String().split('T').first ?? '-'}',
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  'File: ${doc.fileName.isEmpty ? 'No file attached' : doc.fileName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
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

class _DocumentsEmptyState extends StatelessWidget {
  const _DocumentsEmptyState();

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
          Icon(Icons.folder_open_outlined, size: 36, color: AppColors.textSecondary.withValues(alpha: 0.6)),
          const SizedBox(height: 12),
          const Text(
            'No documents found',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 4),
          const Text(
            'No documents match your current search or filters.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
