import 'package:flutter/material.dart';
import '../../models/finance_account_model.dart';
import '../../models/finance_category_model.dart';
import '../../models/finance_expense_model.dart';
import '../../models/vendor_model.dart';
import '../../services/finance_service.dart';

class AddExpenseDialog extends StatefulWidget {
  const AddExpenseDialog({super.key});

  @override
  State<AddExpenseDialog> createState() => _AddExpenseDialogState();
}

class _AddExpenseDialogState extends State<AddExpenseDialog> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _amount = TextEditingController();
  final _billNo = TextEditingController();
  final _reference = TextEditingController();
  final _remarks = TextEditingController();
  final _service = FinanceService();
  String? _categoryId;
  String? _vendorId;
  String? _accountId;
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    _billNo.dispose();
    _reference.dispose();
    _remarks.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      final cats = await _service.watchCategories().first;
      final accounts = await _service.watchAccounts().first;
      final vendors = await _service.watchVendors().first;
      final cat = cats.firstWhere((e) => e.id == _categoryId);
      final acc = accounts.firstWhere((e) => e.id == _accountId);
      final vendor = _vendorId == null ? null : vendors.firstWhere((e) => e.id == _vendorId);
      final now = DateTime.now();
      final model = FinanceExpenseModel(
        id: '',
        title: _title.text.trim(),
        categoryId: cat.id,
        categoryName: cat.name,
        vendorId: vendor?.id ?? '',
        vendorName: vendor?.name ?? '',
        amount: double.tryParse(_amount.text) ?? 0,
        expenseDate: now,
        paymentMode: 'cash',
        accountId: acc.id,
        accountName: acc.name,
        referenceNo: _reference.text.trim(),
        billNo: _billNo.text.trim(),
        remarks: _remarks.text.trim(),
        attachmentUrls: const [],
        ledgerEntryId: '',
        createdAt: now,
        updatedAt: now,
        createdBy: 'admin',
      );
      await _service.createExpense(model);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to save expense')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
        child: SizedBox(
          width: 720,
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('Add Expense', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                TextFormField(controller: _title, decoration: const InputDecoration(labelText: 'Title'), validator: (v) => (v == null || v.isEmpty) ? 'Required' : null),
                const SizedBox(height: 12),
                StreamBuilder<List<FinanceCategoryModel>>(
                  stream: _service.watchCategories(),
                  builder: (context, snap) {
                    final items = snap.data?.where((e) => e.type == 'expense' && e.isActive).toList() ?? [];
                    return DropdownButtonFormField<String>(
                      initialValue: _categoryId,
                      decoration: const InputDecoration(labelText: 'Category'),
                      items: items.map((e) => DropdownMenuItem(value: e.id, child: Text(e.name))).toList(),
                      onChanged: (v) => setState(() => _categoryId = v),
                      validator: (v) => v == null ? 'Required' : null,
                    );
                  },
                ),
                const SizedBox(height: 12),
                StreamBuilder<List<VendorModel>>(
                  stream: _service.watchVendors(),
                  builder: (context, snap) {
                    final items = snap.data?.where((e) => e.isActive).toList() ?? [];
                    return DropdownButtonFormField<String>(
                      initialValue: _vendorId,
                      decoration: const InputDecoration(labelText: 'Vendor (optional)'),
                      items: items.map((e) => DropdownMenuItem(value: e.id, child: Text(e.name))).toList(),
                      onChanged: (v) => setState(() => _vendorId = v),
                    );
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(controller: _amount, decoration: const InputDecoration(labelText: 'Amount'), keyboardType: TextInputType.number, validator: (v) => (double.tryParse(v ?? '') ?? 0) > 0 ? null : 'Enter amount'),
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
                TextFormField(controller: _billNo, decoration: const InputDecoration(labelText: 'Bill No')),
                const SizedBox(height: 12),
                TextFormField(controller: _reference, decoration: const InputDecoration(labelText: 'Reference No')),
                const SizedBox(height: 12),
                TextFormField(controller: _remarks, decoration: const InputDecoration(labelText: 'Remarks'), maxLines: 3),
                const SizedBox(height: 16),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
                  const SizedBox(width: 8),
                  FilledButton(onPressed: _saving ? null : _save, child: _saving ? const CircularProgressIndicator() : const Text('Save')),
                ])
              ]),
            ),
          ),
        ),
      );
}
