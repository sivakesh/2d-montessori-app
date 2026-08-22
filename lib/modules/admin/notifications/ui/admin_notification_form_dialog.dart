import 'package:file_picker/file_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../../../core/theme/app_sizes.dart';
import '../../../../core/widgets/responsive_dialog_shell.dart';
import '../data/admin_notification_service.dart';
import '../models/admin_notification_model.dart';

class AdminNotificationFormDialog extends StatefulWidget {
  const AdminNotificationFormDialog({super.key, this.document});
  final AdminNotificationModel? document;
  @override
  State<AdminNotificationFormDialog> createState() => _AdminNotificationFormDialogState();
}

class _AdminNotificationFormDialogState extends State<AdminNotificationFormDialog> {
  final _service = AdminNotificationService();
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _message = TextEditingController();
  final _academicYear = TextEditingController();
  final _tags = TextEditingController();
  String _notificationType = 'General Announcement';
  String _category = 'General';
  String _priority = 'Normal';
  String _audience = 'Parents';
  String _visibility = 'Parents';
  String _status = 'Draft';
  bool _isPinned = false;
  bool _requiresAck = false;
  bool _saving = false;
  DateTime? _publishDate;
  DateTime? _expiryDate;
  PlatformFile? _attachment;
  String _targetMode = 'allClasses';
  bool _appliesToAllClasses = true;
  bool _appliesToAllStudents = false;
  bool _appliesToAllStaff = false;
  bool _isPublic = false;
  List<String> _applicableClassIds = [];
  List<String> _applicableClassNames = [];
  List<String> _applicableStudentIds = [];
  List<String> _applicableStudentNames = [];
  List<String> _applicableStaffIds = [];
  List<String> _applicableStaffNames = [];
  List<dynamic> _classes = [];
  List<dynamic> _students = [];
  List<dynamic> _staff = [];

  static const _types = ['General Announcement','Circular','Reminder','Emergency Alert','Event Notice','Fee Reminder','Holiday Notice','Academic Notice','Attendance Notice','Exam Notice','Health & Safety','Transport Notice','Parent Meeting','Staff Notice','Public Notice','Other'];
  static const _cats = ['Academic','Administration','Admission','Finance','HR/Staff','Parent Communication','Compliance','Safety','Events','General'];
  static const _audiences = ['Parents','Staff','Public','Admin Only'];
  static const _statuses = ['Draft','Scheduled','Published','Archived','Expired'];
  static const _visibilities = ['Admin Only','Staff','Parents','Public'];
  static const _priorities = ['Low','Normal','High','Urgent'];
  @override
  void initState() {
    super.initState();
    _loadTargets();
    final d = widget.document;
    if (d != null) {
      _title.text = d.title;
      _message.text = d.message;
      _notificationType = d.notificationType;
      _category = d.category;
      _priority = d.priority;
      _audience = d.audience;
      _visibility = d.visibility;
      _status = d.status;
      _academicYear.text = d.academicYear;
      _publishDate = d.publishDate;
      _expiryDate = d.expiryDate;
      _isPinned = d.isPinned;
      _requiresAck = d.requiresAcknowledgement;
      _applicableClassIds = d.applicableClassIds;
      _applicableClassNames = d.applicableClassNames;
      _applicableStudentIds = d.applicableStudentIds;
      _applicableStudentNames = d.applicableStudentNames;
      _applicableStaffIds = d.applicableStaffIds;
      _applicableStaffNames = d.applicableStaffNames;
      _appliesToAllClasses = d.appliesToAllClasses;
      _appliesToAllStudents = d.appliesToAllStudents;
      _appliesToAllStaff = d.appliesToAllStaff;
      _isPublic = d.isPublic;
      _targetMode = d.appliesToAllClasses ? 'allClasses' : d.appliesToAllStudents ? 'selectedStudents' : d.appliesToAllStaff ? 'selectedStaff' : 'selectedClasses';
    } else if (_academicYear.text.trim().isEmpty) {
      _academicYear.text = '2026-2027';
    }
  }

  Future<void> _loadTargets() async {
    final classes = await _service.getActiveClasses();
    final students = await _service.getActiveStudents();
    final staff = await _service.getStaffUsers();
    if (!mounted) return;
    setState(() {
      _classes = classes;
      _students = students;
      _staff = staff;
    });
  }

  @override
  void dispose() {
    _title.dispose();
    _message.dispose();
    _academicYear.dispose();
    _tags.dispose();
    super.dispose();
  }

  Future<void> _pickAttachment() async {
    final f = await _service.pickAttachment();
    if (f != null && mounted) setState(() => _attachment = f);
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  String? get _summaryText {
    if (_audience == 'Public') {
      return 'Public notification';
    }
    if (_audience == 'Admin Only') {
      return 'Admin only notification';
    }
    if (_audience == 'Parents') {
      if (_targetMode == 'allClasses') return 'All Classes';
      if (_targetMode == 'selectedClasses') {
        return '${_applicableClassNames.length} selected classes${_applicableClassNames.isNotEmpty ? ': ${_applicableClassNames.join(', ')}' : ''}';
      }
      if (_targetMode == 'selectedStudents') {
        return '${_applicableStudentNames.length} selected students${_applicableStudentNames.isNotEmpty ? ': ${_applicableStudentNames.join(', ')}' : ''}';
      }
    }
    if (_audience == 'Staff') {
      if (_targetMode == 'allStaff') return 'All Staff';
      if (_targetMode == 'selectedStaff') {
        return '${_applicableStaffNames.length} selected staff${_applicableStaffNames.isNotEmpty ? ': ${_applicableStaffNames.join(', ')}' : ''}';
      }
    }
    return null;
  }

  void _setParentsAllClasses() {
    setState(() {
      _audience = 'Parents';
      _targetMode = 'allClasses';
      _appliesToAllClasses = true;
      _appliesToAllStudents = false;
      _appliesToAllStaff = false;
      _isPublic = false;
      _visibility = 'Parents';
      _applicableClassIds = [];
      _applicableClassNames = [];
      _applicableStudentIds = [];
      _applicableStudentNames = [];
      _applicableStaffIds = [];
      _applicableStaffNames = [];
    });
  }

  void _setParentsSelectedClasses() {
    setState(() {
      _audience = 'Parents';
      _targetMode = 'selectedClasses';
      _appliesToAllClasses = false;
      _appliesToAllStudents = false;
      _appliesToAllStaff = false;
      _isPublic = false;
      _visibility = 'Parents';
      _applicableStudentIds = [];
      _applicableStudentNames = [];
      _applicableStaffIds = [];
      _applicableStaffNames = [];
    });
  }

  void _setParentsSelectedStudents() {
    setState(() {
      _audience = 'Parents';
      _targetMode = 'selectedStudents';
      _appliesToAllClasses = false;
      _appliesToAllStudents = false;
      _appliesToAllStaff = false;
      _isPublic = false;
      _visibility = 'Parents';
      _applicableStaffIds = [];
      _applicableStaffNames = [];
    });
  }

  void _setStaffAll() {
    setState(() {
      _audience = 'Staff';
      _targetMode = 'allStaff';
      _appliesToAllClasses = false;
      _appliesToAllStudents = false;
      _appliesToAllStaff = true;
      _isPublic = false;
      _visibility = 'Staff';
      _applicableClassIds = [];
      _applicableClassNames = [];
      _applicableStudentIds = [];
      _applicableStudentNames = [];
      _applicableStaffIds = [];
      _applicableStaffNames = [];
    });
  }

  void _setStaffSelected() {
    setState(() {
      _audience = 'Staff';
      _targetMode = 'selectedStaff';
      _appliesToAllClasses = false;
      _appliesToAllStudents = false;
      _appliesToAllStaff = false;
      _isPublic = false;
      _visibility = 'Staff';
      _applicableClassIds = [];
      _applicableClassNames = [];
      _applicableStudentIds = [];
      _applicableStudentNames = [];
    });
  }

  void _setPublic() {
    setState(() {
      _audience = 'Public';
      _targetMode = 'public';
      _isPublic = true;
      _appliesToAllClasses = false;
      _appliesToAllStudents = false;
      _appliesToAllStaff = false;
      _applicableClassIds = [];
      _applicableClassNames = [];
      _applicableStudentIds = [];
      _applicableStudentNames = [];
      _applicableStaffIds = [];
      _applicableStaffNames = [];
    });
  }

  void _setAdminOnly() {
    setState(() {
      _audience = 'Admin Only';
      _targetMode = 'adminOnly';
      _isPublic = false;
      _visibility = 'Admin Only';
      _appliesToAllClasses = false;
      _appliesToAllStudents = false;
      _appliesToAllStaff = false;
      _applicableClassIds = [];
      _applicableClassNames = [];
      _applicableStudentIds = [];
      _applicableStudentNames = [];
      _applicableStaffIds = [];
      _applicableStaffNames = [];
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    debugPrint('Saving notification...');
    debugPrint('audience: $_audience');
    debugPrint('type: $_notificationType');
    debugPrint('category: $_category');
    debugPrint('priority: $_priority');
    debugPrint('status: $_status');
    debugPrint('targetMode=$_targetMode');
    debugPrint('classIds=$_applicableClassIds');
    debugPrint('studentIds=$_applicableStudentIds');
    debugPrint('staffIds=$_applicableStaffIds');
    debugPrint('Form state exists: ${_formKey.currentState != null}');
    if (!(_formKey.currentState?.validate() ?? false)) return;

    if (_title.text.trim().isEmpty) {
      _showError('Please enter a title.');
      return;
    }
    if (_message.text.trim().isEmpty) {
      _showError('Please enter a message.');
      return;
    }
    if (_notificationType.trim().isEmpty) {
      _showError('Please select notification type.');
      return;
    }
    if (_category.trim().isEmpty) {
      _showError('Please select category.');
      return;
    }
    if (_audience.trim().isEmpty) {
      _showError('Please select audience.');
      return;
    }
    if (_priority.trim().isEmpty) {
      _showError('Please select priority.');
      return;
    }
    if (_academicYear.text.trim().isEmpty) {
      _showError('Please enter academic year.');
      return;
    }
    if (_status == 'Scheduled' && _publishDate == null) {
      _showError('Scheduled notifications require a publish date.');
      return;
    }
    if (_publishDate != null && _expiryDate != null && _expiryDate!.isBefore(_publishDate!)) {
      _showError('Expiry date cannot be before publish date.');
      return;
    }

    if (_audience == 'Parents') {
      if (_targetMode == 'selectedClasses' && _applicableClassIds.isEmpty) {
        _showError('Please select at least one class.');
        return;
      }
      if (_targetMode == 'selectedStudents' && _applicableStudentIds.isEmpty) {
        _showError('Please select at least one student.');
        return;
      }
    }
    if (_audience == 'Staff' && _targetMode == 'selectedStaff' && _applicableStaffIds.isEmpty) {
      _showError('Please select at least one staff member.');
      return;
    }

    final currentUser = FirebaseAuth.instance.currentUser;
    final currentUserId = currentUser?.uid ?? widget.document?.createdBy ?? 'system';
    final currentUserName = currentUser?.displayName ?? currentUser?.email ?? widget.document?.createdByName ?? 'Admin';

    setState(() => _saving = true);
    try {
      final d = widget.document;
      debugPrint('Validation passed');
      final baseData = {
        'title': _title.text.trim(),
        'message': _message.text.trim(),
        'notificationType': _notificationType,
        'category': _category,
        'priority': _priority,
        'audience': _audience,
        'visibility': _visibility,
        'status': _status,
        'academicYear': _academicYear.text.trim(),
        'publishDate': _publishDate,
        'expiryDate': _expiryDate,
        'createdBy': currentUserId,
        'createdByName': currentUserName,
        'createdAt': d?.createdAt ?? DateTime.now(),
        'updatedAt': DateTime.now(),
        'isPinned': _isPinned,
        'requiresAcknowledgement': _requiresAck,
        'attachmentName': d?.attachmentName ?? '',
        'attachmentUrl': d?.attachmentUrl ?? '',
        'attachmentSize': d?.attachmentSize,
        'attachmentMimeType': d?.attachmentMimeType ?? '',
        'targetMode': _targetMode,
        'appliesToAllClasses': _appliesToAllClasses,
        'applicableClassIds': _applicableClassIds,
        'applicableClassNames': _applicableClassNames,
        'appliesToAllStudents': _appliesToAllStudents,
        'applicableStudentIds': _applicableStudentIds,
        'applicableStudentNames': _applicableStudentNames,
        'appliesToAllStaff': _appliesToAllStaff,
        'applicableStaffIds': _applicableStaffIds,
        'applicableStaffNames': _applicableStaffNames,
        'isPublic': _isPublic,
      };

      final payload = Map<String, dynamic>.from(baseData)
        ..['publishDate'] = _publishDate != null ? Timestamp.fromDate(_publishDate!) : null
        ..['expiryDate'] = _expiryDate != null ? Timestamp.fromDate(_expiryDate!) : null;
      debugPrint('Notification payload: $payload');
      debugPrint('Calling create notification');

      late final String id;
      if (d == null) {
        debugPrint('Creating notification...');
        id = await _service.createNotification(payload);
        debugPrint('Created notification id: $id');
      } else {
        debugPrint('Updating notification: ${d.id}');
        id = d.id;
        await _service.updateNotification(id, payload);
        debugPrint('Updated notification id: $id');
      }

      if (_attachment != null) {
        debugPrint('Uploading attachment for notification: $id');
        final uploaded = await _service.uploadAttachment(notificationId: id, file: _attachment!);
        if (uploaded != null) {
          debugPrint('Attachment uploaded: $uploaded');
          await _service.updateNotification(id, {
            'attachmentName': uploaded['attachmentName']?.toString() ?? '',
            'attachmentUrl': uploaded['attachmentUrl']?.toString() ?? '',
            'attachmentSize': uploaded['attachmentSize'],
            'attachmentMimeType': uploaded['attachmentMimeType']?.toString() ?? '',
          });
          debugPrint('Attachment metadata saved');
        }
      }
      debugPrint('Notification saved successfully: $id');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(d == null ? 'Notification created' : 'Notification updated')),
      );
      debugPrint('Dialog closing');
      Navigator.of(context).pop(true);
    } catch (e, st) {
      debugPrint('Notification save failed: $e');
      debugPrint('$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveDialogShell.form(
      desktopWidth: 860,
      desktopHeight: 680,
      title: widget.document == null ? 'Add Notification' : 'Edit Notification',
      content: Form(
          key: _formKey,
          child: ListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              TextFormField(controller: _title, decoration: const InputDecoration(labelText: 'Title *'), validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null),
              TextFormField(controller: _message, decoration: const InputDecoration(labelText: 'Message *'), maxLines: 4, validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null),
              DropdownButtonFormField<String>(initialValue: _notificationType, items: _types.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: (v) => setState(() => _notificationType = v ?? _notificationType), decoration: const InputDecoration(labelText: 'Notification Type *')),
              DropdownButtonFormField<String>(initialValue: _category, items: _cats.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: (v) => setState(() => _category = v ?? _category), decoration: const InputDecoration(labelText: 'Category *')),
              DropdownButtonFormField<String>(initialValue: _priority, items: _priorities.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: (v) => setState(() => _priority = v ?? _priority), decoration: const InputDecoration(labelText: 'Priority *')),
              DropdownButtonFormField<String>(initialValue: _status, items: _statuses.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: (v) => setState(() => _status = v ?? _status), decoration: const InputDecoration(labelText: 'Status *')),
              DropdownButtonFormField<String>(
                initialValue: _audience,
                items: _audiences.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                onChanged: (v) {
                  final value = v ?? _audience;
                  if (value == 'Parents') {
                    _setParentsAllClasses();
                  } else if (value == 'Staff') {
                    _setStaffAll();
                  } else if (value == 'Public') {
                    _setPublic();
                  } else if (value == 'Admin Only') {
                    _setAdminOnly();
                  } else {
                    setState(() => _audience = value);
                  }
                },
                decoration: const InputDecoration(labelText: 'Audience *'),
              ),
              DropdownButtonFormField<String>(initialValue: _visibility, items: _visibilities.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: (v) => setState(() => _visibility = v ?? _visibility), decoration: const InputDecoration(labelText: 'Visibility *')),
              TextFormField(controller: _academicYear, decoration: const InputDecoration(labelText: 'Academic Year *'), validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null),
              Row(children: [Expanded(child: TextButton(onPressed: () async { final d = await showDatePicker(context: context, firstDate: DateTime(2000), lastDate: DateTime(2100), initialDate: _publishDate ?? DateTime.now()); if (d != null) setState(() => _publishDate = d); }, child: Text(_publishDate == null ? 'Publish Date' : _publishDate!.toIso8601String().split('T').first))), const SizedBox(width: 8), Expanded(child: TextButton(onPressed: () async { final d = await showDatePicker(context: context, firstDate: DateTime(2000), lastDate: DateTime(2100), initialDate: _expiryDate ?? DateTime.now()); if (d != null) setState(() => _expiryDate = d); }, child: Text(_expiryDate == null ? 'Expiry Date' : _expiryDate!.toIso8601String().split('T').first)))]),
              SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Pinned'), value: _isPinned, onChanged: (v) => setState(() => _isPinned = v)),
              SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Requires Acknowledgement'), value: _requiresAck, onChanged: (v) => setState(() => _requiresAck = v)),
              const SizedBox(height: 8),
              Text('Targeting', style: Theme.of(context).textTheme.titleMedium),
              if (_summaryText != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Chip(label: Text(_summaryText!)),
                ),
              if (_audience == 'Parents') ...[
                RadioListTile(value: 'allClasses', groupValue: _targetMode, title: const Text('All Classes'), onChanged: (v) => _setParentsAllClasses()),
                RadioListTile(value: 'selectedClasses', groupValue: _targetMode, title: const Text('Selected Classes'), onChanged: (v) async {
                  _setParentsSelectedClasses();
                  final res = await showDialog<_LinkResult>(context: context, builder: (_) => _ClassLinkDialog(classes: _classes, selectedIds: _applicableClassIds, selectedNames: _applicableClassNames));
                  debugPrint('Class dialog result ids: ${res?.ids}');
                  debugPrint('Class dialog result names: ${res?.names}');
                  if (res != null && mounted) {
                    setState(() {
                      _targetMode = 'selectedClasses';
                      _applicableClassIds = res.ids;
                      _applicableClassNames = res.names;
                      _appliesToAllClasses = false;
                      _appliesToAllStudents = false;
                      _applicableStudentIds = [];
                      _applicableStudentNames = [];
                    });
                  }
                }),
                RadioListTile(value: 'selectedStudents', groupValue: _targetMode, title: const Text('Selected Students'), onChanged: (v) async {
                  _setParentsSelectedStudents();
                  final res = await showDialog<_LinkResult>(context: context, builder: (_) => _StudentLinkDialog(students: _students, selectedIds: _applicableStudentIds, selectedNames: _applicableStudentNames));
                  debugPrint('Student dialog result ids: ${res?.ids}');
                  debugPrint('Student dialog result names: ${res?.names}');
                  if (res != null && mounted) {
                    setState(() {
                      _targetMode = 'selectedStudents';
                      _applicableStudentIds = res.ids;
                      _applicableStudentNames = res.names;
                      _appliesToAllClasses = false;
                      _appliesToAllStudents = false;
                      _applicableClassIds = [];
                      _applicableClassNames = [];
                    });
                  }
                }),
                if (_targetMode == 'selectedClasses')
                  TextButton.icon(
                    onPressed: () async {
                      final res = await showDialog<_LinkResult>(
                        context: context,
                        builder: (_) => _ClassLinkDialog(classes: _classes, selectedIds: _applicableClassIds, selectedNames: _applicableClassNames),
                      );
                      debugPrint('Class dialog result ids: ${res?.ids}');
                      debugPrint('Class dialog result names: ${res?.names}');
                      if (res != null && mounted) {
                        setState(() {
                          _targetMode = 'selectedClasses';
                          _applicableClassIds = List<String>.from(res.ids);
                          _applicableClassNames = List<String>.from(res.names);
                          _appliesToAllClasses = false;
                          _appliesToAllStudents = false;
                          _applicableStudentIds = [];
                          _applicableStudentNames = [];
                        });
                      }
                    },
                    icon: const Icon(Icons.link),
                    label: const Text('Select Classes'),
                  ),
                if (_targetMode == 'selectedStudents')
                  TextButton.icon(
                    onPressed: () async {
                      final res = await showDialog<_LinkResult>(
                        context: context,
                        builder: (_) => _StudentLinkDialog(students: _students, selectedIds: _applicableStudentIds, selectedNames: _applicableStudentNames),
                      );
                      debugPrint('Student dialog result ids: ${res?.ids}');
                      debugPrint('Student dialog result names: ${res?.names}');
                      if (res != null && mounted) {
                        setState(() {
                          _targetMode = 'selectedStudents';
                          _applicableStudentIds = List<String>.from(res.ids);
                          _applicableStudentNames = List<String>.from(res.names);
                          _appliesToAllClasses = false;
                          _appliesToAllStudents = false;
                          _applicableClassIds = [];
                          _applicableClassNames = [];
                        });
                      }
                    },
                    icon: const Icon(Icons.link),
                    label: const Text('Select Students'),
                  ),
              ] else if (_audience == 'Staff') ...[
                RadioListTile(value: 'allStaff', groupValue: _targetMode, title: const Text('All Staff'), onChanged: (v) => _setStaffAll()),
                RadioListTile(value: 'selectedStaff', groupValue: _targetMode, title: const Text('Selected Staff'), onChanged: (v) async {
                  _setStaffSelected();
                  final res = await showDialog<_LinkResult>(context: context, builder: (_) => _StaffLinkDialog(staff: _staff, selectedIds: _applicableStaffIds, selectedNames: _applicableStaffNames));
                  debugPrint('Staff dialog result ids: ${res?.ids}');
                  debugPrint('Staff dialog result names: ${res?.names}');
                  if (res != null && mounted) {
                    setState(() {
                      _targetMode = 'selectedStaff';
                      _applicableStaffIds = res.ids;
                      _applicableStaffNames = res.names;
                      _appliesToAllStaff = false;
                    });
                  }
                }),
                if (_targetMode == 'selectedStaff')
                  TextButton.icon(
                    onPressed: () async {
                      final res = await showDialog<_LinkResult>(
                        context: context,
                        builder: (_) => _StaffLinkDialog(staff: _staff, selectedIds: _applicableStaffIds, selectedNames: _applicableStaffNames),
                      );
                      debugPrint('Staff dialog result ids: ${res?.ids}');
                      debugPrint('Staff dialog result names: ${res?.names}');
                      if (res != null && mounted) {
                        setState(() {
                          _targetMode = 'selectedStaff';
                          _applicableStaffIds = List<String>.from(res.ids);
                          _applicableStaffNames = List<String>.from(res.names);
                          _appliesToAllStaff = false;
                        });
                      }
                    },
                    icon: const Icon(Icons.link),
                    label: const Text('Select Staff'),
                  ),
              ] else if (_audience == 'Public')
                const Chip(label: Text('Public notification, no internal targeting'))
              else if (_audience == 'Admin Only')
                const Chip(label: Text('Admin only notification')),
              if (_attachment != null)
                ListTile(
                  leading: const Icon(Icons.attach_file),
                  title: Text(_attachment!.name),
                ),
              TextButton(onPressed: _pickAttachment, child: const Text('Upload Attachment')),
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

class _LinkResult {
  _LinkResult({required this.ids, required this.names});
  final List<String> ids;
  final List<String> names;
}

class _ClassLinkDialog extends StatefulWidget {
  const _ClassLinkDialog({required this.classes, required this.selectedIds, required this.selectedNames});
  final List<dynamic> classes;
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
  void dispose() { _search.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final q = _search.text.trim().toLowerCase();
    final available = widget.classes.where((d) {
      final data = d.data() as Map<String, dynamic>;
      final name = data['name']?.toString().toLowerCase() ?? '';
      final section = data['section']?.toString().toLowerCase() ?? '';
      return q.isEmpty || name.contains(q) || section.contains(q);
    }).toList();
    return _buildLinkDialog(
      title: 'Select Classes',
      searchHint: 'Search classes',
      search: _search,
      available: available,
      selectedIds: _ids,
      selectedNames: _names,
      onAdd: (id, name) { if (!_ids.contains(id)) setState(() { _ids.add(id); _names.add(name); }); },
      onRemove: (index) => setState(() { _ids.removeAt(index); _names.removeAt(index); }),
      itemSubtitle: (data) => data['section']?.toString() ?? '',
    );
  }
}

class _StudentLinkDialog extends StatefulWidget {
  const _StudentLinkDialog({required this.students, required this.selectedIds, required this.selectedNames});
  final List<dynamic> students;
  final List<String> selectedIds;
  final List<String> selectedNames;
  @override
  State<_StudentLinkDialog> createState() => _StudentLinkDialogState();
}

class _StudentLinkDialogState extends State<_StudentLinkDialog> {
  final _search = TextEditingController();
  late final List<String> _ids = List<String>.from(widget.selectedIds);
  late final List<String> _names = List<String>.from(widget.selectedNames);
  @override
  void dispose() { _search.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final q = _search.text.trim().toLowerCase();
    final available = widget.students.where((d) {
      final data = d.data() as Map<String, dynamic>;
      final name = data['name']?.toString().toLowerCase() ?? '';
      final admission = data['admissionNo']?.toString().toLowerCase() ?? '';
      final classId = data['classId']?.toString().toLowerCase() ?? '';
      return q.isEmpty || name.contains(q) || admission.contains(q) || classId.contains(q);
    }).toList();
    return _buildLinkDialog(
      title: 'Select Students',
      searchHint: 'Search students',
      search: _search,
      available: available,
      selectedIds: _ids,
      selectedNames: _names,
      onAdd: (id, name) { if (!_ids.contains(id)) setState(() { _ids.add(id); _names.add(name); }); },
      onRemove: (index) => setState(() { _ids.removeAt(index); _names.removeAt(index); }),
      itemSubtitle: (data) => 'Admission: ${data['admissionNo']?.toString() ?? '-'}',
    );
  }
}

class _StaffLinkDialog extends StatefulWidget {
  const _StaffLinkDialog({required this.staff, required this.selectedIds, required this.selectedNames});
  final List<dynamic> staff;
  final List<String> selectedIds;
  final List<String> selectedNames;
  @override
  State<_StaffLinkDialog> createState() => _StaffLinkDialogState();
}

class _StaffLinkDialogState extends State<_StaffLinkDialog> {
  final _search = TextEditingController();
  late final List<String> _ids = List<String>.from(widget.selectedIds);
  late final List<String> _names = List<String>.from(widget.selectedNames);
  @override
  void dispose() { _search.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final q = _search.text.trim().toLowerCase();
    final available = widget.staff.where((d) {
      final data = d.data() as Map<String, dynamic>;
      final name = data['name']?.toString().toLowerCase() ?? '';
      final email = data['email']?.toString().toLowerCase() ?? '';
      return q.isEmpty || name.contains(q) || email.contains(q);
    }).toList();
    return _buildLinkDialog(
      title: 'Select Staff',
      searchHint: 'Search staff',
      search: _search,
      available: available,
      selectedIds: _ids,
      selectedNames: _names,
      onAdd: (id, name) { if (!_ids.contains(id)) setState(() { _ids.add(id); _names.add(name); }); },
      onRemove: (index) => setState(() { _ids.removeAt(index); _names.removeAt(index); }),
      itemSubtitle: (data) => data['email']?.toString() ?? '',
    );
  }
}

Widget _buildLinkDialog({
  required String title,
  required String searchHint,
  required TextEditingController search,
  required List<dynamic> available,
  required List<String> selectedIds,
  required List<String> selectedNames,
  required void Function(String id, String name) onAdd,
  required void Function(int index) onRemove,
  required String Function(Map<String, dynamic> data) itemSubtitle,
}) {
  return StatefulBuilder(
    builder: (context, setState) {
      final availablePane = Column(
        children: [
          TextField(controller: search, onChanged: (_) => setState(() {}), decoration: InputDecoration(prefixIcon: const Icon(Icons.search), labelText: searchHint)),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.builder(
              itemCount: available.length,
              itemBuilder: (context, index) {
                final doc = available[index];
                final data = doc.data() as Map<String, dynamic>;
                final id = doc.id as String;
                final name = data['name']?.toString() ?? 'Item';
                if (selectedIds.contains(id)) return const SizedBox.shrink();
                return ListTile(
                  title: Text(name),
                  subtitle: Text(itemSubtitle(data)),
                  trailing: IconButton(
                    icon: const Icon(Icons.add_circle, color: Colors.green),
                    onPressed: () => onAdd(id, name),
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
          Text('Selected (${selectedIds.length})', style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Expanded(
            child: selectedIds.isEmpty
                ? const Center(child: Text('None selected'))
                : ListView.separated(
                    itemCount: selectedIds.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) => ListTile(
                      tileColor: Colors.grey.shade100,
                      title: Text(selectedNames[index]),
                      trailing: IconButton(icon: const Icon(Icons.remove_circle, color: Colors.red), onPressed: () => onRemove(index)),
                    ),
                  ),
          ),
        ],
      );
      final isMobile = MediaQuery.of(context).size.width < AppSizes.mobileBreakpoint;

      return ResponsiveDialogShell.form(
        desktopWidth: 900,
        desktopHeight: 560,
        title: title,
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
          TextButton(
            onPressed: () {
              debugPrint('Returning selected ids: $selectedIds');
              debugPrint('Returning selected names: $selectedNames');
              Navigator.pop(
                context,
                _LinkResult(
                  ids: List<String>.from(selectedIds),
                  names: List<String>.from(selectedNames),
                ),
              );
            },
            child: const Text('Done'),
          ),
        ],
      );
    },
  );
}
