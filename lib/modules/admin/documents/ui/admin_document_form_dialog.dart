import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/theme/app_sizes.dart';
import '../../../../core/widgets/responsive_dialog_shell.dart';
import '../../../classes/data/class_service.dart';
import '../data/admin_documents_service.dart';
import '../models/admin_school_document.dart';

class AdminDocumentFormDialog extends StatefulWidget {
  const AdminDocumentFormDialog({super.key, this.document});

  final AdminSchoolDocument? document;

  @override
  State<AdminDocumentFormDialog> createState() => _AdminDocumentFormDialogState();
}

class _AdminDocumentFormDialogState extends State<AdminDocumentFormDialog> {
  final _service = AdminDocumentsService();
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _academicYear = TextEditingController();
  final _description = TextEditingController();
  final _tags = TextEditingController();
  bool _saving = false;
  bool _active = true;
  bool _appliesToAllClasses = true;
  String _documentType = 'Circular';
  String _category = 'General';
  String _visibility = 'Admin Only';
  String _status = 'Draft';
  DateTime? _issueDate;
  DateTime? _expiryDate;
  PlatformFile? _pickedFile;
  List<String> _applicableClassIds = [];
  List<String> _applicableClassNames = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _allClasses = [];

  static const _documentTypes = ['Circular','Policy','Consent Form','Fee Structure','Academic Calendar','Holiday List','Timetable','Syllabus','Admission Document','Staff Document','Parent Communication','Government Compliance','Medical / Safety','Other'];
  static const _categories = ['Academic','Administration','Admission','Finance','HR / Staff','Parent Communication','Compliance','Safety','Events','General'];
  static const _visibilities = ['Admin Only','Staff','Parents','Public'];
  static const _statuses = ['Draft','Published','Archived'];

  @override
  void initState() {
    super.initState();
    final d = widget.document;
    if (d != null) {
      _title.text = d.title;
      _documentType = d.documentType.isEmpty ? 'Circular' : d.documentType;
      _category = d.category.isEmpty ? 'General' : d.category;
      _academicYear.text = d.academicYear;
      _description.text = d.description;
      _tags.text = d.tags.join(', ');
      _appliesToAllClasses = d.appliesToAllClasses;
      _applicableClassIds = List<String>.from(d.applicableClassIds);
      _applicableClassNames = List<String>.from(d.applicableClassNames);
      _visibility = d.visibility;
      _status = d.status;
      _issueDate = d.issueDate;
      _expiryDate = d.expiryDate;
      _active = d.isActive;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _academicYear.dispose();
    _description.dispose();
    _tags.dispose();
    super.dispose();
  }

  Future<void> _loadClasses() async {
    final classes = await ClassService().getClasses();
    if (!mounted) return;
    setState(() => _allClasses = classes);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_allClasses.isEmpty) {
      _loadClasses();
    }
  }

  Future<void> _pickFile() async {
    final file = await _service.pickFile();
    if (file == null) return;
    setState(() => _pickedFile = file);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_issueDate != null && _expiryDate != null && _expiryDate!.isBefore(_issueDate!)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Expiry date cannot be before issue date')));
      return;
    }
    if (widget.document == null && _pickedFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('File is required')));
      return;
    }
    setState(() => _saving = true);
    try {
      final existing = widget.document;
      final docId = existing?.id ?? await _service.createDocument({
        'title': _title.text.trim(),
        'documentType': _documentType,
        'category': _category,
        'fileName': '',
        'fileUrl': '',
        'fileSize': null,
        'mimeType': '',
        'academicYear': _academicYear.text.trim(),
        'appliesToAllClasses': _appliesToAllClasses,
        'applicableClassIds': _appliesToAllClasses ? const [] : _applicableClassIds,
        'applicableClassNames': _appliesToAllClasses ? const [] : _applicableClassNames,
        'visibility': _visibility,
        'status': _status,
        'issueDate': _issueDate,
        'expiryDate': _expiryDate,
        'uploadedBy': 'admin',
        'uploadedByName': 'Admin',
        'description': _description.text.trim(),
        'tags': _tags.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
        'isActive': _active,
        'createdAt': DateTime.now(),
        'updatedAt': DateTime.now(),
      });
      String fileName = existing?.fileName ?? '';
      String fileUrl = existing?.fileUrl ?? '';
      int? fileSize = existing?.fileSize;
      String mimeType = existing?.mimeType ?? '';
      if (_pickedFile != null) {
        final uploaded = await _service.uploadDocumentFile(documentId: docId, file: _pickedFile!);
        fileName = uploaded?['fileName']?.toString() ?? fileName;
        fileUrl = uploaded?['fileUrl']?.toString() ?? fileUrl;
        fileSize = uploaded?['fileSize'] as int?;
        mimeType = _pickedFile!.extension ?? mimeType;
      }
      await _service.updateDocument(docId, {
        'title': _title.text.trim(),
        'documentType': _documentType,
        'category': _category,
        'fileName': fileName,
        'fileUrl': fileUrl,
        'fileSize': fileSize,
        'mimeType': mimeType,
        'academicYear': _academicYear.text.trim(),
        'appliesToAllClasses': _appliesToAllClasses,
        'applicableClassIds': _appliesToAllClasses ? const [] : _applicableClassIds,
        'applicableClassNames': _appliesToAllClasses ? const [] : _applicableClassNames,
        'visibility': _visibility,
        'status': _status,
        'issueDate': _issueDate,
        'expiryDate': _expiryDate,
        'uploadedBy': existing?.uploadedBy ?? 'admin',
        'uploadedByName': existing?.uploadedByName ?? 'Admin',
        'description': _description.text.trim(),
        'tags': _tags.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
        'isActive': _active,
        'createdAt': existing?.createdAt ?? DateTime.now(),
        'updatedAt': DateTime.now(),
      });
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(existing == null ? 'Document created' : 'Document updated')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save document: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveDialogShell.form(
      desktopWidth: 760,
      desktopHeight: 680,
      title: widget.document == null ? 'Add Document' : 'Edit Document',
      content: Form(
          key: _formKey,
          child: ListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              const Text('Basic Details', style: TextStyle(fontWeight: FontWeight.bold)),
              TextFormField(controller: _title, decoration: const InputDecoration(labelText: 'Title *'), validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null),
              DropdownButtonFormField<String>(initialValue: _documentType, items: _documentTypes.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: (v) => setState(() => _documentType = v ?? _documentType), decoration: const InputDecoration(labelText: 'Document Type *')),
              DropdownButtonFormField<String>(initialValue: _category, items: _categories.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: (v) => setState(() => _category = v ?? _category), decoration: const InputDecoration(labelText: 'Category *')),
              TextFormField(controller: _academicYear, decoration: const InputDecoration(labelText: 'Academic Year')),
              TextFormField(controller: _description, decoration: const InputDecoration(labelText: 'Description'), maxLines: 3),
              const SizedBox(height: 12),
              const Text('Applicability', style: TextStyle(fontWeight: FontWeight.bold)),
              DropdownButtonFormField<String>(initialValue: _visibility, items: _visibilities.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: (v) => setState(() => _visibility = v ?? _visibility), decoration: const InputDecoration(labelText: 'Visibility *')),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Applies To All Classes'),
                value: _appliesToAllClasses,
                onChanged: (v) => setState(() => _appliesToAllClasses = v),
              ),
              if (!_appliesToAllClasses)
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final result = await showDialog<_SelectedClassesResult>(
                            context: context,
                            builder: (_) => _ClassLinkDialog(
                              classes: _allClasses,
                              selectedIds: _applicableClassIds,
                              selectedNames: _applicableClassNames,
                            ),
                          );
                          if (result == null) return;
                          setState(() {
                            _applicableClassIds = result.ids;
                            _applicableClassNames = result.names;
                          });
                        },
                        icon: const Icon(Icons.link),
                        label: const Text('Select Classes'),
                      ),
                    ),
                  ],
                ),
              if (!_appliesToAllClasses && _applicableClassNames.isNotEmpty)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _applicableClassNames
                      .map((name) => Chip(label: Text(name)))
                      .toList(),
                ),
              TextFormField(controller: _tags, decoration: const InputDecoration(labelText: 'Tags (comma separated)')),
              const SizedBox(height: 12),
              const Text('Validity', style: TextStyle(fontWeight: FontWeight.bold)),
              Row(children: [
                Expanded(child: TextButton(onPressed: () async { final d = await showDatePicker(context: context, firstDate: DateTime(2000), lastDate: DateTime(2100), initialDate: _issueDate ?? DateTime.now()); if (d != null) setState(() => _issueDate = d); }, child: Text(_issueDate == null ? 'Issue Date' : _issueDate!.toIso8601String().split('T').first))),
                const SizedBox(width: 8),
                Expanded(child: TextButton(onPressed: () async { final d = await showDatePicker(context: context, firstDate: DateTime(2000), lastDate: DateTime(2100), initialDate: _expiryDate ?? DateTime.now()); if (d != null) setState(() => _expiryDate = d); }, child: Text(_expiryDate == null ? 'Expiry Date' : _expiryDate!.toIso8601String().split('T').first))),
              ]),
              DropdownButtonFormField<String>(initialValue: _status, items: _statuses.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: (v) => setState(() => _status = v ?? _status), decoration: const InputDecoration(labelText: 'Status *')),
              SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Active'), value: _active, onChanged: (v) => setState(() => _active = v)),
              const SizedBox(height: 12),
              const Text('File Upload', style: TextStyle(fontWeight: FontWeight.bold)),
              ListTile(
                title: Text(_pickedFile?.name ?? ((widget.document?.fileName.isNotEmpty ?? false) ? widget.document!.fileName : 'No file selected')),
                subtitle: Text((widget.document?.fileUrl.isNotEmpty ?? false) ? 'Existing file attached' : 'No file attached'),
                trailing: Wrap(spacing: 8, children: [
                  TextButton(onPressed: _pickFile, child: const Text('Upload File')),
                  if ((widget.document?.fileUrl ?? '').isNotEmpty)
                    TextButton(
                      onPressed: () async {
                        await launchUrl(Uri.parse(widget.document!.fileUrl), mode: LaunchMode.externalApplication);
                      },
                      child: const Text('Open Existing'),
                    ),
                ]),
              ),
            ],
          ),
        ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _saving ? null : _save, child: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save')),
      ],
    );
  }
}

class _SelectedClassesResult {
  _SelectedClassesResult({required this.ids, required this.names});
  final List<String> ids;
  final List<String> names;
}

class _ClassLinkDialog extends StatefulWidget {
  const _ClassLinkDialog({
    required this.classes,
    required this.selectedIds,
    required this.selectedNames,
  });

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> classes;
  final List<String> selectedIds;
  final List<String> selectedNames;

  @override
  State<_ClassLinkDialog> createState() => _ClassLinkDialogState();
}

class _ClassLinkDialogState extends State<_ClassLinkDialog> {
  final _search = TextEditingController();
  late final List<String> _ids = List<String>.from(widget.selectedIds);
  late final List<String> _names = List<String>.from(widget.selectedNames);

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.text.trim().toLowerCase();
    final available = widget.classes.where((doc) {
      final data = doc.data();
      final name = data['name']?.toString().toLowerCase() ?? '';
      final section = data['section']?.toString().toLowerCase() ?? '';
      return q.isEmpty || name.contains(q) || section.contains(q);
    }).toList();
    final availablePane = Column(
      children: [
        TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Search classes'),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView.builder(
            itemCount: available.length,
            itemBuilder: (context, index) {
              final doc = available[index];
              final data = doc.data();
              final name = data['name']?.toString() ?? 'Class';
              final section = data['section']?.toString() ?? '';
              final selected = _ids.contains(doc.id);
              return ListTile(
                title: Text(name),
                subtitle: Text(section.isEmpty ? '' : 'Section: $section'),
                trailing: IconButton(
                  icon: const Icon(Icons.add_circle, color: Colors.green),
                  onPressed: selected
                      ? null
                      : () {
                          setState(() {
                            _ids.add(doc.id);
                            _names.add(name);
                          });
                        },
                ),
              );
            },
          ),
        ),
      ],
    );
    final selectedPane = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Selected classes (${_ids.length})', style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        Expanded(
          child: _ids.isEmpty
              ? const Center(child: Text('No classes selected'))
              : ListView.separated(
                  itemCount: _ids.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    return ListTile(
                      tileColor: Colors.grey.shade100,
                      title: Text(_names[index]),
                      trailing: IconButton(
                        icon: const Icon(Icons.remove_circle, color: Colors.red),
                        onPressed: () {
                          setState(() {
                            _ids.removeAt(index);
                            _names.removeAt(index);
                          });
                        },
                      ),
                    );
                  },
                ),
        ),
      ],
    );
    final isMobile = MediaQuery.of(context).size.width < AppSizes.mobileBreakpoint;

    return ResponsiveDialogShell.form(
      desktopWidth: 900,
      desktopHeight: 560,
      title: 'Select Classes',
      content: SizedBox(
        height: isMobile ? 520 : 460,
        child: isMobile
            ? Column(
                children: [
                  Expanded(child: availablePane),
                  const Divider(height: 24),
                  Expanded(child: selectedPane),
                ],
              )
            : Row(
                children: [
                  Expanded(child: availablePane),
                  const SizedBox(width: 12),
                  Expanded(child: selectedPane),
                ],
              ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            _SelectedClassesResult(ids: List<String>.from(_ids), names: List<String>.from(_names)),
          ),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
