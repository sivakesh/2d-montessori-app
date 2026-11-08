import 'package:flutter/material.dart';

import '../../../../core/widgets/responsive_dialog_shell.dart';
import '../../models/fee_due_backfill.dart';
import '../../models/fee_due_date.dart';
import '../../models/fee_month.dart';
import '../../models/student_fee_assignment_model.dart';
import '../../services/fee_service.dart';

/// Fees → Assignments → Set Missing Due Dates. Opens with a read-only scan
/// (FeeService.previewMissingDueDates) and its counts and records; only
/// the confirm button writes (FeeService.applyMissingDueDates), and then a
/// report says what was saved, skipped or failed and what still needs a
/// date. Pops true when any due date was saved.
class FeeDueBackfillDialog extends StatefulWidget {
  const FeeDueBackfillDialog({super.key, required this.service, this.onEdit});

  final FeeService service;

  /// Opens an assignment for the administrator to set its date by hand;
  /// the scan runs again afterwards.
  final Future<void> Function(StudentFeeAssignmentModel assignment)? onEdit;

  static const explanation =
      'Set due dates on existing assignments using their fee structure\'s configured due-date settings. Existing due dates will not be changed.';

  @override
  State<FeeDueBackfillDialog> createState() => _FeeDueBackfillDialogState();
}

class _FeeDueBackfillDialogState extends State<FeeDueBackfillDialog> {
  /// Rows listed per group; the count always shows the full number.
  static const _maxRows = 200;

  FeeDueBackfillPreview? _preview;
  FeeDueBackfillResult? _result;
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
      final preview = await widget.service.previewMissingDueDates();
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
    setState(() => _busy = true);
    try {
      final result = await widget.service.applyMissingDueDates(preview);
      if (!mounted) return;
      setState(() {
        _result = result;
        _savedAny = _savedAny || result.updated.isNotEmpty;
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Nothing more could be saved: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit(StudentFeeAssignmentModel a) async {
    await widget.onEdit?.call(a);
    _savedAny = true; // the screen reloads either way
    if (mounted) await _scan();
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview, result = _result;
    return ResponsiveDialogShell.form(
      desktopWidth: 760,
      desktopHeight: 680,
      title: 'Set Missing Due Dates',
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(FeeDueBackfillDialog.explanation),
          const SizedBox(height: 12),
          if (_busy) const LinearProgressIndicator(key: Key('due-backfill-busy')),
          if (_error case final e?) Text(e, key: const Key('due-backfill-error'), style: const TextStyle(color: Colors.red)),
          if (!_busy && result != null) ..._report(result) else if (!_busy && preview != null) ..._previewBody(preview),
        ],
      ),
      actions: [
        if (result != null && !_busy) TextButton(key: const Key('due-backfill-rescan'), onPressed: _scan, child: const Text('Scan Again')),
        TextButton(
          key: const Key('due-backfill-close'),
          onPressed: _busy ? null : () => Navigator.pop(context, _savedAny),
          child: Text(result == null ? 'Cancel' : 'Close'),
        ),
        if (result == null && preview != null && preview.eligible.isNotEmpty)
          FilledButton(
            key: const Key('due-backfill-confirm'),
            onPressed: _busy ? null : _apply,
            child: Text('Set ${preview.eligible.length} Due ${preview.eligible.length == 1 ? 'Date' : 'Dates'}'),
          ),
      ],
    );
  }

  List<Widget> _previewBody(FeeDueBackfillPreview p) => [
        Text('Preview only: nothing has been changed. Assignments that already have a due date will remain unchanged.',
            key: const Key('due-backfill-unchanged'), style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        Text('Total assignments scanned: ${p.scanned}', key: const Key('due-backfill-count-scanned'), style: const TextStyle(fontWeight: FontWeight.w600)),
        for (final c in FeeDueBackfillCategory.values)
          _group('due-backfill-${c.name}', '${c.label}: ${p.count(c)}', p.of(c), editable: c.needsAttention),
        if (p.eligible.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('No assignment can be given a due date automatically.', key: Key('due-backfill-none')),
          ),
      ];

  List<Widget> _report(FeeDueBackfillResult r) => [
        Text(r.message, key: const Key('due-backfill-summary'), style: const TextStyle(fontWeight: FontWeight.w600)),
        if (r.failed.isNotEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('Not every update was saved. The failed records were left unchanged; you can scan again and retry.',
                key: Key('due-backfill-partial'), style: TextStyle(color: Colors.red)),
          ),
        const SizedBox(height: 8),
        _group('due-backfill-updated', 'Successfully updated: ${r.updated.length}', r.updated),
        _group('due-backfill-had', 'Skipped, a due date already existed: ${r.alreadyHadDate.length}', r.alreadyHadDate),
        _group('due-backfill-changed', 'Skipped, the record changed or disappeared: ${r.changed.length}', r.changed),
        _group('due-backfill-failed', 'Failed updates: ${r.failed.length}', r.failed),
        _group('due-backfill-attention', 'Still requiring manual review: ${r.stillNeedAttention.length}', r.stillNeedAttention,
            editable: true, initiallyExpanded: r.stillNeedAttention.isNotEmpty),
      ];

  Widget _group(String key, String title, List<FeeDueBackfillItem> items, {bool editable = false, bool initiallyExpanded = false}) {
    return ExpansionTile(
      key: Key(key),
      tilePadding: EdgeInsets.zero,
      initiallyExpanded: initiallyExpanded,
      title: Text(title, key: Key('$key-title')),
      children: [
        if (items.isEmpty) const ListTile(dense: true, title: Text('None')),
        for (final i in items.take(_maxRows)) _row(i, editable: editable),
        if (items.length > _maxRows) ListTile(dense: true, title: Text('Showing the first $_maxRows of ${items.length}.')),
      ],
    );
  }

  Widget _row(FeeDueBackfillItem i, {required bool editable}) {
    final a = i.assignment;
    final month = FeeMonth.label(a.feeMonth);
    final details = [
      a.feeStructureName.isEmpty ? 'No fee structure name' : a.feeStructureName,
      a.academicYear.isEmpty ? 'Academic year not recorded' : a.academicYear,
      if (month.isNotEmpty) month else if (a.feeMonth.isNotEmpty) 'Fee month "${a.feeMonth}"',
    ].join(' • ');
    final date = i.proposedDate;
    final outcome = date != null ? 'Due date: ${FeeDueDate.label(date)}${i.reason.startsWith('Recalculated') ? ' — ${i.reason}' : ''}' : i.reason;
    return ListTile(
      key: Key('due-backfill-row-${a.id}'),
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(a.studentName.isEmpty ? a.studentId : a.studentName),
      subtitle: Text('$details\n$outcome', key: Key('due-backfill-row-text-${a.id}')),
      isThreeLine: true,
      trailing: editable && i.category != FeeDueBackfillCategory.structureMissing && widget.onEdit != null && !_busy
          ? TextButton(key: Key('due-backfill-edit-${a.id}'), onPressed: () => _edit(a), child: const Text('Set Date'))
          : null,
    );
  }
}
