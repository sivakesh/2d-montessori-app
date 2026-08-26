import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/responsive_dialog_shell.dart';
import '../../../admin/settings/models/academic_year_matching.dart';
import '../../../admin/settings/models/academic_year_model.dart';
import '../../../admin/settings/models/school_settings_model.dart' show kDefaultSchoolId;
import '../../../admin/settings/providers/academic_year_provider.dart';
import '../../models/fee_structure_model.dart';
import '../../models/student_fee_assignment_model.dart';
import '../../services/fee_service.dart';

class FeeAssignmentDialog extends ConsumerStatefulWidget {
  const FeeAssignmentDialog({super.key, this.assignment, this.service});

  final StudentFeeAssignmentModel? assignment;

  /// Overridable only so tests can inject a fake-Firestore-backed
  /// FeeService — the same DI seam every other injectable Admin
  /// dialog/service in this app already exposes. Production callers never
  /// pass this.
  final FeeService? service;

  @override
  ConsumerState<FeeAssignmentDialog> createState() => _FeeAssignmentDialogState();
}

/// Resolved Academic Year for the currently-selected Fee Structure —
/// [year] non-null means it resolved to a canonical [AcademicYearModel]
/// (via the structure's own `academicYearId`, or a legacy `academicYear`
/// string match); [legacyLabel] carries the stored string only when it
/// exists but matched nothing, so the unresolved message can show exactly
/// what's stored, the same way ClassFormDialog's orphaned-value message
/// does.
class _ResolvedStructureYear {
  const _ResolvedStructureYear({this.year, this.legacyLabel = ''});
  final AcademicYearModel? year;
  final String legacyLabel;
}

class _FeeAssignmentDialogState extends ConsumerState<FeeAssignmentDialog> {
  late final _service = widget.service ?? FeeService();
  final _discount = TextEditingController(text: '0');
  final _formKey = GlobalKey<FormState>();
  String _mode = 'single';
  List<dynamic> _classes = [];
  List<dynamic> _students = [];
  List<FeeStructureModel> _structures = [];
  String? _classId;
  String? _studentId;
  String? _structureId;
  bool _saving = false;
  String? _resultMessage;

  // FEES-AY-IMPLEMENT-01: the Assignment's Academic Year is no longer a
  // manually-typed field — it is always derived from the selected Fee
  // Structure (`FeeStructure.academicYearId`/`academicYear`), never
  // independently selectable here. `_academicYears` is loaded once (active
  // years only, same convention as FeeStructureDialog/ClassFormDialog) so
  // `_resolveStructureYear` can resolve the currently-selected structure's
  // year on every rebuild — recomputed, never cached, so switching the Fee
  // Structure always updates the displayed year immediately.
  bool _loadingAcademicYears = true;
  List<AcademicYearModel> _academicYears = [];

  bool get _identityLocked =>
      widget.assignment != null && widget.assignment!.paidAmount > 0;

  @override
  void initState() {
    super.initState();
    final a = widget.assignment;
    if (a != null) {
      _mode = 'single';
      _discount.text = a.discountAmount.toStringAsFixed(0);
      _classId = a.classId;
      _studentId = a.studentId;
      _structureId = a.feeStructureId;
    }
    _loadClasses();
    _loadAcademicYears();
  }

  Future<void> _loadAcademicYears() async {
    final service = ref.read(academicYearServiceProvider);
    final years = await service.getAllAcademicYears(schoolId: kDefaultSchoolId);
    if (!mounted) return;
    setState(() {
      _academicYears = years.where((y) => y.isActive).toList();
      _loadingAcademicYears = false;
    });
  }

  /// Resolves [structure]'s Academic Year — `academicYearId` first
  /// (authoritative when it resolves), falling back to matching the legacy
  /// `academicYear` string (reusing the same entity-agnostic
  /// `classMatchesAcademicYear` helper ClassFormDialog/FeeStructureDialog
  /// already use — it only ever compares a free-text string against an
  /// AcademicYearModel.name, nothing Class-specific). Returns a null
  /// [_ResolvedStructureYear.year] whenever neither resolves — including
  /// when a non-empty `academicYearId` simply doesn't match any configured
  /// year — never inventing a value.
  _ResolvedStructureYear _resolveStructureYear(FeeStructureModel structure) {
    final id = structure.academicYearId.trim();
    if (id.isNotEmpty) {
      final match = _academicYears.where((y) => y.id == id);
      if (match.isNotEmpty) return _ResolvedStructureYear(year: match.first);
      return const _ResolvedStructureYear();
    }
    final text = structure.academicYear.trim();
    if (text.isEmpty) return const _ResolvedStructureYear();
    final match = _academicYears.where(
      (y) => classMatchesAcademicYear({'academicYear': text}, y),
    );
    if (match.isNotEmpty) return _ResolvedStructureYear(year: match.first);
    return _ResolvedStructureYear(legacyLabel: text);
  }

  FeeStructureModel? get _selectedStructure {
    if (_structureId == null) return null;
    final match = _structures.where((f) => f.id == _structureId);
    return match.isEmpty ? null : match.first;
  }

  Future<void> _loadClasses() async {
    var classes = await _service.getActiveClasses();
    final a = widget.assignment;
    if (a != null && a.classId.isNotEmpty && !classes.any((c) => c.id == a.classId)) {
      final current = await _service.getClassById(a.classId);
      if (current != null) classes = [...classes, current];
    }
    if (!mounted) return;
    setState(() => _classes = classes);
    if (a != null && a.classId.isNotEmpty) {
      await _loadStudents(a.classId, preserveSelection: true);
    }
  }

  Future<void> _loadStudents(String classId, {bool preserveSelection = false}) async {
    var students = await _service.getStudentsByClassId(classId);
    final allStructures = await _service.getFeeStructures();
    final a = widget.assignment;
    if (preserveSelection && a != null && a.studentId.isNotEmpty && !students.any((s) => s.id == a.studentId)) {
      final current = await _service.getStudentById(a.studentId);
      if (current != null) students = [...students, current];
    }
    final currentStructureId = a?.feeStructureId;
    final classStructures = allStructures
        .where((s) => s.isActive || s.id == currentStructureId)
        .toList();
    if (!mounted) return;
    setState(() {
      _students = students;
      _structures = classStructures;
      if (!preserveSelection) {
        _studentId = null;
        _structureId = null;
      }
    });
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_classId == null || _structureId == null) return;
    final classDoc = _classes.firstWhere((e) => e.id == _classId);
    final classData = classDoc.data() as Map<String, dynamic>;
    final selectedFee = _selectedStructure;
    if (selectedFee == null) return;
    final resolvedYear = _resolveStructureYear(selectedFee);
    if (resolvedYear.year == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select a Fee Structure with a resolvable Academic Year before saving.'),
        ),
      );
      return;
    }
    final totalFee = selectedFee.totalAmount;
    final discountAmount = double.tryParse(_discount.text) ?? 0;
    if (discountAmount < 0 || discountAmount > totalFee) return;
    setState(() => _saving = true);
    try {
      final existingAssignment = widget.assignment;
      if (existingAssignment != null) {
        if (_studentId == null) return;
        final studentDoc = _students.firstWhere((e) => e.id == _studentId);
        final studentData = studentDoc.data() as Map<String, dynamic>;
        try {
          await _service.updateAssignment(existingAssignment.id, {
            'studentId': studentDoc.id,
            'studentName': studentData['name']?.toString() ?? '',
            'admissionNo': studentData['admissionNo']?.toString() ?? '',
            'classId': classDoc.id,
            'className': classData['name']?.toString() ?? '',
            'feeStructureId': selectedFee.id,
            'feeStructureName': selectedFee.name,
            'academicYearId': resolvedYear.year!.id,
            'academicYear': resolvedYear.year!.name,
            'totalFee': totalFee,
            'discountAmount': discountAmount,
          });
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to update assignment: $e')),
            );
          }
          return;
        }
        _resultMessage = 'Assignment updated successfully.';
      } else if (_mode == 'single') {
        if (_studentId == null) return;
        final studentDoc = _students.firstWhere((e) => e.id == _studentId);
        final studentData = studentDoc.data() as Map<String, dynamic>;
        final res = await _service.assignFee({
          'studentId': studentDoc.id,
          'studentName': studentData['name']?.toString() ?? '',
          'admissionNo': studentData['admissionNo']?.toString() ?? '',
          'classId': classDoc.id,
          'className': classData['name']?.toString() ?? '',
          'feeStructureId': selectedFee.id,
          'feeStructureName': selectedFee.name,
          'academicYearId': resolvedYear.year!.id,
          'academicYear': resolvedYear.year!.name,
          'totalFee': totalFee,
          'discountAmount': discountAmount,
          'payableAmount': totalFee - discountAmount,
          'paidAmount': 0,
          'balanceAmount': totalFee - discountAmount,
          'status': 'unpaid',
        });
        _resultMessage = res == null ? 'Assignment already exists.' : 'Student assigned successfully.';
      } else {
        final summary = await _service.bulkAssignClassFees(
          classId: classDoc.id,
          className: classData['name']?.toString() ?? '',
          feeStructureId: selectedFee.id,
          feeStructureName: selectedFee.name,
          academicYearId: resolvedYear.year!.id,
          academicYear: resolvedYear.year!.name,
          totalFee: totalFee,
          discountAmount: discountAmount,
        );
        _resultMessage = 'Assigned ${summary['assigned']} students, skipped ${summary['skipped']} duplicates.';
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_resultMessage ?? 'Saved')));
        Navigator.pop(context, true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _buildAcademicYearInfo() {
    final structure = _selectedStructure;
    if (structure == null) return const SizedBox.shrink();
    if (_loadingAcademicYears) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(),
      );
    }

    final resolved = _resolveStructureYear(structure);
    if (resolved.year != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: InputDecorator(
          decoration: const InputDecoration(labelText: 'Academic Year'),
          child: Text('${resolved.year!.name} • ${resolved.year!.isCurrent ? 'Current' : 'Historical'}'),
        ),
      );
    }

    final message = resolved.legacyLabel.isNotEmpty
        ? 'This Fee Structure\'s academic year "${resolved.legacyLabel}" does not match any '
            'configured Academic Year. Update the Fee Structure first.'
        : 'This Fee Structure has no resolvable Academic Year. Update the Fee Structure first.';
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(message, style: const TextStyle(color: Colors.orange, fontSize: 12)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.assignment != null;
    return ResponsiveDialogShell.form(
      desktopWidth: 720,
      desktopHeight: 640,
      title: isEdit ? 'Edit Assignment' : 'Assign Fee',
      content: Form(
          key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!isEdit) ...[
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'single', label: Text('Single Student')),
                      ButtonSegment(value: 'bulk', label: Text('Full Class')),
                    ],
                    selected: {_mode},
                    onSelectionChanged: (s) => setState(() {
                      _mode = s.first;
                      _studentId = null;
                      _structureId = null;
                    }),
                  ),
                  const SizedBox(height: 12),
                ],
                if (_identityLocked)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      'This assignment already has a payment recorded against it, '
                      'so the student, fee structure, and total fee cannot be changed. '
                      'Only the discount can be edited here.',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                    ),
                  ),
                DropdownButtonFormField<String>(
                  initialValue: _classId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Select Class *'),
                  items: _classes
                      .map<DropdownMenuItem<String>>(
                        (e) => DropdownMenuItem<String>(
                          value: e.id as String,
                          child: Text(e.data()['name']?.toString() ?? '', overflow: TextOverflow.ellipsis),
                        ),
                      )
                      .toList(),
                  onChanged: _identityLocked
                      ? null
                      : (v) {
                          setState(() => _classId = v);
                          if (v != null) _loadStudents(v);
                        },
                  validator: (v) => v == null ? 'Required' : null,
                ),
                if (_mode == 'single') ...[
                  DropdownButtonFormField<String>(
                    initialValue: _studentId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Select Student *'),
                    items: _students
                        .map<DropdownMenuItem<String>>(
                          (e) => DropdownMenuItem<String>(
                            value: e.id as String,
                            child: Text(e.data()['name']?.toString() ?? '', overflow: TextOverflow.ellipsis),
                          ),
                        )
                        .toList(),
                    onChanged: _identityLocked ? null : (v) => setState(() => _studentId = v),
                    validator: (v) => v == null ? 'Required' : null,
                  ),
                ],
                DropdownButtonFormField<String>(
                  initialValue: _structureId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Fee Structure *'),
                  items: _structures
                      .map<DropdownMenuItem<String>>(
                        (fee) => DropdownMenuItem<String>(
                          value: fee.id,
                          child: Text(
                            '${fee.name} - ₹${fee.totalAmount.toStringAsFixed(0)}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: _identityLocked ? null : (v) => setState(() => _structureId = v),
                  validator: (v) => v == null ? 'Required' : null,
                ),
                _buildAcademicYearInfo(),
                const SizedBox(height: 16),
                TextFormField(controller: _discount, decoration: const InputDecoration(labelText: 'Discount Amount'), keyboardType: TextInputType.number),
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
