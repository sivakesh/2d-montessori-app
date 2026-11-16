import 'package:cloud_firestore/cloud_firestore.dart';

import '../../calendar/models/calendar_event_model.dart';
import '../models/amount_in_words.dart';
import '../models/fee_month.dart';

/// Fee Bill Issuance (docs/fee_bill_issuance.md): supplementary, month-wise
/// bill documents issued against a payment that has already been collected
/// and receipted in Fees. A bill is a document, not a payment: nothing here
/// creates, changes or reverses a payment, receipt, assignment or Finance
/// record. All amounts are whole paise.

/// A bill-only adjustment's type. It reduces what the bill shows; it never
/// changes a fee structure, student discount, assignment or payment.
enum FeeBillAdjustmentType {
  none('none', 'No adjustment'),
  discount('discount', 'Discount adjustment'),
  other('other', 'Other adjustment');

  const FeeBillAdjustmentType(this.key, this.label);
  final String key, label;

  static FeeBillAdjustmentType of(Object? key) => values.firstWhere((t) => t.key == key, orElse: () => none);
}

enum FeeBillStatus {
  issued('issued', 'Issued'),
  cancelled('cancelled', 'Cancelled');

  const FeeBillStatus(this.key, this.label);
  final String key, label;

  static FeeBillStatus of(Object? key) => key == cancelled.key ? cancelled : issued;
}

/// "₹12,500.00" (screens) from paise.
String billMoney(int paise) => '₹${IndianAmount.figures(paise)}';

/// Rupees typed as "4200", "4,200" or "4200.5" as whole paise, exactly
/// (no floating point); null when it isn't such an amount.
int? parseRupees(String text) {
  final t = text.trim().replaceAll(',', '');
  final m = RegExp(r'^(\d{1,9})(?:\.(\d{1,2}))?$').firstMatch(t);
  if (m == null) return null;
  return int.parse(m.group(1)!) * 100 + int.parse((m.group(2) ?? '0').padRight(2, '0'));
}

/// Paise as an amount to type back: "4200", "4200.50".
String rupeesText(int paise) => paise % 100 == 0 ? '${paise ~/ 100}' : '${paise ~/ 100}.${(paise % 100).toString().padLeft(2, '0')}';

/// One requested bill: one billing month, one item. Each line is issued as
/// its own bill, with its own number and PDF.
class FeeBillLine {
  const FeeBillLine({
    required this.billingMonth,
    required this.description,
    required this.grossPaise,
    this.adjustmentType = FeeBillAdjustmentType.none,
    this.adjustmentPaise = 0,
    this.adjustmentReason = '',
    this.className = '',
  });

  /// `YYYY-MM`.
  final String billingMonth;

  /// The class printed on this bill, chosen by the administrator (default:
  /// the class on the original receipt). Stored on the bill only; never
  /// written to the student or the receipt.
  final String className;
  final String description;
  final int grossPaise;
  final FeeBillAdjustmentType adjustmentType;
  final int adjustmentPaise;
  final String adjustmentReason;

  int get netPaise => grossPaise - adjustmentPaise;

  static const maxDescription = 200, maxReason = 300;

  /// Why this line can't be issued, or null.
  String? get error {
    if (!FeeMonth.isValid(billingMonth)) return 'Choose the billing month.';
    final d = description.trim();
    if (d.isEmpty) return 'Enter the description or fee particulars.';
    if (d.length > maxDescription) return 'The description must be $maxDescription characters or fewer.';
    if (grossPaise <= 0) return 'The gross bill amount must be more than ₹0.';
    if (adjustmentPaise < 0) return 'The adjustment cannot be negative.';
    if (adjustmentPaise > grossPaise) return 'The adjustment cannot be more than the gross bill amount.';
    if (adjustmentPaise > 0 && adjustmentType == FeeBillAdjustmentType.none) return 'Choose the adjustment type.';
    if (adjustmentPaise > 0 && adjustmentReason.trim().isEmpty) return 'Enter the reason for the adjustment.';
    if (adjustmentReason.trim().length > maxReason) return 'The adjustment reason must be $maxReason characters or fewer.';
    return null;
  }

  /// The same line with no adjustment details left over when its amount is
  /// 0 (so a cleared adjustment is stored as none).
  FeeBillLine get normalized => FeeBillLine(
        billingMonth: billingMonth,
        description: description.trim(),
        grossPaise: grossPaise,
        adjustmentType: adjustmentPaise == 0 ? FeeBillAdjustmentType.none : adjustmentType,
        adjustmentPaise: adjustmentPaise,
        adjustmentReason: adjustmentPaise == 0 ? '' : adjustmentReason.trim(),
        className: className.trim(),
      );

  /// Identifies "the same bill line" for one payment: its month and its
  /// description (case and spacing ignored). An active bill with the same
  /// key blocks issuing it again until that bill is cancelled.
  String get key => '$billingMonth|${description.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ')}';

  Map<String, dynamic> toMap() => {
        'billingMonth': billingMonth,
        'description': description.trim(),
        'grossPaise': grossPaise,
        'adjustmentType': adjustmentType.key,
        'adjustmentPaise': adjustmentPaise,
        'adjustmentReason': adjustmentReason.trim(),
        'netPaise': netPaise,
      };

  factory FeeBillLine.fromMap(Map<String, dynamic> m) => FeeBillLine(
        billingMonth: m['billingMonth']?.toString() ?? '',
        description: m['description']?.toString() ?? '',
        grossPaise: _int(m['grossPaise']),
        adjustmentType: FeeBillAdjustmentType.of(m['adjustmentType']),
        adjustmentPaise: _int(m['adjustmentPaise']),
        adjustmentReason: m['adjustmentReason']?.toString() ?? '',
        className: m['className']?.toString() ?? '',
      );
}

int _int(Object? v) => v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? 0;
DateTime? _date(Object? v) => v is Timestamp ? v.toDate() : v is DateTime ? v : null;

/// The original payment a bill is issued against: a `fee_receipts`
/// document, read only. Stored on each bill as a snapshot.
class FeeBillPayment {
  const FeeBillPayment({
    required this.receiptId,
    required this.receiptNo,
    required this.studentId,
    required this.studentName,
    required this.admissionNo,
    required this.className,
    required this.amountPaise,
    required this.paymentMode,
    required this.referenceNo,
    this.paymentDate,
    this.voided = false,
    this.schoolId = '',
    this.feeName = '',
    this.feeMonth = '',
  });

  final String receiptId, receiptNo, studentId, studentName, admissionNo, className, paymentMode, referenceNo;
  final int amountPaise;
  final DateTime? paymentDate;

  /// The receipt has been voided in Fees: no new bill can be issued on it.
  final bool voided;

  /// The receipt's own `schoolId`; '' for receipts that have none (every
  /// receipt today: the app's single school).
  final String schoolId;

  /// The receipt's fee name and fee month, only to prefill a new bill line
  /// (never stored on the bill).
  final String feeName, feeMonth;

  factory FeeBillPayment.fromReceipt(String id, Map<String, dynamic> d) => FeeBillPayment(
        receiptId: id,
        receiptNo: d['receiptNo']?.toString() ?? '',
        studentId: d['studentId']?.toString() ?? '',
        studentName: d['studentName']?.toString() ?? '',
        admissionNo: d['admissionNo']?.toString() ?? '',
        className: d['className']?.toString() ?? '',
        amountPaise: IndianAmount.paiseOf((d['amount'] as num?)?.toDouble() ?? 0),
        paymentMode: d['paymentMode']?.toString() ?? '',
        referenceNo: d['referenceNo']?.toString() ?? '',
        paymentDate: _date(d['paymentDate']),
        voided: d['isDeleted'] == true,
        schoolId: d['schoolId']?.toString() ?? '',
        feeName: d['feeStructureName']?.toString() ?? '',
        feeMonth: d['feeMonth']?.toString() ?? '',
      );

  /// The same payment with the class the bill prints.
  FeeBillPayment withClass(String value) => FeeBillPayment(
        receiptId: receiptId, receiptNo: receiptNo, studentId: studentId, studentName: studentName, admissionNo: admissionNo,
        className: value, amountPaise: amountPaise, paymentMode: paymentMode, referenceNo: referenceNo, paymentDate: paymentDate,
        voided: voided, schoolId: schoolId, feeName: feeName, feeMonth: feeMonth,
      );

  /// Snapshot stored on the bill (`payment`).
  Map<String, dynamic> toSnapshot() => {
        'receiptId': receiptId,
        'receiptNo': receiptNo,
        'amountPaise': amountPaise,
        'paymentMode': paymentMode,
        'referenceNo': referenceNo,
        'paymentDate': paymentDate,
      };

  factory FeeBillPayment.fromSnapshot(Map<String, dynamic> p, Map<String, dynamic> student) => FeeBillPayment(
        receiptId: p['receiptId']?.toString() ?? '',
        receiptNo: p['receiptNo']?.toString() ?? '',
        studentId: student['studentId']?.toString() ?? '',
        studentName: student['studentName']?.toString() ?? '',
        admissionNo: student['admissionNo']?.toString() ?? '',
        className: student['className']?.toString() ?? '',
        amountPaise: _int(p['amountPaise']),
        paymentMode: p['paymentMode']?.toString() ?? '',
        referenceNo: p['referenceNo']?.toString() ?? '',
        paymentDate: _date(p['paymentDate']),
      );
}

/// The school's header as it was when a bill was issued, so a reprint is
/// the same document even if School Settings change later.
class FeeBillSchool {
  const FeeBillSchool({required this.name, this.addressLines = const [], this.contactLines = const [], this.logoUrl = '', this.gstin = ''});

  final String name;
  final List<String> addressLines, contactLines;
  final String logoUrl;

  /// The school's GSTIN printed in the header; '' when "Show GSTIN on bill"
  /// was not ticked (as on the regenerated receipt).
  final String gstin;

  FeeBillSchool withGstin(String value) => FeeBillSchool(name: name, addressLines: addressLines, contactLines: contactLines, logoUrl: logoUrl, gstin: value);

  Map<String, dynamic> toMap() => {'name': name, 'addressLines': addressLines, 'contactLines': contactLines, 'logoUrl': logoUrl, if (gstin.isNotEmpty) 'gstin': gstin};

  factory FeeBillSchool.fromMap(Map<String, dynamic>? m) => FeeBillSchool(
        name: m?['name']?.toString() ?? '',
        addressLines: [for (final l in (m?['addressLines'] as List? ?? const [])) l.toString()],
        contactLines: [for (final l in (m?['contactLines'] as List? ?? const [])) l.toString()],
        logoUrl: m?['logoUrl']?.toString() ?? '',
        gstin: m?['gstin']?.toString() ?? '',
      );
}

/// An issued bill (`fee_issued_bills`). Immutable once issued: only a
/// cancellation (status, reason, who, when, replacement) is ever added.
class FeeIssuedBill {
  const FeeIssuedBill({
    required this.id,
    required this.schoolId,
    required this.billNo,
    required this.status,
    required this.payment,
    required this.line,
    required this.school,
    required this.issuedAt,
    required this.issuedBy,
    this.replacesBillId = '',
    this.replacedByBillId = '',
    this.cancellationReason = '',
    this.cancelledAt,
    this.cancelledBy = '',
    this.issueDate,
    this.parentRelation = '',
    this.parentName = '',
    this.amountIncludesGst = false,
  });

  /// [billNo] is the Bill Reference: `{receipt number}-{six-digit
  /// sequence}` (stored as `billNo`), fixed at issue.
  final String id, schoolId, billNo;

  String get billReference => billNo;

  /// The date printed as the Issue Date: the first working day of the
  /// billing month ([FeeBillIssueDate]), fixed when issued. Older bills
  /// without one show [issuedAt].
  final DateTime? issueDate;

  /// The parent or guardian printed (father, else mother, else guardian),
  /// as linked to the student when the bill was issued; '' : none.
  final String parentRelation, parentName;

  /// "Amount includes GST" was ticked: "(GST Included)" beside the net
  /// amount. Never a GST calculation.
  final bool amountIncludesGst;

  /// The Issue Date printed on the bill.
  DateTime? get documentDate => issueDate ?? issuedAt;
  final FeeBillStatus status;

  /// The original payment and student, as they were at issue.
  final FeeBillPayment payment;
  final FeeBillLine line;
  final FeeBillSchool school;
  final DateTime? issuedAt;
  final String issuedBy;

  /// Set when this bill replaced a cancelled one / was replaced.
  final String replacesBillId, replacedByBillId;
  final String cancellationReason, cancelledBy;
  final DateTime? cancelledAt;

  bool get isCancelled => status == FeeBillStatus.cancelled;

  /// The document id for bill [billNo] of [schoolId]: unique by
  /// construction, so a Bill Reference can never be stored twice.
  static String idFor(String schoolId, String billNo) => '${schoolId}_$billNo';

  factory FeeIssuedBill.fromMap(String id, Map<String, dynamic> d) {
    final student = {
      'studentId': d['studentId'],
      'studentName': d['studentName'],
      'admissionNo': d['admissionNo'],
      'className': d['className'],
    };
    final c = d['cancellation'] as Map?;
    return FeeIssuedBill(
      id: id,
      schoolId: d['schoolId']?.toString() ?? '',
      billNo: d['billNo']?.toString() ?? '',
      status: FeeBillStatus.of(d['status']),
      payment: FeeBillPayment.fromSnapshot(Map<String, dynamic>.from(d['payment'] as Map? ?? const {}), student),
      line: FeeBillLine.fromMap(d),
      school: FeeBillSchool.fromMap((d['school'] as Map?)?.cast<String, dynamic>()),
      issuedAt: _date(d['issuedAt']),
      issuedBy: d['issuedBy']?.toString() ?? '',
      replacesBillId: d['replacesBillId']?.toString() ?? '',
      replacedByBillId: d['replacedByBillId']?.toString() ?? '',
      cancellationReason: c?['reason']?.toString() ?? '',
      cancelledAt: _date(c?['at']),
      cancelledBy: c?['by']?.toString() ?? '',
      issueDate: _date(d['issueDate']),
      parentRelation: d['parentRelation']?.toString() ?? '',
      parentName: d['parentName']?.toString() ?? '',
      amountIncludesGst: d['amountIncludesGst'] == true,
    );
  }
}

/// How much of one payment is represented by active bills
/// (`fee_bill_allocations/{receiptId}`). Changed only inside the issuing
/// and cancelling transactions, which read it first, so two issuances can
/// never both use the same unallocated amount.
class FeeBillAllocation {
  const FeeBillAllocation({
    required this.receiptId,
    required this.paymentPaise,
    this.allocatedPaise = 0,
    this.bills = const {},
    this.lineKeys = const {},
    this.requests = const {},
    this.version = 0,
    this.nextSequence = 1,
  });

  final String receiptId;

  /// The payment amount when last checked (the receipt is authoritative).
  final int paymentPaise;

  /// Sum of the active bills' net amounts.
  final int allocatedPaise;

  /// Active bill id → its net paise.
  final Map<String, int> bills;

  /// Active bill line key ([FeeBillLine.key]) → bill id.
  final Map<String, String> lineKeys;

  /// Issue request id → the bill ids it created (a repeated request
  /// returns those bills instead of issuing again).
  final Map<String, List<String>> requests;
  final int version;

  /// The sequence the payment's next Bill Reference gets (1 for the
  /// first). Only ever increases: a cancelled bill's number is not reused.
  final int nextSequence;

  int availableFor(int payment) => payment - allocatedPaise;

  /// [allocatedPaise] agrees with [bills].
  bool get isConsistent => allocatedPaise == bills.values.fold<int>(0, (s, v) => s + v) && allocatedPaise >= 0;

  factory FeeBillAllocation.fromMap(String receiptId, Map<String, dynamic>? d) => FeeBillAllocation(
        receiptId: receiptId,
        paymentPaise: _int(d?['paymentPaise']),
        allocatedPaise: _int(d?['allocatedPaise']),
        bills: {for (final e in ((d?['bills'] as Map?) ?? const {}).entries) e.key.toString(): _int(e.value)},
        lineKeys: {for (final e in ((d?['lineKeys'] as Map?) ?? const {}).entries) e.key.toString(): e.value.toString()},
        requests: {
          for (final e in ((d?['requests'] as Map?) ?? const {}).entries) e.key.toString(): [for (final v in (e.value as List? ?? const [])) v.toString()],
        },
        version: _int(d?['version']),
        nextSequence: d?['nextSequence'] is num ? (d!['nextSequence'] as num).toInt() : 1,
      );
}

/// Totals of bills issued (documents only; never collections).
class FeeBillTotals {
  const FeeBillTotals({required this.issued, required this.cancelled, required this.grossPaise, required this.adjustmentPaise, required this.netPaise});

  final int issued, cancelled, grossPaise, adjustmentPaise, netPaise;

  /// Active (issued) bills only; cancelled ones are counted separately.
  factory FeeBillTotals.of(Iterable<FeeIssuedBill> bills) {
    var issued = 0, cancelled = 0, gross = 0, adj = 0, net = 0;
    for (final b in bills) {
      if (b.isCancelled) {
        cancelled++;
        continue;
      }
      issued++;
      gross += b.line.grossPaise;
      adj += b.line.adjustmentPaise;
      net += b.line.netPaise;
    }
    return FeeBillTotals(issued: issued, cancelled: cancelled, grossPaise: gross, adjustmentPaise: adj, netPaise: net);
  }
}

/// A bill's Issue Date: the first working day of its billing month, never
/// the day it happens to be issued.
///
/// A working day is a day with a Published "Working Day" event in the
/// school calendar (`school_calendar_events`), or a Monday to Friday
/// without a Published "School Holiday" event (the app's working-day rule,
/// as in Leave). If one date has both, the holiday wins. Draft and
/// Archived events are ignored.
abstract final class FeeBillIssueDate {
  static bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  /// The first working day of [billingMonth] (`YYYY-MM`), given that
  /// month's calendar [events]. Throws [StateError] when the month has
  /// none.
  static DateTime firstWorkingDay(String billingMonth, Iterable<CalendarEventModel> events) {
    final year = int.parse(billingMonth.substring(0, 4)), month = int.parse(billingMonth.substring(5, 7));
    final published = [for (final e in events) if (e.isPublished) e];
    final days = DateTime(year, month + 1, 0).day;
    for (var d = 1; d <= days; d++) {
      final day = DateTime(year, month, d);
      final types = {for (final e in published) if (_sameDay(e.date, day)) e.eventType};
      if (types.contains(CalendarEventType.schoolHoliday)) continue;
      if (types.contains(CalendarEventType.workingDay)) return day;
      if (day.weekday <= DateTime.friday) return day;
    }
    throw StateError('${FeeMonth.label(billingMonth)} has no working day in the school calendar, so its bill has no issue date.');
  }
}

