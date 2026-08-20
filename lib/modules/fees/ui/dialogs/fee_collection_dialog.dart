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
  bool _saving = false;
  bool _loadingAssignment = true;
  StudentFeeAssignmentModel? _latestAssignment;

  @override
  void initState() {
    super.initState();
    _loadLatestAssignment();
  }

  @override
  void dispose() {
    _amount.dispose();
    _ref.dispose();
    _remarks.dispose();
    super.dispose();
  }

  Future<void> _loadLatestAssignment() async {
    final latest = await _service.getAssignmentById(widget.assignment.id);
    if (!mounted) return;
    final assignment = latest ?? widget.assignment;
    setState(() {
      _latestAssignment = assignment;
      _mode = _mode.isNotEmpty ? _mode : 'cash';
      _amount.text = assignment.balanceAmount > 0
          ? assignment.balanceAmount.toStringAsFixed(0)
          : '';
      _loadingAssignment = false;
    });
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amount.text) ?? 0;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Amount is required and must be greater than 0')),
      );
      return;
    }
    final currentBalance = _latestAssignment?.balanceAmount ?? widget.assignment.balanceAmount;
    if (amount > currentBalance) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Amount cannot exceed assignment balance')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await _service.collectFee(
        assignmentId: widget.assignment.id,
        amount: amount,
        paymentDate: _date,
        paymentMode: _mode,
        referenceNo: _ref.text.trim(),
        remarks: _remarks.text.trim(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save collection: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final assignment = _latestAssignment ?? widget.assignment;
    final balance = assignment.balanceAmount;
    final fullyCollected = balance <= 0;

    return AlertDialog(
      title: Text('Collect Fee - ${widget.assignment.studentName}'),
      content: SizedBox(
        width: 540,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_loadingAssignment)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: LinearProgressIndicator(minHeight: 2),
                ),
              if (fullyCollected)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    'This fee has already been fully collected.',
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                ),
              TextField(
                controller: _amount,
                enabled: !fullyCollected,
                decoration: const InputDecoration(labelText: 'Amount'),
                keyboardType: TextInputType.number,
              ),
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
        FilledButton(
          onPressed: _saving || _loadingAssignment || fullyCollected ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}
