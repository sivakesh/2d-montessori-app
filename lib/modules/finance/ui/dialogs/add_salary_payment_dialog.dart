import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../models/finance_account_model.dart';
import '../../models/staff_salary_payment_model.dart';
import '../../services/finance_service.dart';

class AddSalaryPaymentDialog extends StatefulWidget {
  const AddSalaryPaymentDialog({super.key});

  @override
  State<AddSalaryPaymentDialog> createState() => _AddSalaryPaymentDialogState();
}

class _AddSalaryPaymentDialogState extends State<AddSalaryPaymentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _staffSearch = TextEditingController();
  final _base = TextEditingController();
  final _allowance = TextEditingController(text: '0');
  final _deduction = TextEditingController(text: '0');
  final _paid = TextEditingController();
  final _ref = TextEditingController();
  final _remarks = TextEditingController();
  final _service = FinanceService();
  String? _staffId;
  String? _accountId;
  String _month = 'June';
  String _year = '2026';
  String _paymentMode = 'cash';
  bool _saving = false;

  @override
  void dispose() {
    _staffSearch.dispose();
    _base.dispose();
    _allowance.dispose();
    _deduction.dispose();
    _paid.dispose();
    _ref.dispose();
    _remarks.dispose();
    super.dispose();
  }

  double get _net => (double.tryParse(_base.text) ?? 0) + (double.tryParse(_allowance.text) ?? 0) - (double.tryParse(_deduction.text) ?? 0);

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      final users = await FirebaseFirestore.instance.collection('users').get();
      final accounts = await _service.watchAccounts().first;
      final staff = users.docs.firstWhere((d) => d.id == _staffId);
      final acc = accounts.firstWhere((a) => a.id == _accountId);
      final paid = double.tryParse(_paid.text) ?? 0;
      final now = DateTime.now();
      final model = StaffSalaryPaymentModel(
        id: '',
        staffUserId: staff.id,
        staffName: staff.data()['name']?.toString() ?? 'Staff',
        salaryMonth: _month,
        salaryYear: _year,
        baseSalary: double.tryParse(_base.text) ?? 0,
        allowanceAmount: double.tryParse(_allowance.text) ?? 0,
        deductionAmount: double.tryParse(_deduction.text) ?? 0,
        netPayable: _net,
        paidAmount: paid,
        balanceAmount: _net - paid,
        paymentDate: now,
        paymentMode: _paymentMode,
        accountId: acc.id,
        accountName: acc.name,
        referenceNo: _ref.text.trim(),
        status: paid >= _net ? 'paid' : (paid > 0 ? 'partial' : 'unpaid'),
        remarks: _remarks.text.trim(),
        ledgerEntryId: '',
        createdAt: now,
        updatedAt: now,
        createdBy: 'admin',
      );
      await _service.createSalaryPayment(model);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to save salary payment')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
        child: SizedBox(
          width: 760,
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('Add Salary Payment', style: Theme.of(context).textTheme.titleLarge),
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
                Row(children: [
                  Expanded(child: DropdownButtonFormField<String>(initialValue: _month, decoration: const InputDecoration(labelText: 'Month'), items: const ['January','February','March','April','May','June','July','August','September','October','November','December'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: (v) => setState(() => _month = v ?? _month))),
                  const SizedBox(width: 12),
                  Expanded(child: DropdownButtonFormField<String>(initialValue: _year, decoration: const InputDecoration(labelText: 'Year'), items: const ['2025','2026','2027'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: (v) => setState(() => _year = v ?? _year))),
                ]),
                const SizedBox(height: 12),
                TextFormField(controller: _base, decoration: const InputDecoration(labelText: 'Base Salary'), keyboardType: TextInputType.number, validator: (v) => (double.tryParse(v ?? '') ?? 0) >= 0 ? null : 'Invalid'),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: TextFormField(controller: _allowance, decoration: const InputDecoration(labelText: 'Allowance'), keyboardType: TextInputType.number, onChanged: (_) => setState(() {}))),
                  const SizedBox(width: 12),
                  Expanded(child: TextFormField(controller: _deduction, decoration: const InputDecoration(labelText: 'Deduction'), keyboardType: TextInputType.number, onChanged: (_) => setState(() {}))),
                ]),
                const SizedBox(height: 12),
                Text('Net Payable: ₹${_net.toStringAsFixed(0)}'),
                const SizedBox(height: 12),
                TextFormField(controller: _paid, decoration: const InputDecoration(labelText: 'Paid Amount'), keyboardType: TextInputType.number, validator: (v) => (double.tryParse(v ?? '') ?? 0) <= _net ? null : 'Cannot exceed net payable'),
                const SizedBox(height: 12),
                StreamBuilder<List<FinanceAccountModel>>(
                  stream: _service.watchAccounts(),
                  builder: (context, snap) {
                    final items = snap.data?.where((e) => e.isActive).toList() ?? [];
                    return DropdownButtonFormField<String>(
                      initialValue: _accountId,
                      decoration: const InputDecoration(labelText: 'Account'),
                      items: items.map((e) => DropdownMenuItem(value: e.id, child: Text(e.name))).toList(),
                      onChanged: (v) => setState(() => _accountId = v),
                      validator: (v) => v == null ? 'Required' : null,
                    );
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(initialValue: _paymentMode, decoration: const InputDecoration(labelText: 'Payment Mode'), items: const ['cash','upi','bank_transfer','cheque','card','other'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: (v) => setState(() => _paymentMode = v ?? _paymentMode)),
                const SizedBox(height: 12),
                TextFormField(controller: _ref, decoration: const InputDecoration(labelText: 'Reference No')),
                const SizedBox(height: 12),
                TextFormField(controller: _remarks, decoration: const InputDecoration(labelText: 'Remarks'), maxLines: 3),
                const SizedBox(height: 16),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
                  const SizedBox(width: 8),
                  FilledButton(onPressed: _saving ? null : _save, child: _saving ? const CircularProgressIndicator() : const Text('Save')),
                ]),
              ]),
            ),
          ),
        ),
      );
}
