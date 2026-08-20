import 'package:flutter/material.dart';
import '../../../../core/services/document_number_service.dart';
import '../../models/finance_category_model.dart';
import '../../services/finance_service.dart';

class AddExpenseDialog extends StatefulWidget {
  const AddExpenseDialog({super.key});

  @override
  State<AddExpenseDialog> createState() => _AddExpenseDialogState();
}

class _AddExpenseDialogState extends State<AddExpenseDialog> {
  final _formKey = GlobalKey<FormState>();
  final _vendorName = TextEditingController();
  final _description = TextEditingController();
  final _amount = TextEditingController();
  final _tax = TextEditingController(text: '0');
  final _attachment = TextEditingController();
  final _service = FinanceService();
  final _numberService = DocumentNumberService();
  final DateTime _invoiceDate = DateTime.now();
  final DateTime _dueDate = DateTime.now();
  String? _categoryId;
  bool _saving = false;

  @override
  void dispose() {
    _vendorName.dispose();
    _description.dispose();
    _amount.dispose();
    _tax.dispose();
    _attachment.dispose();
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
      final cats = await _service.watchCategories().first;
      final cat = cats.firstWhere((e) => e.id == _categoryId);
      final invoiceAmount = double.tryParse(_amount.text) ?? 0;
      final taxAmount = double.tryParse(_tax.text) ?? 0;
      final total = invoiceAmount + taxAmount;
      await _service.createExpenseInvoice({
        'partyId': '',
        'partyName': _vendorName.text.trim(),
        'categoryName': cat.name,
        'invoiceNo': invoiceNo,
        'invoiceSequence': invoiceSequence,
        'invoiceDate': _invoiceDate,
        'dueDate': _dueDate,
        'amount': invoiceAmount,
        'taxAmount': taxAmount,
        'deductions': 0,
        'bonus': 0,
        'totalAmount': total,
        'description': _description.text.trim(),
        'attachmentUrl': _attachment.text.trim(),
      });
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to save expense invoice')));
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
                Text('Raise Expense Invoice', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'An invoice number is generated automatically when you save.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey.shade700),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(controller: _vendorName, decoration: const InputDecoration(labelText: 'Vendor Name'), validator: (v) => (v == null || v.isEmpty) ? 'Required' : null),
                const SizedBox(height: 12),
                StreamBuilder<List<FinanceCategoryModel>>(
                  stream: _service.watchCategories(),
                  builder: (context, snap) {
                    final items = snap.data?.where((e) => e.type == 'expense' && e.isActive).toList() ?? [];
                    return DropdownButtonFormField<String>(
                      initialValue: _categoryId,
                      decoration: const InputDecoration(labelText: 'Expense Category'),
                      items: items.map((e) => DropdownMenuItem(value: e.id, child: Text(e.name))).toList(),
                      onChanged: (v) => setState(() => _categoryId = v),
                      validator: (v) => v == null ? 'Required' : null,
                    );
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(controller: _amount, decoration: const InputDecoration(labelText: 'Amount'), keyboardType: TextInputType.number, validator: (v) => (double.tryParse(v ?? '') ?? 0) > 0 ? null : 'Required'),
                const SizedBox(height: 12),
                TextFormField(controller: _tax, decoration: const InputDecoration(labelText: 'Tax Amount (optional)'), keyboardType: TextInputType.number),
                const SizedBox(height: 12),
                TextFormField(controller: _description, decoration: const InputDecoration(labelText: 'Description'), maxLines: 3),
                const SizedBox(height: 12),
                TextFormField(controller: _attachment, decoration: const InputDecoration(labelText: 'Attachment URL (optional)')),
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
