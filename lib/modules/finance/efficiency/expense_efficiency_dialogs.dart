import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/finance_ledger_entry_model.dart';
import 'expense_category_pill.dart';
import 'expense_efficiency_models.dart';
import 'expense_efficiency_service.dart';

/// Assess one expense: category, avoidable amount (Waste / Avoidable and
/// Excessive), reason, management note and corrective action. Saves through
/// ExpenseEfficiencyService (which re-checks everything); pops true when
/// saved or removed.
class ExpenseAssessmentDialog extends StatefulWidget {
  const ExpenseAssessmentDialog({super.key, required this.service, required this.role, required this.entry, this.current});

  final ExpenseEfficiencyService service;
  final String role;
  final FinanceLedgerEntryModel entry;
  final ExpenseAssessment? current;

  @override
  State<ExpenseAssessmentDialog> createState() => _ExpenseAssessmentDialogState();
}

class _ExpenseAssessmentDialogState extends State<ExpenseAssessmentDialog> {
  late ExpenseAssessmentCategory _category = widget.current?.category ?? ExpenseAssessmentCategory.underReview;
  late final _avoidable = TextEditingController(text: _initialAvoidable());
  late final _reason = TextEditingController(text: widget.current?.reason ?? '');
  late final _note = TextEditingController(text: widget.current?.managementNote ?? '');
  late final _action = TextEditingController(text: widget.current?.correctiveAction ?? '');
  late ExpenseActionStatus _actionStatus = widget.current?.actionStatus ?? ExpenseActionStatus.none;
  String? _error;
  bool _saving = false;
  List<Map<String, dynamic>>? _history;

  String _initialAvoidable() {
    final c = widget.current;
    if (c != null && c.category.hasAvoidable) return _num(c.avoidableAmount);
    return '';
  }

  static String _num(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  @override
  void dispose() {
    for (final c in [_avoidable, _reason, _note, _action]) {
      c.dispose();
    }
    super.dispose();
  }

  void _setCategory(ExpenseAssessmentCategory c) => setState(() {
        _category = c;
        _error = null;
        // Waste / Avoidable starts at the whole amount; Excessive at 0
        // (only an explicit portion counts).
        if (c == ExpenseAssessmentCategory.waste && _avoidable.text.trim().isEmpty) _avoidable.text = _num(widget.entry.amount);
        if (c == ExpenseAssessmentCategory.excessive && _avoidable.text.trim().isEmpty) _avoidable.text = '0';
      });

  Future<void> _save() async {
    double? avoidable;
    if (_category.hasAvoidable) {
      avoidable = double.tryParse(_avoidable.text.trim());
      final e = ExpenseAssessment.validate(_category, avoidable, widget.entry.amount);
      if (e != null) return setState(() => _error = e);
    }
    setState(() => _saving = true);
    try {
      await widget.service.saveAssessment(
        requesterRole: widget.role,
        transactionId: widget.entry.id,
        category: _category,
        avoidableAmount: avoidable,
        reason: _reason.text,
        managementNote: _note.text,
        correctiveAction: _action.text,
        actionStatus: _actionStatus,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e'.replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _remove() async {
    setState(() => _saving = true);
    try {
      await widget.service.deleteAssessment(requesterRole: widget.role, transactionId: widget.entry.id);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _loadHistory() async {
    final h = await widget.service.history(target: false, id: widget.entry.id);
    if (mounted) setState(() => _history = h);
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final small = Theme.of(context).textTheme.bodySmall;
    return AlertDialog(
      title: const Text('Assess Expense'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(e.title.trim().isEmpty ? 'Untitled expense' : e.title,
                  key: const Key('assessment-expense-title'), style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(
                '${e.transactionDate == null ? 'No date' : DateFormat('d MMM yyyy').format(e.transactionDate!)} · '
                '${e.categoryName.isEmpty ? 'Uncategorised' : e.categoryName} · ${efficiencyMoney(e.amount)}',
                style: small,
              ),
              // The ledger entry's own `description` (an expense's remarks),
              // shown read-only: never edited here or copied into the
              // assessment.
              const SizedBox(height: 8),
              Container(
                key: const Key('assessment-expense-description-section'),
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Expense Description', style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    e.description.trim().isEmpty ? 'No description recorded for this expense.' : e.description,
                    key: const Key('assessment-expense-description'),
                    softWrap: true,
                    style: e.description.trim().isEmpty ? small?.copyWith(fontStyle: FontStyle.italic) : null,
                  ),
                ]),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<ExpenseAssessmentCategory>(
                key: const Key('assessment-category'),
                initialValue: _category,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Assessment'),
                items: [
                  for (final c in ExpenseAssessmentCategory.values)
                    DropdownMenuItem(value: c, child: Align(alignment: Alignment.centerLeft, child: ExpenseCategoryPill(c, key: Key('assessment-option-${c.key}')))),
                ],
                onChanged: _saving ? null : (c) => _setCategory(c!),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  ExpenseCategoryPill(_category, key: const Key('assessment-selected-pill')),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_category.definition, style: small)),
                ]),
              ),
              if (_category.hasAvoidable)
                TextField(
                  key: const Key('assessment-avoidable'),
                  controller: _avoidable,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Avoidable amount (₹)',
                    helperText: _category == ExpenseAssessmentCategory.waste
                        ? 'The whole amount by default; reduce it if only part could have been avoided.'
                        : 'Only this explicit portion counts as potential savings (0 while still being assessed).',
                    helperMaxLines: 2,
                  ),
                ),
              TextField(key: const Key('assessment-reason'), controller: _reason, decoration: const InputDecoration(labelText: 'Reason (optional)')),
              TextField(key: const Key('assessment-note'), controller: _note, maxLines: 2, decoration: const InputDecoration(labelText: 'Management note')),
              TextField(key: const Key('assessment-action'), controller: _action, decoration: const InputDecoration(labelText: 'Corrective action (optional)')),
              DropdownButtonFormField<ExpenseActionStatus>(
                key: const Key('assessment-action-status'),
                initialValue: _actionStatus,
                decoration: const InputDecoration(labelText: 'Corrective action status'),
                items: [for (final s in ExpenseActionStatus.values) DropdownMenuItem(value: s, child: Text(s.label))],
                onChanged: _saving ? null : (s) => setState(() => _actionStatus = s!),
              ),
              if (_error case final err?)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(err, key: const Key('assessment-error'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
              if (widget.current != null) ...[
                const SizedBox(height: 8),
                if (_history == null)
                  TextButton(key: const Key('assessment-history'), onPressed: _loadHistory, child: const Text('Show history'))
                else
                  for (final h in _history!)
                    Text(
                      '${h['action']} · ${(h['at'] as dynamic)?.toDate() == null ? '' : DateFormat('d MMM yyyy, h:mm a').format((h['at'] as dynamic).toDate() as DateTime)} · ${h['by'] ?? ''}'
                      '${h['after'] is Map ? ' → ${ExpenseAssessmentCategory.parse((h['after'] as Map)['assessmentCategory']).label}' : ''}',
                      style: small,
                    ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (widget.current != null)
          TextButton(key: const Key('assessment-remove'), onPressed: _saving ? null : _remove, child: const Text('Remove assessment')),
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(key: const Key('assessment-save'), onPressed: _saving ? null : _save, child: const Text('Save')),
      ],
    );
  }
}

/// Add or edit a monthly category target. Pops true when saved.
class ExpenseTargetDialog extends StatefulWidget {
  const ExpenseTargetDialog({super.key, required this.service, required this.role, required this.categories, this.current, this.initialMonth});

  final ExpenseEfficiencyService service;
  final String role;

  /// Expense categories: id → name.
  final Map<String, String> categories;
  final ExpenseTarget? current;
  final String? initialMonth;

  @override
  State<ExpenseTargetDialog> createState() => _ExpenseTargetDialogState();
}

class _ExpenseTargetDialogState extends State<ExpenseTargetDialog> {
  late String? _categoryId = widget.current?.categoryId;
  late final _amount = TextEditingController(text: widget.current == null ? '' : _num(widget.current!.monthlyAmount));
  late final _start = TextEditingController(text: widget.current?.startMonth ?? widget.initialMonth ?? '');
  late final _end = TextEditingController(text: widget.current?.endMonth ?? '');
  late final _note = TextEditingController(text: widget.current?.note ?? '');
  late bool _active = widget.current?.isActive ?? true;
  String? _error;
  bool _saving = false;

  static String _num(double v) => !v.isFinite ? '' : v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  @override
  void dispose() {
    for (final c in [_amount, _start, _end, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final id = _categoryId;
    final t = ExpenseTarget(
      id: widget.current?.id ?? '',
      schoolId: widget.service.schoolId,
      categoryId: id ?? '',
      categoryName: id == null ? '' : widget.categories[id] ?? widget.current?.categoryName ?? id,
      monthlyAmount: double.tryParse(_amount.text.trim()) ?? double.nan,
      startMonth: _start.text.trim(),
      endMonth: _end.text.trim(),
      note: _note.text,
      isActive: _active,
    );
    if (t.error case final e?) return setState(() => _error = e);
    setState(() => _saving = true);
    try {
      await widget.service.saveTarget(requesterRole: widget.role, target: t);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e'.replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cats = {...widget.categories, if (widget.current case final c?) c.categoryId: c.categoryName};
    return AlertDialog(
      title: Text(widget.current == null ? 'Add Monthly Target' : 'Edit Monthly Target'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              key: const Key('target-category'),
              initialValue: _categoryId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Expense category'),
              items: [for (final MapEntry(:key, :value) in cats.entries) DropdownMenuItem(value: key, child: Text(value))],
              onChanged: widget.current != null ? null : (v) => setState(() => _categoryId = v),
            ),
            TextField(
              key: const Key('target-amount'),
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Monthly target (₹)', helperText: 'Per month; a quarter or year adds up each month’s target.'),
            ),
            TextField(key: const Key('target-start'), controller: _start, decoration: const InputDecoration(labelText: 'Start month (YYYY-MM)')),
            TextField(key: const Key('target-end'), controller: _end, decoration: const InputDecoration(labelText: 'End month (YYYY-MM, optional)')),
            TextField(key: const Key('target-note'), controller: _note, decoration: const InputDecoration(labelText: 'Reason / note')),
            SwitchListTile(
              key: const Key('target-active'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Active'),
              value: _active,
              onChanged: (v) => setState(() => _active = v),
            ),
            const Text('A target is planning data only: it never changes expenses, balances or Profit / Loss.', style: TextStyle(fontSize: 12)),
            if (_error case final err?)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(err, key: const Key('target-error'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(key: const Key('target-save'), onPressed: _saving ? null : _save, child: const Text('Save')),
      ],
    );
  }
}
