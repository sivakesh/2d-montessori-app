import 'package:flutter/material.dart';

import '../../../../core/widgets/responsive_dialog_shell.dart';
import '../../models/fee_discount_apply.dart';
import '../../models/fee_report.dart';
import '../../services/fee_service.dart';

/// Fees → Assignments → Apply Student Discounts to Existing Fees. Opens
/// with a read-only scan (FeeService.previewStudentDiscounts): counts,
/// totals and each assignment with the proposed change and why it is
/// included or excluded. Only the confirm button writes
/// (FeeService.applyStudentDiscounts), after a second confirmation; a
/// report then says what was applied, skipped or failed. Pops true when
/// anything was applied.
class FeeDiscountApplyDialog extends StatefulWidget {
  const FeeDiscountApplyDialog({super.key, required this.service});

  final FeeService service;

  static const title = 'Apply Student Discounts to Existing Fees';
  static const explanation = 'Apply each student\'s fee discount to their existing unpaid and partly paid assignments in its effective dates. '
      'Collected amounts and receipts are never changed; fully paid assignments are excluded.';

  @override
  State<FeeDiscountApplyDialog> createState() => _FeeDiscountApplyDialogState();
}

class _FeeDiscountApplyDialogState extends State<FeeDiscountApplyDialog> {
  static const _maxRows = 200;

  FeeDiscountApplyPreview? _preview;
  FeeDiscountApplyResult? _result;
  String? _error;
  bool _busy = true;
  bool _savedAny = false;

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _scan() async {
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      final preview = await widget.service.previewStudentDiscounts();
      if (mounted) setState(() => _preview = preview);
    } catch (e) {
      if (mounted) setState(() => _error = 'The scan could not be completed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _apply() async {
    final preview = _preview;
    if (preview == null || preview.eligible.isEmpty) return;
    final n = preview.eligible.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('discount-apply-confirm'),
        title: const Text('Apply student discounts?'),
        content: Text(
          'This reduces the payable and outstanding amounts of $n ${n == 1 ? 'assignment' : 'assignments'} by '
          '${FeeReport.money(preview.totalProposed)} in total. Collected amounts, receipts and Finance entries are not changed. '
          'Each assignment is checked again before it is changed.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(key: const Key('discount-apply-confirm-ok'), onPressed: () => Navigator.pop(context, true), child: const Text('Apply')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final result = await widget.service.applyStudentDiscounts(preview);
      if (!mounted) return;
      setState(() {
        _result = result;
        _savedAny = _savedAny || result.applied.isNotEmpty;
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Nothing more could be saved: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview, result = _result;
    return ResponsiveDialogShell.form(
      desktopWidth: 820,
      desktopHeight: 700,
      title: FeeDiscountApplyDialog.title,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(FeeDiscountApplyDialog.explanation),
          const SizedBox(height: 12),
          if (_busy) const LinearProgressIndicator(key: Key('discount-apply-busy')),
          if (_error case final e?) Text(e, key: const Key('discount-apply-error'), style: const TextStyle(color: Colors.red)),
          if (!_busy && result != null) ..._report(result) else if (!_busy && preview != null) ..._previewBody(preview),
        ],
      ),
      actions: [
        if (result != null && !_busy) TextButton(key: const Key('discount-apply-rescan'), onPressed: _scan, child: const Text('Scan Again')),
        TextButton(
          key: const Key('discount-apply-close'),
          onPressed: _busy ? null : () => Navigator.pop(context, _savedAny),
          child: Text(result == null ? 'Cancel' : 'Close'),
        ),
        if (result == null && preview != null && preview.eligible.isNotEmpty)
          FilledButton(
            key: const Key('discount-apply-apply'),
            onPressed: _busy ? null : _apply,
            child: Text('Apply to ${preview.eligible.length} ${preview.eligible.length == 1 ? 'Assignment' : 'Assignments'}'),
          ),
      ],
    );
  }

  List<Widget> _previewBody(FeeDiscountApplyPreview p) => [
        Text('Preview only: nothing has been changed.', key: const Key('discount-apply-preview-note'), style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        Text(
          'Assignments of students with a discount: ${p.items.length}. Proposed discounts: ${FeeReport.money(p.totalProposed)}.',
          key: const Key('discount-apply-totals'),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        for (final c in FeeDiscountApplyCategory.values)
          _group(
            'discount-apply-${c.name}',
            '${c.label}: ${p.count(c)} (gross ${FeeReport.money(p.gross(c))}, outstanding ${FeeReport.money(p.outstanding(c))})',
            p.of(c),
            initiallyExpanded: c == FeeDiscountApplyCategory.eligible,
          ),
        if (p.eligible.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('No assignment can be given a student discount automatically.', key: Key('discount-apply-none')),
          ),
      ];

  List<Widget> _report(FeeDiscountApplyResult r) => [
        Text(r.message, key: const Key('discount-apply-summary'), style: const TextStyle(fontWeight: FontWeight.w600)),
        Text('Total discount applied: ${FeeReport.money(r.totalApplied)}. Operation: ${r.operationId}', style: Theme.of(context).textTheme.bodySmall),
        if (r.failed.isNotEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('Not every update was saved. The failed assignments were left unchanged; scan again to retry them.',
                key: Key('discount-apply-partial'), style: TextStyle(color: Colors.red)),
          ),
        const SizedBox(height: 8),
        _group('discount-apply-applied', 'Applied: ${r.applied.length}', r.applied, initiallyExpanded: true),
        _group('discount-apply-skipped', 'Skipped, changed since the preview: ${r.skipped.length}', r.skipped, initiallyExpanded: r.skipped.isNotEmpty),
        _group('discount-apply-failed', 'Failed: ${r.failed.length}', r.failed, initiallyExpanded: r.failed.isNotEmpty),
      ];

  Widget _group(String key, String title, List<FeeDiscountApplyItem> items, {bool initiallyExpanded = false}) => ExpansionTile(
        key: Key(key),
        tilePadding: EdgeInsets.zero,
        initiallyExpanded: initiallyExpanded,
        title: Text(title, key: Key('$key-title')),
        children: [
          if (items.isEmpty) const ListTile(dense: true, title: Text('None')),
          for (final i in items.take(_maxRows)) _row(i),
          if (items.length > _maxRows) ListTile(dense: true, title: Text('Showing the first $_maxRows of ${items.length}.')),
        ],
      );

  Widget _row(FeeDiscountApplyItem i) {
    final a = i.assignment;
    final m = FeeReport.money;
    final eligible = i.category == FeeDiscountApplyCategory.eligible;
    final figures = [
      'Gross ${m(i.gross)}',
      'existing discount ${m(i.existingDiscount)}',
      'collected ${m(i.collected)}',
      'outstanding ${m(i.outstanding)}',
      if (eligible) ...['discount ${m(i.proposed)}', 'revised payable ${m(i.revisedPayable)}', 'revised outstanding ${m(i.revisedOutstanding)}'],
    ].join(' • ');
    return ListTile(
      key: Key('discount-apply-row-${a.id}'),
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text('${a.studentName.isEmpty ? a.studentId : a.studentName} (${a.studentId})'),
      subtitle: Text(
        '${a.className.isEmpty ? 'No class' : a.className} • ${a.feeStructureName} • ${i.periodLabel}\n$figures\n${i.reason}',
        key: Key('discount-apply-row-text-${a.id}'),
      ),
      isThreeLine: true,
    );
  }
}
