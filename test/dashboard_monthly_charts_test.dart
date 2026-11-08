// Monthly charts on the Fees and Finance dashboards: academic-year month
// boundaries (from the year's start through today, current month partial,
// no future months), fee collections by actual payment date (not fee
// month; all methods; voided receipts excluded), Finance income and
// expenses by ledger transaction date (cancelled excluded, as the Ledger's
// Profit / Loss), the drill-downs (a fee bar opens that payment month's
// receipts; an Income or Expenses bar opens the Ledger on that month and
// type), reconciliation with the underlying records, and that nothing is
// written by showing or drilling into them. Synthetic data only.
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/core/widgets/monthly_bar_chart.dart';
import 'package:montessori_app/modules/admin/settings/data/academic_year_service.dart';
import 'package:montessori_app/modules/admin/settings/models/academic_year_model.dart';
import 'package:montessori_app/modules/admin/settings/models/academic_year_months.dart';
import 'package:montessori_app/modules/admin/settings/models/school_settings_model.dart';
import 'package:montessori_app/modules/admin/settings/providers/academic_year_provider.dart';
import 'package:montessori_app/modules/admin/settings/providers/school_identity_provider.dart';
import 'package:montessori_app/modules/fees/models/fee_monthly_collections.dart';
import 'package:montessori_app/modules/fees/services/fee_service.dart';
import 'package:montessori_app/modules/fees/ui/admin_fees_screen.dart';
import 'package:montessori_app/modules/finance/models/finance_expense_model.dart';
import 'package:montessori_app/modules/finance/models/finance_income_model.dart';
import 'package:montessori_app/modules/finance/models/finance_monthly_totals.dart';
import 'package:montessori_app/modules/finance/models/ledger_period.dart';
import 'package:montessori_app/modules/finance/services/finance_service.dart';
import 'package:montessori_app/modules/finance/ui/admin_finance_screen.dart';

import 'support/buffered_transaction_firestore.dart';

AcademicYearModel _year(DateTime start, DateTime end) => AcademicYearModel(
      id: 'ay', schoolId: kDefaultSchoolId, name: '2026-2027', startDate: start, endDate: end, isCurrent: true, isActive: true,
      createdAt: DateTime(2026), updatedAt: DateTime(2026), createdBy: 't', updatedBy: 't',
    );

void main() {
  final today = DateTime(2026, 11, 7, 10, 30);
  final june = DateTime(2026, 6, 1), mayEnd = DateTime(2027, 5, 31);

  // ================================================================ months
  group('academic-year months', () {
    test('from the year start through the current month; no future months; current month partial', () {
      final w = AcademicYearMonths(_year(june, mayEnd), today);
      expect(w.months, ['2026-06', '2026-07', '2026-08', '2026-09', '2026-10', '2026-11']);
      expect([w.start, w.end], [june, DateTime(2026, 11, 7)]);
      expect([w.isPartial('2026-11'), w.isPartial('2026-10')], [true, false]);
      expect(w.daysOf('2026-11'), (DateTime(2026, 11, 1), DateTime(2026, 11, 7)));
      expect([w.contains(DateTime(2026, 11, 7, 23, 59)), w.contains(DateTime(2026, 11, 8)), w.contains(DateTime(2026, 5, 31))], [true, false, false]);
    });

    test('a year starting mid-month, a finished year, and one not yet started', () {
      final mid = AcademicYearMonths(_year(DateTime(2026, 6, 15), mayEnd), today);
      expect([mid.months.first, mid.isPartial('2026-06'), mid.contains(DateTime(2026, 6, 14))], ['2026-06', true, false]);
      final past = AcademicYearMonths(_year(DateTime(2025, 6, 1), DateTime(2026, 5, 31)), today);
      expect([past.months.length, past.months.last, past.end], [12, '2026-05', DateTime(2026, 5, 31)], reason: 'never beyond the year');
      final future = AcademicYearMonths(_year(DateTime(2027, 6, 1), DateTime(2028, 5, 31)), today);
      expect([future.notStarted, future.months], [true, isEmpty]);
    });
  });

  // ================================================================ data
  late BufferedTransactionFirestore firestore;
  late FinanceService finance;
  late FeeService fees;
  late Map<String, String> accounts;

  setUp(() async {
    firestore = BufferedTransactionFirestore();
    final auth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'admin-uid'));
    finance = FinanceService(firestore: firestore, auth: auth);
    await finance.ensureDefaults();
    fees = FeeService(firestore: firestore, auth: auth, storage: MockFirebaseStorage(), financeService: finance, clock: () => today);
    accounts = {for (final d in (await firestore.collection('finance_accounts').get()).docs) d.data()['type'] as String: d.id};
    await AcademicYearService(firestore: firestore).createAcademicYear(
        schoolId: kDefaultSchoolId, requesterRole: 'admin', name: '2026-2027', startDate: june, endDate: mayEnd, createdBy: 'admin-1', setAsCurrent: true);
    await firestore.collection('classes').doc('c1').set({'name': 'Mont 1', 'isActive': true});
  });

  /// An assignment (fee month [feeMonth]) and a payment on [paid].
  Future<String> pay(String student, double amount, DateTime paid, {String mode = 'cash', String feeMonth = '2026-07', String ref = ''}) async {
    final a = (await firestore.collection('student_fee_assignments').add({
      'studentId': student, 'studentName': student, 'admissionNo': 'ADM-$student', 'classId': 'c1', 'className': 'Mont 1',
      'feeStructureId': 'care', 'feeStructureName': 'Day Care', 'academicYearId': 'ay', 'academicYear': '2026-2027', 'feeMonth': feeMonth,
      'totalFee': 10000, 'discountAmount': 0, 'payableAmount': 10000, 'paidAmount': 0, 'balanceAmount': 10000, 'status': 'unpaid',
      'assignedAt': DateTime(2026, 6, 1), 'dueDate': DateTime(2026, 7, 10),
    })).id;
    return (await fees.collectFee(assignmentId: a, amount: amount, paymentDate: paid, paymentMode: mode, referenceNo: ref, remarks: '')).id;
  }

  /// Payments: Jun 15 cash ₹1,000; Aug 3 UPI ₹2,500 (for July's fee); Aug 20
  /// cash ₹1,500 (for September's); Sep 9 ₹700 voided; Nov 5 ₹900; plus one
  /// before the year (May 30) and one dated after today (Nov 20).
  Future<Map<String, String>> seedPayments() async => {
        'jun': await pay('anu', 1000, DateTime(2026, 6, 15)),
        'aug1': await pay('bala', 2500, DateTime(2026, 8, 3), mode: 'upi', feeMonth: '2026-07', ref: 'UPI-778'),
        'aug2': await pay('chitra', 1500, DateTime(2026, 8, 20, 16, 45), feeMonth: '2026-09'),
        'void': await pay('dev', 700, DateTime(2026, 9, 9)),
        'nov': await pay('esha', 900, DateTime(2026, 11, 5), feeMonth: '2026-11'),
        'before': await pay('farah', 400, DateTime(2026, 5, 30), feeMonth: '2026-05'),
        'after': await pay('gita', 300, DateTime(2026, 11, 20), feeMonth: '2026-11'),
      };

  Future<String> dump() async => [
        for (final c in ['student_fee_assignments', 'fee_receipts', 'fee_transactions', 'finance_ledger', 'finance_income', 'finance_expenses', 'finance_accounts'])
          '$c=${[for (final d in (await firestore.collection(c).get()).docs) '${d.id}:${d.data()}']..sort()}',
      ].join('\n');

  group('Monthly Fee Collection (by payment date)', () {
    test('grouped by payment date, not fee month; all methods; voided, earlier and future payments excluded; zero months kept', () async {
      final ids = await seedPayments();
      await fees.voidReceipt(ids['void']!);
      final receipts = await fees.getReceipts();
      final c = FeeMonthlyCollections.of(receipts, AcademicYearMonths(_year(june, mayEnd), today));
      expect({for (final m in c.months) m: c.totalIn(m)},
          {'2026-06': 1000, '2026-07': 0, '2026-08': 4000, '2026-09': 0, '2026-10': 0, '2026-11': 900});
      expect(c.receiptsIn('2026-08').map((r) => r.id), [ids['aug2'], ids['aug1']], reason: 'both payments, newest first');
      expect(c.receiptsIn('2026-08').map((r) => r.paymentMode).toSet(), {'cash', 'upi'});
      expect(c.totalIn('2026-07'), 0, reason: 'July\'s fee paid in August counts in August');
      expect(c.total, 5900);
      // Reconciles with the receipts themselves for the same dates.
      final sameDates = receipts.where((r) => r.paymentDate != null && !r.paymentDate!.isBefore(june) && !r.paymentDate!.isAfter(DateTime(2026, 11, 7, 23, 59)));
      expect(c.total, sameDates.fold<double>(0, (s, r) => s + r.amount));
    });

    Future<void> pumpFees(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          academicYearServiceProvider.overrideWithValue(AcademicYearService(firestore: firestore)),
          schoolIdentityProvider.overrideWith((ref) async => null),
        ],
        child: MaterialApp(home: AdminFeesScreen(service: fees, clock: () => today)),
      ));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pumpAndSettle();
    }

    testWidgets('the chart shows every month to date; a bar opens that payment month\'s receipts; Back returns to the dashboard', (tester) async {
      late Map<String, String> ids;
      late List<String> receiptNos;
      late String before;
      await tester.runAsync(() async {
        ids = await seedPayments();
        await fees.voidReceipt(ids['void']!);
        receiptNos = [for (final k in ['aug1', 'aug2', 'jun', 'nov']) (await fees.getReceiptById(ids[k]!))!.receiptNo];
        before = await dump();
      });
      await pumpFees(tester);
      expect(find.byKey(const Key('fees-chart')), findsOneWidget);
      for (final m in ['2026-06', '2026-07', '2026-08', '2026-09', '2026-10', '2026-11']) {
        expect(find.byKey(Key('fees-chart-bar-$m')), findsOneWidget, reason: m);
      }
      expect(find.byKey(const Key('fees-chart-bar-2026-12')), findsNothing, reason: 'no future months');
      expect(find.byKey(const Key('fees-chart-bar-2026-05')), findsNothing, reason: 'nothing before the year');
      expect(find.bySemanticsLabel('Collected, Aug\n2026: ₹4,000').evaluate().isNotEmpty || find.bySemanticsLabel(RegExp(r'Collected, Aug.*₹4,000')).evaluate().isNotEmpty, isTrue,
          reason: 'each bar is a labelled button');
      expect(tester.widget<Text>(find.byKey(const Key('fees-chart-total'))).data, contains('5,900'));

      await tester.ensureVisible(find.byKey(const Key('fees-chart-bar-2026-08')));
      await tester.tap(find.byKey(const Key('fees-chart-bar-2026-08')));
      await tester.pumpAndSettle();
      expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Receipts')).selected, isTrue);
      expect(tester.widget<Text>(find.byKey(const Key('fees-payment-month-title'))).data, 'Payments received in August 2026');
      expect(tester.widget<Text>(find.byKey(const Key('fees-payment-month-total'))).data, '2 payments · ₹4,000');
      expect(find.text(receiptNos[0]), findsOneWidget);
      expect(find.text(receiptNos[1]), findsOneWidget);
      expect(find.text(receiptNos[2]), findsNothing, reason: 'June\'s payment not listed');
      expect(find.textContaining('Paid 3 Aug 2026 • Fee month July 2026 • Ref UPI-778'), findsOneWidget, reason: 'payment date and fee month kept distinct');
      expect(find.textContaining('Paid 20 Aug 2026 • Fee month September 2026'), findsOneWidget);
      expect(find.textContaining('upi'), findsWidgets);

      // The existing receipt view still opens from here.
      await tester.tap(find.byTooltip('Actions').first);
      await tester.pumpAndSettle();
      expect(find.text('View'), findsOneWidget);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('fees-payment-month-back')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('fees-payment-month-banner')), findsNothing);
      expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Collections')).selected, isTrue, reason: 'back to where it was');

      // A zero month opens an empty list, not an error.
      await tester.ensureVisible(find.byKey(const Key('fees-chart-bar-2026-07')));
      await tester.tap(find.byKey(const Key('fees-chart-bar-2026-07')));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('fees-payment-month-total'))).data, '0 payments · ₹0');
      // The normal Receipts tab is unchanged afterwards.
      await tester.tap(find.widgetWithText(ChoiceChip, 'Receipts'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('fees-payment-month-banner')), findsNothing);

      expect(await tester.runAsync(dump), before, reason: 'showing and drilling into the chart writes nothing');
    });

    testWidgets('no current academic year: an explanation instead of the chart', (tester) async {
      await tester.runAsync(() async {
        for (final d in (await firestore.collection('academic_years').get()).docs) {
          await d.reference.update({'isCurrent': false});
        }
      });
      await pumpFees(tester);
      expect(find.byKey(const Key('fees-chart-no-year')), findsOneWidget);
      expect(find.byKey(const Key('fees-chart')), findsNothing);
    });
  });

  // ================================================================ Finance
  group('Monthly Income and Expenses (by ledger transaction date)', () {
    Future<String> income(double amount, DateTime date) => finance.createIncome(FinanceIncomeModel(
          id: '', title: 'Donation', categoryId: 'c', categoryName: 'Other Income', programType: 'other', studentId: '', studentName: '',
          classId: '', className: '', amount: amount, incomeDate: date, paymentMode: 'cash', accountId: accounts['cash']!,
          accountName: 'Cash', referenceNo: '', remarks: '', attachmentUrls: const [], ledgerEntryId: '', createdAt: date, updatedAt: date, createdBy: 'admin',
        ));
    Future<String> expense(double amount, DateTime date, {String title = 'Chalk'}) => finance.createExpense(FinanceExpenseModel.fromMap('', {
          'title': title, 'amount': amount, 'accountId': accounts['cash'], 'accountName': 'Cash', 'expenseDate': date, 'categoryId': 'supplies',
          'categoryName': 'Supplies', 'createdAt': date,
        }));

    /// Income: Jun 5,000; Aug 3,000 + 2,000; Oct 1,000 (voided); Nov 1 4,000;
    /// Nov 25 (future) 9,999; May 2026 (before) 8,888. Expenses: Jul 1,200;
    /// Aug 800; Nov 6 600.
    Future<void> seedLedger() async {
      await income(5000, DateTime(2026, 6, 10));
      await income(3000, DateTime(2026, 8, 2));
      await income(2000, DateTime(2026, 8, 28));
      final voided = await income(1000, DateTime(2026, 10, 15));
      await finance.voidIncome(voided);
      await income(4000, DateTime(2026, 11, 1));
      await income(9999, DateTime(2026, 11, 25));
      await income(8888, DateTime(2026, 5, 20));
      await expense(1200, DateTime(2026, 7, 4));
      await expense(800, DateTime(2026, 8, 9));
      await expense(600, DateTime(2026, 11, 6));
    }

    test('income and expenses per month by transaction date; cancelled, earlier and future entries excluded; matches the Ledger', () async {
      await seedLedger();
      final entries = await finance.watchLedger().first;
      final t = FinanceMonthlyTotals.of(entries, AcademicYearMonths(_year(june, mayEnd), today));
      expect({for (final m in t.months) m: (t.incomeIn(m), t.expensesIn(m))}, {
        '2026-06': (5000.0, 0.0),
        '2026-07': (0.0, 1200.0),
        '2026-08': (5000.0, 800.0),
        '2026-09': (0.0, 0.0),
        '2026-10': (0.0, 0.0),
        '2026-11': (4000.0, 600.0),
      });
      // Whole past months equal the Ledger's own Profit / Loss for that month.
      for (final m in ['2026-06', '2026-07', '2026-08', '2026-09', '2026-10']) {
        final d = AcademicYearMonths.monthStart(m);
        final ledger = LedgerPeriodSummary.of(entries, LedgerPeriod.month(d.year, d.month));
        expect((t.incomeIn(m), t.expensesIn(m)), (ledger.totalIncome, ledger.totalExpenses), reason: m);
      }
      final nov = LedgerPeriodSummary.of(entries, const LedgerPeriod.month(2026, 11));
      expect(nov.totalIncome - t.incomeIn('2026-11'), 9999, reason: 'only the entry dated after today is left out of the current month');
    });

    test('drill-down note: whole month, current month (through today), first month starting mid-year, and both', () {
      final full = FinanceMonthlyTotals.of(const [], AcademicYearMonths(_year(june, mayEnd), today));
      expect(full.drillDownNote('2026-08'), 'The chart bar and the Ledger both cover all of August 2026.');
      expect(full.drillDownNote('2026-11'), startsWith('The chart bar counts transactions through today, 7 Nov 2026. The Ledger below shows all of November 2026'));
      final midStart = FinanceMonthlyTotals.of(const [], AcademicYearMonths(_year(DateTime(2026, 6, 15), mayEnd), today));
      expect(midStart.drillDownNote('2026-06'),
          'The chart bar counts from 15 Jun 2026, when the academic year starts. The Ledger below shows all of June 2026, so its totals can be higher.');
      final both = FinanceMonthlyTotals.of(const [], AcademicYearMonths(_year(DateTime(2026, 11, 3), DateTime(2027, 10, 31)), today));
      expect(both.drillDownNote('2026-11'), startsWith('The chart bar counts 3 Nov 2026 (the academic year’s start) to 7 Nov 2026 (today).'));
      // Wording only: the totals' boundaries are the window's, as before.
      expect(midStart.window.daysOf('2026-06'), (DateTime(2026, 6, 15), DateTime(2026, 6, 30)));
    });

    Future<void> pumpFinance(WidgetTester tester, {bool withYears = true}) async {
      tester.view.physicalSize = const Size(1400, 3600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(ProviderScope(
        overrides: [if (withYears) academicYearServiceProvider.overrideWithValue(AcademicYearService(firestore: firestore))],
        child: MaterialApp(home: AdminFinanceScreen(service: finance, feeService: fees, clock: () => today)),
      ));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pumpAndSettle();
    }

    bool ledgerTypeSelected(WidgetTester tester, String label) =>
        tester.widget<SegmentedButton<Object?>>(find.byWidgetPredicate((w) => w is SegmentedButton)).selected.single.toString().endsWith('.$label');

    testWidgets('each Income and Expenses bar opens the Ledger on its month and type; Back returns to the Dashboard', (tester) async {
      late String before;
      await tester.runAsync(() async {
        await seedLedger();
        before = await dump();
      });
      await pumpFinance(tester);
      expect(find.byKey(const Key('finance-chart')), findsOneWidget);
      for (final m in ['2026-06', '2026-07', '2026-08', '2026-09', '2026-10', '2026-11']) {
        expect(find.byKey(Key('finance-chart-income-$m')), findsOneWidget, reason: 'income $m');
        expect(find.byKey(Key('finance-chart-expense-$m')), findsOneWidget, reason: 'expense $m');
      }
      expect(find.byKey(const Key('finance-chart-income-2026-12')), findsNothing);
      expect(find.text('Income'), findsWidgets);
      expect(find.text('Expenses'), findsWidgets, reason: 'legend');
      final chart = tester.widget<MonthlyBarChart>(find.byKey(const Key('finance-chart')));
      expect(chart.series.map((s) => s.color).toSet().length, 2, reason: 'distinct colours');
      expect(chart.series[0].values, [5000, 0, 5000, 0, 0, 4000]);
      expect(chart.series[1].values, [0, 1200, 800, 0, 0, 600]);

      // Income for August.
      await tester.ensureVisible(find.byKey(const Key('finance-chart-income-2026-08')));
      await tester.tap(find.byKey(const Key('finance-chart-income-2026-08')));
      await tester.pumpAndSettle();
      expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Ledger')).selected, isTrue);
      expect(tester.widget<Text>(find.byKey(const Key('ledger-drill-title'))).data, 'From the Dashboard chart: Income for August 2026');
      expect(find.text('August 2026'), findsWidgets, reason: 'the Ledger\'s own month');
      expect(ledgerTypeSelected(tester, 'income'), isTrue);
      expect(find.textContaining('Donation'), findsNWidgets(2), reason: 'August\'s two income entries');
      expect(find.text('Chalk'), findsNothing, reason: 'no expenses');

      await tester.tap(find.byKey(const Key('ledger-drill-back')));
      await tester.pumpAndSettle();
      expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Dashboard')).selected, isTrue);
      expect(find.byKey(const Key('finance-chart')), findsOneWidget);

      // Expenses for July.
      await tester.ensureVisible(find.byKey(const Key('finance-chart-expense-2026-07')));
      await tester.tap(find.byKey(const Key('finance-chart-expense-2026-07')));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('ledger-drill-title'))).data, 'From the Dashboard chart: Expenses for July 2026');
      expect(ledgerTypeSelected(tester, 'expense'), isTrue);
      expect(find.textContaining('Chalk'), findsOneWidget);
      expect(find.textContaining('Donation'), findsNothing);
      // A whole month: the bar and the Ledger cover the same days.
      expect(tester.widget<Text>(find.byKey(const Key('ledger-drill-note'))).data, 'The chart bar and the Ledger both cover all of July 2026.');

      // Income for November (the current month): the bar stops at today, the
      // Ledger shows the whole month, and the note says so. Both boundaries
      // are unchanged: the bar is ₹4,000, the Ledger's month ₹13,999 (with
      // the entry dated 25 Nov).
      await tester.tap(find.byKey(const Key('ledger-drill-back')));
      await tester.pumpAndSettle();
      expect(tester.widget<MonthlyBarChart>(find.byKey(const Key('finance-chart'))).series[0].values.last, 4000);
      await tester.ensureVisible(find.byKey(const Key('finance-chart-income-2026-11')));
      await tester.tap(find.byKey(const Key('finance-chart-income-2026-11')));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('ledger-drill-title'))).data, 'From the Dashboard chart: Income for November 2026');
      expect(
        tester.widget<Text>(find.byKey(const Key('ledger-drill-note'))).data,
        'The chart bar counts transactions through today, 7 Nov 2026. The Ledger below shows all of November 2026, '
        'so its totals can be higher if entries are dated later this month.',
      );
      expect(find.descendant(of: find.byKey(const Key('ledger-total-income')), matching: find.text('₹13999')), findsOneWidget);

      // Opening the Ledger normally afterwards is the usual Ledger (current month, all).
      await tester.tap(find.widgetWithText(ChoiceChip, 'Dashboard'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Ledger'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ledger-drill-banner')), findsNothing);
      expect(ledgerTypeSelected(tester, 'all'), isTrue);
      expect(find.text('November 2026'), findsWidgets);

      expect(await tester.runAsync(dump), before, reason: 'showing and drilling into the chart writes nothing');
    });

    testWidgets('empty ledger: zero months still shown, with a note; no academic year: an explanation', (tester) async {
      await pumpFinance(tester);
      final chart = tester.widget<MonthlyBarChart>(find.byKey(const Key('finance-chart')));
      expect([chart.months.length, chart.series[0].values.every((v) => v == 0)], [6, true]);
      expect(tester.widget<Text>(find.byKey(const Key('finance-chart-hint'))).data, 'No income or expenses recorded yet this academic year.');
      await tester.pumpWidget(const SizedBox());
      await pumpFinance(tester, withYears: false); // the default service can't be read in tests
      expect(find.byKey(const Key('finance-chart-no-year')), findsOneWidget);
    });
  });

  group('Shared chart: readability and responsive layout (presentation only)', () {
    // Eleven months (Jun–Apr) with Income and Expenses deliberately close
    // together, the case where value labels used to collide.
    final months = [for (var i = 0; i < 11; i++) AcademicYearMonths.key(DateTime(2026, 6 + i))];
    final labels = [
      for (final m in months)
        m == months.first || AcademicYearMonths.monthStart(m).month == 1
            ? '${AcademicYearMonths.shortLabel(m)}\n${AcademicYearMonths.monthStart(m).year}'
            : AcademicYearMonths.shortLabel(m),
    ];
    final income = <double>[46250, 79000, 0, 120000, 98765, 5000, 12500, 99999, 1500000, 64000, 0];
    final expense = <double>[45900, 78400, 0, 118000, 97000, 4800, 12400, 101000, 1490000, 0, 33000];

    Future<List<(int, String)>> pumpChart(WidgetTester tester, double width, {int seriesCount = 2}) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final taps = <(int, String)>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(32), // page + card padding
              child: MonthlyBarChart(
                key: const Key('chart'),
                months: months,
                monthLabels: labels,
                series: [
                  MonthlyChartSeries(label: 'Income', color: MonthlyBarChart.moneyInColor, values: income, keyPrefix: 'in'),
                  if (seriesCount == 2) MonthlyChartSeries(label: 'Expenses', color: MonthlyBarChart.moneyOutColor, values: expense, keyPrefix: 'out'),
                ],
                onBarTap: (s, m) => taps.add((s, m)),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      return taps;
    }

    ScrollPosition position(WidgetTester tester) =>
        tester.state<ScrollableState>(find.descendant(of: find.byKey(const Key('chart')), matching: find.byType(Scrollable))).position;

    /// Every rendered value label's rectangle, by bar key.
    Map<String, Rect> valueRects(WidgetTester tester, List<String> prefixes) => {
          for (final p in prefixes)
            for (final m in months)
              '$p-$m': tester.getRect(find.descendant(of: find.byKey(Key('$p-$m')), matching: find.byType(Text))),
        };

    for (final width in [1440.0, 768.0, 400.0]) {
      testWidgets('at ${width.toInt()}px: readable type, no overlapping values, no overflow', (tester) async {
        await pumpChart(tester, width);
        expect(tester.takeException(), isNull);

        // Month labels: 13px semibold; values 12px semibold; legend 14px.
        final month = tester.widget<Text>(find.text('Sep'));
        expect(month.style!.fontSize, 13);
        expect(month.style!.fontWeight, FontWeight.w600);
        final value = tester.widget<Text>(find.descendant(of: find.byKey(Key('in-${months[0]}')), matching: find.byType(Text)));
        expect(value.data, '₹46k');
        expect(value.style!.fontSize, 12);
        expect(value.style!.fontWeight, FontWeight.w600);
        expect(tester.widget<Text>(find.text('Income')).style!.fontSize, 14);

        // Each label stays within its own bar's slot (the test font is far
        // wider than the real one, so a few are scaled to fit here), and none overlap,
        // including each month's Income/Expenses pair of near-equal values.
        final rects = valueRects(tester, ['in', 'out']).values.toList();
        for (var i = 0; i < rects.length; i++) {
          expect(rects[i].width, lessThanOrEqualTo(MonthlyBarChart.slotWidth + 0.01));
          for (var j = i + 1; j < rects.length; j++) {
            expect(rects[i].overlaps(rects[j]), isFalse, reason: 'value labels $i and $j overlap at ${width}px');
          }
        }
        // Each pair is separated by at least the bar gap.
        for (final m in months) {
          final a = tester.getRect(find.byKey(Key('in-$m'))), b = tester.getRect(find.byKey(Key('out-$m')));
          expect(b.left - a.right, greaterThanOrEqualTo(MonthlyBarChart.barGap));
        }

        // Comfortable tap targets.
        final bar = tester.getSize(find.byKey(Key('in-${months[0]}')));
        expect(bar.width, greaterThanOrEqualTo(44));
        expect(bar.height, greaterThanOrEqualTo(44));
      });
    }

    testWidgets('desktop spreads the months across the width; mobile scrolls instead of shrinking', (tester) async {
      await pumpChart(tester, 1440);
      expect(position(tester).maxScrollExtent, 0);
      final desktopGroup = tester.getRect(find.byKey(Key('in-${months[1]}'))).left - tester.getRect(find.byKey(Key('in-${months[0]}'))).left;
      expect(desktopGroup, greaterThan(MonthlyBarChart.groupWidthFor(2)));

      await pumpChart(tester, 400);
      expect(position(tester).maxScrollExtent, greaterThan(0));
      final mobileGroup = tester.getRect(find.byKey(Key('in-${months[1]}'))).left - tester.getRect(find.byKey(Key('in-${months[0]}'))).left;
      expect(mobileGroup, MonthlyBarChart.groupWidthFor(2)); // full minimum width, not squeezed
      final lastMonthLabel = find.text('Apr');
      expect(tester.getRect(lastMonthLabel).left, greaterThan(400)); // off-screen until scrolled

      await tester.drag(find.byKey(const Key('chart')).last, const Offset(-2000, 0));
      await tester.pumpAndSettle();
      expect(tester.getRect(lastMonthLabel).right, lessThanOrEqualTo(400));
      expect(tester.takeException(), isNull);
    });

    testWidgets('exact amounts: tooltip, accessible label, and the hover/focus readout; zero months identifiable', (tester) async {
      await pumpChart(tester, 400);
      expect(find.byTooltip('Income · June 2026: ₹46,250'), findsOneWidget);
      expect(find.byTooltip('Expenses · February 2027: ₹14,90,000'), findsOneWidget);

      final handle = tester.ensureSemantics();
      expect(find.bySemanticsLabel('Income, June 2026: ₹46,250'), findsOneWidget);
      handle.dispose();

      // Keyboard focus on the first bar shows its exact amount.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('monthly-chart-readout'))).data, 'Income · June 2026: ₹46,250');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('monthly-chart-readout'))).data, 'Expenses · June 2026: ₹45,900');

      // August has nothing: both bars still render with a ₹0 label.
      for (final p in ['in', 'out']) {
        expect(find.descendant(of: find.byKey(Key('$p-2026-08')), matching: find.text('₹0')), findsOneWidget);
        expect(tester.getSize(find.byKey(Key('$p-2026-08'))).height, greaterThanOrEqualTo(44));
      }
    });

    testWidgets('taps still report the right series and month (drill-down unchanged)', (tester) async {
      final taps = await pumpChart(tester, 1440);
      await tester.tap(find.byKey(const Key('out-2026-09')));
      await tester.tap(find.byKey(const Key('in-2027-01')));
      expect(taps, [(1, '2026-09'), (0, '2027-01')]);
    });

    testWidgets('single series (Fees) has the same type and minimum widths', (tester) async {
      await pumpChart(tester, 400, seriesCount: 1);
      expect(tester.widget<Text>(find.text('Sep')).style!.fontSize, 13);
      final step = tester.getRect(find.byKey(Key('in-${months[1]}'))).left - tester.getRect(find.byKey(Key('in-${months[0]}'))).left;
      expect(step, MonthlyBarChart.groupWidthFor(1));
      expect(position(tester).maxScrollExtent, greaterThan(0));
    });

    test('compact labels use Indian units; full amounts use Indian grouping', () {
      expect(MonthlyBarChart.compact(950), '₹950');
      expect(MonthlyBarChart.compact(1500), '₹1.5k');
      expect(MonthlyBarChart.compact(46250), '₹46k');
      expect(MonthlyBarChart.compact(79000), '₹79k');
      expect(MonthlyBarChart.compact(320000), '₹3.2L');
      expect(MonthlyBarChart.compact(1500000), '₹15L');
      expect(MonthlyBarChart.compact(12000000), '₹1.2Cr');
      expect(MonthlyBarChart.compact(0), '₹0');
      expect(MonthlyBarChart.money(46250), '₹46,250');
      expect(MonthlyBarChart.money(1490000), '₹14,90,000');
    });
  });
}
