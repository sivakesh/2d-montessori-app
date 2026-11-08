import 'package:intl/intl.dart';

import '../../admin/students/models/admission_date.dart';
import 'fee_due_date.dart';
import 'fee_list_filter.dart';
import 'fee_month.dart';
import 'fee_receipt_model.dart';
import 'fee_student.dart';
import 'student_fee_assignment_model.dart';

/// Fees → Reports: the Student Monthly Fee Statement and the All Students
/// – Fee Collection and Outstanding Report, built once from the records
/// and shown on screen and in the PDFs from this same model (so the two
/// always agree). Read-only: nothing here writes.
///
/// Rules:
/// - Amounts come from each assignment as recorded: assigned `totalFee`,
///   `discountAmount`, payable `payableAmount`, collected `paidAmount`,
///   outstanding `balanceAmount` (FeeService keeps these, including when a
///   payment is voided). `discountAmount` is the total discount; its
///   student-discount part comes from the assignment's own snapshot
///   (`studentDiscount`), never the student's current configuration, and
///   the rest is manual. A discount is counted once, in its own fee month. Receipts are listed beside them; when the
///   receipts don't add up to the recorded paid amount a reconciliation
///   warning is shown and no figure is changed.
/// - Fee Month is the assignment's own `feeMonth`; Payment Date is the
///   receipt's `paymentDate`. Neither stands in for the other.
/// - A voided receipt is listed as Cancelled and never counted.
/// - Term, One-time and mixed fees (no fee month) are a separate section;
///   a Monthly assignment with no month recorded is in "Month not
///   recorded"; neither is given a month.
/// - A receipt whose assignment can't be found is listed as unlinked,
///   never attached to an assignment and never counted.

/// A receipt with whether it has been voided (`isDeleted`).
class FeeReportPayment {
  const FeeReportPayment(this.receipt, {this.voided = false});
  final FeeReceiptModel receipt;
  final bool voided;
}

/// Everything the reports read: one query per collection.
class FeeReportData {
  const FeeReportData({required this.assignments, required this.payments});

  /// Live (not deleted) assignments, including older ones without
  /// `assignedAt`.
  final List<StudentFeeAssignmentModel> assignments;

  /// Every receipt, voided ones included.
  final List<FeeReportPayment> payments;
}

enum FeePaymentStatus {
  paid('Paid'),
  partial('Partially Paid'),
  unpaid('Not Paid'),
  none('No assignments');

  const FeePaymentStatus(this.label);
  final String label;

  static FeePaymentStatus of(double payable, double collected, double outstanding) {
    // Nothing outstanding (including a fee discounted to zero): Paid.
    if (_cents(outstanding) <= 0) return paid;
    return _cents(collected) > 0 ? partial : unpaid;
  }
}

int _cents(double v) => (v * 100).round();

/// The report's filters, applied the same way on screen and in the PDF.
class FeeReportFilter {
  const FeeReportFilter({required this.base, this.search = '', this.status, this.admittedFrom, this.admittedTo});

  /// Academic Year, Class (the student's current class), Student and Fee
  /// Month, shared with the Fees screen (FeeListFilter).
  final FeeListFilter base;

  /// Name or admission number, any part, any case.
  final String search;

  /// null: All.
  final FeePaymentStatus? status;

  /// Admission-date range, both ends included; when either is set, a
  /// student without an admission date is not shown.
  final DateTime? admittedFrom, admittedTo;

  bool get hasAdmissionRange => admittedFrom != null || admittedTo != null;
}

/// One row of a statement table: a payment, or "Not paid" when the fee has
/// no completed payment, with the fee's totals repeated on every row.
class FeeStatementRow {
  const FeeStatementRow({
    required this.line,
    this.payment,
    required this.status,
  });

  final FeeReportLine line;

  /// null: the "Not paid" row.
  final FeeReportPayment? payment;
  final String status;

  bool get voided => payment?.voided ?? false;
  double get amount => payment == null || voided ? 0 : payment!.receipt.amount;
}

/// One assignment with its receipts.
class FeeReportLine {
  FeeReportLine(this.assignment, List<FeeReportPayment> payments)
      : payments = [...payments]..sort((a, b) => (a.receipt.paymentDate ?? DateTime(0)).compareTo(b.receipt.paymentDate ?? DateTime(0)));

  final StudentFeeAssignmentModel assignment;

  /// Sorted by payment date; voided ones included (marked).
  final List<FeeReportPayment> payments;

  double get assigned => assignment.totalFee;
  double get discount => assignment.discountAmount;

  /// The parts of [discount]: the student's global discount (from the
  /// assignment's own snapshot) and any manual one.
  double get studentDiscount => assignment.studentDiscountAmount;
  double get manualDiscount => assignment.manualDiscountAmount;
  double get payable => assignment.payableAmount;
  double get paid => assignment.paidAmount;
  double get outstanding => assignment.balanceAmount;
  double get receiptsTotal => payments.where((p) => !p.voided).fold(0.0, (s, p) => s + p.receipt.amount);

  FeePaymentStatus get status => FeePaymentStatus.of(payable, paid, outstanding);

  String get feeMonthLabel => FeeMonth.label(assignment.feeMonth);

  /// Why the recorded figures and the receipts disagree, or null.
  String? get reconciliationWarning {
    final name = '${assignment.feeStructureName}${feeMonthLabel.isEmpty ? '' : ' ($feeMonthLabel)'}';
    if (_cents(receiptsTotal) != _cents(paid)) {
      return '$name: receipts total ${FeeReport.money(receiptsTotal)} but the recorded paid amount is ${FeeReport.money(paid)}. Figures are shown as recorded.';
    }
    if (_cents(paid + outstanding) != _cents(payable)) {
      return '$name: paid ${FeeReport.money(paid)} plus outstanding ${FeeReport.money(outstanding)} does not equal payable ${FeeReport.money(payable)}. Figures are shown as recorded.';
    }
    return null;
  }

  List<FeeStatementRow> get rows => [
        for (final p in payments) FeeStatementRow(line: this, payment: p, status: p.voided ? 'Cancelled (voided)' : 'Completed'),
        if (!payments.any((p) => !p.voided)) FeeStatementRow(line: this, status: 'Not paid'),
      ];
}

/// A student's statement for the filtered period.
class FeeStudentStatement {
  FeeStudentStatement({
    required this.student,
    required this.className,
    required this.monthly,
    required this.nonMonthly,
    required this.noMonth,
    required this.unlinked,
    this.recordMissing = false,
  });

  final FeeStudent student;
  final String className;

  /// By fee month, then structure.
  final List<FeeReportLine> monthly;

  /// Term, One-time and mixed fees.
  final List<FeeReportLine> nonMonthly;

  /// Monthly assignments with no month recorded.
  final List<FeeReportLine> noMonth;

  /// Receipts for this student whose assignment can't be found: listed,
  /// never counted.
  final List<FeeReportPayment> unlinked;

  /// Only known from assignments: no `students` record was found.
  final bool recordMissing;

  List<FeeReportLine> get lines => [...monthly, ...nonMonthly, ...noMonth];
  bool get hasAssignments => lines.isNotEmpty;

  double get assigned => _sum((l) => l.assigned);
  double get discounts => _sum((l) => l.discount);
  double get studentDiscounts => _sum((l) => l.studentDiscount);
  double get manualDiscounts => _sum((l) => l.manualDiscount);
  double get payable => _sum((l) => l.payable);
  double get collected => _sum((l) => l.paid);
  double get outstanding => _sum((l) => l.outstanding);
  double get collectionPercent => FeeReport.percent(collected, payable);
  double _sum(double Function(FeeReportLine) f) => lines.fold(0.0, (s, l) => s + f(l));

  FeePaymentStatus get status => hasAssignments ? FeePaymentStatus.of(payable, collected, outstanding) : FeePaymentStatus.none;

  List<String> get warnings => [for (final l in lines) ?l.reconciliationWarning];
}

/// A row of the month-wise (or Term / One-time) summary.
class FeeReportSummaryRow {
  FeeReportSummaryRow(this.label);
  final String label;
  final Set<String> students = {};
  double assigned = 0, discounts = 0, payable = 0, collected = 0, outstanding = 0;
  double get percent => FeeReport.percent(collected, payable);

  void add(FeeReportLine l) {
    students.add(l.assignment.studentId);
    assigned += l.assigned;
    discounts += l.discount;
    payable += l.payable;
    collected += l.paid;
    outstanding += l.outstanding;
  }
}

/// The All Students report for a filter.
class FeeSchoolReport {
  FeeSchoolReport(this.students, this.filter);

  /// Every matching student, sorted by name.
  final List<FeeStudentStatement> students;
  final FeeReportFilter filter;

  int get totalStudents => students.length;
  int get withAssignments => students.where((s) => s.hasAssignments).length;
  int count(FeePaymentStatus s) => students.where((x) => x.status == s).length;

  double get assigned => _sum((s) => s.assigned);
  double get discounts => _sum((s) => s.discounts);
  double get studentDiscounts => _sum((s) => s.studentDiscounts);
  double get manualDiscounts => _sum((s) => s.manualDiscounts);
  double get payable => _sum((s) => s.payable);
  double get collected => _sum((s) => s.collected);
  double get outstanding => _sum((s) => s.outstanding);
  double get collectionPercent => FeeReport.percent(collected, payable);
  double _sum(double Function(FeeStudentStatement) f) => students.fold(0.0, (t, s) => t + f(s));

  /// One row per fee month (date order).
  List<FeeReportSummaryRow> get monthlySummary {
    final rows = <String, FeeReportSummaryRow>{};
    for (final s in students) {
      for (final l in s.monthly) {
        rows.putIfAbsent(l.assignment.feeMonth, () => FeeReportSummaryRow(l.feeMonthLabel)).add(l);
      }
    }
    return [for (final k in rows.keys.toList()..sort()) rows[k]!];
  }

  /// Term, One-time and mixed fees by fee structure.
  List<FeeReportSummaryRow> get nonMonthlySummary {
    final rows = <String, FeeReportSummaryRow>{};
    for (final s in students) {
      for (final l in s.nonMonthly) {
        final name = l.assignment.feeStructureName.isEmpty ? 'Unnamed fee' : l.assignment.feeStructureName;
        rows.putIfAbsent(name, () => FeeReportSummaryRow(name)).add(l);
      }
    }
    return [for (final k in rows.keys.toList()..sort()) rows[k]!];
  }

  /// Monthly assignments with no month recorded, or null when none.
  FeeReportSummaryRow? get noMonthSummary {
    final row = FeeReportSummaryRow(FeeReport.noMonthTitle);
    for (final s in students) {
      s.noMonth.forEach(row.add);
    }
    return row.students.isEmpty ? null : row;
  }
}

abstract final class FeeReport {
  static const statementTitle = 'Student Monthly Fee Statement';
  static const schoolTitle = 'All Students – Fee Collection and Outstanding Report';
  static const nonMonthlyTitle = 'Term and One-time Fees';
  static const noMonthTitle = 'Month not recorded';
  static const unlinkedTitle = 'Unlinked receipts (not counted in totals)';
  static const noAssignments = 'No fee assignments for the selected period.';

  static final _money = NumberFormat.decimalPatternDigits(locale: 'en_IN', decimalDigits: 0);
  static final _money2 = NumberFormat.decimalPatternDigits(locale: 'en_IN', decimalDigits: 2);

  /// "₹1,500" (paise shown only when present). [symbol] "Rs. " for the
  /// PDF's built-in font.
  static String money(double v, {String symbol = '₹'}) {
    final whole = _cents(v) % 100 == 0;
    return '${v < 0 ? '-' : ''}$symbol${(whole ? _money : _money2).format(v.abs())}';
  }

  static double percent(double part, double whole) => _cents(whole) <= 0 ? 0 : part / whole * 100;
  static String percentLabel(double p) => '${p.toStringAsFixed(1)}%';
  static String date(DateTime? d) => d == null ? '—' : FeeDueDate.label(d);

  /// Builds every matching student's statement. [students]: every student
  /// record (active or not); a student known only from an assignment is
  /// included too ([FeeStudentStatement.recordMissing]).
  static FeeSchoolReport build({
    required List<FeeStudent> students,
    required FeeReportData data,
    required Map<String, String> classNames,
    required FeeReportFilter filter,
  }) {
    final base = filter.base;
    final byStudent = <String, List<StudentFeeAssignmentModel>>{};
    for (final a in data.assignments) {
      byStudent.putIfAbsent(a.studentId, () => []).add(a);
    }
    final liveIds = {for (final a in data.assignments) a.id};
    final paymentsByAssignment = <String, List<FeeReportPayment>>{};
    final unlinkedByStudent = <String, List<FeeReportPayment>>{};
    for (final p in data.payments) {
      if (liveIds.contains(p.receipt.assignmentId)) {
        paymentsByAssignment.putIfAbsent(p.receipt.assignmentId, () => []).add(p);
      } else {
        unlinkedByStudent.putIfAbsent(p.receipt.studentId, () => []).add(p);
      }
    }

    final known = {for (final s in students) s.id: s};
    final everyone = [
      for (final s in students) (s, false),
      // Students only known from their assignments (record missing).
      for (final MapEntry(:key, :value) in byStudent.entries)
        if (!known.containsKey(key))
          (FeeStudent(id: key, name: value.first.studentName, admissionNo: value.first.admissionNo, classId: value.first.classId), true),
    ];

    final query = filter.search.trim().toLowerCase();
    final from = filter.admittedFrom == null ? null : AdmissionDate.dateOnly(filter.admittedFrom!);
    final to = filter.admittedTo == null ? null : AdmissionDate.dateOnly(filter.admittedTo!);
    // Assignments by year and month only: a student's own fees are all
    // listed whichever class they were under.
    final period = FeeListFilter(year: base.year, feeMonth: base.feeMonth, monthlyStructureIds: base.monthlyStructureIds);
    final out = <FeeStudentStatement>[];
    for (final (s, missing) in everyone) {
      if (!base.matchesStudent(s)) continue;
      if (query.isNotEmpty && !s.name.toLowerCase().contains(query) && !s.admissionNo.toLowerCase().contains(query)) continue;
      if (filter.hasAdmissionRange) {
        final d = s.admissionDate;
        if (d == null || (from != null && d.isBefore(from)) || (to != null && d.isAfter(to))) continue;
      }
      final lines = [
        for (final a in byStudent[s.id] ?? const <StudentFeeAssignmentModel>[])
          if (period.matchesAssignment(a)) FeeReportLine(a, paymentsByAssignment[a.id] ?? const []),
      ];
      int byMonth(FeeReportLine x, FeeReportLine y) {
        final c = x.assignment.feeMonth.compareTo(y.assignment.feeMonth);
        return c != 0 ? c : x.assignment.feeStructureName.compareTo(y.assignment.feeStructureName);
      }

      final statement = FeeStudentStatement(
        student: s,
        className: classNames[s.classId] ?? (s.classId.isEmpty ? '—' : s.classId),
        monthly: [for (final l in lines) if (FeeMonth.isValid(l.assignment.feeMonth)) l]..sort(byMonth),
        nonMonthly: [
          for (final l in lines)
            if (!FeeMonth.isValid(l.assignment.feeMonth) && !base.monthlyStructureIds.contains(l.assignment.feeStructureId)) l,
        ]..sort(byMonth),
        noMonth: [
          for (final l in lines)
            if (!FeeMonth.isValid(l.assignment.feeMonth) && base.monthlyStructureIds.contains(l.assignment.feeStructureId)) l,
        ]..sort(byMonth),
        unlinked: unlinkedByStudent[s.id] ?? const [],
        recordMissing: missing,
      );
      if (filter.status != null && statement.status != filter.status) continue;
      out.add(statement);
    }
    out.sort((a, b) {
      final c = a.student.name.toLowerCase().compareTo(b.student.name.toLowerCase());
      return c != 0 ? c : a.student.id.compareTo(b.student.id);
    });
    return FeeSchoolReport(out, filter);
  }
}
