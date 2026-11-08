// Finance -> Ledger: the period (a month, the current one at first, or All
// time) behind Total Income, Total Expenses and Profit / Loss and the
// Transactions list; the All / Income / Expense filter and "Show cancelled
// transactions" with the search; the
// transaction detail dialog and its actions. Closing Balance and Account
// Balances stay current balances. Synthetic test data only.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/finance/models/finance_income_model.dart';
import 'package:montessori_app/modules/finance/models/finance_ledger_entry_model.dart';
import 'package:montessori_app/modules/finance/models/ledger_period.dart';
import 'package:montessori_app/modules/finance/services/finance_service.dart';
import 'package:montessori_app/modules/finance/ui/admin_finance_screen.dart';
import 'package:montessori_app/modules/finance/ui/dialogs/add_income_dialog.dart';
import 'package:montessori_app/modules/finance/widgets/finance_summary_card.dart';
import 'package:montessori_app/modules/finance/widgets/ledger_entry_card.dart';

import 'support/buffered_transaction_firestore.dart';

DateTime _today() => DateTime(2026, 11, 6, 10);

FinanceLedgerEntryModel _entry(String type, double amount, DateTime? date, {String status = 'confirmed', String id = 'x'}) =>
    FinanceLedgerEntryModel.fromMap(id, {'entryType': type, 'amount': amount, 'transactionDate': date, 'status': status});

void main() {
  // ---------------------------------------------------------------- summary
  group('monthly summary (LedgerPeriodSummary)', () {
    final nov = const LedgerPeriod.month(2026, 11);
    final entries = [
      _entry('income', 1000, DateTime(2026, 11, 1)), // first day, midnight
      _entry('income', 500, DateTime(2026, 11, 30, 23, 59, 59)), // last day, last second
      _entry('expense', 300, DateTime(2026, 11, 15)),
      _entry('income', 700, DateTime(2026, 11, 10), status: 'cancelled'),
      _entry('expense', 250, DateTime(2026, 11, 12), status: 'cancelled'),
      _entry('income', 900, DateTime(2026, 10, 31, 23, 59, 59)), // previous month
      _entry('expense', 400, DateTime(2026, 12, 1)), // next month
      _entry('expense', 2000, DateTime(2026, 10, 5)),
      _entry('income', 50, null), // no transaction date
    ];

    test('1, 2, 3. income, expenses and profit for a month', () {
      final s = LedgerPeriodSummary.of(entries, nov);
      expect(s.totalIncome, 1500);
      expect(s.totalExpenses, 300);
      expect(s.profitLoss, 1200);
      expect(s.isProfit, isTrue);
    });

    test('4. a loss', () {
      final s = LedgerPeriodSummary.of(entries, const LedgerPeriod.month(2026, 10));
      expect(s.profitLoss, -1100);
      expect(s.isLoss, isTrue);
    });

    test('5. break-even, to the paisa', () {
      final s = LedgerPeriodSummary.of([_entry('income', 0.1, DateTime(2027, 1, 2)), _entry('income', 0.2, DateTime(2027, 1, 3)), _entry('expense', 0.3, DateTime(2027, 1, 4))], const LedgerPeriod.month(2027, 1));
      expect(s.isBreakEven, isTrue);
      expect(s.isLoss || s.isProfit, isFalse);
    });

    test('6. a month with no transactions', () {
      final s = LedgerPeriodSummary.of(entries, const LedgerPeriod.month(2026, 9));
      expect([s.totalIncome, s.totalExpenses, s.profitLoss], [0, 0, 0]);
      expect(s.isBreakEven, isTrue);
    });

    test('7. All time: every confirmed entry, those without a date too', () {
      final s = LedgerPeriodSummary.of(entries, const LedgerPeriod.allTime());
      expect(s.totalIncome, 1000 + 500 + 900 + 50);
      expect(s.totalExpenses, 300 + 400 + 2000);
      expect(s.profitLoss, -250);
    });

    test('8, 9. first and last day included; adjacent months excluded', () {
      final p = const LedgerPeriod.month(2026, 11);
      expect(p.firstDay, DateTime(2026, 11, 1));
      expect(p.lastDay, DateTime(2026, 11, 30));
      expect(p.contains(DateTime(2026, 11, 1)), isTrue);
      expect(p.contains(DateTime(2026, 11, 30, 23, 59, 59, 999)), isTrue);
      expect(p.contains(DateTime(2026, 10, 31, 23, 59, 59, 999)), isFalse);
      expect(p.contains(DateTime(2026, 12, 1)), isFalse);
      expect(p.contains(null), isFalse);
      expect(const LedgerPeriod.month(2028, 2).lastDay, DateTime(2028, 2, 29), reason: 'leap year');
      // A stored Timestamp is placed by its local date, as the Ledger shows it.
      final stored = FinanceLedgerEntryModel.fromMap('t', {'entryType': 'income', 'amount': 10, 'transactionDate': Timestamp.fromDate(DateTime(2026, 11, 30, 23, 30))});
      expect(LedgerPeriodSummary.of([stored], p).totalIncome, 10);
    });

    test('10. cancelled (voided or reversed) entries count in neither total', () {
      final s = LedgerPeriodSummary.of([_entry('income', 700, DateTime(2026, 11, 10), status: 'cancelled'), _entry('expense', 250, DateTime(2026, 11, 12), status: 'cancelled')], nov);
      expect([s.totalIncome, s.totalExpenses], [0, 0]);
    });

    test('11. no other kind of entry is counted (opening balances live on accounts, not the ledger), and nothing twice', () {
      final s = LedgerPeriodSummary.of([
        _entry('income', 100, DateTime(2026, 11, 2)),
        _entry('transfer', 5000, DateTime(2026, 11, 2)),
        _entry('opening_balance', 9000, DateTime(2026, 11, 1)),
      ], nov);
      expect([s.totalIncome, s.totalExpenses], [100, 0]);
    });

    test('previous / next month cross years; labels', () {
      expect(const LedgerPeriod.month(2026, 1).previous, const LedgerPeriod.month(2025, 12));
      expect(const LedgerPeriod.month(2026, 12).next, const LedgerPeriod.month(2027, 1));
      expect(const LedgerPeriod.month(2026, 11).label, 'November 2026');
      expect(const LedgerPeriod.allTime().label, 'All time');
      expect(const LedgerPeriod.allTime().next, const LedgerPeriod.allTime());
    });
  });

  // ---------------------------------------------------------------- screen
  late BufferedTransactionFirestore firestore;
  late FinanceService service;
  late String cashId;

  setUp(() async {
    firestore = BufferedTransactionFirestore();
    service = FinanceService(firestore: firestore, auth: MockFirebaseAuth());
    await service.ensureDefaults();
    cashId = (await firestore.collection('finance_accounts').where('type', isEqualTo: 'cash').get()).docs.single.id;
  });

  var seq = 0;
  Future<String> add(String title, String type, double amount, DateTime? date, {String status = 'confirmed', Map<String, dynamic> extra = const {}}) async {
    seq++;
    final ref = await firestore.collection('finance_ledger').add({
      'entryType': type,
      'amount': amount,
      'accountId': cashId,
      'accountName': 'Cash',
      'categoryName': type == 'income' ? 'Donations' : 'Supplies',
      'status': status,
      'title': title,
      'transactionDate': date,
      'createdAt': DateTime(2026, 1, 1).add(Duration(minutes: seq)),
      ...extra,
    });
    return ref.id;
  }

  /// Nov 2026: income 1000 (1st) + 500 (30th), expense 300, a cancelled
  /// income of 700; Oct: income 900 (31st), expense 2000; Dec: expense 400
  /// (1st); one income of 50 with no date. Cash opening balance 5000.
  Future<void> seed() async {
    await add('Tuition first day', 'income', 1000, DateTime(2026, 11, 1));
    await add('Donation last day', 'income', 500, DateTime(2026, 11, 30, 23, 59));
    await add('Stationery', 'expense', 300, DateTime(2026, 11, 15), extra: {'subCategoryName': 'Acme Supplies'});
    await add('Voided gift', 'income', 700, DateTime(2026, 11, 10), status: 'cancelled');
    await add('October fees', 'income', 900, DateTime(2026, 10, 31, 23, 59));
    await add('October repairs', 'expense', 2000, DateTime(2026, 10, 5));
    await add('December rent', 'expense', 400, DateTime(2026, 12, 1));
    await add('Undated income', 'income', 50, null);
    await firestore.collection('finance_accounts').doc(cashId).update({'openingBalance': 5000});
  }

  Finder key(String k) => find.byKey(Key(k));

  Future<void> pumpLedger(WidgetTester tester, {Size size = const Size(1400, 3200)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(child: MaterialApp(home: AdminFinanceScreen(service: service, clock: _today))));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Ledger'));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  String cardValue(WidgetTester tester, String cardKey) {
    final card = tester.widget<FinanceSummaryCard>(key(cardKey));
    return card.value;
  }

  /// A current Account Balances card (not its month-end namesake).
  String cardByLabel(WidgetTester tester, String label) => tester.widget<FinanceSummaryCard>(key('finance-balance-${label.toLowerCase()}')).value;

  List<String> shown(WidgetTester tester) => [for (final c in tester.widgetList<LedgerEntryCard>(find.byType(LedgerEntryCard))) c.entry.title];

  void expectSummary(WidgetTester tester, {required String income, required String expenses, required String profit, required String caption}) {
    expect(cardValue(tester, 'ledger-total-income'), income);
    expect(cardValue(tester, 'ledger-total-expenses'), expenses);
    expect(cardValue(tester, 'ledger-profit-loss'), profit);
    expect(tester.widget<FinanceSummaryCard>(key('ledger-profit-loss')).caption, caption);
  }

  group('Ledger tab', () {
    testWidgets('opens on the current month: its totals, profit and transactions; balances current', (tester) async {
      await seed();
      await pumpLedger(tester);
      expect(tester.widget<Text>(key('ledger-period-label')).data, 'November 2026');
      expectSummary(tester, income: '₹1500', expenses: '₹300', profit: '₹1200', caption: 'Profit (surplus)');
      expect(tester.widget<FinanceSummaryCard>(key('ledger-profit-loss')).valueColor, isNot(const Color(0xFFD32F2F)));
      expect(shown(tester), ['Stationery', 'Donation last day', 'Tuition first day'], reason: 'newest first; cancelled ones hidden by default');
      expect(key('ledger-period-note'), findsOneWidget);
    });

    testWidgets('15, 16, 25, 26. previous / next month update summary and list; closing and account balances never change', (tester) async {
      await seed();
      await pumpLedger(tester);
      // All-time movement −250 (income 2450 − expenses 2700) + opening 5000.
      final closing = cardValue(tester, 'ledger-closing-balance');
      final cash = cardByLabel(tester, 'Cash');
      expect(closing, '₹4750');
      expect(cash, '₹4750');

      await tap(tester, key('ledger-period-previous'));
      expect(tester.widget<Text>(key('ledger-period-label')).data, 'October 2026');
      expectSummary(tester, income: '₹900', expenses: '₹2000', profit: '-₹1100', caption: 'Loss (deficit)');
      expect(tester.widget<FinanceSummaryCard>(key('ledger-profit-loss')).valueColor, const Color(0xFFD32F2F));
      expect(shown(tester), ['October repairs', 'October fees']);
      expect(cardValue(tester, 'ledger-closing-balance'), closing);
      expect(cardByLabel(tester, 'Cash'), cash);

      await tap(tester, key('ledger-period-next'));
      await tap(tester, key('ledger-period-next'));
      expect(tester.widget<Text>(key('ledger-period-label')).data, 'December 2026');
      expectSummary(tester, income: '₹0', expenses: '₹400', profit: '-₹400', caption: 'Loss (deficit)');
      expect(shown(tester), ['December rent']);
      expect(cardValue(tester, 'ledger-closing-balance'), closing);
      expect(cardByLabel(tester, 'Cash'), cash);
    });

    testWidgets('6. a month with nothing: zero figures, break-even, a clear empty state (search box kept)', (tester) async {
      await seed();
      await pumpLedger(tester);
      await tap(tester, key('ledger-period-pick'));
      await tap(tester, key('ledger-month-9'));
      expect(tester.widget<Text>(key('ledger-period-label')).data, 'September 2026');
      expectSummary(tester, income: '₹0', expenses: '₹0', profit: '₹0', caption: 'Break-even');
      expect(find.byType(LedgerEntryCard), findsNothing);
      expect(find.text('No transactions found in September 2026.'), findsOneWidget);
      expect(key('ledger-search'), findsOneWidget);
      expect(key('ledger-pagination'), findsNothing);
    });

    testWidgets('7, 17. All time: every transaction and the all-time totals; This month goes back', (tester) async {
      await seed();
      await pumpLedger(tester);
      await tap(tester, key('ledger-period-all-time'));
      expect(tester.widget<Text>(key('ledger-period-label')).data, 'All time');
      expectSummary(tester, income: '₹2450', expenses: '₹2700', profit: '-₹250', caption: 'Loss (deficit)');
      expect(find.byType(LedgerEntryCard), findsNWidgets(7), reason: 'every active entry, the undated one too');
      expect(tester.widget<IconButton>(key('ledger-period-previous')).onPressed, isNull, reason: 'no month to step from');
      expect(key('ledger-period-note'), findsNothing);
      await tap(tester, key('ledger-period-this-month'));
      expect(tester.widget<Text>(key('ledger-period-label')).data, 'November 2026');

      // The month picker reaches any year and All time.
      await tap(tester, key('ledger-period-pick'));
      await tap(tester, key('ledger-year-previous'));
      expect(tester.widget<Text>(key('ledger-picker-year')).data, '2025');
      await tap(tester, key('ledger-month-3'));
      expect(tester.widget<Text>(key('ledger-period-label')).data, 'March 2025');
      await tap(tester, key('ledger-period-pick'));
      await tap(tester, key('ledger-picker-all-time'));
      expect(tester.widget<Text>(key('ledger-period-label')).data, 'All time');
    });

    testWidgets('12, 13, 14. All / Income / Expense, with the month and the search', (tester) async {
      await seed();
      await pumpLedger(tester);
      await tap(tester, key('ledger-type-income'));
      expect(shown(tester), ['Donation last day', 'Tuition first day']);
      expectSummary(tester, income: '₹1500', expenses: '₹300', profit: '₹1200', caption: 'Profit (surplus)');
      await tap(tester, key('ledger-type-expense'));
      expect(shown(tester), ['Stationery']);
      await tap(tester, key('ledger-period-previous'));
      expect(shown(tester), ['October repairs'], reason: 'type and month together');
      await tap(tester, key('ledger-type-all'));
      expect(shown(tester), ['October repairs', 'October fees']);

      await tap(tester, key('ledger-period-all-time'));
      await tester.enterText(key('ledger-search'), 'october');
      await tester.pumpAndSettle();
      expect(shown(tester), ['October repairs', 'October fees']);
      await tap(tester, key('ledger-type-income'));
      expect(shown(tester), ['October fees'], reason: 'search kept across the filter');
      await tap(tester, key('ledger-period-this-month'));
      expect(find.text('No income transactions in November 2026 match "october".'), findsOneWidget);
      await tester.enterText(key('ledger-search'), 'acme');
      await tester.pumpAndSettle();
      await tap(tester, key('ledger-type-expense'));
      expect(shown(tester), ['Stationery'], reason: 'vendor search within the month and type');
      expect(((tester.widget(key('ledger-type-filter')) as dynamic).selected as Set).single.toString(), contains('expense'), reason: 'the active filter is the selected segment');
    });
  });

  // ---------------------------------------------------------- cancelled
  group('Show cancelled transactions', () {
    bool checked(WidgetTester tester) => tester.widget<Checkbox>(key('ledger-show-cancelled-checkbox')).value!;

    /// Nov: the seed, plus a cancelled expense (a reversed payment).
    Future<void> seedWithCancelledExpense() async {
      await seed();
      await add('Reversed payment', 'expense', 650, DateTime(2026, 11, 20), status: 'cancelled');
    }

    testWidgets('1, 2, 3, 4, 8. hidden by default; shown and hidden again; totals never change', (tester) async {
      await seedWithCancelledExpense();
      await pumpLedger(tester);
      expect(checked(tester), isFalse);
      expect(find.text('Show cancelled transactions'), findsOneWidget);
      expect(shown(tester), ['Stationery', 'Donation last day', 'Tuition first day'], reason: 'active income and expenses only');
      void totals() {
        expectSummary(tester, income: '₹1500', expenses: '₹300', profit: '₹1200', caption: 'Profit (surplus)');
        expect(cardValue(tester, 'ledger-closing-balance'), '₹4750');
        expect(cardByLabel(tester, 'Cash'), '₹4750');
      }

      totals();
      await tap(tester, key('ledger-show-cancelled'));
      expect(checked(tester), isTrue);
      expect(shown(tester), ['Reversed payment', 'Voided gift', 'Stationery', 'Donation last day', 'Tuition first day']);
      expect(find.descendant(of: find.ancestor(of: find.text('Voided gift'), matching: find.byType(LedgerEntryCard)), matching: find.text('cancelled')), findsOneWidget);
      totals();
      await tap(tester, key('ledger-show-cancelled-checkbox'));
      expect(checked(tester), isFalse);
      expect(shown(tester), ['Stationery', 'Donation last day', 'Tuition first day']);
      totals();
    });

    testWidgets('5, 6, 7. with the month, All time, Income / Expense and the search', (tester) async {
      await seedWithCancelledExpense();
      await add('October refund voided', 'income', 120, DateTime(2026, 10, 3), status: 'cancelled');
      await pumpLedger(tester);
      await tap(tester, key('ledger-show-cancelled'));
      await tap(tester, key('ledger-type-income'));
      expect(shown(tester), ['Voided gift', 'Donation last day', 'Tuition first day']);
      await tap(tester, key('ledger-type-expense'));
      expect(shown(tester), ['Reversed payment', 'Stationery']);
      await tap(tester, key('ledger-period-previous'));
      expect(shown(tester), ['October repairs']);
      await tap(tester, key('ledger-type-all'));
      expect(shown(tester), ['October refund voided', 'October repairs', 'October fees']);
      expectSummary(tester, income: '₹900', expenses: '₹2000', profit: '-₹1100', caption: 'Loss (deficit)');
      await tap(tester, key('ledger-period-all-time'));
      expect(find.byType(LedgerEntryCard), findsNWidgets(10));
      expectSummary(tester, income: '₹2450', expenses: '₹2700', profit: '-₹250', caption: 'Loss (deficit)');

      await tester.enterText(key('ledger-search'), 'voided');
      await tester.pumpAndSettle();
      expect(shown(tester), ['October refund voided', 'Voided gift']);
      await tap(tester, key('ledger-show-cancelled'));
      expect(shown(tester), isEmpty);
      expect(find.text('No transactions match "voided".'), findsOneWidget, reason: 'the search kept');
      await tap(tester, key('ledger-show-cancelled'));
      expect(shown(tester), ['October refund voided', 'Voided gift']);
      expectSummary(tester, income: '₹2450', expenses: '₹2700', profit: '-₹250', caption: 'Loss (deficit)');
    });

    testWidgets('9. a shown cancelled transaction opens its details: badge, struck amount, note, no actions', (tester) async {
      await seedWithCancelledExpense();
      await pumpLedger(tester);
      await tap(tester, key('ledger-show-cancelled'));
      await tap(tester, find.ancestor(of: find.text('Reversed payment'), matching: find.byType(LedgerEntryCard)));
      expect(key('ledger-detail'), findsOneWidget);
      expect(key('ledger-detail-cancelled'), findsOneWidget);
      expect(key('ledger-detail-cancelled-note'), findsOneWidget);
      expect(tester.widget<Text>(key('ledger-detail-amount')).style!.decoration, TextDecoration.lineThrough);
      for (final action in ['edit', 'void', 'reverse']) {
        expect(key('ledger-detail-$action'), findsNothing, reason: action);
      }
    });

    testWidgets('10. empty states, in both modes', (tester) async {
      await add('Only cancelled', 'income', 100, DateTime(2026, 11, 3), status: 'cancelled');
      await pumpLedger(tester);
      expect(find.text('No transactions found in November 2026.'), findsOneWidget);
      await tap(tester, key('ledger-period-all-time'));
      expect(find.text('No transactions found.'), findsOneWidget);
      await tap(tester, key('ledger-show-cancelled'));
      expect(shown(tester), ['Only cancelled']);
      await tap(tester, key('ledger-type-expense'));
      expect(find.text('No expense transactions found, including cancelled transactions.'), findsOneWidget);
      await tap(tester, key('ledger-type-all'));
      await tap(tester, key('ledger-period-this-month'));
      await tap(tester, key('ledger-period-previous'));
      expect(find.text('No transactions found in October 2026, including cancelled transactions.'), findsOneWidget);
      await tap(tester, key('ledger-period-all-time'));
      await tester.enterText(key('ledger-search'), 'nothing like this');
      await tester.pumpAndSettle();
      expect(find.text('No transactions, including cancelled transactions, match "nothing like this".'), findsOneWidget);
      await tester.enterText(key('ledger-search'), '');
      await tap(tester, key('ledger-show-cancelled'));
      expect(find.text('No transactions found.'), findsOneWidget);
    });

    for (final size in const [Size(1400, 2400), Size(800, 2400), Size(360, 2400)]) {
      testWidgets('11. renders without overflow at ${size.width.toInt()}px, and works there', (tester) async {
        await seedWithCancelledExpense();
        await pumpLedger(tester, size: size);
        expect(tester.takeException(), isNull);
        final rect = tester.getRect(key('ledger-show-cancelled'));
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(size.width));
        final filter = tester.getRect(key('ledger-type-filter'));
        expect(filter.right, lessThanOrEqualTo(size.width));
        if (size.width >= 1000) expect((rect.center.dy - filter.center.dy).abs(), lessThan(4), reason: 'same row as the type filter');
        await tap(tester, key('ledger-show-cancelled'));
        expect(tester.takeException(), isNull);
        expect(find.text('Reversed payment'), findsOneWidget);
      });
    }
  });

  // ---------------------------------------------------------------- details
  group('transaction details', () {
    Future<String> createIncome() async {
      final cat = (await service.watchCategories().first).firstWhere((c) => c.name == 'Other Income');
      return service.createIncome(FinanceIncomeModel(
        id: '',
        title: 'School fair stall',
        categoryId: cat.id,
        categoryName: 'Other Income',
        programType: 'other',
        studentId: '',
        studentName: 'Parent Committee',
        classId: '',
        className: '',
        amount: 2500,
        incomeDate: DateTime(2026, 11, 4),
        paymentMode: 'upi',
        accountId: cashId,
        accountName: 'Cash',
        referenceNo: 'UPI-778',
        remarks: 'Stall rent for the fair',
        attachmentUrls: const [],
        ledgerEntryId: '',
        createdAt: DateTime(2026, 11, 4, 9, 30),
        updatedAt: DateTime(2026, 11, 4, 9, 30),
        createdBy: 'admin',
      ));
    }

    Future<String> ledgerIdOf(String incomeId) async => (await firestore.collection('finance_income').doc(incomeId).get()).data()!['ledgerEntryId'] as String;

    Future<void> openRow(WidgetTester tester, String title) async {
      await tap(tester, find.ancestor(of: find.text(title), matching: find.byType(LedgerEntryCard)));
      expect(key('ledger-detail'), findsOneWidget);
    }

    String value(WidgetTester tester, String field) => tester.widget<SelectableText>(key('ledger-detail-$field-value')).data!;

    testWidgets('18, 19, 21. the tapped transaction, every available field, formatted as in Finance', (tester) async {
      await add('Other row', 'income', 10, DateTime(2026, 11, 3));
      final ledgerId = await ledgerIdOf(await createIncome());
      await pumpLedger(tester);
      await openRow(tester, 'School fair stall');
      expect(tester.widget<Text>(key('ledger-detail-title')).data, 'School fair stall');
      expect(find.descendant(of: key('ledger-detail-type'), matching: find.text('Income')), findsOneWidget);
      expect(tester.widget<Text>(key('ledger-detail-amount')).data, '+₹2500');
      expect(value(tester, 'date'), '04 Nov 2026');
      expect(value(tester, 'category'), 'Other Income');
      expect(value(tester, 'subcategory'), 'other');
      expect(value(tester, 'party'), 'Parent Committee');
      expect(value(tester, 'account'), 'Cash');
      expect(value(tester, 'payment-mode'), 'UPI');
      expect(value(tester, 'reference'), 'UPI-778');
      expect(value(tester, 'notes'), 'Stall rent for the fair');
      expect(value(tester, 'source'), 'Income entered in Finance');
      expect(value(tester, 'id'), ledgerId);
      expect(value(tester, 'created-by'), isNotEmpty);
    });

    testWidgets('20. fields with no value are left out; an expense is marked as one; a cancelled entry says so', (tester) async {
      await add('Bare expense', 'expense', 120, null, status: 'cancelled', extra: {'categoryName': '', 'accountName': '', 'createdAt': null});
      await add('Anchor', 'income', 1, DateTime(2026, 11, 2));
      await pumpLedger(tester);
      await tap(tester, key('ledger-period-all-time'));
      await tap(tester, key('ledger-show-cancelled'));
      await openRow(tester, 'Bare expense');
      expect(find.descendant(of: key('ledger-detail-type'), matching: find.text('Expense')), findsOneWidget);
      expect(tester.widget<Text>(key('ledger-detail-amount')).data, '-₹120');
      expect(key('ledger-detail-cancelled'), findsOneWidget);
      expect(key('ledger-detail-cancelled-note'), findsOneWidget);
      for (final f in ['date', 'category', 'subcategory', 'party', 'class', 'account', 'payment-mode', 'reference', 'invoice', 'notes', 'attachments', 'created', 'updated']) {
        expect(key('ledger-detail-$f'), findsNothing, reason: f);
      }
      expect(key('ledger-detail-edit'), findsNothing);
      expect(key('ledger-detail-void'), findsNothing);
    });

    testWidgets('22. close button, Escape and a tap outside close it', (tester) async {
      await createIncome();
      await pumpLedger(tester);
      await openRow(tester, 'School fair stall');
      await tap(tester, key('ledger-detail-close'));
      expect(key('ledger-detail'), findsNothing);
      await openRow(tester, 'School fair stall');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(key('ledger-detail'), findsNothing);
      await openRow(tester, 'School fair stall');
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(key('ledger-detail'), findsNothing);
    });

    for (final size in const [Size(1400, 1000), Size(800, 1000), Size(360, 640)]) {
      testWidgets('23. fits and scrolls at ${size.width.toInt()}px', (tester) async {
        await createIncome();
        await pumpLedger(tester, size: size);
        await openRow(tester, 'School fair stall');
        expect(tester.takeException(), isNull);
        final rect = tester.getRect(key('ledger-detail'));
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(size.width));
        expect(rect.bottom, lessThanOrEqualTo(size.height));
        expect(key('ledger-detail-scroll'), findsOneWidget);
        expect(key('ledger-detail-close'), findsOneWidget);
      });
    }

    testWidgets('24. Edit opens the existing Edit Income dialog; Void runs the existing void (entry cancelled, totals updated)', (tester) async {
      final incomeId = await createIncome();
      await pumpLedger(tester);
      expect(cardValue(tester, 'ledger-total-income'), '₹2500');
      await openRow(tester, 'School fair stall');
      await tap(tester, key('ledger-detail-edit'));
      expect(key('ledger-detail'), findsNothing);
      expect(find.byType(AddIncomeDialog), findsOneWidget);
      expect(tester.widget<AddIncomeDialog>(find.byType(AddIncomeDialog)).initial!.id, incomeId);
      Navigator.of(tester.element(find.byType(AddIncomeDialog))).pop();
      await tester.pumpAndSettle();

      await openRow(tester, 'School fair stall');
      await tap(tester, key('ledger-detail-void'));
      expect(find.text('Void Income Entry'), findsOneWidget, reason: 'the existing confirmation');
      await tap(tester, find.widgetWithText(FilledButton, 'Void'));
      expect((await firestore.collection('finance_income').doc(incomeId).get()).data()!['isDeleted'], isTrue);
      expect(cardValue(tester, 'ledger-total-income'), '₹0');
      expect(find.text('School fair stall'), findsNothing, reason: 'voided: hidden by default');
      await tap(tester, key('ledger-show-cancelled'));
      await openRow(tester, 'School fair stall');
      expect(key('ledger-detail-cancelled'), findsOneWidget);
      expect(key('ledger-detail-edit'), findsNothing, reason: 'a voided entry has no actions');
    });

    testWidgets('24. an expense invoice payment offers the existing Reverse payment; a direct expense has no edit', (tester) async {
      final ledgerRef = firestore.collection('finance_ledger').doc();
      await ledgerRef.set({
        'entryType': 'expense', 'amount': 800, 'accountId': cashId, 'accountName': 'Cash', 'status': 'confirmed',
        'sourceModule': 'invoice', 'sourceId': 'inv-1', 'invoiceNo': 'EXP-0042', 'categoryId': 'expense', 'categoryName': 'Expense',
        'title': 'Expense Payment - Acme', 'transactionDate': DateTime(2026, 11, 5), 'createdAt': DateTime(2026, 11, 5),
      });
      await firestore.collection('finance_income').add({
        'title': 'Expense Payment - Acme', 'amount': 800, 'programType': 'invoice', 'invoiceType': 'expense', 'sourceModule': 'invoice',
        'studentName': 'Acme', 'ledgerEntryId': ledgerRef.id, 'createdAt': DateTime(2026, 11, 5),
      });
      await add('Direct purchase', 'expense', 90, DateTime(2026, 11, 2), extra: {'sourceModule': 'finance', 'subCategoryName': 'Corner Shop'});
      await pumpLedger(tester);

      await openRow(tester, 'Expense Payment - Acme');
      expect(value(tester, 'invoice'), 'EXP-0042');
      expect(value(tester, 'party'), 'Acme');
      expect(value(tester, 'source'), 'Expense invoice payment');
      expect(key('ledger-detail-edit'), findsNothing);
      await tap(tester, key('ledger-detail-reverse'));
      expect(find.text('Reverse Payment'), findsWidgets, reason: 'the existing reversal dialog');
      await tap(tester, find.widgetWithText(TextButton, 'Back'));
      expect((await firestore.collection('finance_ledger').doc(ledgerRef.id).get()).data()!['status'], 'confirmed', reason: 'nothing reversed without confirming');

      await openRow(tester, 'Direct purchase');
      expect(value(tester, 'subcategory'), 'Corner Shop');
      expect(find.text('Vendor'), findsOneWidget);
      expect(key('ledger-detail-edit'), findsNothing);
      expect(key('ledger-detail-reverse'), findsNothing);
      expect(key('ledger-detail-done'), findsOneWidget);
    });
  });

  testWidgets('27. the Dashboard and other tabs are unchanged; the Dashboard rows don’t open details', (tester) async {
    await seed();
    tester.view.physicalSize = const Size(1400, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(child: MaterialApp(home: AdminFinanceScreen(service: service, clock: _today))));
    await tester.pumpAndSettle();
    for (final c in tester.widgetList<LedgerEntryCard>(find.byType(LedgerEntryCard))) {
      expect(c.onTap, isNull);
    }
    final s = await service.watchDashboardSummary().first;
    expect(s.closingBalance, 4750);
    expect(s.cashBalance, 4750);
    expect(s.totalIncome, 2450);
    expect(s.totalExpenses, 2700);
  });
}
