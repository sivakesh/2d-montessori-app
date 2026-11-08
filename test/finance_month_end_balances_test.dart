// Finance Phase 2: historical month-end account balances.
// For a month ending on D, each account's balance is its opening balance
// plus every non-cancelled ledger entry dated on or before D (local
// calendar day), income in and everything else out — FinanceService
// .dashboardSummaryAt (watchDashboardSummary's own calculation bounded by
// `periodEnd`), the same calculation as
// the current balances. Undated entries can't be placed and are left out
// (and disclosed). The Ledger shows these for a chosen month; All time and
// the monthly Income / Expenses / Profit / Loss are unchanged.
// Synthetic test data only.
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/finance/models/finance_income_model.dart';
import 'package:montessori_app/modules/finance/models/finance_ledger_entry_model.dart';
import 'package:montessori_app/modules/finance/models/ledger_period.dart';
import 'package:montessori_app/modules/finance/services/finance_service.dart';
import 'package:montessori_app/modules/finance/ui/admin_finance_screen.dart';
import 'package:montessori_app/modules/finance/widgets/finance_summary_card.dart';

import 'support/buffered_transaction_firestore.dart';

void main() {
  late BufferedTransactionFirestore firestore;
  late FinanceService finance;
  late Map<String, String> ids; // type -> account id
  late String walletId;

  setUp(() async {
    firestore = BufferedTransactionFirestore();
    finance = FinanceService(firestore: firestore, auth: MockFirebaseAuth());
    await finance.ensureDefaults();
    ids = {for (final d in (await firestore.collection('finance_accounts').get()).docs) d.data()['type'] as String: d.id};
    walletId = (await firestore.collection('finance_accounts').add({'name': 'Petty Wallet', 'type': 'wallet', 'isActive': true, 'openingBalance': 200, 'currentBalance': 200})).id;
  });

  var seq = 0;
  Future<void> entry(String type, double amount, String accountId, DateTime? date, {String status = 'confirmed', String title = ''}) async {
    seq++;
    await firestore.collection('finance_ledger').add({
      'entryType': type, 'amount': amount, 'accountId': accountId, 'accountName': 'x', 'status': status,
      'title': title.isEmpty ? 'Entry $seq' : title, 'transactionDate': date, 'createdAt': DateTime(2026, 1, 1).add(Duration(minutes: seq)),
    });
  }

  /// Opening: Cash 1000, Bank 5000, UPI 0, Wallet 200.
  /// Sep 10 cash +2000 · Oct 5 bank −1500 · Oct 12 wallet −50 · Oct 25 a
  /// deleted account +80 · Oct 31 23:59 UPI +700 · Nov 1 00:00 cash −400 ·
  /// cancelled: Oct 15 cash +300, Oct 20 bank −250 · undated cash +60.
  Future<void> seed() async {
    await firestore.collection('finance_accounts').doc(ids['cash']).update({'openingBalance': 1000, 'currentBalance': 1000});
    await firestore.collection('finance_accounts').doc(ids['bank']).update({'openingBalance': 5000, 'currentBalance': 5000});
    await entry('income', 2000, ids['cash']!, DateTime(2026, 9, 10));
    await entry('expense', 1500, ids['bank']!, DateTime(2026, 10, 5));
    await entry('expense', 50, walletId, DateTime(2026, 10, 12));
    await entry('income', 80, 'deleted-acc', DateTime(2026, 10, 25));
    await entry('income', 700, ids['upi']!, DateTime(2026, 10, 31, 23, 59, 59), title: 'Last minute of October');
    await entry('expense', 400, ids['cash']!, DateTime(2026, 11, 1), title: 'First minute of November');
    await entry('income', 300, ids['cash']!, DateTime(2026, 10, 15), status: 'cancelled');
    await entry('expense', 250, ids['bank']!, DateTime(2026, 10, 20), status: 'cancelled');
    await entry('income', 60, ids['cash']!, null, title: 'Undated');
  }

  Future<List<double>> monthEnd(int year, int month) async {
    final s = await finance.dashboardSummaryAt(periodEnd: LedgerPeriod.month(year, month).lastDay!);
    final streamed = await finance.watchDashboardSummary(periodEnd: LedgerPeriod.month(year, month).lastDay).first;
    expect(streamed.closingBalance, s.closingBalance, reason: 'one calculation');
    return [s.cashBalance, s.bankBalance, s.upiBalance, s.unclassifiedBalance, s.closingBalance];
  }

  group('calculation', () {
    test('opening balances plus everything up to each month-end; several months; boundaries; cancelled and undated left out', () async {
      await seed();
      expect(await monthEnd(2026, 8), [1000, 5000, 0, 200, 6200], reason: 'before any transaction: opening balances only');
      expect(await monthEnd(2026, 9), [3000, 5000, 0, 200, 8200]);
      expect(await monthEnd(2026, 10), [3000, 3500, 700, 230, 7430], reason: 'Oct 31 23:59 in, Nov 1 out; wallet and deleted account are Other');
      expect(await monthEnd(2026, 11), [2600, 3500, 700, 230, 7030], reason: 'cumulative, not just November');
      expect(await monthEnd(2027, 3), [2600, 3500, 700, 230, 7030], reason: 'a later month with no transactions');
      final now = await finance.watchDashboardSummary().first;
      expect([now.cashBalance, now.closingBalance], [2660, 7090], reason: 'current balances still include the undated ₹60');
      final ledger = (await firestore.collection('finance_ledger').get()).docs.map((d) => FinanceLedgerEntryModel.fromMap(d.id, d.data()));
      final undated = UndatedLedgerEntries.of(ledger);
      expect([undated.count, undated.net], [1, 60]);
    });

    test('voided income and reversed payments are left out of every month-end, back to their own date', () async {
      final cat = (await finance.watchCategories().first).firstWhere((c) => c.name == 'Other Income');
      final incomeId = await finance.createIncome(FinanceIncomeModel(
        id: '', title: 'Gift', categoryId: cat.id, categoryName: 'Other Income', programType: 'other', studentId: '', studentName: '', classId: '',
        className: '', amount: 900, incomeDate: DateTime(2026, 10, 10), paymentMode: 'cash', accountId: ids['cash']!, accountName: 'Cash',
        referenceNo: '', remarks: '', attachmentUrls: const [], ledgerEntryId: '', createdAt: DateTime(2026, 10, 10), updatedAt: DateTime(2026, 10, 10), createdBy: 'a',
      ));
      final invoice = await finance.createExpenseInvoice({'partyName': 'Vendor', 'totalAmount': 400, 'amount': 400, 'invoiceNo': 'E1', 'invoiceDate': DateTime(2026, 10, 1)});
      final payment = (await finance.payInvoice(invoiceId: invoice, invoiceType: 'expense', amount: 400, paidDate: DateTime(2026, 10, 20), paymentMode: 'upi', referenceNo: '', remarks: ''))!;
      expect((await monthEnd(2026, 10)).take(3), [900, 0, -400]);
      await finance.voidIncome(incomeId);
      await finance.reverseExpenseInvoicePayment(paymentId: payment, reason: 'mistake');
      expect(await monthEnd(2026, 10), [0, 0, 0, 200, 200], reason: 'only the wallet’s opening balance is left');
      expect(await monthEnd(2026, 11), [0, 0, 0, 200, 200]);
    });

    test('a negative historical balance shows as negative, even when the account is positive now', () async {
      await entry('expense', 500, ids['cash']!, DateTime(2026, 10, 3));
      await entry('income', 800, ids['cash']!, DateTime(2026, 11, 2));
      expect((await monthEnd(2026, 10)).first, -500);
      expect((await finance.watchDashboardSummary().first).cashBalance, 300);
    });
  });

  group('Ledger', () {
    /// Lets the month-end figures, worked out after the ledger arrives, show.
    Future<void> settle(WidgetTester tester) async {
      await tester.pumpAndSettle();
      // The section starts collapsed: open it to read its cards.
      final toggle = find.byKey(const Key('ledger-month-end-toggle'));
      if (toggle.evaluate().isNotEmpty && find.byKey(const Key('ledger-month-end-content')).evaluate().isEmpty) {
        await tester.ensureVisible(toggle);
        await tester.pumpAndSettle();
        await tester.tap(toggle);
        await tester.pumpAndSettle();
      }
      for (var i = 0; i < 20 && find.text('…').evaluate().isNotEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pumpAndSettle();
      }
      expect(find.text('…'), findsNothing, reason: 'month-end balances loaded');
    }

    Future<void> pump(WidgetTester tester, {Size size = const Size(1400, 3400)}) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(ProviderScope(child: MaterialApp(home: AdminFinanceScreen(service: finance, clock: () => DateTime(2026, 11, 6, 10)))));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Ledger'));
      await settle(tester);
    }

    Future<void> tap(WidgetTester tester, Finder f) async {
      await tester.ensureVisible(f);
      await tester.pumpAndSettle();
      await tester.tap(f);
      await settle(tester);
    }

    Finder key(String k) => find.byKey(Key(k));
    FinanceSummaryCard card(WidgetTester tester, String k) => tester.widget<FinanceSummaryCard>(key(k));
    List<String> monthEndValues(WidgetTester tester) => [for (final k in ['cash', 'bank', 'upi', 'other', 'total']) card(tester, 'ledger-month-end-$k').value];

    testWidgets('a chosen month: its month-end balances, dated and labelled historical; monthly cards and current balances unchanged', (tester) async {
      await seed();
      await pump(tester);
      expect(tester.widget<Text>(key('ledger-month-end-date')).data, '30 November 2026');
      expect(monthEndValues(tester), ['₹2600', '₹3500', '₹700', '₹230', '₹7030']);
      expect(key('ledger-month-end-not-over'), findsOneWidget, reason: 'November isn’t over on 6 November');
      expect(find.textContaining('Historical, from the ledger'), findsOneWidget);
      expect(key('ledger-month-end-limits'), findsOneWidget);
      // Undated: disclosed, left out, and the total says so.
      expect(find.text('1 undated transaction (net +₹60) is not in these month-end balances: with no date, it can’t be placed in a month. It is included in the current Account Balances.'), findsOneWidget);
      expect(card(tester, 'ledger-month-end-total').label, 'Total at month-end (excl. undated)');
      // Current balances: as before (with the undated ₹60).
      expect(card(tester, 'finance-balance-cash').value, '₹2660');
      expect(card(tester, 'ledger-closing-balance').value, '₹7090');
      // Monthly figures: November only.
      expect([card(tester, 'ledger-total-income').value, card(tester, 'ledger-total-expenses').value, card(tester, 'ledger-profit-loss').value], ['₹0', '₹400', '-₹400']);

      await tap(tester, key('ledger-period-previous'));
      expect(tester.widget<Text>(key('ledger-month-end-date')).data, '31 October 2026');
      expect(monthEndValues(tester), ['₹3000', '₹3500', '₹700', '₹230', '₹7430']);
      expect(key('ledger-month-end-not-over'), findsNothing);
      expect([card(tester, 'ledger-total-income').value, card(tester, 'ledger-total-expenses').value, card(tester, 'ledger-profit-loss').value], ['₹780', '₹1550', '-₹770']);
      expect(card(tester, 'ledger-closing-balance').value, '₹7090', reason: 'current, whatever the month');
      expect(card(tester, 'finance-balance-cash').value, '₹2660');

      await tap(tester, key('ledger-period-pick'));
      await tap(tester, key('ledger-month-8'));
      expect(monthEndValues(tester), ['₹1000', '₹5000', '₹0', '₹200', '₹6200'], reason: 'a month with no transactions: opening balances');
    });

    testWidgets('All time: no month-end section; the current balances as before', (tester) async {
      await seed();
      await pump(tester);
      await tap(tester, key('ledger-period-all-time'));
      expect(key('ledger-month-end'), findsNothing);
      expect(card(tester, 'ledger-closing-balance').value, '₹7090');
      expect(card(tester, 'finance-balance-cash').value, '₹2660');
      expect([card(tester, 'ledger-total-income').value, card(tester, 'ledger-total-expenses').value], ['₹2840', '₹1950']);
    });

    testWidgets('negative month-end balances are marked; no Other card or undated note when there are none', (tester) async {
      await firestore.collection('finance_accounts').doc(walletId).delete();
      await entry('expense', 500, ids['cash']!, DateTime(2026, 10, 3));
      await entry('income', 800, ids['cash']!, DateTime(2026, 11, 2));
      await pump(tester);
      await tap(tester, key('ledger-period-previous'));
      final cash = card(tester, 'ledger-month-end-cash');
      expect(cash.value, '₹-500');
      expect(cash.caption, 'Negative balance');
      expect(cash.valueColor, const Color(0xFFD32F2F));
      expect(card(tester, 'ledger-month-end-total').label, 'Total at month-end');
      expect(key('ledger-month-end-other'), findsNothing);
      expect(key('ledger-month-end-undated'), findsNothing);
      expect(card(tester, 'finance-balance-cash').caption, isNull, reason: 'the current balance (₹300) is not negative');
    });

    testWidgets('a transaction recorded while a month is shown updates its month-end figures', (tester) async {
      await seed();
      await pump(tester);
      await tap(tester, key('ledger-period-previous'));
      expect(card(tester, 'ledger-month-end-cash').value, '₹3000');
      await tester.runAsync(() => entry('income', 500, ids['cash']!, DateTime(2026, 10, 30)));
      await settle(tester);
      for (var i = 0; i < 20 && card(tester, 'ledger-month-end-cash').value == '₹3000'; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pumpAndSettle();
      }
      expect(card(tester, 'ledger-month-end-cash').value, '₹3500');
      expect(card(tester, 'ledger-month-end-total').value, '₹7930');
    });

    for (final size in const [Size(800, 3600), Size(360, 5200)]) {
      testWidgets('${size.width.toInt()}px: the section fits', (tester) async {
        await seed();
        await pump(tester, size: size);
        expect(tester.takeException(), isNull);
        expect(tester.getRect(key('ledger-month-end-total')).right, lessThanOrEqualTo(size.width));
      });
    }
  });
}
