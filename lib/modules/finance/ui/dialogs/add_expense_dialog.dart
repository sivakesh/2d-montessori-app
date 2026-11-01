import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/services/document_number_service.dart';
import '../../../../core/widgets/responsive_dialog_shell.dart';
import '../../models/finance_category_model.dart';
import '../../models/finance_invoice_model.dart';
import '../../models/vendor_model.dart';
import '../../services/finance_service.dart';

/// The vendor an invoice is (or will be) saved with: the `vendors` doc id
/// (stored as the invoice's `partyId`, empty for legacy name-only invoices)
/// and the name stored as `partyName`.
typedef _VendorChoice = ({String id, String name});

/// Raise / edit an expense invoice. The vendor is picked (with search) from
/// Finance -> Vendors; the selected vendor's id is saved as `partyId` and
/// its name as `partyName`. Editing an invoice whose saved vendor is
/// inactive, no longer in Vendors, or only a name that matches no vendor
/// keeps that saved vendor unless a different one is chosen.
class AddExpenseDialog extends StatefulWidget {
  const AddExpenseDialog({super.key, this.initial, this.service, this.numberService});

  /// When set, the dialog edits this existing expense invoice in place
  /// (via [FinanceService.updateExpenseInvoice]) instead of raising a new
  /// one — no new invoice number is allocated.
  final FinanceInvoiceModel? initial;

  /// Optional injection seam (tests); defaults to `FinanceService()` as before.
  final FinanceService? service;

  /// Optional injection seam (tests); defaults to `DocumentNumberService()`.
  final DocumentNumberService? numberService;

  @override
  State<AddExpenseDialog> createState() => _AddExpenseDialogState();
}

class _AddExpenseDialogState extends State<AddExpenseDialog> {
  final _formKey = GlobalKey<FormState>();
  final _vendorText = TextEditingController();
  final _vendorFocus = FocusNode();
  final _description = TextEditingController();
  final _amount = TextEditingController();
  final _tax = TextEditingController(text: '0');
  final _attachment = TextEditingController();
  late final _service = widget.service ?? FinanceService();
  // Lazy: only the create path allocates an invoice number; editing never does.
  late final _numberService = widget.numberService ?? DocumentNumberService();
  late final Stream<List<VendorModel>> _vendors = _service.watchVendors();
  _VendorChoice? _vendor;
  // Edit: the saved vendor is matched against Vendors once, on first load.
  bool _vendorMatched = false;
  String? _vendorNote;
  DateTime _invoiceDate = DateTime.now();
  final DateTime _dueDate = DateTime.now();
  String? _categoryId;
  bool _saving = false;

  bool get _isEdit => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial != null) {
      if (initial.partyName.trim().isNotEmpty) {
        _vendor = (id: initial.partyId, name: initial.partyName);
        _vendorText.text = initial.partyName;
      }
      _description.text = initial.description;
      _amount.text = _exactAmount(initial.amount);
      _tax.text = _exactAmount(initial.taxAmount);
      _attachment.text = initial.attachmentUrl;
      _invoiceDate = initial.invoiceDate ?? initial.createdAt ?? DateTime.now();
    }
    // Typing after a selection clears it until a vendor is picked again.
    _vendorText.addListener(() {
      if (_vendor != null && _vendorText.text != _vendor!.name) setState(() => _vendor = null);
    });
  }

  /// Edit only: links the saved vendor to Vendors without changing it. A
  /// saved id is looked up by id; a legacy name-only invoice is linked when
  /// exactly one vendor has that name (its stored name is kept). Anything
  /// else stays as saved, with a note.
  void _matchSavedVendor(List<VendorModel> vendors) {
    _vendorMatched = true;
    final initial = widget.initial!;
    final saved = initial.partyName.trim();
    if (saved.isEmpty) return;
    const keep = 'The invoice keeps this vendor unless you choose another.';
    if (initial.partyId.isNotEmpty) {
      final match = vendors.where((v) => v.id == initial.partyId).firstOrNull;
      if (match == null) {
        _vendorNote = '"$saved" is no longer in Vendors. $keep';
      } else if (!match.isActive) {
        _vendorNote = '"$saved" is inactive in Vendors. $keep';
      }
      return;
    }
    final matches = vendors.where((v) => v.name.trim().toLowerCase() == saved.toLowerCase()).toList();
    if (matches.length == 1) {
      _vendor = (id: matches.single.id, name: initial.partyName);
      if (!matches.single.isActive) _vendorNote = '"$saved" is inactive in Vendors. $keep';
    } else if (matches.isEmpty) {
      _vendorNote = '"$saved" was saved as a name and doesn\'t match a vendor in Vendors. $keep';
    } else {
      _vendorNote = 'More than one vendor is named "$saved", so it isn\'t linked to either. $keep';
    }
  }

  /// Pre-fills without rounding, so saving a descriptive-only edit never
  /// changes the stored amount (e.g. 1234.5 stays 1234.5, 1000 shows "1000").
  static String _exactAmount(double value) =>
      value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toString();

  /// When editing an invoice that already has payments, the new total
  /// (amount + tax) may not drop below what has been paid.
  String? _validateAgainstPaid() {
    final paid = widget.initial?.paidAmount ?? 0;
    if (paid <= 0) return null;
    final total = (double.tryParse(_amount.text) ?? 0) + (double.tryParse(_tax.text) ?? 0);
    if (total < paid) return 'Total cannot be less than ₹${_exactAmount(paid)} already paid';
    return null;
  }

  Future<void> _pickInvoiceDate() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDate: _invoiceDate,
    );
    if (picked != null) setState(() => _invoiceDate = picked);
  }

  @override
  void dispose() {
    _vendorText.dispose();
    _vendorFocus.dispose();
    _description.dispose();
    _amount.dispose();
    _tax.dispose();
    _attachment.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final initial = widget.initial;
    if (initial != null) {
      try {
        final cats = await _service.watchCategories().first;
        final cat = cats.firstWhere((e) => e.id == _categoryId);
        final vendor = _vendor!;
        await _service.updateExpenseInvoice(
          id: initial.id,
          partyId: vendor.id.isEmpty ? null : vendor.id,
          partyName: vendor.name.trim(),
          categoryName: cat.name,
          invoiceDate: _invoiceDate,
          amount: double.tryParse(_amount.text) ?? 0,
          taxAmount: double.tryParse(_tax.text) ?? 0,
          description: _description.text.trim(),
          attachmentUrl: _attachment.text.trim(),
        );
        if (!mounted) return;
        Navigator.pop(context, true);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to update expense invoice: $e')));
      } finally {
        if (mounted) setState(() => _saving = false);
      }
      return;
    }
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
        'partyId': _vendor!.id,
        'partyName': _vendor!.name.trim(),
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

  Widget _vendorField() => StreamBuilder<List<VendorModel>>(
    stream: _vendors,
    builder: (context, snap) {
      final loading = !snap.hasData && !snap.hasError;
      final all = snap.data ?? const <VendorModel>[];
      if (_isEdit && !_vendorMatched && snap.hasData) _matchSavedVendor(all);
      final active = all.where((v) => v.isActive && v.name.trim().isNotEmpty).toList();
      final String? status = snap.hasError
          ? "Couldn't load vendors. Close and reopen this form to try again."
          : loading
          ? 'Loading vendors…'
          : active.isEmpty
          ? 'No active vendors yet. Add one under Finance → Vendors first.'
          : null;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          RawAutocomplete<VendorModel>(
            key: const Key('expense-vendor'),
            textEditingController: _vendorText,
            focusNode: _vendorFocus,
            displayStringForOption: (v) => v.name.trim(),
            optionsBuilder: (value) {
              final query = value.text.trim().toLowerCase();
              return active.where((v) => v.name.toLowerCase().contains(query));
            },
            onSelected: (v) => setState(() {
              _vendor = (id: v.id, name: v.name.trim());
              _vendorNote = null;
            }),
            fieldViewBuilder: (context, controller, focusNode, onSubmitted) => TextFormField(
              controller: controller,
              focusNode: focusNode,
              validator: (_) => _vendor == null ? 'Select a vendor from the list' : null,
              enabled: !loading && !_saving,
              decoration: InputDecoration(
                labelText: 'Vendor',
                hintText: 'Search vendors by name',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: loading
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : null,
                helperText: status,
                helperMaxLines: 3,
              ),
            ),
            optionsViewBuilder: (context, onSelected, options) => Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 4,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 240, maxWidth: 480),
                  child: ListView(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    children: [
                      for (final v in options)
                        ListTile(
                          key: Key('vendor-option-${v.id}'),
                          dense: true,
                          title: Text(v.name.trim()),
                          subtitle: v.serviceType.trim().isEmpty ? null : Text(v.serviceType.trim()),
                          onTap: () => onSelected(v),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_vendorNote != null && _vendor != null) ...[const SizedBox(height: 4), Text(_vendorNote!, style: TextStyle(fontSize: 12, color: Colors.orange.shade900))],
        ],
      );
    },
  );

  @override
  Widget build(BuildContext context) => ResponsiveDialogShell(
        desktopWidth: 760,
        desktopHeight: 640,
        child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(_isEdit ? 'Edit Expense Invoice' : 'Raise Expense Invoice', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _isEdit
                        ? 'Invoice No: ${widget.initial!.invoiceNo.isEmpty ? '—' : widget.initial!.invoiceNo}'
                        : 'An invoice number is generated automatically when you save.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey.shade700),
                  ),
                ),
                const SizedBox(height: 12),
                _vendorField(),
                const SizedBox(height: 12),
                StreamBuilder<List<FinanceCategoryModel>>(
                  stream: _service.watchCategories(),
                  builder: (context, snap) {
                    final initialCategory = widget.initial?.categoryName;
                    // Editing: pre-select the invoice's existing category
                    // (stored by name only), keeping it selectable even if
                    // that category has since been deactivated.
                    if (_isEdit && _categoryId == null) {
                      for (final c in snap.data ?? const <FinanceCategoryModel>[]) {
                        if (c.type == 'expense' && c.name == initialCategory) _categoryId = c.id;
                      }
                    }
                    final items = snap.data
                            ?.where((e) => e.type == 'expense' && (e.isActive || (_isEdit && e.id == _categoryId)))
                            .toList() ??
                        [];
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
                TextFormField(
                  controller: _amount,
                  decoration: InputDecoration(
                    labelText: 'Amount',
                    helperText: (widget.initial?.paidAmount ?? 0) > 0
                        ? '₹${_exactAmount(widget.initial!.paidAmount)} already paid — total cannot go below this'
                        : null,
                  ),
                  keyboardType: TextInputType.number,
                  validator: (v) => (double.tryParse(v ?? '') ?? 0) > 0 ? _validateAgainstPaid() : 'Required',
                ),
                const SizedBox(height: 12),
                TextFormField(controller: _tax, decoration: const InputDecoration(labelText: 'Tax Amount (optional)'), keyboardType: TextInputType.number),
                if (_isEdit) ...[
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Invoice Date'),
                    subtitle: Text(DateFormat('dd MMM yyyy').format(_invoiceDate)),
                    trailing: TextButton(
                      onPressed: _saving ? null : _pickInvoiceDate,
                      child: const Text('Change'),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                TextFormField(controller: _description, decoration: const InputDecoration(labelText: 'Description'), maxLines: 3),
                const SizedBox(height: 12),
                TextFormField(controller: _attachment, decoration: const InputDecoration(labelText: 'Attachment URL (optional)')),
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
