import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../../../core/services/document_number_service.dart';
import '../../../../core/theme/app_sizes.dart';
import '../../../../core/widgets/responsive_dialog_shell.dart';
import '../../services/finance_service.dart';

class AddSalaryPaymentDialog extends StatefulWidget {
  const AddSalaryPaymentDialog({super.key});

  @override
  State<AddSalaryPaymentDialog> createState() => _AddSalaryPaymentDialogState();
}

class _AddSalaryPaymentDialogState extends State<AddSalaryPaymentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _month = TextEditingController();
  final _amount = TextEditingController();
  final _deductions = TextEditingController(text: '0');
  final _bonus = TextEditingController(text: '0');
  final _remarks = TextEditingController();
  final _service = FinanceService();
  final _numberService = DocumentNumberService();
  String? _staffId;
  final DateTime _invoiceDate = DateTime.now();
  final DateTime _dueDate = DateTime.now();
  bool _saving = false;

  @override
  void dispose() {
    _month.dispose();
    _amount.dispose();
    _deductions.dispose();
    _bonus.dispose();
    _remarks.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      // Allocate the invoice number only once the invoice is actually being
      // saved, so a cancelled dialog never burns a number and leaves a gap.
      final invoiceNo = await _numberService.generateDocumentNumber(
        counterKey: 'finance_invoice',
        defaultPrefix: 'INV-',
        defaultStartNumber: 10010,
        defaultPadLength: 8,
      );
      final invoiceSequence = int.tryParse(invoiceNo.replaceAll(RegExp(r'[^0-9]'), ''));
      final users = await FirebaseFirestore.instance.collection('users').get();
      final staff = users.docs.firstWhere((d) => d.id == _staffId);
      final amount = double.tryParse(_amount.text) ?? 0;
      final deductions = double.tryParse(_deductions.text) ?? 0;
      final bonus = double.tryParse(_bonus.text) ?? 0;
      final net = amount - deductions + bonus;
      await _service.createSalaryInvoice({
        'partyId': staff.id,
        'partyName': staff.data()['name']?.toString() ?? 'Staff',
        'categoryName': 'Salary',
        'invoiceNo': invoiceNo,
        'invoiceSequence': invoiceSequence,
        'invoiceDate': _invoiceDate,
        'dueDate': _dueDate,
        'amount': amount,
        'taxAmount': 0,
        'deductions': deductions,
        'bonus': bonus,
        'totalAmount': net,
        'description': _remarks.text.trim(),
        'attachmentUrl': '',
        'salaryMonth': _month.text.trim(),
      });
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to save salary invoice')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => ResponsiveDialogShell(
        desktopWidth: 760,
        desktopHeight: 680,
        child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('Raise Salary Invoice', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'An invoice number is generated automatically when you save.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey.shade700),
                  ),
                ),
                const SizedBox(height: 12),
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance.collection('users').where('role', whereIn: ['staff', 'teacher', 'admin']).snapshots(),
                  builder: (context, snap) {
                    final docs = snap.data?.docs ?? [];
                    return DropdownButtonFormField<String>(
                      initialValue: _staffId,
                      decoration: const InputDecoration(labelText: 'Staff'),
                      items: docs.map((d) => DropdownMenuItem(value: d.id, child: Text(d.data()['name']?.toString() ?? d.id))).toList(),
                      onChanged: (v) => setState(() => _staffId = v),
                      validator: (v) => v == null ? 'Required' : null,
                    );
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(controller: _month, decoration: const InputDecoration(labelText: 'Salary Month'), validator: (v) => (v == null || v.isEmpty) ? 'Required' : null),
                const SizedBox(height: 12),
                TextFormField(controller: _amount, decoration: const InputDecoration(labelText: 'Amount'), keyboardType: TextInputType.number, validator: (v) => (double.tryParse(v ?? '') ?? 0) > 0 ? null : 'Required'),
                const SizedBox(height: 12),
                Builder(
                  builder: (context) {
                    final deductionsField = TextFormField(controller: _deductions, decoration: const InputDecoration(labelText: 'Deductions'), keyboardType: TextInputType.number);
                    final bonusField = TextFormField(controller: _bonus, decoration: const InputDecoration(labelText: 'Bonus'), keyboardType: TextInputType.number);
                    if (MediaQuery.of(context).size.width < AppSizes.mobileBreakpoint) {
                      return Column(children: [
                        deductionsField,
                        const SizedBox(height: 12),
                        bonusField,
                      ]);
                    }
                    return Row(children: [
                      Expanded(child: deductionsField),
                      const SizedBox(width: 12),
                      Expanded(child: bonusField),
                    ]);
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(controller: _remarks, decoration: const InputDecoration(labelText: 'Remarks'), maxLines: 3),
                const SizedBox(height: 16),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Save'),
                  ),
                ]),
              ]),
            ),
          ),
      );
}
