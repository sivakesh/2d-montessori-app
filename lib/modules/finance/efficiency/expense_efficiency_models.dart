import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

/// Finance → Expense Efficiency: management assessments of recorded
/// expenses and monthly category spending targets. Analytical data only,
/// stored apart from Finance (ExpenseEfficiencyService); it never creates,
/// changes or removes a ledger entry, account, balance or fee record.

int paiseOf(double v) => (v * 100).round();
double rupeesOf(int p) => p / 100;

/// The five assessment categories. An expense without an assessment is
/// [underReview]; none is ever inferred from a description or amount.
enum ExpenseAssessmentCategory {
  necessary('necessary', 'Necessary', 'Essential school expenditure.'),
  useful('useful', 'Useful', 'Beneficial operational expenditure that is not strictly essential.'),
  waste('waste', 'Waste / Avoidable', 'Expenditure that could reasonably have been avoided.'),
  excessive('excessive', 'Excessive',
      'A necessary expense where part of the amount may be avoidable because of inefficient purchasing, consumption or planning.'),
  underReview('underReview', 'Under Review', 'Not yet assessed or awaiting management decision.');

  const ExpenseAssessmentCategory(this.key, this.label, this.definition);
  final String key, label, definition;

  /// Whether an avoidable amount can be recorded (and counted as savings).
  bool get hasAvoidable => this == waste || this == excessive;

  static ExpenseAssessmentCategory parse(Object? v) =>
      values.firstWhere((c) => c.key == v?.toString(), orElse: () => underReview);
}

/// Follow-up on a corrective action (optional).
enum ExpenseActionStatus {
  none('none', 'No action'),
  open('open', 'Open'),
  inProgress('inProgress', 'In progress'),
  done('done', 'Done');

  const ExpenseActionStatus(this.key, this.label);
  final String key, label;
  static ExpenseActionStatus parse(Object? v) => values.firstWhere((s) => s.key == v?.toString(), orElse: () => none);
}

DateTime? _ts(Object? v) => v is Timestamp ? v.toDate() : v is DateTime ? v : null;

/// One expense's assessment (`finance_expense_assessments/{transactionId}`):
/// the document id is the ledger entry's id, so an expense has at most one.
class ExpenseAssessment {
  const ExpenseAssessment({
    required this.transactionId,
    required this.schoolId,
    required this.category,
    this.reason = '',
    this.managementNote = '',
    this.correctiveAction = '',
    this.actionStatus = ExpenseActionStatus.none,
    this.avoidableAmount = 0,
    this.amountAtAssessment = 0,
    this.assessedAt,
    this.assessedBy = '',
    this.updatedAt,
    this.updatedBy = '',
  });

  /// The ledger entry (`finance_ledger`) id: the stable transaction id.
  final String transactionId;
  final String schoolId;
  final ExpenseAssessmentCategory category;
  final String reason, managementNote, correctiveAction;
  final ExpenseActionStatus actionStatus;

  /// Waste / Avoidable and Excessive only; 0 otherwise.
  final double avoidableAmount;

  /// The expense's amount when it was assessed (to notice later edits).
  final double amountAtAssessment;
  final DateTime? assessedAt, updatedAt;
  final String assessedBy, updatedBy;

  static ExpenseAssessment fromMap(String id, Map<String, dynamic> m) => ExpenseAssessment(
        transactionId: m['transactionId']?.toString() ?? id,
        schoolId: m['schoolId']?.toString() ?? '',
        category: ExpenseAssessmentCategory.parse(m['assessmentCategory']),
        reason: m['reason']?.toString() ?? '',
        managementNote: m['managementNote']?.toString() ?? '',
        correctiveAction: m['correctiveAction']?.toString() ?? '',
        actionStatus: ExpenseActionStatus.parse(m['actionStatus']),
        avoidableAmount: (m['avoidableAmount'] as num?)?.toDouble() ?? 0,
        amountAtAssessment: (m['amountAtAssessment'] as num?)?.toDouble() ?? 0,
        assessedAt: _ts(m['assessedAt']),
        assessedBy: m['assessedBy']?.toString() ?? '',
        updatedAt: _ts(m['updatedAt']),
        updatedBy: m['updatedBy']?.toString() ?? '',
      );

  /// The analytical fields (timestamps and identities are set by the
  /// service).
  Map<String, dynamic> toMap() => {
        'transactionId': transactionId,
        'schoolId': schoolId,
        'assessmentCategory': category.key,
        'reason': reason.trim(),
        'managementNote': managementNote.trim(),
        'correctiveAction': correctiveAction.trim(),
        'actionStatus': actionStatus.key,
        'avoidableAmount': category.hasAvoidable ? avoidableAmount : 0,
        'amountAtAssessment': amountAtAssessment,
      };

  /// Why [avoidable] can't be saved for [category] on an expense of
  /// [expenseAmount], or null. Necessary, Useful and Under Review record
  /// none; Waste / Avoidable and Excessive from 0 up to the expense amount.
  static String? validate(ExpenseAssessmentCategory category, double? avoidable, double expenseAmount) {
    if (!category.hasAvoidable) return null;
    if (avoidable == null || !avoidable.isFinite) return 'Enter the avoidable amount as a number.';
    if (paiseOf(avoidable) < 0) return 'The avoidable amount cannot be negative.';
    if (paiseOf(avoidable) > paiseOf(expenseAmount)) return 'The avoidable amount cannot be more than the expense amount (${efficiencyMoney(expenseAmount)}).';
    return null;
  }
}

/// A monthly spending target for one expense category
/// (`finance_expense_targets/{id}`): [monthlyAmount] for every month from
/// [startMonth] to [endMonth] (open-ended when empty), both `YYYY-MM`.
class ExpenseTarget {
  const ExpenseTarget({
    required this.id,
    required this.schoolId,
    required this.categoryId,
    required this.categoryName,
    required this.monthlyAmount,
    required this.startMonth,
    this.endMonth = '',
    this.note = '',
    this.isActive = true,
    this.createdAt,
    this.createdBy = '',
    this.updatedAt,
    this.updatedBy = '',
  });

  final String id, schoolId, categoryId, categoryName;
  final double monthlyAmount;
  final String startMonth, endMonth, note;
  final bool isActive;
  final DateTime? createdAt, updatedAt;
  final String createdBy, updatedBy;

  static final _month = RegExp(r'^\d{4}-(0[1-9]|1[0-2])$');
  static bool isMonth(String v) => _month.hasMatch(v);

  static ExpenseTarget fromMap(String id, Map<String, dynamic> m) => ExpenseTarget(
        id: id,
        schoolId: m['schoolId']?.toString() ?? '',
        categoryId: m['categoryId']?.toString() ?? '',
        categoryName: m['categoryName']?.toString() ?? '',
        monthlyAmount: (m['monthlyAmount'] as num?)?.toDouble() ?? double.nan,
        startMonth: m['startMonth']?.toString() ?? '',
        endMonth: m['endMonth']?.toString() ?? '',
        note: m['note']?.toString() ?? '',
        isActive: m['isActive'] != false,
        createdAt: _ts(m['createdAt']),
        createdBy: m['createdBy']?.toString() ?? '',
        updatedAt: _ts(m['updatedAt']),
        updatedBy: m['updatedBy']?.toString() ?? '',
      );

  Map<String, dynamic> toMap() => {
        'schoolId': schoolId,
        'categoryId': categoryId,
        'categoryName': categoryName.trim(),
        'monthlyAmount': monthlyAmount,
        'startMonth': startMonth,
        'endMonth': endMonth,
        'note': note.trim(),
        'isActive': isActive,
      };

  bool covers(String month) => startMonth.compareTo(month) <= 0 && (endMonth.isEmpty || month.compareTo(endMonth) <= 0);

  /// Same category and at least one month in common.
  bool overlaps(ExpenseTarget o) =>
      categoryId == o.categoryId &&
      (o.endMonth.isEmpty || startMonth.compareTo(o.endMonth) <= 0) &&
      (endMonth.isEmpty || o.startMonth.compareTo(endMonth) <= 0);

  String? get error {
    if (categoryId.trim().isEmpty) return 'Choose the expense category.';
    if (!monthlyAmount.isFinite) return 'Enter the monthly target as a number.';
    if (paiseOf(monthlyAmount) < 0) return 'The monthly target cannot be negative.';
    if (!isMonth(startMonth)) return 'Choose the month the target starts.';
    if (endMonth.isNotEmpty && !isMonth(endMonth)) return 'The end month is not a month.';
    if (endMonth.isNotEmpty && endMonth.compareTo(startMonth) < 0) return 'The end month cannot be before the start month.';
    return null;
  }

  String get monthsLabel => endMonth.isEmpty ? 'From ${monthLabel(startMonth)}' : '${monthLabel(startMonth)} – ${monthLabel(endMonth)}';
}

String monthKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';
DateTime monthStart(String key) => DateTime(int.parse(key.substring(0, 4)), int.parse(key.substring(5)));
String monthLabel(String key) => ExpenseTarget.isMonth(key) ? DateFormat('MMM yyyy').format(monthStart(key)) : key;

final _money0 = NumberFormat.decimalPatternDigits(locale: 'en_IN', decimalDigits: 0);
final _money2 = NumberFormat.decimalPatternDigits(locale: 'en_IN', decimalDigits: 2);

/// "₹1,500" (paise only when present), "-₹200" below zero. [symbol]
/// "Rs. " for the PDF's built-in font.
String efficiencyMoney(double v, {String symbol = '₹'}) {
  final p = paiseOf(v);
  return '${p < 0 ? '-' : ''}$symbol${(p % 100 == 0 ? _money0 : _money2).format(rupeesOf(p.abs()))}';
}
