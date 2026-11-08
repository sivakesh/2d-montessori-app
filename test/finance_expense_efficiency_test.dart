// Finance → Expense Efficiency: assessments (five categories, Under Review
// by default, avoidable-amount rules), transaction lifecycle (edited,
// cancelled, deleted, duplicates), Actual / Adjusted / Target formulas and
// their reconciliation with the Ledger's Profit / Loss, monthly targets,
// permissions, strict separation from every Finance and Fees record, and
// the PDF. Synthetic data only.
import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/admin/settings/data/academic_year_service.dart';
import 'package:montessori_app/modules/admin/settings/models/school_settings_model.dart';
import 'package:montessori_app/modules/admin/settings/providers/academic_year_provider.dart';
import 'package:montessori_app/modules/auth/models/app_user.dart';
import 'package:montessori_app/modules/auth/providers/auth_provider.dart';
import 'package:montessori_app/modules/fees/services/fee_report_pdf.dart';
import 'package:montessori_app/modules/finance/efficiency/expense_category_pill.dart';
import 'package:montessori_app/modules/finance/efficiency/expense_efficiency_analysis.dart';
import 'package:montessori_app/modules/finance/efficiency/expense_efficiency_models.dart';
import 'package:montessori_app/modules/finance/efficiency/expense_efficiency_pdf.dart';
import 'package:montessori_app/modules/finance/efficiency/expense_efficiency_service.dart';
import 'package:montessori_app/modules/finance/models/finance_expense_model.dart';
import 'package:montessori_app/modules/finance/models/finance_income_model.dart';
import 'package:montessori_app/modules/finance/models/finance_ledger_entry_model.dart';
import 'package:montessori_app/modules/finance/models/ledger_period.dart';
import 'package:montessori_app/modules/finance/services/finance_service.dart';
import 'package:montessori_app/modules/finance/ui/admin_finance_screen.dart';

import 'support/buffered_transaction_firestore.dart';

List<String> _pdfWords(Uint8List bytes) =>
    [for (final m in RegExp(r'\(((?:[^()\\]|\\.)*)\)').allMatches(latin1.decode(bytes))) m.group(1)!.replaceAll(r'\(', '(').replaceAll(r'\)', ')')];

/// WCAG contrast ratio of two opaque colours.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return ((la > lb ? la : lb) + 0.05) / ((la > lb ? lb : la) + 0.05);
}

bool _hasPhrase(List<String> words, String phrase) {
  final want = phrase.split(' ');
  for (var i = 0; i + want.length <= words.length; i++) {
    var ok = true;
    for (var j = 0; j < want.length && ok; j++) {
      ok = words[i + j] == want[j];
    }
    if (ok) return true;
  }
  return false;
}

/// Finance → Reports → Expense Efficiency, as a user gets there.
Future<void> _openFromReports(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(ChoiceChip, 'Reports'));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byKey(const Key('finance-report-expense-efficiency')));
  await tester.tap(find.byKey(const Key('finance-report-expense-efficiency')));
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  await tester.pumpAndSettle();
}

const _financeTabs = ['Dashboard', 'Income', 'Expenses', 'Salary', 'Vendors', 'Ledger', 'Reports', 'Settings'];

void main() {
  late BufferedTransactionFirestore firestore;
  late FinanceService finance;
  late ExpenseEfficiencyService eff;
  late Map<String, String> accounts;
  const admin = 'admin';

  setUp(() async {
    firestore = BufferedTransactionFirestore();
    final auth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'admin-uid', email: 'admin@example.com'));
    finance = FinanceService(firestore: firestore, auth: auth);
    await finance.ensureDefaults();
    eff = ExpenseEfficiencyService(firestore: firestore, auth: auth);
    accounts = {for (final d in (await firestore.collection('finance_accounts').get()).docs) d.data()['type'] as String: d.id};
    await firestore.collection('finance_categories').doc('supplies').set({'name': 'Supplies', 'type': 'expense', 'isActive': true});
    await firestore.collection('finance_categories').doc('power').set({'name': 'Electricity', 'type': 'expense', 'isActive': true});
  });

  /// A real income through FinanceService (ledger, account balance).
  Future<String> income(double amount, DateTime date) => finance.createIncome(FinanceIncomeModel(
        id: '', title: 'Donation', categoryId: 'c', categoryName: 'Other Income', programType: 'other', studentId: '', studentName: '',
        classId: '', className: '', amount: amount, incomeDate: date, paymentMode: 'cash', accountId: accounts['cash']!,
        accountName: 'Cash', referenceNo: '', remarks: '', attachmentUrls: const [], ledgerEntryId: '',
        createdAt: date, updatedAt: date, createdBy: 'admin',
      ));

  /// A real expense through FinanceService; returns its ledger entry id.
  Future<String> expense(double amount, DateTime date, {String category = 'supplies', String name = 'Supplies', String title = 'Chalk', String remarks = ''}) async {
    final id = await finance.createExpense(FinanceExpenseModel.fromMap('', {
      'title': title, 'amount': amount, 'accountId': accounts['cash'], 'accountName': 'Cash', 'expenseDate': date,
      'categoryId': category, 'categoryName': name, 'createdAt': date, 'remarks': remarks,
    }));
    return (await firestore.doc('finance_expenses/$id').get()).data()!['ledgerEntryId'] as String;
  }

  Future<List<FinanceLedgerEntryModel>> ledger() => finance.watchLedger().first;

  Future<ExpenseEfficiencyReport> report(EfficiencyPeriod p, {EfficiencyFilter filter = const EfficiencyFilter()}) async => ExpenseEfficiencyReport.build(
        entries: await ledger(),
        assessments: await eff.getAssessments(),
        targets: await eff.getTargets(),
        period: p,
        filter: filter,
        categoryNames: const {'supplies': 'Supplies', 'power': 'Electricity'},
      );

  final nov = EfficiencyPeriod.month(2026, 11);

  Future<String> financeDump() async => [
        for (final c in ['finance_ledger', 'finance_income', 'finance_expenses', 'finance_accounts', 'finance_categories', 'finance_invoices',
          'staff_salary_payments', 'vendors', 'student_fee_assignments', 'fee_receipts', 'fee_transactions', 'students'])
          '$c=${[for (final d in (await firestore.collection(c).get()).docs) '${d.id}:${d.data()}']..sort()}',
      ].join('\n');

  // ================================================================ assessments
  group('assessments', () {
    test('every expense starts Under Review (existing and new); nothing is written for the default', () async {
      final a = await expense(500, DateTime(2026, 11, 3));
      var r = await report(nov);
      expect([r.allItems.single.id, r.allItems.single.category, r.allItems.single.isAssessed], [a, ExpenseAssessmentCategory.underReview, false]);
      expect(await firestore.collection(ExpenseEfficiencyService.assessmentsCollection).get().then((s) => s.docs), isEmpty);
      await eff.saveAssessment(requesterRole: admin, transactionId: a, category: ExpenseAssessmentCategory.necessary);
      final b = await expense(300, DateTime(2026, 11, 4)); // a new expense afterwards
      r = await report(nov);
      expect({for (final i in r.allItems) i.id: i.category}, {a: ExpenseAssessmentCategory.necessary, b: ExpenseAssessmentCategory.underReview});
      expect([r.count(ExpenseAssessmentCategory.underReview), r.total(ExpenseAssessmentCategory.underReview)], [1, 300]);
    });

    test('all five categories; only Waste / Avoidable and Excessive count as savings', () async {
      final ids = [for (var i = 0; i < 5; i++) await expense(1000, DateTime(2026, 11, 2 + i))];
      for (final (i, c) in ExpenseAssessmentCategory.values.indexed) {
        await eff.saveAssessment(requesterRole: admin, transactionId: ids[i], category: c, avoidableAmount: 400);
      }
      final r = await report(nov);
      expect({for (final c in ExpenseAssessmentCategory.values) c: r.total(c)}, {for (final c in ExpenseAssessmentCategory.values) c: 1000.0});
      expect(r.potentialSavings, 800, reason: 'waste 400 + excessive 400; necessary, useful and under review nothing even when an amount was sent');
      final stored = await eff.getAssessments();
      expect([for (final id in ids) stored[id]!.avoidableAmount], [0, 0, 400, 400, 0]);
      expect([r.assessedCount, r.unassessedCount, r.coveragePercent], [4, 1, 80], reason: 'explicit Under Review is not assessed');
    });

    test('Waste / Avoidable defaults to the whole amount and may be reduced; invalid amounts are refused with nothing written', () async {
      final a = await expense(750.50, DateTime(2026, 11, 3));
      await eff.saveAssessment(requesterRole: admin, transactionId: a, category: ExpenseAssessmentCategory.waste);
      expect((await eff.getAssessments())[a]!.avoidableAmount, 750.50);
      await eff.saveAssessment(requesterRole: admin, transactionId: a, category: ExpenseAssessmentCategory.waste, avoidableAmount: 200.25);
      expect((await report(nov)).potentialSavings, 200.25);
      final before = await eff.getAssessments();
      for (final bad in [-1.0, 750.51, double.nan]) {
        await expectLater(eff.saveAssessment(requesterRole: admin, transactionId: a, category: ExpenseAssessmentCategory.waste, avoidableAmount: bad),
            throwsA(isA<StateError>()), reason: '$bad');
      }
      expect((await eff.getAssessments())[a]!.avoidableAmount, before[a]!.avoidableAmount);
    });

    test('Excessive: only the explicit avoidable portion counts (zero allowed while pending)', () async {
      final a = await expense(2000, DateTime(2026, 11, 3));
      await eff.saveAssessment(requesterRole: admin, transactionId: a, category: ExpenseAssessmentCategory.excessive);
      expect([(await eff.getAssessments())[a]!.avoidableAmount, (await report(nov)).potentialSavings], [0, 0], reason: 'never the full amount automatically');
      await eff.saveAssessment(requesterRole: admin, transactionId: a, category: ExpenseAssessmentCategory.excessive, avoidableAmount: 350, reason: 'Bought at retail price');
      final r = await report(nov);
      expect([r.potentialSavings, r.total(ExpenseAssessmentCategory.excessive), r.excessiveWithAvoidable.single.id], [350, 2000, a]);
    });

    test('editing keeps the reason, note and first assessor; every change is in the audit history', () async {
      final a = await expense(500, DateTime(2026, 11, 3));
      await eff.saveAssessment(requesterRole: admin, transactionId: a, category: ExpenseAssessmentCategory.useful, reason: 'Parent event', managementNote: 'Keep');
      await eff.saveAssessment(requesterRole: admin, transactionId: a, category: ExpenseAssessmentCategory.waste, avoidableAmount: 100,
          reason: 'Duplicate order', managementNote: 'Order once a term', correctiveAction: 'Central purchasing', actionStatus: ExpenseActionStatus.open);
      final doc = (await firestore.doc('${ExpenseEfficiencyService.assessmentsCollection}/$a').get()).data()!;
      expect([doc['transactionId'], doc['schoolId'], doc['assessmentCategory'], doc['reason'], doc['managementNote'], doc['correctiveAction'], doc['actionStatus'], doc['avoidableAmount']],
          [a, kDefaultSchoolId, 'waste', 'Duplicate order', 'Order once a term', 'Central purchasing', 'open', 100]);
      expect([doc['assessedBy'], doc['updatedBy'], doc['amountAtAssessment']], ['admin-uid', 'admin-uid', 500]);
      expect(doc.keys.toSet().intersection({'title', 'description', 'amount', 'accountId', 'transactionDate'}), isEmpty, reason: 'no copy of the transaction');
      final h = await eff.history(target: false, id: a);
      expect(h.map((e) => e['action']).toSet(), {'created', 'updated'});
      await eff.deleteAssessment(requesterRole: admin, transactionId: a);
      expect((await report(nov)).allItems.single.category, ExpenseAssessmentCategory.underReview);
      expect((await eff.history(target: false, id: a)).length, 3, reason: 'history kept after removal');
    });

    test('only real expenses of this school can be assessed', () async {
      final inc = await income(5000, DateTime(2026, 11, 1));
      final incLedger = (await firestore.doc('finance_income/$inc').get()).data()!['ledgerEntryId'] as String;
      await expectLater(eff.saveAssessment(requesterRole: admin, transactionId: incLedger, category: ExpenseAssessmentCategory.waste), throwsA(isA<StateError>()));
      await expectLater(eff.saveAssessment(requesterRole: admin, transactionId: 'no-such', category: ExpenseAssessmentCategory.waste), throwsA(isA<StateError>()));
      final other = await expense(100, DateTime(2026, 11, 3));
      await firestore.doc('finance_ledger/$other').update({'schoolId': 'other-school'});
      await expectLater(eff.saveAssessment(requesterRole: admin, transactionId: other, category: ExpenseAssessmentCategory.waste),
          throwsA(isA<StateError>().having((e) => e.message, 'm', contains('another school'))));
      expect((await firestore.collection(ExpenseEfficiencyService.assessmentsCollection).get()).docs, isEmpty);
    });
  });

  // ================================================================ lifecycle
  group('transaction lifecycle', () {
    test('edited amounts: current amount used; avoidable above it is capped and flagged, never increased', () async {
      final a = await expense(1000, DateTime(2026, 11, 3));
      final b = await expense(1000, DateTime(2026, 11, 4));
      await eff.saveAssessment(requesterRole: admin, transactionId: a, category: ExpenseAssessmentCategory.waste); // 1000
      await eff.saveAssessment(requesterRole: admin, transactionId: b, category: ExpenseAssessmentCategory.excessive, avoidableAmount: 300);
      await firestore.doc('finance_ledger/$a').update({'amount': 600}); // edited down below the avoidable amount
      await firestore.doc('finance_ledger/$b').update({'amount': 1500}); // edited up
      final r = await report(nov);
      final ia = r.allItems.firstWhere((i) => i.id == a), ib = r.allItems.firstWhere((i) => i.id == b);
      expect([ia.countedAvoidable, ia.avoidableExceedsAmount, ia.needsReview], [600, true, true]);
      expect(ia.reviewReason, contains('only ₹600 is counted'));
      expect([ib.countedAvoidable, ib.needsReview], [300, true], reason: 'not increased with the amount');
      expect([r.expenses, r.potentialSavings], [2100, 900]);
      expect(r.needsReview.map((i) => i.id).toSet(), {a, b});
      expect((await eff.getAssessments())[a]!.avoidableAmount, 1000, reason: 'the stored assessment is not rewritten');
    });

    test('cancelled expenses: out of actual expenses and savings, assessment kept, no further changes', () async {
      final a = await expense(800, DateTime(2026, 11, 3));
      await expense(200, DateTime(2026, 11, 4));
      await eff.saveAssessment(requesterRole: admin, transactionId: a, category: ExpenseAssessmentCategory.waste);
      await firestore.doc('finance_ledger/$a').update({'status': 'cancelled'});
      final r = await report(nov);
      expect([r.expenses, r.potentialSavings, r.cancelledCount], [200, 0, 1]);
      expect(r.allItems.firstWhere((i) => i.id == a).cancelled, isTrue);
      expect((await report(nov, filter: const EfficiencyFilter(status: EfficiencyStatusFilter.cancelled))).items.single.assessment!.category, ExpenseAssessmentCategory.waste);
      await expectLater(eff.saveAssessment(requesterRole: admin, transactionId: a, category: ExpenseAssessmentCategory.necessary), throwsA(isA<StateError>()));
      expect(r.total(ExpenseAssessmentCategory.waste), 0);
    });

    test('a deleted transaction leaves an orphaned assessment: listed, never counted or moved', () async {
      final a = await expense(500, DateTime(2026, 11, 3));
      await expense(500, DateTime(2026, 11, 3));
      await eff.saveAssessment(requesterRole: admin, transactionId: a, category: ExpenseAssessmentCategory.waste);
      await firestore.doc('finance_ledger/$a').delete();
      final r = await report(nov);
      expect([r.orphans.single.transactionId, r.potentialSavings, r.allItems.single.category], [a, 0, ExpenseAssessmentCategory.underReview]);
    });

    test('same description, amount and date: separate expenses by their stable ids', () async {
      final a = await expense(250, DateTime(2026, 11, 5), title: 'Printer paper');
      final b = await expense(250, DateTime(2026, 11, 5), title: 'Printer paper');
      expect(a, isNot(b));
      await eff.saveAssessment(requesterRole: admin, transactionId: a, category: ExpenseAssessmentCategory.waste);
      final r = await report(nov);
      expect({for (final i in r.allItems) i.id: i.category}, {a: ExpenseAssessmentCategory.waste, b: ExpenseAssessmentCategory.underReview});
      expect(r.potentialSavings, 250);
      // Editing the description does not detach the assessment.
      await firestore.doc('finance_ledger/$a').update({'title': 'Paper (renamed)'});
      expect((await report(nov)).allItems.firstWhere((i) => i.id == a).category, ExpenseAssessmentCategory.waste);
    });
  });

  // ================================================================ actual / adjusted
  group('actual and adjusted', () {
    Future<void> seed() async {
      await income(10000, DateTime(2026, 10, 2));
      await income(12000, DateTime(2026, 11, 2));
      await expense(3000, DateTime(2026, 10, 10));
      final w = await expense(1500, DateTime(2026, 11, 10));
      final x = await expense(4000, DateTime(2026, 11, 12), category: 'power', name: 'Electricity');
      await expense(2500, DateTime(2026, 11, 15));
      final c = await expense(900, DateTime(2026, 11, 20));
      await eff.saveAssessment(requesterRole: admin, transactionId: w, category: ExpenseAssessmentCategory.waste, avoidableAmount: 500);
      await eff.saveAssessment(requesterRole: admin, transactionId: x, category: ExpenseAssessmentCategory.excessive, avoidableAmount: 1000);
      await eff.saveAssessment(requesterRole: admin, transactionId: c, category: ExpenseAssessmentCategory.waste);
      await firestore.doc('finance_ledger/$c').update({'status': 'cancelled'});
    }

    test('Actual equals the Ledger Profit / Loss for a month, a financial year and a custom range', () async {
      await seed();
      final entries = await ledger();
      final r = await report(nov);
      final p = LedgerPeriodSummary.of(entries, const LedgerPeriod.month(2026, 11));
      expect([r.income, r.expenses, r.actualSurplus], [p.totalIncome, p.totalExpenses, p.profitLoss]);
      expect([r.income, r.expenses, r.actualSurplus], [12000, 8000, 4000]);
      final years = AcademicYearService(firestore: firestore);
      await years.createAcademicYear(schoolId: kDefaultSchoolId, requesterRole: 'admin', name: '2026-2027', startDate: DateTime(2026, 6, 1),
          endDate: DateTime(2027, 5, 31), createdBy: 'admin-1', setAsCurrent: true);
      final fy = (await years.getAllAcademicYears(schoolId: kDefaultSchoolId)).single;
      final fyr = await report(EfficiencyPeriod.financialYear(fy));
      final months = [for (var m = 6; m <= 17; m++) LedgerPeriodSummary.of(entries, LedgerPeriod.month(2026 + (m - 1) ~/ 12, (m - 1) % 12 + 1))];
      expect(fyr.income, months.fold<double>(0, (s, x) => s + x.totalIncome));
      expect(fyr.expenses, months.fold<double>(0, (s, x) => s + x.totalExpenses));
      expect([fyr.income, fyr.expenses, fyr.actualSurplus], [22000, 11000, 11000]);
      final custom = await report(EfficiencyPeriod.custom(DateTime(2026, 11, 11), DateTime(2026, 11, 30)));
      expect([custom.income, custom.expenses], [0, 6500]);
    });

    test('Adjusted = Actual + identified savings (waste + explicit excessive), cancelled excluded, nothing twice', () async {
      await seed();
      final r = await report(nov);
      expect([r.potentialSavings, r.adjustedSurplus], [1500, 5500]);
      expect(r.adjustedSurplus - r.actualSurplus, r.potentialSavings);
      // Saving the same assessment again replaces it: one record per expense.
      final w = r.allItems.firstWhere((i) => i.category == ExpenseAssessmentCategory.waste && !i.cancelled).id;
      await eff.saveAssessment(requesterRole: admin, transactionId: w, category: ExpenseAssessmentCategory.waste, avoidableAmount: 500);
      expect((await report(nov)).potentialSavings, 1500);
      expect((await firestore.collection(ExpenseEfficiencyService.assessmentsCollection).get()).docs.length, 3);
    });

    test('filtered periods reconcile: months add up to the year; filters narrow lists but never the surplus', () async {
      await seed();
      final oct = await report(EfficiencyPeriod.month(2026, 10));
      final n = await report(nov);
      final both = await report(EfficiencyPeriod.custom(DateTime(2026, 10, 1), DateTime(2026, 11, 30)));
      expect([both.income, both.expenses, both.potentialSavings], [oct.income + n.income, oct.expenses + n.expenses, oct.potentialSavings + n.potentialSavings]);
      final filtered = await report(nov, filter: const EfficiencyFilter(categoryId: 'power'));
      expect([filtered.actualSurplus, filtered.potentialSavings], [n.actualSurplus, n.potentialSavings]);
      expect([filtered.items.length, filtered.filteredExpenses, filtered.filteredSavings], [1, 4000, 1000]);
      final waste = await report(nov, filter: const EfficiencyFilter(assessment: ExpenseAssessmentCategory.waste));
      expect(waste.items.single.entry.amount, 1500, reason: 'the cancelled waste expense is not in the Waste list');
    });
  });

  // ================================================================ targets
  group('targets', () {
    ExpenseTarget t(String cat, double amount, String start, {String end = '', bool active = true, String id = ''}) => ExpenseTarget(
        id: id, schoolId: kDefaultSchoolId, categoryId: cat, categoryName: cat == 'supplies' ? 'Supplies' : 'Electricity',
        monthlyAmount: amount, startMonth: start, endMonth: end, isActive: active);

    test('create, edit, deactivate; overlapping active targets refused; invalid values refused', () async {
      final id = await eff.saveTarget(requesterRole: admin, target: t('supplies', 2000, '2026-06', end: '2027-05'));
      await expectLater(eff.saveTarget(requesterRole: admin, target: t('supplies', 1500, '2027-01')),
          throwsA(isA<StateError>().having((e) => e.message, 'm', contains('already has an active target'))));
      expect(await eff.saveTarget(requesterRole: admin, target: t('supplies', 1500, '2027-06')), isNotEmpty, reason: 'after the first ends');
      expect(await eff.saveTarget(requesterRole: admin, target: t('power', 3000, '2026-06')), isNotEmpty, reason: 'another category');
      for (final bad in [t('supplies', -1, '2028-01'), t('supplies', 100, '2028-13'), t('supplies', 100, '2028-05', end: '2028-01'), t('', 100, '2028-01')]) {
        await expectLater(eff.saveTarget(requesterRole: admin, target: bad), throwsA(isA<StateError>()));
      }
      await eff.saveTarget(requesterRole: admin, target: t('supplies', 1800, '2026-06', end: '2027-05', id: id));
      final saved = (await eff.getTargets()).firstWhere((x) => x.id == id);
      expect([saved.monthlyAmount, saved.createdBy, saved.updatedBy], [1800, 'admin-uid', 'admin-uid']);
      await eff.setTargetActive(requesterRole: admin, target: saved, active: false);
      expect(await eff.saveTarget(requesterRole: admin, target: t('supplies', 1500, '2027-01', end: '2027-03')), isNotEmpty, reason: 'no clash once deactivated');
      final h = await eff.history(target: true, id: id);
      expect(h.map((e) => e['action']).toSet(), {'created', 'updated', 'deactivated'});
    });

    test('monthly targets add up per month for a year; missing targets use actual spending ("Target not set"), never zero', () async {
      await income(30000, DateTime(2026, 11, 1));
      await expense(2500, DateTime(2026, 10, 5)); // supplies Oct
      await expense(1500, DateTime(2026, 11, 5)); // supplies Nov
      await expense(4000, DateTime(2026, 11, 6), category: 'power', name: 'Electricity');
      await eff.saveTarget(requesterRole: admin, target: t('supplies', 2000, '2026-10', end: '2026-12'));
      await eff.saveTarget(requesterRole: admin, target: t('power', 9999, '2025-01', end: '2025-12', active: false)); // inactive: ignored
      final q = await report(EfficiencyPeriod.custom(DateTime(2026, 10, 1), DateTime(2026, 12, 31))); // a quarter
      final supplies = q.categories.firstWhere((c) => c.key == 'supplies');
      final power = q.categories.firstWhere((c) => c.key == 'power');
      expect([supplies.target, supplies.targetedMonths, supplies.actual, supplies.difference, supplies.variancePercent], [6000, 3, 4000, -2000, closeTo(-33.33, 0.01)]);
      expect([power.hasTarget, power.targetLabel, power.scenario], [false, 'Target not set', 4000]);
      expect(q.targetExpenses, 6000 + 4000);
      expect(q.targetSurplus, 30000 - 10000);
      expect(q.untargetedCategories.map((c) => c.key), contains('power'));
      // Over target in two months: recurring overspending.
      await expense(2600, DateTime(2026, 12, 2));
      await expense(1000, DateTime(2026, 11, 20));
      final again = await report(EfficiencyPeriod.custom(DateTime(2026, 10, 1), DateTime(2026, 12, 31)));
      expect(again.recurringOverspend.map((c) => c.key), ['supplies']);
      expect(again.insights.any((i) => i.observation.contains('Supplies was over its target in 3 of 3')), isTrue);
    });

    test('a partly covered month uses actual spending; target data never changes actual figures', () async {
      await expense(1000, DateTime(2026, 11, 5));
      await expense(1000, DateTime(2026, 11, 25));
      await eff.saveTarget(requesterRole: admin, target: t('supplies', 100, '2026-11'));
      final half = await report(EfficiencyPeriod.custom(DateTime(2026, 11, 15), DateTime(2026, 11, 30)));
      expect([half.categories.firstWhere((c) => c.key == 'supplies').hasTarget, half.targetExpenses, half.expenses], [false, 1000, 1000]);
      final full = await report(nov);
      expect([full.targetExpenses, full.expenses, full.actualSurplus, full.potentialSavings], [100, 2000, -2000, 0]);
    });
  });

  // ================================================================ permissions
  group('permissions', () {
    test('only an administrator can write assessments or targets', () async {
      final a = await expense(500, DateTime(2026, 11, 3));
      final target = ExpenseTarget(id: '', schoolId: kDefaultSchoolId, categoryId: 'supplies', categoryName: 'Supplies', monthlyAmount: 100, startMonth: '2026-11');
      for (final role in ['teacher', 'parent', 'staff', '']) {
        await expectLater(eff.saveAssessment(requesterRole: role, transactionId: a, category: ExpenseAssessmentCategory.waste), throwsA(isA<UnauthorizedExpenseEfficiencyException>()));
        await expectLater(eff.deleteAssessment(requesterRole: role, transactionId: a), throwsA(isA<UnauthorizedExpenseEfficiencyException>()));
        await expectLater(eff.saveTarget(requesterRole: role, target: target), throwsA(isA<UnauthorizedExpenseEfficiencyException>()));
        await expectLater(eff.deleteTarget(requesterRole: role, id: 'x'), throwsA(isA<UnauthorizedExpenseEfficiencyException>()));
      }
      expect((await firestore.collection(ExpenseEfficiencyService.assessmentsCollection).get()).docs, isEmpty);
      expect((await firestore.collection(ExpenseEfficiencyService.targetsCollection).get()).docs, isEmpty);
      await eff.saveAssessment(requesterRole: 'Admin', transactionId: a, category: ExpenseAssessmentCategory.waste);
      expect(await eff.saveTarget(requesterRole: admin, target: target), isNotEmpty);
    });
  });

  // ================================================================ separation
  group('separation from Finance', () {
    test('creating, editing and deleting assessments and targets changes no Finance or Fees record, balance or Profit / Loss', () async {
      await income(20000, DateTime(2026, 11, 1));
      final a = await expense(1200, DateTime(2026, 11, 3));
      final b = await expense(800, DateTime(2026, 11, 4), category: 'power', name: 'Electricity');
      await firestore.collection('student_fee_assignments').doc('fa1').set({'studentId': 's1', 'totalFee': 3000, 'paidAmount': 1000});
      await firestore.collection('fee_receipts').doc('r1').set({'assignmentId': 'fa1', 'amount': 1000});
      final before = await financeDump();
      final summary = await finance.watchDashboardSummary().first;
      final pl = LedgerPeriodSummary.of(await ledger(), const LedgerPeriod.month(2026, 11));
      final monthEnd = await finance.dashboardSummaryAt(periodEnd: DateTime(2026, 11, 30));

      await eff.saveAssessment(requesterRole: admin, transactionId: a, category: ExpenseAssessmentCategory.waste);
      await eff.saveAssessment(requesterRole: admin, transactionId: a, category: ExpenseAssessmentCategory.waste, avoidableAmount: 600, reason: 'edit');
      await eff.saveAssessment(requesterRole: admin, transactionId: b, category: ExpenseAssessmentCategory.excessive, avoidableAmount: 100);
      final tid = await eff.saveTarget(requesterRole: admin,
          target: const ExpenseTarget(id: '', schoolId: kDefaultSchoolId, categoryId: 'supplies', categoryName: 'Supplies', monthlyAmount: 500, startMonth: '2026-11'));
      final t = (await eff.getTargets()).single;
      await eff.setTargetActive(requesterRole: admin, target: t, active: false);
      await eff.deleteTarget(requesterRole: admin, id: tid);
      await eff.deleteAssessment(requesterRole: admin, transactionId: b);
      await report(nov);

      expect(await financeDump(), before, reason: 'ledger, income, expenses, accounts, categories, invoices, fee assignments and receipts unchanged');
      final after = await finance.watchDashboardSummary().first;
      expect([after.openingBalance, after.closingBalance, after.cashBalance, after.bankBalance, after.upiBalance, after.totalIncome, after.totalExpenses, after.netBalance],
          [summary.openingBalance, summary.closingBalance, summary.cashBalance, summary.bankBalance, summary.upiBalance, summary.totalIncome, summary.totalExpenses, summary.netBalance]);
      final pl2 = LedgerPeriodSummary.of(await ledger(), const LedgerPeriod.month(2026, 11));
      expect([pl2.totalIncome, pl2.totalExpenses, pl2.profitLoss], [pl.totalIncome, pl.totalExpenses, pl.profitLoss]);
      final monthEnd2 = await finance.dashboardSummaryAt(periodEnd: DateTime(2026, 11, 30));
      expect(monthEnd2.closingBalance, monthEnd.closingBalance);
      final written = {
        for (final c in [ExpenseEfficiencyService.assessmentsCollection, ExpenseEfficiencyService.targetsCollection])
          c: (await firestore.collection(c).get()).docs.length,
      };
      expect(written, {ExpenseEfficiencyService.assessmentsCollection: 2, ExpenseEfficiencyService.targetsCollection: 1},
          reason: 'only its own records (removed ones kept as isDeleted)');
      expect([(await eff.getAssessments()).keys.toList(), await eff.getTargets()], [[a], isEmpty]);
    });
  });

  // ================================================================ reports
  group('reports', () {
    test('PDF totals match the report the screen shows', () async {
      await income(12000, DateTime(2026, 11, 2));
      final w = await expense(1500, DateTime(2026, 11, 10), title: 'Extra chairs');
      await expense(4000, DateTime(2026, 11, 12), category: 'power', name: 'Electricity');
      await eff.saveAssessment(requesterRole: admin, transactionId: w, category: ExpenseAssessmentCategory.waste, avoidableAmount: 500, reason: 'Not needed', managementNote: 'Check stock first');
      await eff.saveTarget(requesterRole: admin,
          target: const ExpenseTarget(id: '', schoolId: kDefaultSchoolId, categoryId: 'power', categoryName: 'Electricity', monthlyAmount: 3500, startMonth: '2026-01'));
      final r = await report(nov);
      expect([r.actualSurplus, r.potentialSavings, r.adjustedSurplus, r.targetExpenses, r.targetSurplus], [6500, 500, 7000, 5000, 7000]);
      final h = FeeReportPdfHeader(schoolName: 'Test School', title: ExpenseEfficiencyPdf.title, filters: const ['Category: All'], generatedAt: DateTime(2026, 11, 30, 9));
      final words = _pdfWords(await ExpenseEfficiencyPdf.build(r, h, compress: false));
      for (final (label, v) in [
        ('Actual income:', r.income), ('Actual expenses:', r.expenses), ('Actual Operating Surplus:', r.actualSurplus),
        ('Identified Potential Savings:', r.potentialSavings), ('Target Operating Surplus:', r.targetSurplus), ('Target expenses:', r.targetExpenses),
      ]) {
        expect(_hasPhrase(words, '$label ${efficiencyMoney(v, symbol: 'Rs. ')}'), isTrue, reason: label);
      }
      expect(_hasPhrase(words, '${ExpenseEfficiencyPdf.adjustedLabel}: ${efficiencyMoney(r.adjustedSurplus, symbol: 'Rs. ')}'), isTrue);
      for (final phrase in ['Extra chairs', 'Not needed', 'Check stock first', 'Waste / Avoidable', 'Period: November 2026', 'Page 1 of 1']) {
        expect(_hasPhrase(words, phrase), isTrue, reason: phrase);
      }
    });

    group('navigation: Finance → Reports → Expense Efficiency', () {
      Future<void> pumpFinance(WidgetTester tester) async {
        tester.view.physicalSize = const Size(1400, 4000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(ProviderScope(
          overrides: [
            currentUserProvider.overrideWith((ref) => AppUser(id: 'u1', phone: '9999999999', role: 'admin', isActive: true)),
            academicYearServiceProvider.overrideWithValue(AcademicYearService(firestore: firestore)),
          ],
          child: MaterialApp(home: AdminFinanceScreen(service: finance, efficiencyService: eff, clock: () => DateTime(2026, 11, 20))),
        ));
        await tester.pumpAndSettle();
      }

      bool reportsSelected(WidgetTester tester) => tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Reports')).selected;

      testWidgets('no separate tab; Reports lists it last as a working entry beside the unchanged Coming Soon reports', (tester) async {
        await pumpFinance(tester);
        expect([for (final c in tester.widgetList<ChoiceChip>(find.byType(ChoiceChip))) (c.label as Text).data], _financeTabs);
        expect(find.widgetWithText(ChoiceChip, 'Expense Efficiency'), findsNothing);
        await tester.tap(find.widgetWithText(ChoiceChip, 'Reports'));
        await tester.pumpAndSettle();
        for (final t in ['Daily Cash Book', 'Monthly Income & Expense', 'Category Expense Report', 'Staff Salary Report', 'Vendor Payment Report', 'Profit / Loss Summary']) {
          expect(find.text(t), findsOneWidget, reason: t);
        }
        expect(find.text('COMING SOON'), findsNWidgets(6), reason: 'existing reports unchanged');
        final card = find.byKey(const Key('finance-report-expense-efficiency'));
        expect(find.descendant(of: card, matching: find.text('Expense Efficiency')), findsOneWidget);
        expect(
          find.descendant(
              of: card,
              matching: find.text('Analyse expenses, identify avoidable spending, manage monthly targets and compare actual, adjusted and target financial performance.')),
          findsOneWidget,
        );
        expect(find.descendant(of: card, matching: find.text('COMING SOON')), findsNothing, reason: 'it works');
        expect(tester.getTopLeft(card).dy, greaterThan(tester.getTopLeft(find.text('Profit / Loss Summary')).dy), reason: 'after Profit / Loss Summary');
        expect(find.byKey(const Key('finance-add')), findsNothing, reason: 'Reports still has no Add button');
      });

      testWidgets('opens the whole existing feature; Back returns to Reports; browser/system back does too', (tester) async {
        late String w;
        await tester.runAsync(() async {
          await income(12000, DateTime(2026, 11, 2));
          w = await expense(1500, DateTime(2026, 11, 10), title: 'Extra chairs', remarks: 'Bought before checking the store room');
          await eff.saveTarget(requesterRole: admin,
              target: const ExpenseTarget(id: '', schoolId: kDefaultSchoolId, categoryId: 'supplies', categoryName: 'Supplies', monthlyAmount: 1000, startMonth: '2026-11'));
        });
        await pumpFinance(tester);
        await _openFromReports(tester);
        expect(find.byKey(const Key('expense-efficiency')), findsOneWidget);
        expect(find.byKey(const Key('expense-efficiency-breadcrumb')), findsOneWidget);
        for (final k in ['efficiency-overview', 'efficiency-assessment', 'efficiency-scenarios', 'efficiency-categories', 'efficiency-months',
          'efficiency-comparison', 'efficiency-insights', 'efficiency-targets', 'efficiency-expenses', 'efficiency-export', 'efficiency-filter-category',
          'efficiency-filter-assessment', 'efficiency-filter-status', 'efficiency-period-kind']) {
          expect(find.byKey(Key(k)), findsOneWidget, reason: k);
        }
        expect(tester.widget<ExpenseCategoryPill>(find.byKey(Key('efficiency-expense-pill-$w'))).category, ExpenseAssessmentCategory.underReview);
        expect(find.byKey(const Key('efficiency-target-add')), findsOneWidget, reason: 'admin role still checked the same way');
        expect(tester.widget<Text>(find.byKey(const Key('efficiency-target-supplies'))).data, '₹1,000');

        // Assess from here, as before.
        await tester.ensureVisible(find.byKey(Key('efficiency-assess-$w')));
        await tester.tap(find.byKey(Key('efficiency-assess-$w')));
        await tester.pumpAndSettle();
        expect(tester.widget<Text>(find.byKey(const Key('assessment-expense-description'))).data, 'Bought before checking the store room');
        await tester.tap(find.byKey(const Key('assessment-category')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('assessment-option-waste')).last);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('assessment-save')));
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pumpAndSettle();
        expect(tester.widget<Text>(find.byKey(const Key('efficiency-tile-savings'))).data, '₹1,500');

        // The page's own Back button.
        await tester.ensureVisible(find.byKey(const Key('expense-efficiency-back')));
        await tester.tap(find.byKey(const Key('expense-efficiency-back')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('expense-efficiency')), findsNothing);
        expect(find.byKey(const Key('finance-report-expense-efficiency')), findsOneWidget);
        expect(reportsSelected(tester), isTrue, reason: 'back on Finance → Reports');

        // Browser back (a popRoute from the platform) does the same, once.
        await _openFromReports(tester);
        expect(find.byKey(const Key('expense-efficiency')), findsOneWidget);
        expect(tester.widget<Text>(find.byKey(const Key('efficiency-tile-savings'))).data, '₹1,500', reason: 'the same saved data');
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('expense-efficiency')), findsNothing);
        expect([reportsSelected(tester), find.byType(AdminFinanceScreen).evaluate().length], [true, 1], reason: 'Finance stays open on Reports');
      });
    });

    group('Assess dialog: the ledger entry\'s own description', () {
      const longText = 'Bought 40 reams of A4 paper and 12 toner cartridges for the term because the previous order arrived late; '
          'the supplier charged express delivery and a small-order surcharge. Stock on hand was already enough for six weeks, '
          'so part of this purchase could have waited for the regular monthly order.';

      Future<void> openTab(WidgetTester tester) async {
        tester.view.physicalSize = const Size(1400, 4000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(ProviderScope(
          overrides: [
            currentUserProvider.overrideWith((ref) => AppUser(id: 'u1', phone: '9999999999', role: 'admin', isActive: true)),
            academicYearServiceProvider.overrideWithValue(AcademicYearService(firestore: firestore)),
          ],
          child: MaterialApp(home: AdminFinanceScreen(service: finance, efficiencyService: eff, clock: () => DateTime(2026, 11, 20))),
        ));
        await tester.pumpAndSettle();
        await _openFromReports(tester);
      }

      Future<void> openAssess(WidgetTester tester, String id) async {
        await tester.ensureVisible(find.byKey(Key('efficiency-assess-$id')));
        await tester.tap(find.byKey(Key('efficiency-assess-$id')));
        await tester.pumpAndSettle();
      }

      String shownTitle(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('assessment-expense-title'))).data!;
      Text shownDescription(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('assessment-expense-description')));

      testWidgets('each expense shows its own description (multi-line, long, or none), separate from the title', (tester) async {
        late String multi, long, none;
        await tester.runAsync(() async {
          multi = await expense(1200, DateTime(2026, 11, 3), title: 'Art supplies', remarks: 'Crayons and chart paper\nfor the Diwali display');
          long = await expense(5400, DateTime(2026, 11, 4), title: 'Stationery', remarks: longText);
          none = await expense(300, DateTime(2026, 11, 5), title: 'Printer paper');
        });
        await openTab(tester);

        await openAssess(tester, multi);
        expect(find.text('Expense Description'), findsOneWidget);
        expect(shownTitle(tester), 'Art supplies');
        expect(shownDescription(tester).data, 'Crayons and chart paper\nfor the Diwali display', reason: 'line breaks kept');
        expect(find.text(longText), findsNothing, reason: 'not another expense\'s description');
        expect(tester.widget<TextField>(find.byKey(const Key('assessment-note'))).controller!.text, isEmpty, reason: 'not prefilled into the assessment');
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        await openAssess(tester, long);
        final text = shownDescription(tester);
        expect([text.data, text.softWrap, text.maxLines, text.overflow], [longText, true, null, null], reason: 'shown in full and wrapped');
        expect(tester.getSize(find.byKey(const Key('assessment-expense-description'))).height, greaterThan(30), reason: 'wraps onto several lines');
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        await openAssess(tester, none);
        expect(shownTitle(tester), 'Printer paper');
        expect(shownDescription(tester).data, 'No description recorded for this expense.');
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
      });

      testWidgets('coloured pills: all five categories in the list and summary, Under Review grey, avoidable amount beside the pill', (tester) async {
        final ids = <ExpenseAssessmentCategory, String>{};
        late String unassessed;
        late Map<String, dynamic> before;
        await tester.runAsync(() async {
          for (final (i, c) in ExpenseAssessmentCategory.values.indexed) {
            ids[c] = await expense(1000, DateTime(2026, 11, 2 + i), title: 'Item ${c.key}');
            if (c != ExpenseAssessmentCategory.underReview) {
              await eff.saveAssessment(requesterRole: admin, transactionId: ids[c]!, category: c, avoidableAmount: 250);
            }
          }
          unassessed = ids[ExpenseAssessmentCategory.underReview]!; // never assessed
          before = {
            for (final c in ['finance_ledger', ExpenseEfficiencyService.assessmentsCollection])
              c: [for (final d in (await firestore.collection(c).get()).docs) '${d.id}:${d.data()}']..sort(),
          };
        });
        await openTab(tester);

        // The one mapping: hue per category, Under Review neutral grey.
        final expected = {
          ExpenseAssessmentCategory.necessary: Colors.green,
          ExpenseAssessmentCategory.useful: Colors.blue,
          ExpenseAssessmentCategory.waste: Colors.red,
        };
        for (final MapEntry(key: c, value: hue) in expected.entries) {
          final st = ExpenseCategoryStyle.of(c);
          expect([st.background, st.border, st.foreground], [hue.shade50, hue.shade200, hue.shade900], reason: c.label);
        }
        final orange = ExpenseCategoryStyle.of(ExpenseAssessmentCategory.excessive);
        expect([orange.background, orange.border, orange.foreground], [Colors.orange.shade50, Colors.orange.shade200, Colors.deepOrange.shade900]);
        final grey = ExpenseCategoryStyle.of(ExpenseAssessmentCategory.underReview);
        expect([grey.background, grey.foreground], [Colors.grey.shade100, Colors.grey.shade800]);
        for (final c in ExpenseAssessmentCategory.values) {
          final st = ExpenseCategoryStyle.of(c);
          expect(_contrast(st.foreground, st.background), greaterThan(4.5), reason: '${c.label}: readable (WCAG AA)');
        }

        // Expense list: each expense's pill is its category; unassessed is Under Review.
        Container pillBox(Finder pill) => tester.widget<Container>(find.descendant(of: pill, matching: find.byType(Container)).first);
        for (final MapEntry(key: c, value: id) in ids.entries) {
          final pill = find.byKey(Key('efficiency-expense-pill-$id'));
          expect(tester.widget<ExpenseCategoryPill>(pill).category, c);
          expect((pillBox(pill).decoration as BoxDecoration).color, ExpenseCategoryStyle.of(c).background, reason: c.label);
          final label = tester.widget<Text>(find.descendant(of: pill, matching: find.byType(Text)));
          expect([label.data, label.style!.color], [c.label, ExpenseCategoryStyle.of(c).foreground]);
        }
        expect(tester.widget<ExpenseCategoryPill>(find.byKey(Key('efficiency-expense-pill-$unassessed'))).category, ExpenseAssessmentCategory.underReview);
        // The avoidable amount is separate text next to the pill, never inside it.
        final waste = ids[ExpenseAssessmentCategory.waste]!;
        expect(tester.widget<Text>(find.byKey(Key('efficiency-expense-avoidable-$waste'))).data, 'Avoidable ₹250');
        expect(find.descendant(of: find.byKey(Key('efficiency-expense-pill-$waste')), matching: find.textContaining('250')), findsNothing);
        expect(find.byKey(Key('efficiency-expense-avoidable-${ids[ExpenseAssessmentCategory.necessary]}')), findsNothing);
        // Long names are never clipped.
        final longest = find.descendant(of: find.byKey(Key('efficiency-expense-pill-$waste')), matching: find.byType(Text));
        expect(tester.renderObject<RenderParagraph>(longest).didExceedMaxLines, isFalse);
        expect(tester.takeException(), isNull, reason: 'no overflow');

        // Summary: one pill-headed tile per category, amounts unchanged.
        for (final c in ExpenseAssessmentCategory.values) {
          final tile = find.byKey(Key('efficiency-category-tile-${c.key}'));
          expect(tester.widget<ExpenseCategoryPill>(find.descendant(of: tile, matching: find.byType(ExpenseCategoryPill))).category, c);
          expect(tester.widget<Text>(find.byKey(Key('efficiency-tile-${c.key}'))).data, '₹1,000');
          expect(tester.widget<Text>(find.byKey(Key('efficiency-tile-count-${c.key}'))).data, '1');
        }
        final after = (await tester.runAsync(() async => {
              for (final c in ['finance_ledger', ExpenseEfficiencyService.assessmentsCollection])
                c: [for (final d in (await firestore.collection(c).get()).docs) '${d.id}:${d.data()}']..sort(),
            }))!;
        expect(after, before, reason: 'display only: no stored value changes');
      });

      testWidgets('the dialog shows the selected category as its pill; saving and editing keep the category and badge', (tester) async {
        late String id;
        await tester.runAsync(() async => id = await expense(900, DateTime(2026, 11, 3), title: 'Extra chairs'));
        await openTab(tester);
        ExpenseAssessmentCategory selected() => tester.widget<ExpenseCategoryPill>(find.byKey(const Key('assessment-selected-pill'))).category;
        ExpenseAssessmentCategory listed() => tester.widget<ExpenseCategoryPill>(find.byKey(Key('efficiency-expense-pill-$id'))).category;
        expect(listed(), ExpenseAssessmentCategory.underReview);

        await openAssess(tester, id);
        expect(selected(), ExpenseAssessmentCategory.underReview, reason: 'not yet assessed');
        await tester.tap(find.byKey(const Key('assessment-category')));
        await tester.pumpAndSettle();
        for (final c in ExpenseAssessmentCategory.values) {
          expect(find.byKey(Key('assessment-option-${c.key}')), findsWidgets, reason: 'each option is its pill');
        }
        await tester.tap(find.byKey(const Key('assessment-option-excessive')).last);
        await tester.pumpAndSettle();
        expect(selected(), ExpenseAssessmentCategory.excessive);
        await tester.enterText(find.byKey(const Key('assessment-avoidable')), '150');
        await tester.tap(find.byKey(const Key('assessment-save')));
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pumpAndSettle();
        expect(listed(), ExpenseAssessmentCategory.excessive);
        expect(tester.widget<Text>(find.byKey(Key('efficiency-expense-avoidable-$id'))).data, 'Avoidable ₹150');

        await openAssess(tester, id);
        expect(selected(), ExpenseAssessmentCategory.excessive, reason: 'Edit opens on the saved category');
        await tester.enterText(find.byKey(const Key('assessment-note')), 'Buy in bulk next time');
        await tester.tap(find.byKey(const Key('assessment-save')));
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pumpAndSettle();
        expect(listed(), ExpenseAssessmentCategory.excessive);
        final stored = (await tester.runAsync(() async => (await firestore.doc('${ExpenseEfficiencyService.assessmentsCollection}/$id').get()).data()!))!;
        expect([stored['assessmentCategory'], stored['avoidableAmount'], stored['managementNote']], ['excessive', 150, 'Buy in bulk next time'],
            reason: 'stored key unchanged by the display');
      });

      testWidgets('editing an assessment shows it too; saving never changes the ledger entry or copies the description', (tester) async {
        late String id;
        late Map<String, dynamic> ledgerBefore;
        await tester.runAsync(() async {
          id = await expense(1200, DateTime(2026, 11, 3), title: 'Art supplies', remarks: 'Crayons and chart paper');
          ledgerBefore = (await firestore.doc('finance_ledger/$id').get()).data()!;
        });
        await openTab(tester);
        await openAssess(tester, id);
        await tester.tap(find.byKey(const Key('assessment-category')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Useful').last);
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('assessment-reason')), 'Festival display');
        await tester.tap(find.byKey(const Key('assessment-save')));
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pumpAndSettle();

        // Edit: the same description, read-only (not a text field).
        expect(find.byKey(Key('efficiency-assess-$id')), findsOneWidget);
        expect(tester.widget<TextButton>(find.byKey(Key('efficiency-assess-$id'))).child, isA<Text>().having((t) => t.data, 'label', 'Edit'));
        await openAssess(tester, id);
        expect(shownDescription(tester).data, 'Crayons and chart paper');
        expect(find.descendant(of: find.byKey(const Key('assessment-expense-description-section')), matching: find.byType(EditableText)), findsNothing);
        await tester.enterText(find.byKey(const Key('assessment-note')), 'Reuse next year');
        await tester.tap(find.byKey(const Key('assessment-save')));
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pumpAndSettle();

        final (ledgerAfter, assessment) = (await tester.runAsync(() async => (
              (await firestore.doc('finance_ledger/$id').get()).data()!,
              (await firestore.doc('${ExpenseEfficiencyService.assessmentsCollection}/$id').get()).data()!,
            )))!;
        expect(ledgerAfter, ledgerBefore, reason: 'the ledger entry, its description included, is unchanged');
        expect([assessment['assessmentCategory'], assessment['reason'], assessment['managementNote']], ['useful', 'Festival display', 'Reuse next year']);
        expect(assessment.containsKey('description'), isFalse);
        expect(assessment.values.whereType<String>().any((v) => v.contains('Crayons')), isFalse, reason: 'the description is not copied into the assessment');
      });
    });

    testWidgets('Reports → Expense Efficiency: figures shown; admin can assess, others only view', (tester) async {
      tester.view.physicalSize = const Size(1400, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late String w;
      await tester.runAsync(() async {
        await income(12000, DateTime(2026, 11, 2));
        w = await expense(1500, DateTime(2026, 11, 10), title: 'Extra chairs');
      });
      Future<void> pump(String role) async {
        await tester.pumpWidget(ProviderScope(
          overrides: [
            currentUserProvider.overrideWith((ref) => AppUser(id: 'u1', phone: '9999999999', role: role, isActive: true)),
            academicYearServiceProvider.overrideWithValue(AcademicYearService(firestore: firestore)),
          ],
          child: MaterialApp(home: AdminFinanceScreen(service: finance, efficiencyService: eff, clock: () => DateTime(2026, 11, 20))),
        ));
        await tester.pumpAndSettle();
        expect([for (final c in tester.widgetList<ChoiceChip>(find.byType(ChoiceChip))) (c.label as Text).data], _financeTabs,
            reason: 'no separate Expense Efficiency tab');
        await _openFromReports(tester);
      }

      await pump('admin');
      String tile(String k) => tester.widget<Text>(find.byKey(Key('efficiency-tile-$k'))).data!;
      expect([tile('income'), tile('expenses'), tile('surplus'), tile('savings')], ['₹12,000', '₹1,500', '₹10,500', '₹0']);
      expect(find.byKey(const Key('finance-add')), findsNothing, reason: 'no Add button on the Expense Efficiency page');
      await tester.tap(find.byKey(Key('efficiency-assess-$w')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('assessment-category')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Waste / Avoidable').last);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byKey(const Key('assessment-avoidable'))).controller!.text, '1500', reason: 'defaults to the whole amount');
      await tester.enterText(find.byKey(const Key('assessment-avoidable')), '400');
      await tester.enterText(find.byKey(const Key('assessment-reason')), 'Not needed');
      await tester.tap(find.byKey(const Key('assessment-save')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      expect([tile('savings'), tester.widget<Text>(find.byKey(const Key('efficiency-scenario-adjusted'))).data], ['₹400', '₹10,900']);

      await tester.pumpWidget(const SizedBox());
      await pump('teacher');
      expect(find.byKey(Key('efficiency-assess-$w')), findsNothing);
      expect(find.byKey(const Key('efficiency-target-add')), findsNothing);
      expect(tile('savings'), '₹400', reason: 'figures still visible read-only');
    });
  });
}
