// Finance opening balances (Phase B):
// - Net Movement = income − expenses for the period (opening balances
//   excluded).
// - Closing Balance = opening balances + Net Movement, calculated once in
//   FinanceService.watchDashboardSummary.
// - Cash/Bank/UPI include the opening balances of accounts of exactly that
//   stored `type` (never the name); other/missing types go to the
//   unclassified bucket, so Cash + Bank + UPI + Unclassified = Closing.
// - For a period, the opening balance is the stored opening balance plus
//   movement dated before the period; entries after it are excluded.
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/finance/models/finance_dashboard_summary_model.dart';
import 'package:montessori_app/modules/finance/services/finance_service.dart';
import 'package:montessori_app/modules/finance/ui/admin_finance_screen.dart';

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

  Future<void> setOpening(String type, double amount) async {
    final id = await accountIdByType(type);
    await firestore.collection('finance_accounts').doc(id).update({'openingBalance': amount, 'currentBalance': amount});
  }

  Future<String> addAccount(String name, String type, double opening) async =>
      (await firestore.collection('finance_accounts').add({
        'name': name, 'type': type, 'openingBalance': opening, 'currentBalance': opening, 'isActive': true,
      })).id;

  var seq = 0;
  Future<void> addEntry({
    required String accountId,
    required double amount,
    String entryType = 'income',
    String status = 'confirmed',
    DateTime? date,
  }) async {
    seq++;
    await firestore.collection('finance_ledger').add({
      'entryType': entryType,
      'amount': amount,
      'accountId': accountId,
      'status': status,
      'title': 'Entry $seq',
      'transactionDate': date ?? DateTime(2026, 9, 1),
      'createdAt': DateTime(2026, 9, 1).add(Duration(minutes: seq)),
    });
  }

  void expectBucketsAddUp(FinanceDashboardSummaryModel s) {
    expect(s.cashBalance + s.bankBalance + s.upiBalance + s.unclassifiedBalance, s.closingBalance);
    expect(s.openingBalance + s.netBalance, s.closingBalance);
    expect(
      s.cashOpeningBalance + s.bankOpeningBalance + s.upiOpeningBalance + s.unclassifiedOpeningBalance,
      s.openingBalance,
    );
  }

  test('opening balance plus income', () async {
    await setOpening('cash', 10000);
    await addEntry(accountId: await accountIdByType('cash'), amount: 4500);

    final s = await service.watchDashboardSummary().first;
    expect(s.totalIncome, 4500);
    expect(s.netBalance, 4500); // Net Movement unchanged in meaning
    expect(s.openingBalance, 10000);
    expect(s.cashOpeningBalance, 10000);
    expect(s.closingBalance, 14500);
    expect(s.cashBalance, 14500);
    expectBucketsAddUp(s);
  });

  test('opening balance plus expenses', () async {
    await setOpening('bank', 50000);
    final bank = await accountIdByType('bank');
    await addEntry(accountId: bank, amount: 12000, entryType: 'expense');
    await addEntry(accountId: bank, amount: 3000, entryType: 'expense', status: 'cancelled');

    final s = await service.watchDashboardSummary().first;
    expect(s.totalExpenses, 12000);
    expect(s.netBalance, -12000);
    expect(s.closingBalance, 38000);
    expect(s.bankBalance, 38000);
    expectBucketsAddUp(s);
  });

  test('Cash, Bank and UPI each get only their own type\'s opening balance', () async {
    await setOpening('cash', 1000);
    await setOpening('bank', 20000);
    await setOpening('upi', 300);
    await addAccount('HDFC Savings', 'bank', 5000); // custom name, still bank
    await addAccount('Bank UPI', 'upi', 700); // misleading name, upi only
    await addEntry(accountId: await accountIdByType('cash'), amount: 500);
    await addEntry(accountId: (await firestore.collection('finance_accounts').where('name', isEqualTo: 'Bank UPI').get()).docs.single.id, amount: 100);

    final s = await service.watchDashboardSummary().first;
    expect(s.cashOpeningBalance, 1000);
    expect(s.bankOpeningBalance, 25000);
    expect(s.upiOpeningBalance, 1000);
    expect(s.cashBalance, 1500);
    expect(s.bankBalance, 25000);
    expect(s.upiBalance, 1100);
    expect(s.unclassifiedBalance, 0);
    expect(s.closingBalance, 27600);
    expectBucketsAddUp(s);
  });

  test('accounts without an opening balance behave exactly as before', () async {
    // Legacy account doc with no openingBalance field at all.
    final legacy = await firestore.collection('finance_accounts').add({'name': 'Old Cash', 'type': 'cash', 'currentBalance': 0, 'isActive': true});
    await addEntry(accountId: legacy.id, amount: 4500);
    await addEntry(accountId: await accountIdByType('upi'), amount: 2000, entryType: 'expense');

    final s = await service.watchDashboardSummary().first;
    expect(s.openingBalance, 0);
    expect(s.cashBalance, 4500);
    expect(s.upiBalance, -2000);
    expect(s.netBalance, 2500);
    expect(s.closingBalance, s.netBalance);
    expectBucketsAddUp(s);
  });

  test('opening balances of unclassified account types are reported, not allocated', () async {
    final wallet = await addAccount('Cash Box', 'wallet', 800); // cash-looking name
    await addAccount('Untyped', '', 200);
    await addEntry(accountId: wallet, amount: 50, entryType: 'expense');
    await addEntry(accountId: 'deleted-account', amount: 100);

    final s = await service.watchDashboardSummary().first;
    expect(s.cashBalance, 0);
    expect(s.bankBalance, 0);
    expect(s.upiBalance, 0);
    expect(s.unclassifiedOpeningBalance, 1000);
    expect(s.unclassifiedBalance, 1050); // 1000 opening + 100 − 50
    expect(s.closingBalance, 1050);
    expectBucketsAddUp(s);
  });

  group('date range', () {
    late String cash;
    setUp(() async {
      await setOpening('cash', 10000);
      cash = await accountIdByType('cash');
      await addEntry(accountId: cash, amount: 2000, date: DateTime(2026, 5, 31)); // before
      await addEntry(accountId: cash, amount: 500, entryType: 'expense', date: DateTime(2026, 5, 15)); // before
      await addEntry(accountId: cash, amount: 4000, date: DateTime(2026, 6, 1)); // first day
      await addEntry(accountId: cash, amount: 1000, entryType: 'expense', date: DateTime(2026, 6, 30, 18)); // last day
      await addEntry(accountId: cash, amount: 9000, date: DateTime(2026, 7, 1)); // after
      await addEntry(accountId: cash, amount: 700, date: DateTime(2026, 6, 10), status: 'cancelled');
    });

    test('period opening carries earlier movement; later entries are excluded', () async {
      final s = await service
          .watchDashboardSummary(periodStart: DateTime(2026, 6, 1), periodEnd: DateTime(2026, 6, 30))
          .first;
      expect(s.totalIncome, 4000);
      expect(s.totalExpenses, 1000);
      expect(s.netBalance, 3000);
      expect(s.openingBalance, 11500); // 10000 stored + 2000 − 500 before June
      expect(s.closingBalance, 14500);
      expect(s.cashBalance, 14500);
      expectBucketsAddUp(s);
    });

    test('consecutive periods chain: one closing is the next opening', () async {
      final june = await service
          .watchDashboardSummary(periodStart: DateTime(2026, 6, 1), periodEnd: DateTime(2026, 6, 30))
          .first;
      final july = await service.watchDashboardSummary(periodStart: DateTime(2026, 7, 1)).first;
      final allTime = await service.watchDashboardSummary().first;
      expect(july.openingBalance, june.closingBalance);
      expect(july.closingBalance, allTime.closingBalance);
      expect(allTime.openingBalance, 10000);
      expect(allTime.netBalance, 13500);
      expect(allTime.closingBalance, 23500);
    });
  });

  testWidgets('Dashboard and Ledger show the same closing figures without double-counting', (tester) async {
    await setOpening('cash', 10000);
    await setOpening('upi', 2000);
    final wallet = await addAccount('Wallet', 'wallet', 300);
    await addEntry(accountId: await accountIdByType('cash'), amount: 4500);
    await addEntry(accountId: wallet, amount: 100, entryType: 'expense');
    tester.view.physicalSize = const Size(1400, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(ProviderScope(child: MaterialApp(home: AdminFinanceScreen(service: service))));
    await tester.pumpAndSettle();
    // Dashboard: Net Balance remains the period movement; account cards are closing balances.
    expect(find.text('₹4400'), findsWidgets); // Net Balance (4500 − 100)
    expect(find.text('₹14500'), findsOneWidget); // Cash
    expect(find.text('₹2000'), findsOneWidget); // UPI

    await tester.tap(find.widgetWithText(ChoiceChip, 'Ledger'));
    await tester.pumpAndSettle();
    expect(find.text('₹4400'), findsOneWidget); // Net Movement
    expect(find.text('₹16700'), findsOneWidget); // Closing = 12300 opening + 4400
    expect(find.text('₹14500'), findsOneWidget); // Cash
    expect(find.text('₹2000'), findsOneWidget); // UPI
    expect(find.textContaining('includes ₹12300 in account opening balances'), findsOneWidget);
    expect(find.textContaining('₹200 is not shown in Cash, Bank or UPI'), findsOneWidget);
    expect(find.textContaining('includes ₹300 opening balance'), findsOneWidget);

    final s = await service.watchDashboardSummary().first;
    expect(s.closingBalance, 16700);
    expectBucketsAddUp(s);
  });
}
