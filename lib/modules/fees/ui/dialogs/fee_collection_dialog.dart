import 'package:flutter/material.dart';
import '../../models/student_fee_assignment_model.dart';
import '../../services/fee_service.dart';

class FeeCollectionDialog extends StatefulWidget {
  const FeeCollectionDialog({super.key, required this.assignment});
  final StudentFeeAssignmentModel assignment;

  @override
  State<FeeCollectionDialog> createState() => _FeeCollectionDialogState();
}

class _FeeCollectionDialogState extends State<FeeCollectionDialog> {
  final _service = FeeService();
  final _amount = TextEditingController();
  final _ref = TextEditingController();
  final _remarks = TextEditingController();
  final DateTime _date = DateTime.now();
  String _mode = 'cash';

  Future<void> _save() async {
    final amount = double.tryParse(_amount.text) ?? 0;
    if (amount <= 0 || amount > widget.assignment.balanceAmount) return;
    await _service.collectFee(
      assignmentId: widget.assignment.id,
      amount: amount,
      paymentDate: _date,
      paymentMode: _mode,
      referenceNo: _ref.text.trim(),
      remarks: _remarks.text.trim(),
    );
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Collect Fee - ${widget.assignment.studentName}'),
      content: SizedBox(
        width: 540,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: _amount, decoration: const InputDecoration(labelText: 'Amount'), keyboardType: TextInputType.number),
              DropdownButtonFormField<String>(
                initialValue: _mode,
                items: const ['cash', 'upi', 'bank_transfer', 'cheque', 'other'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                onChanged: (v) => setState(() => _mode = v ?? _mode),
              ),
              TextField(controller: _ref, decoration: const InputDecoration(labelText: 'Reference No')),
              TextField(controller: _remarks, decoration: const InputDecoration(labelText: 'Remarks')),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
