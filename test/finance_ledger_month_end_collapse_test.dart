// Finance -> Ledger presentation: "Historical Month-end Balances" is a
// collapsible section (collapsed when the Ledger opens and when the month
// changes; hidden for All time), and the current figures are labelled as
// current ("Current Closing Balance", "Current Account Balances"). No
// figure changes. Synthetic test data only.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/finance/models/finance_account_model.dart';
import 'package:montessori_app/modules/finance/models/finance_dashboard_summary_model.dart';
import 'package:montessori_app/modules/finance/services/finance_service.dart';
import 'package:montessori_app/modules/finance/ui/admin_finance_screen.dart';
import 'package:montessori_app/modules/finance/widgets/finance_summary_card.dart';

import 'support/buffered_transaction_firestore.dart';

/// Counts the month-end calculations (FinanceService.dashboardSummaryAt).
class _CountingFinance extends FinanceService {
  _CountingFinance({required super.firestore, required super.auth});
  int calls = 0;

  /// Subscriptions to the name-ordered account list.
  int namedAccountStreams = 0;

  @override
  Stream<List<FinanceAccountModel>> watchAccounts() {
    namedAccountStreams++;
    return super.watchAccounts();
  }

  @override
  Future<FinanceDashboardSummaryModel> dashboardSummaryAt({required DateTime periodEnd}) {
    calls++;
    return super.dashboardSummaryAt(periodEnd: periodEnd);
  }
}

void main() {
  late BufferedTransactionFirestore firestore;
  late FinanceService finance;
  late Map<String, String> ids;

  setUp(() async {
    firestore = BufferedTransactionFirestore();
    finance = FinanceService(firestore: firestore, auth: MockFirebaseAuth());
    await finance.ensureDefaults();
    ids = {for (final d in (await firestore.collection('finance_accounts').get()).docs) d.data()['type'] as String: d.id};
    // Cash opening ₹1000 from 1 June; Oct +500 cash; Nov −200 bank; an
    // undated opening balance on UPI (₹300).
    await finance.updateAccount(id: ids['cash']!, name: 'Cash', type: 'cash', openingBalance: 1000, isActive: true, openingBalanceDate: DateTime(2026, 6, 1));
    await firestore.collection('finance_accounts').doc(ids['upi']).update({'openingBalance': 300, 'currentBalance': 300});
    var n = 0;
    for (final (type, amount, account, date) in [('income', 500.0, 'cash', DateTime(2026, 10, 10)), ('expense', 200.0, 'bank', DateTime(2026, 11, 3))]) {
      n++;
      await firestore.collection('finance_ledger').add({'entryType': type, 'amount': amount, 'accountId': ids[account], 'status': 'confirmed', 'title': 'Entry $n', 'transactionDate': date, 'createdAt': DateTime(2026, 1, 1).add(Duration(minutes: n))});
    }
  });

  Finder key(String k) => find.byKey(Key(k));

  Future<void> settle(WidgetTester tester) async {
    await tester.pumpAndSettle();
    for (var i = 0; i < 20 && find.text('…').evaluate().isNotEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pumpAndSettle();
    }
  }

  Future<void> pumpLedger(WidgetTester tester, {Size size = const Size(1400, 3000), FinanceService? service}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(child: MaterialApp(home: AdminFinanceScreen(service: service ?? finance, clock: () => DateTime(2026, 11, 6)))));
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

  bool expanded() => key('ledger-month-end-content').evaluate().isNotEmpty;
  IconData chevron(WidgetTester tester) => tester.widget<Icon>(key('ledger-month-end-chevron')).icon!;
  String value(WidgetTester tester, String k) => tester.widget<FinanceSummaryCard>(key(k)).value;
  List<String> current(WidgetTester tester) => [for (final k in ['ledger-closing-balance', 'finance-balance-cash', 'finance-balance-bank', 'finance-balance-upi']) value(tester, k)];

  testWidgets('collapsed by default; opens and closes from its heading; its cards and disclosures are all there', (tester) async {
    await pumpLedger(tester);
    expect(find.text('Historical Month-end Balances'), findsOneWidget);
    expect(tester.widget<Text>(key('ledger-month-end-date')).data, '30 November 2026');
    expect(find.text('View historical Cash, Bank, UPI and total balances at the end of the selected month.'), findsOneWidget);
    expect(expanded(), isFalse);
    expect(key('ledger-month-end-total'), findsNothing);
    expect(chevron(tester), Icons.expand_more_rounded);

    await tap(tester, key('ledger-month-end-toggle'));
    expect(expanded(), isTrue);
    expect(chevron(tester), Icons.expand_less_rounded);
    expect([for (final k in ['cash', 'bank', 'upi', 'total']) value(tester, 'ledger-month-end-$k')], ['₹1500', '₹-200', '₹300', '₹1600']);
    for (final k in ['ledger-month-end-opening-dated', 'ledger-month-end-opening-undated', 'ledger-month-end-not-over', 'ledger-month-end-limits']) {
      expect(key(k), findsOneWidget, reason: k);
    }
    expect(find.textContaining('Historical, from the ledger'), findsOneWidget);

    await tap(tester, key('ledger-month-end-toggle'));
    expect(expanded(), isFalse);
    expect(key('ledger-month-end-limits'), findsNothing);
  });

  testWidgets('a new month: the date and figures follow, collapsed again; current balances never change; All time hides it', (tester) async {
    await pumpLedger(tester);
    final now = current(tester);
    expect(now, ['₹1600', '₹1500', '₹-200', '₹300']);
    await tap(tester, key('ledger-month-end-toggle'));
    await tap(tester, key('ledger-period-previous'));
    expect(tester.widget<Text>(key('ledger-month-end-date')).data, '31 October 2026');
    expect(expanded(), isFalse, reason: 'collapsed after changing months');
    expect(current(tester), now);
    await tap(tester, key('ledger-month-end-toggle'));
    expect([for (final k in ['cash', 'bank', 'upi', 'total']) value(tester, 'ledger-month-end-$k')], ['₹1500', '₹0', '₹300', '₹1800']);

    await tap(tester, key('ledger-period-pick'));
    await tap(tester, key('ledger-month-5'));
    expect(tester.widget<Text>(key('ledger-month-end-date')).data, '31 May 2026');
    await tap(tester, key('ledger-month-end-toggle'));
    expect(value(tester, 'ledger-month-end-cash'), '₹0', reason: 'Cash’s opening balance starts 1 June');
    expect(current(tester), now);

    await tap(tester, key('ledger-period-all-time'));
    expect(key('ledger-month-end'), findsNothing);
    expect(current(tester), now);
    await tap(tester, key('ledger-period-this-month'));
    expect(expanded(), isFalse);
  });

  testWidgets('worked out only while open: on expanding, again after an account\'s opening date changes, never while collapsed', (tester) async {
    final counting = _CountingFinance(firestore: firestore, auth: MockFirebaseAuth());
    await pumpLedger(tester, service: counting);
    expect(expanded(), isFalse);
    expect(counting.calls, 0, reason: 'collapsed: nothing is calculated');

    await tap(tester, key('ledger-month-end-toggle'));
    expect(counting.calls, 1, reason: 'one calculation on opening');
    // Cash 1000 (from 1 Jun) + 500, Bank −200, UPI 300 undated.
    expect(value(tester, 'ledger-month-end-total'), '₹1600');

    // The Cash opening balance now applies from 1 December: November's
    // month-end leaves it out once the account changes (no ledger change).
    await tester.runAsync(() => counting.updateAccount(
        id: ids['cash']!, name: 'Cash', type: 'cash', openingBalance: 1000, isActive: true, openingBalanceDate: DateTime(2026, 12, 1)));
    await settle(tester);
    expect(counting.calls, 2, reason: 'the account change recalculated it');
    expect(value(tester, 'ledger-month-end-total'), '₹600');
    expect(key('ledger-month-end-opening-later'), findsOneWidget);
    final current0 = current(tester);

    // Collapsed: neither an account change nor a new transaction recalculates.
    await tap(tester, key('ledger-month-end-toggle'));
    final whileClosed = counting.calls;
    await tester.runAsync(() async {
      await counting.updateAccount(id: ids['cash']!, name: 'Cash', type: 'cash', openingBalance: 1000, isActive: true, openingBalanceDate: DateTime(2026, 6, 1));
      await firestore.collection('finance_ledger').add({'entryType': 'income', 'amount': 50.0, 'accountId': ids['cash'], 'status': 'confirmed', 'title': 'Late entry', 'transactionDate': DateTime(2026, 11, 4), 'createdAt': DateTime(2026, 1, 2)});
    });
    await settle(tester);
    expect(counting.calls, whileClosed, reason: 'collapsed: no recalculation');
    expect(current(tester), isNot(current0), reason: 'the current balances still follow the ledger');

    // Reopened: the current figures (opening back from 1 June, +50).
    await tap(tester, key('ledger-month-end-toggle'));
    expect(counting.calls, whileClosed + 1);
    expect(value(tester, 'ledger-month-end-total'), '₹1650');
  });

  testWidgets('a legacy account with no name: its changes refresh the open section too; nothing while collapsed', (tester) async {
    late String legacy;
    await tester.runAsync(() async {
      legacy = (await firestore.collection('finance_accounts').add({'type': 'bank', 'openingBalance': 0, 'currentBalance': 0, 'isActive': true})).id;
    });
    final counting = _CountingFinance(firestore: firestore, auth: MockFirebaseAuth());
    await pumpLedger(tester, service: counting);
    expect(counting.calls, 0, reason: 'collapsed: nothing is calculated');

    final namedBefore = counting.namedAccountStreams;
    await tap(tester, key('ledger-month-end-toggle'));
    expect(counting.calls, 1, reason: 'one calculation on opening');
    expect(value(tester, 'ledger-month-end-total'), '₹1600');
    // Real Firestore leaves documents without `name` out of the name-ordered
    // list (the test fake doesn't), so the section must not listen to it.
    expect(counting.namedAccountStreams, namedBefore, reason: 'listens to every account, not the name-ordered list');

    // Its opening balance: ₹400 from 1 June. Only the account changes.
    await tester.runAsync(() => firestore.collection('finance_accounts').doc(legacy).update({
          'openingBalance': 400, 'currentBalance': 400, 'openingBalanceDate': Timestamp.fromDate(DateTime(2026, 6, 1))}));
    await settle(tester);
    expect(counting.calls, 2, reason: 'the nameless account\'s change recalculated it');
    expect(value(tester, 'ledger-month-end-total'), '₹2000');
    expect(key('ledger-month-end-opening-later'), findsNothing);

    // Its opening date moves to 1 December: left out of November, with the note.
    await tester.runAsync(() => firestore.collection('finance_accounts').doc(legacy).update({'openingBalanceDate': Timestamp.fromDate(DateTime(2026, 12, 1))}));
    await settle(tester);
    expect(counting.calls, 3);
    expect(value(tester, 'ledger-month-end-total'), '₹1600');
    expect(key('ledger-month-end-opening-later'), findsOneWidget);

    // Collapsed: its changes recalculate nothing.
    await tap(tester, key('ledger-month-end-toggle'));
    await tester.runAsync(() => firestore.collection('finance_accounts').doc(legacy).update({'openingBalanceDate': Timestamp.fromDate(DateTime(2026, 6, 1))}));
    await settle(tester);
    expect(counting.calls, 3, reason: 'collapsed: no recalculation');

    await tap(tester, key('ledger-month-end-toggle'));
    expect(counting.calls, 4);
    expect(value(tester, 'ledger-month-end-total'), '₹2000');
    // The document is never rewritten.
    final stored = (await tester.runAsync(() => firestore.collection('finance_accounts').doc(legacy).get()))!.data()!;
    expect(stored.containsKey('name'), isFalse);
  });

  testWidgets('collapsed again each time the Ledger tab opens', (tester) async {
    await pumpLedger(tester);
    await tap(tester, key('ledger-month-end-toggle'));
    expect(expanded(), isTrue);
    await tap(tester, find.widgetWithText(ChoiceChip, 'Income'));
    await tap(tester, find.widgetWithText(ChoiceChip, 'Ledger'));
    expect(expanded(), isFalse);
  });

  testWidgets('current figures are labelled as current, with the month note distinguishing all three', (tester) async {
    await pumpLedger(tester);
    final closing = tester.widget<FinanceSummaryCard>(key('ledger-closing-balance'));
    expect(closing.label, 'Current Closing Balance');
    expect(closing.caption, 'Current, all accounts');
    expect(find.text('Current Account Balances'), findsOneWidget);
    expect(find.text('Account Balances'), findsNothing);
    expect(find.text('Today’s balances, whatever month is selected.'), findsOneWidget);
    expect(find.textContaining('Current Closing Balance includes ₹1300 in account opening balances'), findsOneWidget);
    expect(
      tester.widget<Text>(key('ledger-period-note')).data,
      'Total Income, Total Expenses and Profit / Loss are for November 2026. Historical Month-end Balances show the accounts at the end of November 2026. '
      'Current Account Balances and the Current Closing Balance are today’s balances and don’t change with the month.',
    );
    // The Dashboard keeps its own labels.
    await tap(tester, find.widgetWithText(ChoiceChip, 'Dashboard'));
    expect(find.text('Account Balances'), findsOneWidget);
  });

  testWidgets('accessible: a button with its expanded state, named with its date', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpLedger(tester);
    final node = find.bySemanticsLabel(RegExp(r'^Historical Month-end Balances, 30 November 2026\. Expand$'));
    expect(node, findsOneWidget);
    expect(tester.getSemantics(node), isSemantics(isButton: true, hasExpandedState: true, isExpanded: false, hasTapAction: true));
    await tap(tester, key('ledger-month-end-toggle'));
    final open = find.bySemanticsLabel(RegExp(r'^Historical Month-end Balances, 30 November 2026\. Collapse$'));
    expect(tester.getSemantics(open), isSemantics(isButton: true, hasExpandedState: true, isExpanded: true, hasTapAction: true));
    handle.dispose();
  });

  for (final size in const [Size(1400, 1000), Size(800, 1200), Size(360, 800)]) {
    testWidgets('${size.width.toInt()}px: compact when collapsed; the opened cards fit; the Add button covers no heading', (tester) async {
      await pumpLedger(tester, size: size);
      expect(tester.takeException(), isNull);
      final collapsed = tester.getRect(key('ledger-month-end'));
      expect(collapsed.height, lessThan(size.width < 600 ? 220 : 130), reason: 'just its heading (its description wraps on a phone)');
      expect(collapsed.right, lessThanOrEqualTo(size.width));
      await tap(tester, key('ledger-month-end-toggle'));
      expect(tester.takeException(), isNull);
      expect(tester.getRect(key('ledger-month-end')).height, greaterThan(collapsed.height * 3), reason: 'collapsing saves real space');
      for (final k in ['cash', 'bank', 'upi', 'total']) {
        expect(tester.getRect(key('ledger-month-end-$k')).right, lessThanOrEqualTo(size.width), reason: k);
      }
      // Scrolled to the heading, the floating Add button doesn't cover it.
      await tester.ensureVisible(key('ledger-month-end-toggle'));
      await tester.pumpAndSettle();
      final heading = tester.getRect(key('ledger-month-end-toggle'));
      final fab = tester.getRect(key('finance-add'));
      expect(heading.overlaps(fab) && fab.top < heading.bottom && fab.left < heading.right, isFalse);
    });
  }
}
