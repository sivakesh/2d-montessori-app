import 'package:flutter/material.dart';

import '../../../../core/widgets/responsive_dialog_shell.dart';
import '../../models/fee_structure_model.dart';
import '../../models/student_fee_assignment_model.dart';
import '../../services/fee_service.dart';

class FeeAssignmentDialog extends StatefulWidget {
  const FeeAssignmentDialog({super.key, this.assignment});

  /// Non-null to edit this existing assignment instead of creating a new
  /// one. Same optional-parameter/branch-on-null pattern as
  /// FeeStructureDialog's `structure` param.
  final StudentFeeAssignmentModel? assignment;

  @override
  State<FeeAssignmentDialog> createState() => _FeeAssignmentDialogState();
}

class _FeeAssignmentDialogState extends State<FeeAssignmentDialog> {
  final _service = FeeService();
  final _year = TextEditingController(text: '2026-2027');
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

  /// True once the assignment being edited already has a payment recorded
  /// against it — the point past which student/fee-structure/total-fee
  /// become unsafe to change (see [FeeService.updateAssignment]'s doc
  /// comment). Always false when creating a new assignment.
  bool get _identityLocked =>
      widget.assignment != null && widget.assignment!.paidAmount > 0;

  @override
  void initState() {
    super.initState();
    final a = widget.assignment;
    if (a != null) {
      _mode = 'single';
      _year.text = a.academicYear;
      _discount.text = a.discountAmount.toStringAsFixed(0);
      _classId = a.classId;
      _studentId = a.studentId;
      _structureId = a.feeStructureId;
    }
    _loadClasses();
  }

  Future<void> _loadClasses() async {
    var classes = await _service.getActiveClasses();
    final a = widget.assignment;
    // The assignment's own class may since have been deactivated — keep it
    // selectable (see FeeService.getClassById's doc comment) rather than
    // leaving `_classId` pointing at an item missing from the dropdown.
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
    // Same reasoning as the class list above, applied to the fee structure:
    // an assignment's structure may since have been deactivated via the
    // Structures tab's own Edit dialog (which supports isActive toggling).
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
    final selectedFee = _structures.firstWhere((f) => f.id == _structureId);
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
            'academicYear': _year.text.trim(),
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
          'academicYear': _year.text.trim(),
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
          academicYear: _year.text.trim(),
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
                      'Only academic year and discount can be edited here.',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                    ),
                  ),
                DropdownButtonFormField<String>(
                  initialValue: _classId,
                  decoration: const InputDecoration(labelText: 'Select Class *'),
                  items: _classes
                      .map<DropdownMenuItem<String>>(
                        (e) => DropdownMenuItem<String>(value: e.id as String, child: Text(e.data()['name']?.toString() ?? '')),
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
                    decoration: const InputDecoration(labelText: 'Select Student *'),
                    items: _students
                        .map<DropdownMenuItem<String>>(
                          (e) => DropdownMenuItem<String>(value: e.id as String, child: Text(e.data()['name']?.toString() ?? '')),
                        )
                        .toList(),
                    onChanged: _identityLocked ? null : (v) => setState(() => _studentId = v),
                    validator: (v) => v == null ? 'Required' : null,
                  ),
                ],
                DropdownButtonFormField<String>(
                  initialValue: _structureId,
                  decoration: const InputDecoration(labelText: 'Fee Structure *'),
                  items: _structures
                      .map<DropdownMenuItem<String>>(
                        (fee) => DropdownMenuItem<String>(
                          value: fee.id,
                          child: Text('${fee.name} - ₹${fee.totalAmount.toStringAsFixed(0)}'),
                        ),
                      )
                      .toList(),
                  onChanged: _identityLocked ? null : (v) => setState(() => _structureId = v),
                  validator: (v) => v == null ? 'Required' : null,
                ),
                TextFormField(controller: _year, decoration: const InputDecoration(labelText: 'Academic Year *'), validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null),
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
