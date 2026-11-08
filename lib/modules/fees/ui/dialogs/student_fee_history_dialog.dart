import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/widgets/responsive_dialog_shell.dart';
import '../../../admin/settings/models/academic_year_model.dart';
import '../../models/fee_collection_record.dart';
import '../../models/fee_list_filter.dart';
import '../../models/fee_month.dart';
import '../../models/fee_structure_model.dart';
import '../../models/fee_student.dart';
import '../../models/student_fee_assignment_model.dart';
import '../../models/student_fee_history.dart';
import '../../services/fee_service.dart';
import '../../widgets/fee_payment_tile.dart';
import 'fee_receipt_view_dialog.dart';

String _date(DateTime? d) => d == null ? 'Date not recorded' : DateFormat('d MMM yyyy').format(d);

/// Fees -> Students -> View Fee History: one student's read-only fee
/// account for the selected academic year (or all years). Loaded only
/// when opened: the student's assignments (one `studentId` query), the
/// payments for those assignments (`assignmentId in` queries), and the
/// student's receipts with no assignment to go by. Writes nothing.
class StudentFeeHistoryDialog extends StatefulWidget {
  const StudentFeeHistoryDialog({
    super.key,
    required this.student,
    required this.className,
    required this.year,
    required this.service,
    this.structures = const [],
    this.today,
  });

  /// Today, for Overdue labels (defaults to now).
  final DateTime? today;

  final FeeStudent student;

  /// The student's current class name ('' when unknown).
  final String className;

  /// The academic year shown; null for All Academic Years.
  final AcademicYearModel? year;
  final FeeService service;

  /// For each assignment's components and whether it is Monthly.
  final List<FeeStructureModel> structures;

  /// How many assignments and timeline events are shown before "Show more".
  static const assignmentsPageSize = 10;
  static const timelinePageSize = 20;

  @override
  State<StudentFeeHistoryDialog> createState() => _StudentFeeHistoryDialogState();
}

class _StudentFeeHistoryDialogState extends State<StudentFeeHistoryDialog> {
  late final Future<StudentFeeHistory> _history = _load();
  int _assignmentsShown = StudentFeeHistoryDialog.assignmentsPageSize;
  int _eventsShown = StudentFeeHistoryDialog.timelinePageSize;

  Future<StudentFeeHistory> _load() async {
    final service = widget.service;
    final all = await service.getAssignmentsForStudent(widget.student.id);
    final inYear = all.where(FeeListFilter(year: widget.year).assignmentInYear).toList();
    final records = await service.getCollectionHistoryForAssignments([for (final a in inYear) a.id]);
    final unlinked = await service.getUnlinkedCollectionsForStudent(widget.student.id, {for (final a in all) a.id});
    return StudentFeeHistory.of(inYear, records, unlinked: unlinked);
  }

  FeeStructureModel? _structureOf(StudentFeeAssignmentModel a) => widget.structures.where((s) => s.id == a.feeStructureId).firstOrNull;

  /// "January 2027", "Month not recorded" for a Monthly structure's older
  /// assignment, or null.
  String? _monthOf(StudentFeeAssignmentModel a) {
    if (a.feeMonth.isNotEmpty) return FeeMonth.label(a.feeMonth);
    final s = _structureOf(a);
    return s != null && FeeMonth.isMonthlyStructure(s) ? 'Month not recorded' : null;
  }

  String get _yearLabel => widget.year?.name ?? 'All Academic Years';

  Widget _section(String title, List<Widget> children, {Key? key}) => Container(
        key: key,
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      );

  Future<void> _openReceipt(FeeCollectionRecord record) => showDialog<void>(
        context: context,
        builder: (_) => FeeReceiptViewDialog(receipt: record.receipt, service: widget.service, voided: record.isVoided),
      );

  Widget _studentSection() {
    final s = widget.student;
    return _section('Student', key: const Key('student-history-student'), [
      FeeDetailRow('Name', s.name, bold: true),
      FeeDetailRow('Admission No', s.admissionNo.isEmpty ? '-' : s.admissionNo),
      FeeDetailRow('Current class', widget.className.isEmpty ? '-' : widget.className),
      FeeDetailRow('Academic year', _yearLabel, key: const Key('student-history-year')),
      if (!s.isActive) const FeeDetailRow('Status', 'Inactive student'),
    ]);
  }

  Widget _summarySection(StudentFeeHistory h) {
    return _section('Financial summary', key: const Key('student-history-summary'), [
      FeeDetailRow('Total assigned', formatFeeMoney(h.totalAssigned), key: const Key('student-history-assigned')),
      FeeDetailRow('Total discounts', formatFeeMoney(h.totalDiscounts), key: const Key('student-history-discounts')),
      if ((h.totalStudentDiscounts * 100).round() > 0)
        FeeDetailRow('Of which student discounts', formatFeeMoney(h.totalStudentDiscounts), key: const Key('student-history-student-discounts')),
      FeeDetailRow('Net payable', formatFeeMoney(h.netPayable), key: const Key('student-history-payable'), bold: true),
      FeeDetailRow('Total collected', formatFeeMoney(h.totalCollected), key: const Key('student-history-collected'), color: Colors.green.shade800),
      FeeDetailRow(
        'Outstanding',
        formatFeeMoney(h.outstanding),
        key: const Key('student-history-outstanding'),
        bold: true,
        color: h.outstanding > 0 ? Colors.red.shade800 : null,
      ),
      const SizedBox(height: 4),
      Text(
        'Totals of the ${h.assignments.length} fee ${h.assignments.length == 1 ? 'assignment' : 'assignments'} below, '
        'each month of a monthly fee counted separately. Total collected and Outstanding are the amounts recorded on '
        'those assignments: voided payments are not included.',
        key: const Key('student-history-rules'),
        style: const TextStyle(fontSize: 12, color: Colors.black54),
      ),
      if (!h.paymentsMatchCollected)
        Padding(
          key: const Key('student-history-total-mismatch'),
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            'The completed payments listed below total ${formatFeeMoney(h.completedPaymentsTotal)}, but the assignments record '
            '${formatFeeMoney(h.totalCollected)} collected. The figures above are the recorded amounts; some payments may '
            'have been recorded before receipts were linked to assignments.',
            style: TextStyle(fontSize: 12, color: Colors.orange.shade900),
          ),
        ),
    ]);
  }

  Widget _assignmentCard(StudentFeeHistory h, StudentFeeAssignmentModel a) {
    final structure = _structureOf(a);
    final month = _monthOf(a);
    final payments = h.paymentsByAssignment[a.id]!;
    final components = structure?.components ?? const [];
    return Container(
      key: Key('student-history-assignment-${a.id}'),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(month == null ? a.feeStructureName : '${a.feeStructureName} • $month', style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          if (components.isNotEmpty)
            FeeDetailRow(
              'Components',
              [for (final c in components) '${c.name} ${formatFeeMoney(c.amount)} (${c.frequency}${c.termName == null || c.termName!.isEmpty ? '' : ', ${c.termName}'})'].join('\n'),
            ),
          FeeDetailRow('Academic year', a.academicYear.isEmpty ? '-' : a.academicYear),
          if (month != null)
            FeeDetailRow(
              'Fee month',
              month,
              key: Key('student-history-month-${a.id}'),
              color: a.feeMonth.isEmpty ? Colors.orange.shade900 : null,
            ),
          FeeDetailRow('Assigned on', _date(a.assignedAt), key: Key('student-history-assigned-on-${a.id}')),
          FeeDueDateRow(assignment: a, today: widget.today ?? DateTime.now(), keyPrefix: 'student-history'),
          FeeDetailRow('Original fee', formatFeeMoney(a.totalFee)),
          FeeDetailRow('Discount', formatFeeMoney(a.discountAmount)),
          if (a.studentDiscount case final snap?) ...[
            FeeDetailRow('Student discount', snap.label, key: Key('student-history-student-discount-${a.id}')),
            FeeDetailRow('Manual discount', formatFeeMoney(a.manualDiscountAmount)),
          ],
          FeeDetailRow('Net payable', formatFeeMoney(a.payableAmount)),
          FeeDetailRow('Total paid', formatFeeMoney(a.paidAmount), key: Key('student-history-paid-${a.id}')),
          FeeDetailRow('Outstanding', formatFeeMoney(a.balanceAmount), key: Key('student-history-balance-${a.id}')),
          FeeDetailRow('Status', switch (a.status) { 'paid' => 'Paid', 'partial' => 'Partly paid', 'unpaid' => 'Unpaid', final s => s }),
          const SizedBox(height: 8),
          Text('Payments (${payments.length})', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 6),
          if (payments.isEmpty)
            const Text('No payments recorded yet.', style: TextStyle(fontSize: 12, color: Colors.black54))
          else
            for (final r in payments)
              FeePaymentTile(record: r, expectedStudentId: a.studentId, expectedFeeMonth: a.feeMonth, onViewReceipt: () => _openReceipt(r)),
        ],
      ),
    );
  }

  Widget _moreButton(Key key, int shown, int total, VoidCallback onPressed) => Align(
        alignment: Alignment.centerLeft,
        child: TextButton(key: key, onPressed: onPressed, child: Text('Show more ($shown of $total shown)')),
      );

  Widget _assignmentsSection(StudentFeeHistory h) {
    final total = h.assignments.length;
    final shown = _assignmentsShown.clamp(0, total);
    return _section('Fee assignments', key: const Key('student-history-assignments'), [
      if (total == 0)
        Text('No fee assignments in $_yearLabel.', key: const Key('student-history-empty'), style: const TextStyle(color: Colors.black54))
      else ...[
        Text(
          '${h.paymentCount} ${h.paymentCount == 1 ? 'payment' : 'payments'}: completed payments total '
          '${formatFeeMoney(h.completedPaymentsTotal)}${h.cancelledCount == 0 ? '' : '; ${h.cancelledCount} cancelled, not counted'}.',
          key: const Key('student-history-payments-count'),
          style: const TextStyle(fontSize: 12, color: Colors.black54),
        ),
        const SizedBox(height: 10),
        for (final a in h.assignments.take(shown)) _assignmentCard(h, a),
        if (shown < total)
          _moreButton(const Key('student-history-assignments-more'), shown, total,
              () => setState(() => _assignmentsShown += StudentFeeHistoryDialog.assignmentsPageSize)),
      ],
    ]);
  }

  Widget _unlinkedSection(StudentFeeHistory h) {
    if (h.unlinked.isEmpty) return const SizedBox.shrink();
    final n = h.unlinked.length;
    final caption = '$n older ${n == 1 ? 'payment' : 'payments'} for this student ${n == 1 ? 'is' : 'are'} not linked to a fee '
        'assignment (no assignment recorded, or it was deleted), so ${n == 1 ? 'it has' : 'they have'} no academic year or month '
        'and ${n == 1 ? 'is' : 'are'} not counted in the totals above.';
    return _section('Payments not linked to an assignment', key: const Key('student-history-unlinked'), [
      Text(caption, style: TextStyle(fontSize: 12, color: Colors.orange.shade900)),
      const SizedBox(height: 8),
      if (widget.year == null)
        for (final r in h.unlinked) FeePaymentTile(record: r, expectedStudentId: widget.student.id, onViewReceipt: () => _openReceipt(r))
      else
        const Text('Choose All Academic Years to list them.', style: TextStyle(fontSize: 12, color: Colors.black54)),
    ]);
  }

  Widget _event(int i, FeeTimelineEvent e) {
    final a = e.assignment;
    final r = e.record;
    final month = _monthOf(a);
    final voided = e.kind == FeeTimelineKind.voided || e.kind == FeeTimelineKind.cancelledPayment;
    final details = [
      a.feeStructureName,
      if (month != null) 'Fee month: $month',
      if (r == null) 'Payable ${formatFeeMoney(a.payableAmount)}' else '${formatFeeMoney(r.receipt.amount)} • ${paymentModeLabel(r.receipt.paymentMode)}',
      if (r != null && r.receipt.receiptNo.isNotEmpty) r.receipt.receiptNo,
    ].join(' • ');
    return Padding(
      key: Key('student-history-event-$i'),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            switch (e.kind) {
              FeeTimelineKind.assigned => Icons.assignment_outlined,
              FeeTimelineKind.voided => Icons.block,
              _ => Icons.payments_outlined,
            },
            size: 18,
            color: voided ? Colors.red.shade700 : Colors.black54,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_date(e.date), key: Key('student-history-event-date-$i'), style: const TextStyle(fontSize: 12, color: Colors.black54)),
                Text(e.title, key: Key('student-history-event-title-$i'), style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: voided ? Colors.red.shade800 : null)),
                Text(details, key: Key('student-history-event-details-$i'), style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _timelineSection(StudentFeeHistory h) {
    final events = h.timeline;
    final shown = _eventsShown.clamp(0, events.length);
    return _section('Timeline', key: const Key('student-history-timeline'), [
      if (events.isEmpty)
        const Text('Nothing recorded yet.', style: TextStyle(color: Colors.black54))
      else ...[
        const Text(
          'Each event at its own recorded date: a fee month is the month a fee is for, not when it was paid.',
          style: TextStyle(fontSize: 12, color: Colors.black54),
        ),
        for (var i = 0; i < shown; i++) _event(i, events[i]),
        if (shown < events.length)
          _moreButton(const Key('student-history-timeline-more'), shown, events.length,
              () => setState(() => _eventsShown += StudentFeeHistoryDialog.timelinePageSize)),
      ],
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveDialogShell.form(
      key: const Key('student-history'),
      desktopWidth: 760,
      desktopHeight: 840,
      title: 'Student Fee History',
      content: FutureBuilder<StudentFeeHistory>(
        future: _history,
        builder: (context, snapshot) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _studentSection(),
            if (snapshot.hasError)
              const Text('The fee history could not be loaded. Close this and try again.', key: Key('student-history-error'), style: TextStyle(color: Colors.red))
            else if (!snapshot.hasData)
              const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
            else ...[
              _summarySection(snapshot.data!),
              _assignmentsSection(snapshot.data!),
              _unlinkedSection(snapshot.data!),
              _timelineSection(snapshot.data!),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(key: const Key('student-history-close'), onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
      ],
    );
  }
}
