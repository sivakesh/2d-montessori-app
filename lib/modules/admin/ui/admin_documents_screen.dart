import 'package:flutter/material.dart';

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
                Text('Documents', style: Theme.of(context).textTheme.headlineSmall),
                const Spacer(),
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
            const SizedBox(height: 16),
            TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Search by title, file name, document type, category, tags',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 12),
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
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _typeFilter,
              decoration: const InputDecoration(labelText: 'Document Type'),
              items: _types.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
              onChanged: (value) => setState(() => _typeFilter = value ?? 'All'),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : filtered.isEmpty
                      ? const Center(child: Text('No documents uploaded'))
                      : ListView.builder(
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final doc = filtered[index];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const CircleAvatar(
                                        radius: 24,
                                        child: Icon(Icons.description),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(doc.title, style: Theme.of(context).textTheme.titleMedium),
                                            const SizedBox(height: 4),
                                            Text('Type: ${doc.documentType}'),
                                            Text('Category: ${doc.category}'),
                                            Text('Academic Year: ${doc.academicYear.isEmpty ? '-' : doc.academicYear}'),
                                            Text('Visibility: ${doc.visibility}'),
                                            Text('Status: ${doc.status}'),
                                            if (doc.appliesToAllClasses)
                                              const Padding(
                                                padding: EdgeInsets.only(top: 4),
                                                child: Chip(label: Text('All Classes')),
                                              )
                                            else if (doc.applicableClassNames.isNotEmpty)
                                              Padding(
                                                padding: const EdgeInsets.only(top: 4),
                                                child: Wrap(
                                                  spacing: 8,
                                                  runSpacing: 8,
                                                  children: doc.applicableClassNames
                                                      .map((name) => Chip(label: Text(name)))
                                                      .toList(),
                                                ),
                                              ),
                                            if (doc.issueDate != null || doc.expiryDate != null)
                                              Text('Issue/Expiry: ${doc.issueDate?.toIso8601String().split('T').first ?? '-'} / ${doc.expiryDate?.toIso8601String().split('T').first ?? '-'}'),
                                            Text('File: ${doc.fileName.isEmpty ? 'No file attached' : doc.fileName}'),
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
                                              builder: (_) => AdminDocumentViewDialog(documentId: doc.id),
                                            ),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.edit),
                                            onPressed: () => _openForm(doc: doc),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.delete),
                                            onPressed: () => _deleteDoc(doc),
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
