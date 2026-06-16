import 'package:flutter/material.dart';

import '../../models/fee_structure_model.dart';
import '../../services/fee_service.dart';

class FeeAssignmentDialog extends StatefulWidget {
  const FeeAssignmentDialog({super.key});

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

  @override
  void initState() {
    super.initState();
    _loadClasses();
  }

  Future<void> _loadClasses() async {
    final classes = await _service.getActiveClasses();
    if (!mounted) return;
    setState(() => _classes = classes);
  }

  Future<void> _loadStudents(String classId) async {
    final students = await _service.getStudentsByClassId(classId);
    final classStructures = await _service.getActiveStructuresForClass(classId);
    if (!mounted) return;
    setState(() {
      _students = students;
      _structures = classStructures;
      _studentId = null;
      _structureId = null;
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
      if (_mode == 'single') {
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
    return AlertDialog(
      title: const Text('Assign Fee'),
      content: SizedBox(
        width: 720,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                DropdownButtonFormField<String>(
                  initialValue: _classId,
                  decoration: const InputDecoration(labelText: 'Select Class *'),
                  items: _classes
                      .map<DropdownMenuItem<String>>(
                        (e) => DropdownMenuItem<String>(value: e.id as String, child: Text(e.data()['name']?.toString() ?? '')),
                      )
                      .toList(),
                  onChanged: (v) {
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
                    onChanged: (v) => setState(() => _studentId = v),
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
                  onChanged: (v) => setState(() => _structureId = v),
                  validator: (v) => v == null ? 'Required' : null,
                ),
                TextFormField(controller: _year, decoration: const InputDecoration(labelText: 'Academic Year *'), validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null),
                TextFormField(controller: _discount, decoration: const InputDecoration(labelText: 'Discount Amount'), keyboardType: TextInputType.number),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _saving ? null : _save, child: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save')),
      ],
    );
  }
}
