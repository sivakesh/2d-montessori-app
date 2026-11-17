import 'package:cloud_firestore/cloud_firestore.dart';

import '../../admin/ui/admin_attendance_management_screen.dart' show computeAttendanceSummary, resolveAttendanceDisplayStatus;
import '../../attendance/data/attendance_service.dart';
import '../../fees/bill_issuance/fee_bill_models.dart';
import '../../fees/models/fee_receipt_model.dart';
import '../../fees/models/student_fee_assignment_model.dart';
import '../../fees/services/fee_service.dart';
import '../../leave/models/leave_request_model.dart';
import 'parent_file_service.dart';
import 'parent_projections.dart' show parentAttendanceRecord;
import 'parent_service.dart';

/// One child's attendance over the recent window, as the existing parent
/// attendance history computes it: the same 30 days
/// (AttendanceService.getAttendanceHistoryForEntity, one document per day),
/// the same counts ([computeAttendanceSummary]) and the same rule for an
/// approved leave on an unmarked day ([resolveAttendanceDisplayStatus]).
/// No percentage: the app has no established attendance-rate calculation.
class ParentAttendanceSnapshot {
  const ParentAttendanceSnapshot({
    required this.today,
    required this.todayStatus,
    required this.present,
    required this.absent,
    required this.onLeave,
    required this.notMarked,
    required this.days,
    this.lastMarkedStatus,
    this.lastMarkedDate,
  });

  /// Today's record in its parent-facing form (photo by Storage path only;
  /// null when today isn't marked).
  final Map<String, dynamic>? today;

  /// 'present', 'absent', 'on_leave' or 'not_marked'.
  final String todayStatus;
  final int present, absent, onLeave, notMarked, days;

  /// The most recent day marked Present or Absent in the window.
  final String? lastMarkedStatus;
  final String? lastMarkedDate;

  bool get hasAnyRecord => present + absent > 0;

  /// Builds the snapshot from the history's records (newest first, one per
  /// day, `not_marked` for a day without one) and the child's leave
  /// requests.
  factory ParentAttendanceSnapshot.from(List<Map<String, dynamic>> records, {required List<LeaveRequestModel> leaveRequests}) {
    final approved = [for (final r in leaveRequests) if (r.status == LeaveStatus.approved) r];
    bool onApprovedLeave(String dateKey) {
      final day = DateTime.tryParse(dateKey);
      if (day == null) return false;
      // The same day-coverage rule as LeaveService.getStudentIdsOnApprovedLeave.
      return approved.any((r) {
        final start = DateTime(r.startDate.year, r.startDate.month, r.startDate.day);
        final end = DateTime(r.endDate.year, r.endDate.month, r.endDate.day);
        return !day.isBefore(start) && !day.isAfter(end);
      });
    }

    final statuses = [
      for (final r in records)
        resolveAttendanceDisplayStatus(rawStatus: r['status']?.toString() ?? 'not_marked', isOnApprovedLeave: onApprovedLeave(r['date']?.toString() ?? '')),
    ];
    final summary = computeAttendanceSummary(statuses);
    final lastIndex = statuses.indexWhere((s) => s == 'present' || s == 'absent');
    final todayRaw = records.isEmpty ? null : records.first;
    return ParentAttendanceSnapshot(
      today: todayRaw == null || todayRaw['status'] == 'not_marked' ? null : parentAttendanceRecord(todayRaw),
      todayStatus: statuses.isEmpty ? 'not_marked' : statuses.first,
      present: summary.present,
      absent: summary.absent,
      onLeave: statuses.where((s) => s == 'on_leave').length,
      notMarked: summary.notMarked,
      days: summary.total,
      lastMarkedStatus: lastIndex < 0 ? null : statuses[lastIndex],
      lastMarkedDate: lastIndex < 0 ? null : records[lastIndex]['date']?.toString(),
    );
  }
}

/// Whether a child's supplementary bills could be shown, and if not why —
/// never collapsed into an empty list.
enum ParentBillsStatus {
  /// Read from the parent-safe copies ([ParentChildFinance.bills], maybe
  /// empty: no bills issued, or not yet copied for parents).
  loaded,

  /// This account has no parent access record yet (the school's parent
  /// access setup — Settings → Parent access → Apply — hasn't covered it),
  /// so the parent-safe bill copies can't be read.
  accessNotConfigured,

  /// The app's Father/Mother check refused (not this child's Father or
  /// Mother in the access record).
  notPermitted,

  /// Reading failed (e.g. `permission-denied` from the security rules, or
  /// the network): see [ParentChildFinance.billsError].
  failed,
}

/// A Father's or Mother's view of one child's money, kept as three separate
/// things: fee assignments (what is charged and still owed), payments
/// (actual collections, voided ones already removed), and supplementary
/// bills (documents issued against payments — never evidence of a payment).
/// Every amount is the stored one; nothing is recalculated beyond adding up
/// the child's own assignments, as the Fees screens already do.
class ParentChildFinance {
  const ParentChildFinance({required this.assignments, required this.payments, this.bills, this.billsStatus = ParentBillsStatus.loaded, this.billsError = ''});

  final List<StudentFeeAssignmentModel> assignments;

  /// Newest first; from the parent-safe copies (no remarks, collector or
  /// receipt PDF link — `pdfUrl`/`pdfPath` are always empty here).
  final List<FeeReceiptModel> payments;

  /// The child's supplementary bills from the parent-safe copies, newest
  /// first; null unless [billsStatus] is loaded.
  final List<FeeIssuedBill>? bills;
  final ParentBillsStatus billsStatus;

  /// Why reading the bills failed (error code and message), for
  /// [ParentBillsStatus.failed].
  final String billsError;

  double _sum(double Function(StudentFeeAssignmentModel a) f) => assignments.fold<double>(0, (t, a) => t + f(a));
  double get gross => _sum((a) => a.totalFee);
  double get discount => _sum((a) => a.discountAmount);
  double get net => _sum((a) => a.payableAmount);
  double get paid => _sum((a) => a.paidAmount);
  double get outstanding => _sum((a) => a.balanceAmount);

  /// The earliest due date of a fee that still has a balance.
  DateTime? get nextDue {
    final due = [for (final a in assignments) if (a.balanceAmount > 0 && a.dueDate != null) a.dueDate!]..sort();
    return due.isEmpty ? null : due.first;
  }

  FeeReceiptModel? get lastPayment => payments.isEmpty ? null : payments.first;
}

/// Everything the Parent Dashboard shows about one linked child, loaded
/// once per dashboard load and shared by the family overview and the
/// child's own view.
class ParentChildOverview {
  const ParentChildOverview({
    required this.child,
    this.attendance,
    this.attendanceFailed = false,
    this.finance,
    this.financeRestricted = false,
    this.financeFailed = false,
    this.pendingLeave = 0,
  });

  final LinkedChild child;
  final ParentAttendanceSnapshot? attendance;
  final bool attendanceFailed;

  /// Null when restricted, failed, or not loaded.
  final ParentChildFinance? finance;

  /// The parent may not see this child's money (not the Father or Mother,
  /// or refused by the security rules). Nothing financial was read.
  final bool financeRestricted;
  final bool financeFailed;

  /// The child's leave requests still waiting for the school.
  final int pendingLeave;
}

/// Loads [ParentChildOverview]s from the existing services and parent-safe
/// copies only — no new collection, query shape or calculation:
/// - attendance: AttendanceService.getAttendanceHistoryForEntity (the
///   child's own 30 day documents, the same reads as the History dialog);
/// - fees: the parent-safe fee copies (or, before the reconciliation, the
///   child's own assignments), exactly as ParentFeeHistoryView reads them;
/// - payments: the parent-safe payment copies (voided ones excluded);
/// - bills: ParentFileService.feeBillsForStudent (checks the parent's
///   access record for Father/Mother first).
///
/// Financial data is never requested for a child the parent may not see
/// (canViewFinance == false); a refusal by the security rules is treated
/// the same way. These checks are in the app; server enforcement depends on
/// the security rules (docs/parent_access_security.md).
class ParentFamilyOverviewLoader {
  ParentFamilyOverviewLoader({required this.parentService, required this.attendanceService, required this.feeService, this.fileService});

  final ParentService parentService;
  final AttendanceService attendanceService;
  final FeeService feeService;
  final ParentFileService? fileService;

  /// One child's overview. Never throws: each part that fails is marked as
  /// failed on its own, so the rest of the card (and the family) still shows.
  Future<ParentChildOverview> load(LinkedChild linked, {List<LeaveRequestModel> leaveRequests = const []}) async {
    final id = linked.student.id;
    final ownLeave = [for (final r in leaveRequests) if (r.studentId == id) r];

    ParentAttendanceSnapshot? attendance;
    var attendanceFailed = false;
    try {
      final records = await attendanceService.getAttendanceHistoryForEntity(entityType: 'student', entityId: id);
      attendance = ParentAttendanceSnapshot.from(records, leaveRequests: ownLeave);
    } catch (_) {
      attendanceFailed = true;
    }

    ParentChildFinance? finance;
    var restricted = linked.canViewFinance == false;
    var financeFailed = false;
    if (!restricted) {
      try {
        finance = await _finance(linked);
      } on FirebaseException catch (e) {
        if (e.code == 'permission-denied') {
          restricted = true;
        } else {
          financeFailed = true;
        }
      } catch (_) {
        financeFailed = true;
      }
    }

    return ParentChildOverview(
      child: linked,
      attendance: attendance,
      attendanceFailed: attendanceFailed,
      finance: finance,
      financeRestricted: restricted,
      financeFailed: financeFailed,
      pendingLeave: ownLeave.where((r) => r.status == LeaveStatus.pending).length,
    );
  }

  Future<ParentChildFinance> _finance(LinkedChild linked) async {
    final id = linked.student.id;
    final projections = parentService.projections;
    final assignments = linked.fromProjection ? await projections.getFeeAssignments(id) : await feeService.getAssignmentsForStudent(id);
    final rows = linked.fromProjection ? await projections.getPayments(id) : await projections.getLegacyPayments(id);
    final payments = [for (final r in rows) FeeReceiptModel.fromMap(r['receiptId']?.toString() ?? '', r)];
    // Bills are read on their own: a bill problem is reported as such and
    // never hides (or "restricts") the fees and payments above.
    final files = fileService;
    if (!linked.fromProjection || files == null) {
      return ParentChildFinance(assignments: assignments, payments: payments, billsStatus: ParentBillsStatus.accessNotConfigured);
    }
    try {
      return ParentChildFinance(assignments: assignments, payments: payments, bills: await files.feeBillsForStudent(id));
    } on ParentFileAccessDenied {
      return ParentChildFinance(assignments: assignments, payments: payments, billsStatus: ParentBillsStatus.notPermitted);
    } catch (e) {
      final error = e is FirebaseException ? '${e.code}${(e.message ?? '').isEmpty ? '' : ': ${e.message}'}' : '$e';
      return ParentChildFinance(assignments: assignments, payments: payments, billsStatus: ParentBillsStatus.failed, billsError: error);
    }
  }
}

/// Family-wide figures for the summary tiles — only what is available and
/// reliable: a value is null while any part of it is still loading or
/// failed, never a partial figure shown as complete, and never zero for
/// "unknown".
class ParentFamilyTotals {
  const ParentFamilyTotals({
    required this.children,
    required this.presentToday,
    required this.markedToday,
    required this.financeChildren,
    required this.outstanding,
    required this.financeIncomplete,
  });

  final int children;

  /// Children marked Present today, and children whose attendance is
  /// known; null until every child's attendance has loaded.
  final int? presentToday;
  final int? markedToday;

  /// Children whose fees this parent may see (Father or Mother). Zero: no
  /// financial figure is shown at all.
  final int financeChildren;

  /// Sum of those children's outstanding balances; null while loading or
  /// when any of them failed ([financeIncomplete]).
  final double? outstanding;
  final bool financeIncomplete;

  /// [children]: every linked child; [overviews]: those loaded so far, by
  /// student id.
  factory ParentFamilyTotals.of(List<LinkedChild> children, Map<String, ParentChildOverview> overviews) {
    final all = [for (final c in children) overviews[c.student.id]];
    final loaded = all.whereType<ParentChildOverview>().toList();
    final attendanceKnown = loaded.length == all.length && loaded.every((o) => o.attendance != null);
    // Whether the parent may see a child's fees is known from the access
    // record before anything loads; a refusal found while loading wins.
    final financeIds = {
      for (final c in children)
        if (overviews[c.student.id] case final o?) ...[if (!o.financeRestricted) c.student.id] else if (c.canViewFinance != false) c.student.id,
    };
    final finance = [for (final id in financeIds) overviews[id]];
    return ParentFamilyTotals(
      children: children.length,
      presentToday: attendanceKnown ? loaded.where((o) => o.attendance!.todayStatus == 'present').length : null,
      markedToday: attendanceKnown ? loaded.where((o) => o.attendance!.todayStatus != 'not_marked').length : null,
      financeChildren: financeIds.length,
      outstanding: finance.any((o) => o?.finance == null) ? null : finance.fold<double>(0, (t, o) => t + o!.finance!.outstanding),
      financeIncomplete: finance.any((o) => o != null && o.financeFailed),
    );
  }
}
