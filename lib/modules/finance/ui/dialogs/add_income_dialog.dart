import 'package:flutter/material.dart';

import '../../../../core/widgets/responsive_dialog_shell.dart';
import '../../models/finance_account_model.dart';
import '../../models/finance_category_model.dart';
import '../../models/finance_income_model.dart';
import '../../services/finance_service.dart';

class AddIncomeDialog extends StatefulWidget {
  const AddIncomeDialog({super.key, this.initial});

  final FinanceIncomeModel? initial;

  @override
  State<AddIncomeDialog> createState() => _AddIncomeDialogState();
}

class _AddIncomeDialogState extends State<AddIncomeDialog> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _amount = TextEditingController();
  final _reference = TextEditingController();
  final _remarks = TextEditingController();
  final _service = FinanceService();
  String? _categoryId;
  String _programType = 'tuition';
  String? _accountId;
  DateTime _date = DateTime.now();
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    _reference.dispose();
    _remarks.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      final categories = await _service.watchCategories().first;
      final accounts = await _service.watchAccounts().first;
      final cat = categories.firstWhere((c) => c.id == _categoryId);
      final acc = accounts.firstWhere((a) => a.id == _accountId);
      final now = DateTime.now();
      final model = FinanceIncomeModel(
        id: widget.initial?.id ?? '',
        title: _title.text.trim(),
        categoryId: cat.id,
        categoryName: cat.name,
        programType: _programType,
        studentId: '',
        studentName: '',
        classId: '',
        className: '',
        amount: double.tryParse(_amount.text.trim()) ?? 0,
        incomeDate: _date,
        paymentMode: 'cash',
        accountId: acc.id,
        accountName: acc.name,
        referenceNo: _reference.text.trim(),
        remarks: _remarks.text.trim(),
        attachmentUrls: const [],
        ledgerEntryId: '',
        createdAt: now,
        updatedAt: now,
        createdBy: 'admin',
      );
      await _service.createIncome(model);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to save income')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveDialogShell(
      desktopWidth: 720,
      desktopHeight: 680,
      child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Add Income', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _title,
                  decoration: const InputDecoration(labelText: 'Title'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                StreamBuilder<List<FinanceCategoryModel>>(
                  stream: _service.watchCategories(),
                  builder: (context, snap) {
                    final items = snap.data?.where((e) => e.type == 'income' && e.isActive).toList() ?? [];
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
                DropdownButtonFormField<String>(
                  initialValue: _programType,
                  decoration: const InputDecoration(labelText: 'Program Type'),
                  items: const ['tuition', 'after_school', 'day_care', 'training', 'phonics', 'material', 'uniform', 'transport', 'other']
                      .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                      .toList(),
                  onChanged: (v) => setState(() => _programType = v ?? 'tuition'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _amount,
                  decoration: const InputDecoration(labelText: 'Amount'),
                  keyboardType: TextInputType.number,
                  validator: (v) => (double.tryParse(v ?? '') ?? 0) > 0 ? null : 'Enter amount',
                ),
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
                TextFormField(
                  controller: _reference,
                  decoration: const InputDecoration(labelText: 'Reference No'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _remarks,
                  decoration: const InputDecoration(labelText: 'Remarks'),
                  maxLines: 3,
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Save'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
    );
  }
}
