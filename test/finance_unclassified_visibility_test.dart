// Unclassified visibility fix:
// - FinanceDashboardSummaryModel.hasUnclassifiedActivity is set by a
//   non-zero opening balance on an unclassified account, or a non-cancelled,
//   non-zero ledger entry whose account is unclassified, blank/missing type,
//   or missing/unknown — independently of the net unclassified amount.
// - The Unclassified card (Dashboard) and note (Dashboard and Ledger) show
//   whenever it is set, with the actual unclassifiedBalance (₹0 or negative
//   included); a zero-balance unclassified account with no activity
//   doesn't show them.
// - Balances are unchanged: Cash + Bank + UPI + Unclassified = Closing.
// - Settings -> Accounts no longer shows a missing account type as CASH.
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/finance/models/finance_dashboard_summary_model.dart';
import 'package:montessori_app/modules/finance/services/finance_service.dart';
import 'package:montessori_app/modules/finance/ui/admin_finance_screen.dart';
import 'package:montessori_app/modules/finance/widgets/finance_summary_card.dart';

import 'support/buffered_transaction_firestore.dart';

void main() {
  late BufferedTransactionFirestore firestore;
  late FinanceService service;

  setUp(() async {
    firestore = BufferedTransactionFirestore();
    service = FinanceService(firestore: firestore, auth: MockFirebaseAuth());
    await service.ensureDefaults();
  });

  Future<String> accountIdByType(String type) async =>
      (await firestore.collection('finance_accounts').where('type', isEqualTo: type).get()).docs.single.id;

  Future<String> addAccount(String name, Object? type, {double opening = 0}) async =>
      (await firestore.collection('finance_accounts').add({
        'name': name, 'type': ?type, 'openingBalance': opening, 'currentBalance': opening, 'isActive': true,
      })).id;

  var seq = 0;
  Future<void> addEntry(String? accountId, double amount, {String entryType = 'income', String status = 'confirmed'}) async {
    seq++;
    await firestore.collection('finance_ledger').add({
      'entryType': entryType,
      'amount': amount,
      'accountId': ?accountId,
      'status': status,
      'title': 'Entry $seq',
      'transactionDate': DateTime(2026, 9, 1),
      'createdAt': DateTime(2026, 9, 1).add(Duration(minutes: seq)),
    });
  }

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(child: MaterialApp(home: AdminFinanceScreen(service: service))));
    await tester.pumpAndSettle();
  }

  Future<void> openTab(WidgetTester tester, String label) async {
    await tester.tap(find.widgetWithText(ChoiceChip, label));
    await tester.pumpAndSettle();
  }

  final note = find.textContaining('is not shown in Cash, Bank or UPI');
  Finder unclassifiedCard(String value) => find.descendant(
        of: find.ancestor(of: find.text('Unclassified'), matching: find.byType(FinanceSummaryCard)),
        matching: find.text(value),
      );

  void expectReconciles(FinanceDashboardSummaryModel s) {
    expect(s.cashBalance + s.bankBalance + s.upiBalance + s.unclassifiedBalance, s.closingBalance);
    expect(s.openingBalance + s.netBalance, s.closingBalance);
  }

  /// Dashboard: card + note; Ledger: note. Or neither.
  Future<void> expectShown(WidgetTester tester, {required String? value}) async {
    await pump(tester);
    if (value == null) {
      expect(find.text('Unclassified'), findsNothing);
      expect(note, findsNothing);
    } else {
      expect(unclassifiedCard(value), findsOneWidget);
      expect(note, findsOneWidget);
    }
    await openTab(tester, 'Ledger');
    expect(note, value == null ? findsNothing : findsOneWidget);
  }

  testWidgets('1. no unclassified account or activity: card and note hidden', (tester) async {
    await addEntry(await accountIdByType('cash'), 1000);
    await addEntry(await accountIdByType('upi'), 100);
    await addAccount('Spare Wallet', 'wallet'); // unclassified type, no balance, no activity
    await addEntry(await accountIdByType('cash'), 0); // zero-amount entry is not activity
    final s = await service.watchDashboardSummary().first;
    expect(s.hasUnclassifiedActivity, isFalse);
    expect(s.unclassifiedBalance, 0);
    expectReconciles(s);
    await expectShown(tester, value: null);
  });

  testWidgets('2. unclassified balance ₹250: card and note shown', (tester) async {
    await addEntry(await addAccount('Petty', 'other'), 250);
    final s = await service.watchDashboardSummary().first;
    expect(s.hasUnclassifiedActivity, isTrue);
    expect(s.unclassifiedBalance, 250);
    expectReconciles(s);
    await expectShown(tester, value: '₹250');
  });

  testWidgets('3. opening ₹500 and expense ₹500: Unclassified shown at ₹0', (tester) async {
    final wallet = await addAccount('Wallet', 'wallet', opening: 500);
    await addEntry(wallet, 500, entryType: 'expense');
    final s = await service.watchDashboardSummary().first;
    expect(s.hasUnclassifiedActivity, isTrue);
    expect(s.unclassifiedOpeningBalance, 500);
    expect(s.unclassifiedBalance, 0);
    expectReconciles(s);
    await expectShown(tester, value: '₹0');
    expect(find.textContaining('net to ₹0'), findsOneWidget);
    expect(find.textContaining('+ Unclassified ₹0'), findsOneWidget);
  });

  testWidgets('4. negative unclassified net balance: card shown with the negative amount', (tester) async {
    await addEntry(await addAccount('Wallet', 'wallet'), 300, entryType: 'expense');
    final s = await service.watchDashboardSummary().first;
    expect(s.hasUnclassifiedActivity, isTrue);
    expect(s.unclassifiedBalance, -300);
    expectReconciles(s);
    await expectShown(tester, value: '₹-300');
  });

  testWidgets('5a. missing account type with activity: card shown', (tester) async {
    await addEntry(await addAccount('Untyped', null), 40);
    final s = await service.watchDashboardSummary().first;
    expect(s.hasUnclassifiedActivity, isTrue);
    expect(s.unclassifiedBalance, 40);
    await expectShown(tester, value: '₹40');
  });

  testWidgets('5b. missing account ID with activity: card shown', (tester) async {
    await addEntry(null, 60);
    await addEntry('deleted-account', 0); // no amount: not activity on its own
    final s = await service.watchDashboardSummary().first;
    expect(s.hasUnclassifiedActivity, isTrue);
    expect(s.unclassifiedBalance, 60);
    await expectShown(tester, value: '₹60');
  });

  test('5c. missing type / missing ID without financial activity, or only cancelled: not shown', () async {
    await addAccount('Untyped', null);
    await addEntry('deleted-account', 75, status: 'cancelled');
    final s = await service.watchDashboardSummary().first;
    expect(s.hasUnclassifiedActivity, isFalse);
    expect(s.unclassifiedBalance, 0);
  });

  test('period summaries count activity carried into the opening balance, not after the period', () async {
    final wallet = await addAccount('Wallet', 'wallet');
    await firestore.collection('finance_ledger').add({
      'entryType': 'income', 'amount': 20, 'accountId': wallet, 'status': 'confirmed',
      'transactionDate': DateTime(2026, 5, 1), 'createdAt': DateTime(2026, 5, 1),
    });
    final june = await service.watchDashboardSummary(periodStart: DateTime(2026, 6, 1), periodEnd: DateTime(2026, 6, 30)).first;
    expect(june.hasUnclassifiedActivity, isTrue);
    expect(june.unclassifiedBalance, 20);
    final april = await service.watchDashboardSummary(periodStart: DateTime(2026, 4, 1), periodEnd: DateTime(2026, 4, 30)).first;
    expect(april.hasUnclassifiedActivity, isFalse);
  });

  testWidgets('6. all displayed balances reconcile exactly to Closing Balance', (tester) async {
    await firestore.doc('finance_accounts/${await accountIdByType('cash')}').update({'openingBalance': 1000});
    await addEntry(await accountIdByType('cash'), 4500);
    await addEntry(await accountIdByType('bank'), 700, entryType: 'expense');
    await addEntry(await accountIdByType('upi'), 100);
    final wallet = await addAccount('Wallet', 'wallet', opening: 500);
    await addEntry(wallet, 500, entryType: 'expense');
    await addEntry(null, 20, entryType: 'expense');

    final s = await service.watchDashboardSummary().first;
    expect(s.cashBalance, 5500);
    expect(s.bankBalance, -700);
    expect(s.upiBalance, 100);
    expect(s.unclassifiedBalance, -20);
    expect(s.closingBalance, 4880);
    expectReconciles(s);

    const line = 'Closing Balance ₹4880 = Cash ₹5500 + Bank ₹-700 + UPI ₹100 + Unclassified ₹-20';
    await pump(tester);
    expect(find.text(line), findsOneWidget);
    await openTab(tester, 'Ledger');
    expect(find.text(line), findsOneWidget);
    expect(find.text('₹4880'), findsOneWidget); // Closing Balance card
  });

  testWidgets('Settings -> Accounts shows a missing type as unclassified, not CASH', (tester) async {
    await addAccount('Untyped Account', null);
    await pump(tester);
    await openTab(tester, 'Settings');
    final card = find.ancestor(of: find.text('Untyped Account'), matching: find.byType(Container)).first;
    expect(find.descendant(of: card, matching: find.text('NO TYPE · UNCLASSIFIED')), findsOneWidget);
    expect(find.descendant(of: card, matching: find.text('CASH')), findsNothing);
    // Standard accounts are unchanged.
    expect(find.text('CASH'), findsOneWidget);
    expect(find.text('UPI'), findsWidgets);
  });
}
