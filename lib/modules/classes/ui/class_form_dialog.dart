import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/responsive_dialog_shell.dart';
import '../../admin/settings/models/academic_year_matching.dart';
import '../../admin/settings/models/academic_year_model.dart';
import '../../admin/settings/models/school_settings_model.dart' show kDefaultSchoolId;
import '../../admin/settings/providers/academic_year_provider.dart';
import '../data/class_service.dart';

class ClassFormDialog extends ConsumerStatefulWidget {
  const ClassFormDialog({super.key, this.classId, this.initialData, this.service});

  final String? classId;
  final Map<String, dynamic>? initialData;

  /// Overridable only so tests can inject a fake-Firestore-backed
  /// ClassService — the same DI seam every other injectable Admin
  /// dialog/service in this app already exposes. Production callers never
  /// pass this.
  final ClassService? service;

  @override
  ConsumerState<ClassFormDialog> createState() => _ClassFormDialogState();
}

class _ClassFormDialogState extends ConsumerState<ClassFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _service = widget.service ?? ClassService();
  late final TextEditingController _name;
  late final TextEditingController _section;
  late final TextEditingController _capacity;
  late final TextEditingController _teacherName;
  late final TextEditingController _notes;
  bool _isActive = true;
  String _approvalStatus = 'Approved';
  bool _saving = false;

  // AY-02: Academic Year is now a canonical AcademicYearModel selection
  // instead of free text. AY-IMPLEMENT-02-B additive migration: the
  // dropdown resolution below now prefers the class's own `academicYearId`
  // (authoritative once present) and only falls back to the legacy
  // `academicYear` string match — via `classMatchesAcademicYear` — for a
  // Class that has no id yet. See `_loadAcademicYears`'s doc comment for
  // the exact resolution/mismatch sequence.
  bool _loadingAcademicYears = true;
  List<AcademicYearModel> _academicYears = [];
  String? _academicYearId;

  /// The class's own pre-existing `academicYear` string (Edit only) —
  /// kept so the orphaned-value message can show exactly what's stored
  /// when it doesn't match any configured Academic Year.
  String? _existingAcademicYearText;

  /// The class's own pre-existing `academicYearId` (Edit only, may be
  /// absent on a legacy document) — read once here and never written back
  /// except through an explicit Save, exactly like
  /// [_existingAcademicYearText].
  String? _existingAcademicYearId;

  /// True only when this Edit's `academicYearId` resolves to a configured
  /// Academic Year *and* the class's own `academicYear` string disagrees
  /// with that year's name — see [_loadAcademicYears]'s doc comment. Never
  /// auto-corrected; only ever cleared by an explicit Save.
  bool _hasIdTextMismatch = false;

  @override
  void initState() {
    super.initState();
    final data = widget.initialData ?? const {};
    _name = TextEditingController(text: data['name']?.toString() ?? '');
    _section = TextEditingController(text: data['section']?.toString() ?? '');
    _capacity = TextEditingController(text: data['capacity']?.toString() ?? '');
    _teacherName = TextEditingController(text: data['teacherName']?.toString() ?? '');
    _notes = TextEditingController(text: data['description']?.toString() ?? '');
    _isActive = data['isActive'] != false;
    _approvalStatus = data['approvalStatus']?.toString() ??
        (data['isApproved'] == true ? 'Approved' : 'Pending Approval');
    _existingAcademicYearText = data['academicYear']?.toString();
    _existingAcademicYearId = data['academicYearId']?.toString();
    _loadAcademicYears();
  }

  @override
  void dispose() {
    _name.dispose();
    _section.dispose();
    _capacity.dispose();
    _teacherName.dispose();
    _notes.dispose();
    super.dispose();
  }

  /// Loads every active Academic Year, then resolves this dialog's initial
  /// selection:
  ///
  /// - Add (no existing class): the current Academic Year, if one exists —
  ///   never invented, never hardcoded. No current year means no
  ///   preselection at all; the "Academic Year *" dropdown's own required
  ///   validator blocks Save until the admin picks one.
  /// - Edit, AY-IMPLEMENT-02-B resolution order:
  ///   1. If the class has an `academicYearId` that resolves to a
  ///      configured Academic Year, that year is authoritative and is
  ///      preselected — the legacy `academicYear` string is never
  ///      consulted for *selection* once an id resolves.
  ///   2. If the id is absent or doesn't resolve, fall back to matching
  ///      the legacy `academicYear` string via [classMatchesAcademicYear]
  ///      exactly as before AY-IMPLEMENT-02-B.
  ///   3. If neither resolves, the selection is left empty — never
  ///      defaulted to the current year — and [_hasOrphanedAcademicYear]
  ///      drives the existing "orphaned" explanatory message.
  ///   In every case, "editing a class does not automatically change its
  ///   academic year" even if a *different* year has since become current,
  ///   and nothing is written back to Firestore here — only an explicit
  ///   Save writes anything.
  ///
  /// A resolved `academicYearId` whose year's name *disagrees* with the
  /// stored `academicYear` string (both present, pointing at different
  /// years) is a real data inconsistency — see the live-data finding in
  /// AY-IMPLEMENT-02-A §11. It is never silently repaired: the id-resolved
  /// year is still what gets preselected (id is authoritative), but
  /// [_hasIdTextMismatch] is set so the form can surface a clear warning,
  /// and nothing is written until the admin explicitly saves.
  Future<void> _loadAcademicYears() async {
    final service = ref.read(academicYearServiceProvider);
    final years = await service.getAllAcademicYears(schoolId: kDefaultSchoolId);
    final activeYears = years.where((y) => y.isActive).toList();

    if (!mounted) return;

    String? resolvedId;
    var mismatch = false;
    if (widget.classId == null) {
      final current = activeYears.where((y) => y.isCurrent);
      if (current.isNotEmpty) resolvedId = current.first.id;
    } else {
      final existingId = _existingAcademicYearId;
      final existingText = _existingAcademicYearText;

      AcademicYearModel? byId;
      if (existingId != null && existingId.trim().isNotEmpty) {
        final match = activeYears.where((y) => y.id == existingId.trim());
        if (match.isNotEmpty) byId = match.first;
      }

      if (byId != null) {
        resolvedId = byId.id;
        if (existingText != null &&
            existingText.trim().isNotEmpty &&
            !classMatchesAcademicYear({'academicYear': existingText}, byId)) {
          mismatch = true;
        }
      } else if (existingText != null && existingText.trim().isNotEmpty) {
        final match = activeYears.where(
          (y) => classMatchesAcademicYear({'academicYear': existingText}, y),
        );
        if (match.isNotEmpty) resolvedId = match.first.id;
      }
    }

    setState(() {
      _academicYears = activeYears;
      _academicYearId = resolvedId;
      _hasIdTextMismatch = mismatch;
      _loadingAcademicYears = false;
    });
  }

  /// True when this is an Edit of an existing class whose stored
  /// `academicYear` text is non-empty but matches no currently-configured
  /// Academic Year — never silently substituted with the current year or
  /// left ambiguous; the dropdown shows this explanatory state instead.
  bool get _hasOrphanedAcademicYear =>
      widget.classId != null &&
      _academicYearId == null &&
      (_existingAcademicYearText?.trim().isNotEmpty ?? false);

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final selectedYear = _academicYears.firstWhere((y) => y.id == _academicYearId);
      final payload = {
        'name': _name.text.trim(),
        'section': _section.text.trim(),
        // AY-IMPLEMENT-02-B: the canonical id is always written alongside
        // the legacy name string — id comes straight from the selected
        // AcademicYearModel, never derived/guessed from the name — so any
        // explicit save (including one that resolves an orphaned or
        // mismatched value) upgrades the Class to the canonical
        // relationship. This is the *only* place a Class's academicYearId
        // is ever written; nothing above auto-writes it on load.
        'academicYearId': selectedYear.id,
        'academicYear': selectedYear.name,
        'capacity': _capacity.text.trim().isEmpty ? null : int.parse(_capacity.text.trim()),
        'teacherName': _teacherName.text.trim(),
        'description': _notes.text.trim(),
        'isActive': _isActive,
        'approvalStatus': _approvalStatus,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (widget.classId == null) {
        payload['createdAt'] = FieldValue.serverTimestamp();
        payload['createdBy'] = 'admin';
        await _service.createClass(payload);
      } else {
        await _service.updateClass(classId: widget.classId!, data: payload);
      }
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.classId == null ? 'Class created' : 'Class updated')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save class: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveDialogShell.form(
      desktopWidth: 600,
      desktopHeight: 620,
      title: widget.classId == null ? 'Add Class' : 'Edit Class',
      content: Form(
          key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Class Name *'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                TextFormField(controller: _section, decoration: const InputDecoration(labelText: 'Section')),
                _buildAcademicYearField(),
                TextFormField(
                  controller: _capacity,
                  decoration: const InputDecoration(labelText: 'Capacity'),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return null;
                    return int.tryParse(v.trim()) == null ? 'Enter a valid number' : null;
                  },
                ),
                TextFormField(controller: _teacherName, decoration: const InputDecoration(labelText: 'Class Teacher / Staff in charge')),
                TextFormField(
                  controller: _notes,
                  decoration: const InputDecoration(labelText: 'Description / Notes'),
                  maxLines: 3,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Active'),
                  value: _isActive,
                  onChanged: (value) => setState(() => _isActive = value),
                ),
                DropdownButtonFormField<String>(
                  initialValue: _approvalStatus,
                  decoration: const InputDecoration(labelText: 'Approval Status'),
                  items: const [
                    DropdownMenuItem(value: 'Approved', child: Text('Approved')),
                    DropdownMenuItem(value: 'Pending Approval', child: Text('Pending Approval')),
                    DropdownMenuItem(value: 'Rejected', child: Text('Rejected')),
                  ],
                  onChanged: (value) => setState(() => _approvalStatus = value ?? 'Approved'),
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

  Widget _buildAcademicYearField() {
    if (_loadingAcademicYears) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: LinearProgressIndicator(),
      );
    }

    if (_academicYears.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'No academic years configured. Set one up in Settings -> Academic Year first.',
          style: TextStyle(color: Colors.red, fontSize: 12),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_hasOrphanedAcademicYear)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              'Stored academic year "${_existingAcademicYearText!.trim()}" does not match any '
              'configured Academic Year. Select one below to continue.',
              style: const TextStyle(color: Colors.orange, fontSize: 12),
            ),
          ),
        if (_hasIdTextMismatch)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              'This class\'s linked Academic Year does not match its stored academic year '
              'text ("${_existingAcademicYearText!.trim()}"). The linked Academic Year is '
              'selected below — save to confirm it, or choose a different year.',
              style: const TextStyle(color: Colors.orange, fontSize: 12),
            ),
          ),
        DropdownButtonFormField<String>(
          // Recreated whenever the resolved selection changes so the
          // dropdown's internal state can never disagree with
          // `initialValue` — the same fix AY-01-R1 applied to the Class
          // dropdown in the Student form for this identical
          // DropdownButtonFormField limitation.
          key: ValueKey('academic_year_dropdown_${_academicYearId ?? 'none'}'),
          initialValue: _academicYearId,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Academic Year *'),
          items: [
            for (final year in _academicYears)
              DropdownMenuItem(
                value: year.id,
                child: Text(
                  '${year.name} • ${year.isCurrent ? 'Current' : 'Historical'}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (value) => setState(() => _academicYearId = value),
          validator: (value) => value == null || value.isEmpty ? 'Required' : null,
        ),
      ],
    );
  }
}
