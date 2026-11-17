import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/responsive_dialog_shell.dart';
import '../../admin/students/models/admin_student_model.dart';
import '../../calendar/models/calendar_event_model.dart';
import '../../calendar/ui/calendar_event_style.dart';
import '../../fees/bill_issuance/fee_bill_models.dart';
import '../../fees/bill_issuance/fee_bill_pdf.dart';
import '../../fees/models/amount_in_words.dart';
import '../../fees/models/fee_month.dart';
import '../../fees/models/fee_receipt_model.dart';
import '../../finance/widgets/finance_status_chip.dart';
import '../data/parent_family_overview.dart';
import '../data/parent_file_service.dart';
import 'parent_child_avatar.dart';

// Parent Dashboard Phase 1: the family overview's building blocks. They only
// display what ParentFamilyOverviewLoader loaded (existing services and
// parent-safe copies); none of them reads Firestore.

/// "₹12,500.00": amounts as the Fees module shows them (Indian grouping).
String parentMoney(double rupees) {
  final paise = (rupees * 100).round();
  return paise < 0 ? '-${billMoney(-paise)}' : billMoney(paise);
}

final _date = DateFormat('d MMM yyyy');
final _eventDate = DateFormat('EEE, d MMM');

String parentDate(DateTime? d) => d == null ? '' : _date.format(d);

/// A `yyyy-MM-dd` key as "5 Nov 2026" ('' when it isn't one).
String parentDateKey(String? key) => parentDate(DateTime.tryParse(key ?? ''));

/// "Class · Section", or just the class.
String parentClassLine(AdminStudentModel child, String className) =>
    [if (className.isNotEmpty && className != '-') className, if (child.section.trim().isNotEmpty) child.section.trim()].join(' · ');

/// (label, colour) for an attendance status as parents see it.
(String, Color) parentAttendanceStyle(String? status) => switch ((status ?? '').toLowerCase()) {
      'present' => ('Present', AppColors.secondary),
      'absent' => ('Absent', Colors.redAccent),
      'on_leave' => ('On leave', Colors.orange),
      _ => ('Not marked yet', Colors.grey),
    };

TextStyle get _sectionTitle => const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary);
const _muted = TextStyle(fontSize: 12, color: AppColors.textSecondary);

Card _card({required Widget child, EdgeInsets padding = const EdgeInsets.all(20), Key? key}) => Card(
      key: key,
      elevation: 0,
      margin: EdgeInsets.zero,
      color: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(padding: padding, child: child),
    );

/// The dashboard's greeting: who is signed in, that this is the family's
/// overview, when it was loaded, and the way to the notifications.
class ParentFamilyHeader extends StatelessWidget {
  const ParentFamilyHeader({super.key, required this.parentName, required this.childCount, required this.onOpenNotifications, this.updatedAt, this.viewingChild});

  static const notificationsKey = Key('parent-header-notifications');

  final String parentName;
  final int childCount;
  final VoidCallback onOpenNotifications;

  /// When the figures below were loaded (pull down to refresh).
  final DateTime? updatedAt;

  /// The child whose own dashboard a family is looking at, if any.
  final String? viewingChild;

  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    final greeting = hour < 12 ? 'Good morning' : hour < 17 ? 'Good afternoon' : 'Good evening';
    final name = parentName.trim().isNotEmpty ? parentName.trim() : 'there';
    final subtitle = viewingChild != null
        ? "$viewingChild's dashboard"
        : childCount > 1
        ? 'Your family overview · $childCount children'
        : childCount == 1
            ? "Here's what's happening with your child today."
            : 'Your family overview';
    return _card(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$greeting, $name', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                const SizedBox(height: 6),
                Text(subtitle, style: const TextStyle(fontSize: 14, color: AppColors.textSecondary)),
                if (updatedAt != null) ...[
                  const SizedBox(height: 4),
                  Text('Updated ${DateFormat('h:mm a').format(updatedAt!)} · pull down to refresh', style: _muted),
                ],
              ],
            ),
          ),
          IconButton(
            key: notificationsKey,
            tooltip: 'Notifications',
            onPressed: onOpenNotifications,
            icon: const Icon(Icons.notifications_outlined, color: AppColors.primary),
          ),
        ],
      ),
    );
  }
}

/// One family summary tile.
class ParentSummaryTile {
  const ParentSummaryTile({required this.key, required this.icon, required this.label, required this.value, this.caption = '', this.onTap});
  final Key key;
  final IconData icon;
  final String label, value, caption;
  final VoidCallback? onTap;
}

/// The family-wide figures as tiles, two or more per row (never a single
/// tall column on a phone).
class ParentFamilySummary extends StatelessWidget {
  const ParentFamilySummary({super.key, required this.tiles});

  final List<ParentSummaryTile> tiles;

  @override
  Widget build(BuildContext context) {
    if (tiles.isEmpty) return const SizedBox.shrink();
    const gap = 12.0, minTile = 120.0;
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      final columns = ((width + gap) ~/ (minTile + gap)).clamp(1, tiles.length);
      final tileWidth = (width - gap * (columns - 1)) / columns;
      // A last row with a single tile spans the row instead of leaving a gap.
      final lone = tiles.length % columns == 1 && columns > 1;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (var i = 0; i < tiles.length; i++)
            SizedBox(width: lone && i == tiles.length - 1 ? width : tileWidth, child: _Tile(tile: tiles[i])),
        ],
      );
    });
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.tile});
  final ParentSummaryTile tile;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: tile.key,
      color: AppColors.card,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: tile.onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(tile.icon, size: 18, color: AppColors.primary),
                const SizedBox(width: 6),
                Flexible(child: Text(tile.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
              ]),
              const SizedBox(height: 8),
              Text(tile.value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              if (tile.caption.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(tile.caption, maxLines: 2, overflow: TextOverflow.ellipsis, style: _muted),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Lays out one card per child: one column on a phone, two on a tablet,
/// three on a wide desktop — every child shown, none dropped.
class ParentChildCardGrid extends StatelessWidget {
  const ParentChildCardGrid({super.key, required this.cards});
  final List<Widget> cards;

  @override
  Widget build(BuildContext context) {
    const gap = 16.0;
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      final columns = width >= 1000 ? 3 : width >= 600 ? 2 : 1;
      final cardWidth = (width - gap * (columns - 1)) / columns;
      return Wrap(spacing: gap, runSpacing: gap, children: [for (final c in cards) SizedBox(width: cardWidth, child: c)]);
    });
  }
}

/// One child on the family overview: who they are, today's attendance and
/// the last 30 days, their fees (Father/Mother only), reminders, and the way
/// into the child's own dashboard. Each child keeps their own figures.
class ParentChildOverviewCard extends StatelessWidget {
  const ParentChildOverviewCard({
    super.key,
    required this.student,
    required this.className,
    required this.overview,
    required this.onOpen,
    this.photoPath = '',
    this.fileService,
    this.childNotices = 0,
    this.onPayments,
    this.onBills,
    this.onRetry,
  });

  static Key openKey(String studentId) => Key('parent-open-child-$studentId');
  static Key paymentsKey(String studentId) => Key('parent-child-payments-$studentId');
  static Key billsKey(String studentId) => Key('parent-child-bills-$studentId');
  static Key feesKey(String studentId) => Key('parent-child-fees-$studentId');

  final AdminStudentModel student;
  final String className, photoPath;
  final ParentFileService? fileService;

  /// Null while this child's details are loading.
  final ParentChildOverview? overview;

  /// Notices aimed at this child or their class (not school-wide ones).
  final int childNotices;
  final VoidCallback onOpen;
  final VoidCallback? onPayments, onBills, onRetry;

  @override
  Widget build(BuildContext context) {
    final o = overview;
    final classLine = parentClassLine(student, className);
    return _card(
      key: Key('parent-child-card-${student.id}'),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onOpen,
            child: Row(
              children: [
                ParentChildAvatar(name: student.name, studentId: student.id, photoPath: photoPath, photoUrl: student.profileImageUrl, radius: 24, fileService: fileService),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(student.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                      if (classLine.isNotEmpty) Text(classLine, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                      if (student.admissionNo.isNotEmpty) Text('Adm. No. ${student.admissionNo}', maxLines: 1, overflow: TextOverflow.ellipsis, style: _muted),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: AppColors.textSecondary),
              ],
            ),
          ),
          const Divider(height: 24),
          if (o == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: LinearProgressIndicator(minHeight: 3),
            )
          else ...[
            ParentAttendanceLine(attendance: o.attendance, failed: o.attendanceFailed, onRetry: onRetry),
            if (!o.financeRestricted) ...[
              const SizedBox(height: 12),
              if (o.financeFailed)
                _FailedLine(text: "Fees couldn't load.", onRetry: onRetry)
              else if (o.finance case final f?)
                ParentFeeFigures(finance: f, compact: true),
            ],
            if (o.pendingLeave > 0 || childNotices > 0) ...[
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 6, children: [
                if (o.pendingLeave > 0) FinanceStatusChip(label: '${o.pendingLeave} leave request${o.pendingLeave == 1 ? '' : 's'} pending', color: Colors.orange),
                if (childNotices > 0) FinanceStatusChip(label: '$childNotices notice${childNotices == 1 ? '' : 's'} for this child', color: AppColors.primary),
              ]),
            ],
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.tonalIcon(key: openKey(student.id), onPressed: onOpen, icon: const Icon(Icons.dashboard_outlined, size: 18), label: const Text('Open dashboard')),
              if (o?.finance != null && onPayments != null)
                TextButton(key: paymentsKey(student.id), onPressed: onPayments, child: const Text('Payments')),
              if (o?.finance != null && onBills != null) TextButton(key: billsKey(student.id), onPressed: onBills, child: Text(parentBillsLabel(o!.finance!))),
            ],
          ),
        ],
      ),
    );
  }
}

class _FailedLine extends StatelessWidget {
  const _FailedLine({required this.text, this.onRetry});
  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 4,
        children: [
          Text(text, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          if (onRetry != null) TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      );
}

/// Today's status and the last 30 days (present, absent, on leave), or an
/// error with a retry; no percentage (the app has no attendance-rate rule).
class ParentAttendanceLine extends StatelessWidget {
  const ParentAttendanceLine({super.key, required this.attendance, this.failed = false, this.onRetry});
  final ParentAttendanceSnapshot? attendance;
  final bool failed;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final a = attendance;
    if (failed || a == null) return _FailedLine(text: "Attendance couldn't load.", onRetry: onRetry);
    final (label, color) = parentAttendanceStyle(a.todayStatus);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          const Text('Today', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
          FinanceStatusChip(label: label, color: color),
        ]),
        const SizedBox(height: 6),
        Text(
          a.hasAnyRecord || a.onLeave > 0
              ? 'Last ${a.days} days: ${a.present} present · ${a.absent} absent · ${a.onLeave} on leave'
              : 'No attendance marked in the last ${a.days} days.',
          key: const Key('parent-attendance-30-days'),
          style: _muted,
        ),
        if (a.lastMarkedStatus != null && a.todayStatus == 'not_marked')
          Text('Last marked ${parentAttendanceStyle(a.lastMarkedStatus).$1.toLowerCase()} on ${parentDateKey(a.lastMarkedDate)}', style: _muted),
      ],
    );
  }
}

/// A child's fee figures, exactly as stored: net payable, paid and
/// outstanding, with the gross and the discount actually applied, the next
/// due date, and the last payment. Father/Mother only (never built for a
/// restricted child).
class ParentFeeFigures extends StatelessWidget {
  const ParentFeeFigures({super.key, required this.finance, this.compact = false});
  final ParentChildFinance finance;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final f = finance;
    if (f.assignments.isEmpty) return const Text('No fee assignments yet.', style: TextStyle(color: AppColors.textSecondary, fontSize: 13));
    final due = f.nextDue;
    final today = DateUtils.dateOnly(DateTime.now());
    final overdue = due != null && due.isBefore(today);
    final last = f.lastPayment;
    Widget amount(String label, double value, {bool emphasize = false}) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            const SizedBox(height: 2),
            Text(parentMoney(value), maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: emphasize ? Colors.redAccent : AppColors.textPrimary)),
          ]),
        );
    return Column(
      key: const Key('parent-fee-figures'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          amount('Net payable', f.net),
          const SizedBox(width: 8),
          amount('Paid', f.paid),
          const SizedBox(width: 8),
          amount('Outstanding', f.outstanding, emphasize: f.outstanding > 0),
        ]),
        const SizedBox(height: 6),
        Text('Gross ${parentMoney(f.gross)} · Discount ${parentMoney(f.discount)}', style: _muted),
        if (due != null)
          Text(overdue ? 'Overdue since ${parentDate(due)}' : 'Next due ${parentDate(due)}',
              style: TextStyle(fontSize: 12, color: overdue ? Colors.redAccent : AppColors.textSecondary, fontWeight: overdue ? FontWeight.w600 : FontWeight.normal)),
        if (compact)
          Text(
            last == null
                ? 'No payments recorded yet.'
                : 'Last payment ${parentMoney(last.amount)} on ${parentDate(last.paymentDate)}${last.paymentMode.isEmpty ? '' : ' (${last.paymentMode})'}',
            style: _muted,
          ),
      ],
    );
  }
}

/// A notice that some linked children couldn't be shown (no names: the
/// app doesn't have them).
class ParentUnavailableChildrenNotice extends StatelessWidget {
  const ParentUnavailableChildrenNotice({super.key, required this.count});
  final int count;

  @override
  Widget build(BuildContext context) => _card(
        key: const Key('parent-children-unavailable'),
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          const Icon(Icons.info_outline, color: AppColors.textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              count == 1
                  ? "One linked child's profile isn't available yet. Please contact the school office if this continues."
                  : "$count linked children's profiles aren't available yet. Please contact the school office if this continues.",
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ),
        ]),
      );
}

/// The child selector shared by the child's own screens: every linked
/// child with their class, the selected one highlighted, and (for a family)
/// the way back to the family overview.
class ParentChildSwitcher extends StatelessWidget {
  const ParentChildSwitcher({super.key, required this.children, required this.classNames, required this.selectedId, required this.onSelected, this.onFamilyOverview});

  static const familyOverviewKey = Key('parent-family-overview');

  final List<AdminStudentModel> children;
  final Map<String, String> classNames;
  final String selectedId;
  final ValueChanged<String> onSelected;
  final VoidCallback? onFamilyOverview;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (onFamilyOverview != null)
          TextButton.icon(key: familyOverviewKey, onPressed: onFamilyOverview, icon: const Icon(Icons.arrow_back, size: 18), label: const Text('Family overview')),
        if (children.length > 1)
          // A long name is ellipsised at 70% of the width, so on a narrow
          // phone the next child's chip still shows beside it (the row
          // scrolls for more); the full name is the chip's tooltip.
          LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final child in children)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        tooltip: child.name,
                        label: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.7),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(child.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                              if (parentClassLine(child, classNames[child.classId] ?? '') case final c when c.isNotEmpty)
                                Text(c, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                            ],
                          ),
                        ),
                        selected: child.id == selectedId,
                        onSelected: (_) => onSelected(child.id),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Published Parents/Public calendar items from today on, soonest first.
List<CalendarEventModel> upcomingParentEvents(List<CalendarEventModel> events, {DateTime? now}) {
  final today = DateUtils.dateOnly(now ?? DateTime.now());
  return [for (final e in events) if (!DateUtils.dateOnly(e.date).isBefore(today)) e]..sort((a, b) => a.date.compareTo(b.date));
}

/// The next few school calendar items, with the way to the full calendar.
class ParentUpcomingEvents extends StatelessWidget {
  const ParentUpcomingEvents({
    super.key,
    required this.events,
    required this.loading,
    required this.failed,
    required this.onOpenCalendar,
    required this.onOpenEvent,
    required this.onRetry,
    this.limit = 4,
  });

  static const viewCalendarKey = Key('parent-view-calendar');

  /// Already upcoming only ([upcomingParentEvents]).
  final List<CalendarEventModel> events;
  final bool loading, failed;
  final int limit;
  final VoidCallback onOpenCalendar, onRetry;
  final ValueChanged<CalendarEventModel> onOpenEvent;

  @override
  Widget build(BuildContext context) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Upcoming Events', style: _sectionTitle),
              TextButton(key: viewCalendarKey, onPressed: onOpenCalendar, child: const Text('View calendar')),
            ],
          ),
          const SizedBox(height: 4),
          if (loading)
            const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: LinearProgressIndicator(minHeight: 3))
          else if (failed)
            _FailedLine(text: "Couldn't load upcoming events.", onRetry: onRetry)
          else if (events.isEmpty)
            const Text('No upcoming events.', style: TextStyle(color: AppColors.textSecondary))
          else
            for (final e in events.take(limit)) ...[
              _EventRow(event: e, onTap: () => onOpenEvent(e)),
              const SizedBox(height: 8),
            ],
        ],
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event, required this.onTap});
  final CalendarEventModel event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = calendarEventTypeStyle(event.eventType);
    final time = [if ((event.startTime ?? '').isNotEmpty) event.startTime!, if ((event.endTime ?? '').isNotEmpty) event.endTime!].join(' – ');
    return Material(
      color: AppColors.background,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            CircleAvatar(radius: 18, backgroundColor: color.withValues(alpha: 0.12), child: Icon(icon, size: 18, color: color)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(event.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                Text([_eventDate.format(event.date), if (time.isNotEmpty) time, event.eventType].join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis, style: _muted),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// A child's payments — actual collections recorded by the school, never
/// bills. Payment details and references only; original receipt PDFs are
/// not offered to parents.
void showParentPaymentHistory(BuildContext context, {required String childName, required List<FeeReceiptModel> payments}) {
  showDialog<void>(
    context: context,
    builder: (_) => ResponsiveDialogShell.form(
      key: const Key('parent-payment-history'),
      desktopWidth: 560,
      desktopHeight: 640,
      title: 'Payment History',
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(childName, style: _sectionTitle),
          const SizedBox(height: 4),
          const Text('Payments recorded by the school. Original receipts are kept by the school office.', style: _muted),
          const SizedBox(height: 12),
          if (payments.isEmpty)
            const Text('No payments recorded yet.', style: TextStyle(color: AppColors.textSecondary))
          else
            for (final p in payments) ...[_PaymentTile(payment: p), const SizedBox(height: 10)],
        ],
      ),
    ),
  );
}

class _PaymentTile extends StatelessWidget {
  const _PaymentTile({required this.payment});
  final FeeReceiptModel payment;

  @override
  Widget build(BuildContext context) {
    final p = payment;
    final period = [if (p.feeStructureName.isNotEmpty) p.feeStructureName, if (FeeMonth.label(p.feeMonth).isNotEmpty) FeeMonth.label(p.feeMonth)].join(' · ');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(alignment: WrapAlignment.spaceBetween, spacing: 8, children: [
          Text(parentMoney(p.amount), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          Text(parentDate(p.paymentDate), style: _muted),
        ]),
        if (period.isNotEmpty) Text('For $period', style: const TextStyle(fontSize: 13)),
        Text(['Mode: ${p.paymentMode.isEmpty ? '-' : p.paymentMode}', if (p.referenceNo.isNotEmpty) 'Ref: ${p.referenceNo}'].join(' · '), style: _muted),
        if (p.receiptNo.isNotEmpty) Text('Receipt No. ${p.receiptNo}', style: _muted),
      ]),
    );
  }
}

/// A child's supplementary bills, issued by the school against payments
/// already made. A bill is a document, not a payment. Downloads come with
/// the Fees screens. When they can't be shown, the dialog says exactly why
/// ([ParentBillsStatus]) — an empty list only ever means none were found.
void showParentIssuedBills(BuildContext context, {required String childName, required ParentChildFinance finance, VoidCallback? onRetry, ParentBillDownloader? onDownload}) {
  // Active bills only (the data layer already leaves cancelled ones out;
  // this keeps the dialog safe for any older copy).
  final bills = finance.bills?.where((b) => b.status == FeeBillStatus.issued).toList();
  const muted = TextStyle(color: AppColors.textSecondary);
  showDialog<void>(
    context: context,
    builder: (dialogContext) => ResponsiveDialogShell.form(
      key: const Key('parent-issued-bills'),
      desktopWidth: 560,
      desktopHeight: 640,
      title: 'Issued Bills',
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(childName, style: _sectionTitle),
          const SizedBox(height: 4),
          const Text('Supplementary bills issued by the school for payments already made. A bill is not a payment. Tap a bill to see its details.', style: _muted),
          const SizedBox(height: 12),
          switch (finance.billsStatus) {
            ParentBillsStatus.accessNotConfigured => const Text(
                "Bills can't be shown yet: the school hasn't finished setting up parent access for your account. Please contact the school office.",
                key: Key('parent-bills-access-not-configured'),
                style: muted,
              ),
            ParentBillsStatus.notPermitted => const Text(
                "Your account isn't set up to view this child's bills. Please contact the school office.",
                key: Key('parent-bills-not-permitted'),
                style: muted,
              ),
            ParentBillsStatus.failed => Column(
                key: const Key('parent-bills-failed'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Couldn't load issued bills (${finance.billsError}). Please try again.", style: muted),
                  if (onRetry != null)
                    TextButton(
                      key: const Key('parent-bills-retry'),
                      onPressed: () {
                        Navigator.of(context).pop();
                        onRetry();
                      },
                      child: const Text('Retry'),
                    ),
                ],
              ),
            ParentBillsStatus.loaded => const SizedBox.shrink(),
          },
          if (finance.billsStatus == ParentBillsStatus.loaded && (bills ?? const []).isEmpty)
            const Text('No supplementary bills have been issued yet.', key: Key('parent-bills-none'), style: muted)
          else if (bills != null)
            for (final b in bills) ...[
              _BillTile(bill: b, onOpen: () => showParentBillDetail(dialogContext, bill: b, childName: childName, onDownload: onDownload)),
              const SizedBox(height: 10),
            ],
        ],
      ),
    ),
  );
}

/// "Issued bills (3)": active bills only; no count when they couldn't be
/// read.
String parentBillsLabel(ParentChildFinance finance) =>
    finance.billsStatus == ParentBillsStatus.loaded ? 'Issued bills (${parentActiveBillCount(finance)})' : 'Issued bills';

/// The active bills a [finance] shows to parents (for counts on buttons).
int parentActiveBillCount(ParentChildFinance finance) => finance.bills?.where((b) => b.status == FeeBillStatus.issued).length ?? 0;

/// One active bill in the list: the whole card opens its details.
class _BillTile extends StatelessWidget {
  const _BillTile({required this.bill, required this.onOpen});
  final FeeIssuedBill bill;
  final VoidCallback onOpen;

  static Key keyFor(String billId) => Key('parent-bill-$billId');

  @override
  Widget build(BuildContext context) {
    final b = bill;
    return Semantics(
      button: true,
      label: 'Open bill ${b.billNo}',
      child: Material(
        key: keyFor(b.id),
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Text(b.billNo, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                    FinanceStatusChip(label: FeeBillStatus.issued.label, color: AppColors.secondary),
                  ]),
                  const SizedBox(height: 4),
                  Text(['Billing month: ${_billingMonth(b)}', 'Issued ${parentDate(b.documentDate)}'].join(' · '), style: _muted),
                  Text(
                    'Gross ${billMoney(b.line.grossPaise)} · Adjustment ${billMoney(b.line.adjustmentPaise)} · Net ${billMoney(b.line.netPaise)}',
                    style: const TextStyle(fontSize: 13),
                  ),
                ]),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, color: AppColors.textSecondary),
            ]),
          ),
        ),
      ),
    );
  }
}

String _billingMonth(FeeIssuedBill b) => FeeMonth.label(b.line.billingMonth).isEmpty ? b.line.billingMonth : FeeMonth.label(b.line.billingMonth);

/// Downloads an active bill's PDF for the signed-in parent
/// (ParentFileService.downloadFeeBillById).
typedef ParentBillDownloader = Future<void> Function(FeeIssuedBill bill);

/// One active supplementary bill's details, read-only: the same rows the
/// bill PDF prints (FeeBillPdf.studentRows / billRows — including its
/// parent-name choice), the net amount with "(GST Included)" when chosen,
/// and the school's GSTIN when the bill carries one. [onDownload] offers
/// "Download PDF". Closing returns to the Issued Bills list.
void showParentBillDetail(BuildContext context, {required FeeIssuedBill bill, required String childName, ParentBillDownloader? onDownload}) {
  showDialog<void>(context: context, builder: (_) => _BillDetail(bill: bill, onDownload: onDownload));
}

class _BillDetail extends StatefulWidget {
  const _BillDetail({required this.bill, this.onDownload});
  final FeeIssuedBill bill;
  final ParentBillDownloader? onDownload;

  @override
  State<_BillDetail> createState() => _BillDetailState();
}

class _BillDetailState extends State<_BillDetail> {
  bool _busy = false;
  String? _message;
  bool _failed = false;

  Future<void> _download() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await widget.onDownload!(widget.bill);
      if (mounted) {
        setState(() {
          _failed = false;
          _message = 'PDF of ${widget.bill.billNo} downloaded.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _failed = true;
          _message = e is ParentFileAccessDenied
              ? "This bill can't be downloaded: ${e.reason}"
              : "Couldn't create the PDF. Please check your connection and try again. (${'$e'.replaceFirst('Bad state: ', '')})";
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.bill;
    Widget row(String label, String value, {Key? key}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Wrap(
            key: key,
            spacing: 12,
            runSpacing: 2,
            alignment: WrapAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            ],
          ),
        );
    return ResponsiveDialogShell.form(
      key: const Key('parent-bill-detail'),
      desktopWidth: 540,
      desktopHeight: 680,
      title: 'Bill details',
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(12)),
            child: const Text(
              'Supplementary bill document for a payment already collected. This bill is not a payment receipt.',
              key: Key('parent-bill-detail-notice'),
              style: TextStyle(fontSize: 13),
            ),
          ),
          const SizedBox(height: 8),
          row('Bill Reference', b.billNo, key: const Key('parent-bill-detail-reference')),
          row('Issue Date', parentDate(b.documentDate)),
          const Divider(height: 20),
          for (final (label, value) in FeeBillPdf.studentRows(b)) row(label, value),
          const Divider(height: 20),
          for (final (label, value) in FeeBillPdf.billRows(b)) row(label, value),
          row('Net Bill Amount', FeeBillPdf.netLabel(b), key: const Key('parent-bill-detail-net')),
          row('Amount in Words', IndianAmount.words(b.line.netPaise)),
          if (b.school.gstin.trim().isNotEmpty) row('GSTIN', b.school.gstin.trim()),
          row('Status', FeeBillStatus.issued.label),
          if (widget.onDownload != null) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                key: const Key('parent-bill-download'),
                onPressed: _busy ? null : _download,
                icon: _busy
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.picture_as_pdf_outlined, size: 18),
                label: Text(_busy ? 'Preparing PDF…' : 'Download PDF'),
              ),
            ),
          ],
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _message!,
                key: const Key('parent-bill-download-message'),
                style: TextStyle(fontSize: 13, color: _failed ? Colors.red.shade800 : AppColors.secondary),
              ),
            ),
        ],
      ),
    );
  }
}
