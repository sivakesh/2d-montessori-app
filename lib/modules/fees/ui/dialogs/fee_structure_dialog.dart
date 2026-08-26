import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/responsive_dialog_shell.dart';
import '../../../admin/settings/models/academic_year_matching.dart';
import '../../../admin/settings/models/academic_year_model.dart';
import '../../../admin/settings/models/school_settings_model.dart' show kDefaultSchoolId;
import '../../../admin/settings/providers/academic_year_provider.dart';
import '../../models/fee_component_model.dart';
import '../../models/fee_structure_model.dart';
import '../../services/fee_service.dart';

class FeeStructureDialog extends ConsumerStatefulWidget {
  const FeeStructureDialog({super.key, this.structure, this.service});
  final FeeStructureModel? structure;

  /// Overridable only so tests can inject a fake-Firestore-backed
  /// FeeService — the same DI seam every other injectable Admin
  /// dialog/service in this app already exposes. Production callers never
  /// pass this.
  final FeeService? service;

  @override
  ConsumerState<FeeStructureDialog> createState() => _FeeStructureDialogState();
}

class _FeeStructureDialogState extends ConsumerState<FeeStructureDialog> {
  late final _service = widget.service ?? FeeService();
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _desc = TextEditingController();
  final List<FeeComponentModel> _components = [];
  bool _saving = false;

  // FEES-AY-IMPLEMENT-01: Academic Year is now a canonical AcademicYearModel
  // selection instead of free text — see `_loadAcademicYears`'s doc comment
  // for the load/resolve/mismatch sequence, which mirrors ClassFormDialog's
  // own (AY-IMPLEMENT-02-B) resolution exactly. Reuses the same shared
  // `classMatchesAcademicYear` helper from academic_year_matching.dart —
  // despite its name, it only ever compares a free-text `academicYear`
  // string against an AcademicYearModel.name and has nothing Class-specific
  // in its body, so it applies identically here rather than needing a
  // duplicate Fees-specific matching function.
  bool _loadingAcademicYears = true;
  List<AcademicYearModel> _academicYears = [];
  String? _academicYearId;
  String? _existingAcademicYearText;
  String? _existingAcademicYearId;
  bool _hasIdTextMismatch = false;

  bool get _hasOrphanedAcademicYear =>
      widget.structure != null &&
      _academicYearId == null &&
      (_existingAcademicYearText?.trim().isNotEmpty ?? false);

  @override
  void initState() {
    super.initState();
    final s = widget.structure;
    if (s != null) {
      _name.text = s.name;
      _desc.text = s.description;
      _components.addAll(s.components);
      _existingAcademicYearText = s.academicYear;
      _existingAcademicYearId = s.academicYearId;
    }
    _loadAcademicYears();
  }

  /// Loads every active Academic Year, then resolves this dialog's initial
  /// selection — identical resolution order to
  /// ClassFormDialog._loadAcademicYears (AY-IMPLEMENT-02-B):
  ///
  /// - Add (no existing structure): the current Academic Year, if one
  ///   exists — never invented.
  /// - Edit: (1) `academicYearId`, if it resolves, is authoritative and
  ///   preselected; (2) otherwise fall back to matching the legacy
  ///   `academicYear` string; (3) if neither resolves, no selection —
  ///   never defaulted to current.
  ///
  /// A resolved `academicYearId` whose year disagrees with the stored
  /// `academicYear` string sets [_hasIdTextMismatch] so the form can warn,
  /// without silently repairing either field — only an explicit Save
  /// writes anything.
  Future<void> _loadAcademicYears() async {
    final service = ref.read(academicYearServiceProvider);
    final years = await service.getAllAcademicYears(schoolId: kDefaultSchoolId);
    final activeYears = years.where((y) => y.isActive).toList();

    if (!mounted) return;

    String? resolvedId;
    var mismatch = false;
    if (widget.structure == null) {
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

  Future<void> _addComponent() async {
    final name = TextEditingController();
    final amount = TextEditingController();
    final term = TextEditingController();
    final dueDay = TextEditingController();
    DateTime? dueDate;
    String frequency = 'monthly';
    bool optional = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => ResponsiveDialogShell.form(
          desktopWidth: 460,
          desktopHeight: 520,
          title: 'Add Component',
          content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: name, decoration: const InputDecoration(labelText: 'Component Name *')),
                  TextField(controller: amount, decoration: const InputDecoration(labelText: 'Amount *'), keyboardType: TextInputType.number),
                  DropdownButtonFormField<String>(
                    initialValue: frequency,
                    decoration: const InputDecoration(labelText: 'Frequency *'),
                    items: const ['monthly', 'term', 'oneTime'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                    onChanged: (v) => setModalState(() => frequency = v ?? frequency),
                  ),
                  if (frequency == 'term')
                    TextField(controller: term, decoration: const InputDecoration(labelText: 'Term Name *')),
                  if (frequency == 'monthly')
                    TextField(controller: dueDay, decoration: const InputDecoration(labelText: 'Due Day of Month (optional)'), keyboardType: TextInputType.number),
                  if (frequency != 'monthly')
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(dueDate == null ? 'Optional Due Date' : dueDate!.toIso8601String().split('T').first),
                      trailing: TextButton(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                            initialDate: dueDate ?? DateTime.now(),
                          );
                          if (picked != null) setModalState(() => dueDate = picked);
                        },
                        child: const Text('Pick'),
                      ),
                    ),
                  SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Optional'), value: optional, onChanged: (v) => setModalState(() => optional = v)),
                ],
              ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (name.text.trim().isEmpty || double.tryParse(amount.text) == null || double.parse(amount.text) <= 0) return;
                if (frequency == 'term' && term.text.trim().isEmpty) return;
                Navigator.pop(context, true);
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      setState(() {
        _components.add(
          FeeComponentModel(
            name: name.text.trim(),
            amount: double.parse(amount.text),
            frequency: frequency,
            termName: frequency == 'term' ? term.text.trim() : null,
            dueDate: frequency == 'monthly' ? null : dueDate,
            dueDayOfMonth: frequency == 'monthly' ? int.tryParse(dueDay.text) : null,
            isOptional: optional,
          ),
        );
      });
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_components.isEmpty) return;
    if (_components.any((c) => c.amount <= 0)) return;
    if (_components.any((c) => c.frequency == 'term' && (c.termName ?? '').trim().isEmpty)) return;
    if (_academicYearId == null) return;
    setState(() => _saving = true);
    final total = _components.fold<double>(0, (total, c) => total + c.amount);
    final selectedYear = _academicYears.firstWhere((y) => y.id == _academicYearId);
    final data = {
      'name': _name.text.trim(),
      'description': _desc.text.trim(),
      // FEES-AY-IMPLEMENT-01: the canonical id is always written alongside
      // the legacy name string — id comes straight from the selected
      // AcademicYearModel, never derived/guessed from the name. This is the
      // only place a FeeStructure's academicYearId is ever written; nothing
      // above auto-writes it on load.
      'academicYearId': selectedYear.id,
      'academicYear': selectedYear.name,
      'components': _components.map((e) => e.toMap()).toList(),
      'totalAmount': total,
      'isActive': true,
      'createdBy': 'admin',
    };
    late final String structureId;
    if (widget.structure == null) {
      structureId = await _service.createFeeStructure(data);
    } else {
      structureId = widget.structure!.id;
      await _service.updateFeeStructure(structureId, data);
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Fee structure saved')),
    );
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveDialogShell.form(
      desktopWidth: 860,
      desktopHeight: 680,
      title: widget.structure == null ? 'Add Fee Structure' : 'Edit Fee Structure',
      content: Form(
          key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'Fee Structure Name *'), validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null),
                TextFormField(controller: _desc, decoration: const InputDecoration(labelText: 'Description')),
                _buildAcademicYearField(),
                const SizedBox(height: 12),
                const SizedBox(height: 16),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    const Text('Components'),
                    TextButton.icon(onPressed: _addComponent, icon: const Icon(Icons.add), label: const Text('Add Component')),
                  ],
                ),
                if (_components.isEmpty)
                  const Text('At least one component required')
                else
                  ..._components.map((c) => Card(
                        child: ListTile(
                          title: Text(c.name),
                          subtitle: Text('${c.frequency} • ${c.amount.toStringAsFixed(0)}${c.frequency == 'term' && (c.termName ?? '').isNotEmpty ? ' • ${c.termName}' : ''}'),
                        ),
                      )),
                const SizedBox(height: 12),
                Text('Total Amount: ${totalAmountText()}'),
              ],
            ),
          ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _saving ? null : _save, child: const Text('Save')),
      ],
    );
  }

  String totalAmountText() => _components.fold<double>(0, (t, c) => t + c.amount).toStringAsFixed(0);

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
              'This structure\'s linked Academic Year does not match its stored academic year '
              'text ("${_existingAcademicYearText!.trim()}"). The linked Academic Year is '
              'selected below — save to confirm it, or choose a different year.',
              style: const TextStyle(color: Colors.orange, fontSize: 12),
            ),
          ),
        DropdownButtonFormField<String>(
          // Recreated whenever the resolved selection changes so the
          // dropdown's internal state can never disagree with
          // `initialValue` — same fix ClassFormDialog already applies.
          key: ValueKey('fee_structure_academic_year_dropdown_${_academicYearId ?? 'none'}'),
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
