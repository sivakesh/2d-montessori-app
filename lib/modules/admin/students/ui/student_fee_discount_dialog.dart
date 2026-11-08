import 'package:flutter/material.dart';

import '../../../fees/models/fee_discount.dart';

/// Add or edit a student's fee discount (Add / Edit Student). Returns the
/// configuration (validated with StudentFeeDiscount.validate), or null when
/// cancelled. Nothing is saved until the student is saved; existing fee
/// assignments are never changed by this (see Fees → Apply Student
/// Discounts to Existing Fees).
class StudentFeeDiscountDialog extends StatefulWidget {
  const StudentFeeDiscountDialog({super.key, this.initial});

  final StudentFeeDiscount? initial;

  static const note = 'Applies automatically to new fee assignments in its effective dates. '
      'Existing assignments are changed only with Fees → Apply Student Discounts to Existing Fees.';

  @override
  State<StudentFeeDiscountDialog> createState() => _StudentFeeDiscountDialogState();
}

class _StudentFeeDiscountDialogState extends State<StudentFeeDiscountDialog> {
  final _formKey = GlobalKey<FormState>();
  late FeeDiscountType _type = widget.initial?.type ?? FeeDiscountType.percentage;
  late final _value = TextEditingController(text: _initialValue());
  late final _reason = TextEditingController(text: widget.initial?.reason ?? '');
  late DateTime? _from = widget.initial?.effectiveFrom;
  late DateTime? _until = widget.initial?.effectiveUntil;
  late bool _active = widget.initial?.isActive ?? true;
  String? _error;

  String _initialValue() {
    final v = widget.initial?.value;
    if (v == null || !v.isFinite) return '';
    return v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
  }

  @override
  void dispose() {
    _value.dispose();
    _reason.dispose();
    super.dispose();
  }

  String _label(DateTime? d) => d == null ? 'Not set' : '${d.day}/${d.month}/${d.year}';

  Future<void> _pick(bool from) async {
    final current = from ? _from : _until;
    final picked = await showDatePicker(
      context: context,
      firstDate: StudentFeeDiscount.firstDate,
      lastDate: StudentFeeDiscount.lastDate,
      initialDate: current ?? (from ? null : _from) ?? DateTime.now(),
      helpText: from ? 'Effective from' : 'Effective until',
    );
    if (picked == null) return;
    setState(() {
      final d = DateTime(picked.year, picked.month, picked.day);
      if (from) {
        _from = d;
      } else {
        _until = d;
      }
      _error = null;
    });
  }

  void _save() {
    final value = double.tryParse(_value.text.trim());
    final error = StudentFeeDiscount.validate(type: _type, value: value, effectiveFrom: _from, effectiveUntil: _until);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.pop(
      context,
      StudentFeeDiscount(
        id: widget.initial?.id ?? '',
        type: _type,
        value: value!,
        effectiveFrom: _from,
        effectiveUntil: _until,
        reason: _reason.text.trim(),
        isActive: _active,
        createdAt: widget.initial?.createdAt,
      ),
    );
  }

  Widget _dateRow(String label, bool from) {
    final d = from ? _from : _until;
    return Row(
      children: [
        Expanded(child: Text('$label: ${_label(d)}', key: Key('fee-discount-${from ? 'from' : 'until'}-value'))),
        TextButton(key: Key('fee-discount-${from ? 'from' : 'until'}-pick'), onPressed: () => _pick(from), child: const Text('Choose')),
        if (!from && d != null)
          TextButton(key: const Key('fee-discount-until-clear'), onPressed: () => setState(() => _until = null), child: const Text('Clear')),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? 'Add Fee Discount' : 'Edit Fee Discount'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SegmentedButton<FeeDiscountType>(
                  key: const Key('fee-discount-type'),
                  segments: const [
                    ButtonSegment(value: FeeDiscountType.percentage, label: Text('Percentage')),
                    ButtonSegment(value: FeeDiscountType.fixed, label: Text('Fixed amount')),
                  ],
                  selected: {_type},
                  onSelectionChanged: (s) => setState(() => _type = s.first),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('fee-discount-value'),
                  controller: _value,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: _type == FeeDiscountType.percentage ? 'Discount (%)' : 'Discount amount (₹, once per fee period)',
                    helperText: _type == FeeDiscountType.percentage
                        ? 'More than 0, up to 100.'
                        : 'Once per month for monthly fees; once per term or one-time fee, never per component.',
                    helperMaxLines: 2,
                  ),
                ),
                const SizedBox(height: 12),
                _dateRow('Effective from', true),
                _dateRow('Effective until (optional)', false),
                TextField(key: const Key('fee-discount-reason'), controller: _reason, decoration: const InputDecoration(labelText: 'Reason (optional)')),
                SwitchListTile(
                  key: const Key('fee-discount-active'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Active'),
                  subtitle: const Text('Turn off to stop applying it to new assignments.'),
                  value: _active,
                  onChanged: (v) => setState(() => _active = v),
                ),
                Text(StudentFeeDiscountDialog.note, style: Theme.of(context).textTheme.bodySmall),
                if (_error case final e?)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(e, key: const Key('fee-discount-error'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(key: const Key('fee-discount-cancel'), onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(key: const Key('fee-discount-save'), onPressed: _save, child: const Text('Done')),
      ],
    );
  }
}
