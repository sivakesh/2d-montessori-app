// UAT investigation: when does the Unclassified card/note appear?
// Evidence only — exercises the current watchDashboardSummary and the
// Dashboard/Ledger rendering without changing either.
// - The card/note render when unclassified balances or activity exist.
// - Account `type` is trimmed and lower-cased, then must be exactly
//   cash/bank/upi; anything else, and any missing/blank/unknown accountId,
//   is unclassified.
// - Unclassified records whose amounts net to exactly zero are shown at ₹0
//   (hasUnclassifiedActivity; previously hidden).
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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

  Future<String> addAccount(String name, Object? type, {double opening = 0}) async =>
      (await firestore.collection('finance_accounts').add({
        'name': name, 'type': ?type, 'openingBalance': opening, 'currentBalance': opening, 'isActive': true,
      })).id;

  var seq = 0;
  Future<void> addEntry(String? accountId, double amount, {String entryType = 'income'}) async {
    seq++;
    await firestore.collection('finance_ledger').add({
      'entryType': entryType,
      'amount': amount,
      'accountId': ?accountId,
      'status': 'confirmed',
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

  Future<void> openLedger(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(ChoiceChip, 'Ledger'));
    await tester.pumpAndSettle();
  }

  final note = find.textContaining('is not shown in Cash, Bank or UPI');

  testWidgets('a transaction on an unknown account type shows the Unclassified card and note', (tester) async {
    final other = await addAccount('Petty Float', 'other'); // a type the Add Account dialog offers
    await addEntry(other, 250);

    final s = await service.watchDashboardSummary().first;
    expect(s.unclassifiedBalance, 250);
    expect(s.unclassifiedOpeningBalance, 0);

    await pump(tester);
    expect(find.text('Unclassified'), findsOneWidget);
    expect(find.text('₹250'), findsWidgets);
    expect(find.textContaining('₹250 is not shown in Cash, Bank or UPI'), findsOneWidget);
    await openLedger(tester);
    expect(find.textContaining('₹250 is not shown in Cash, Bank or UPI'), findsOneWidget);
  });

  test('type matching: trimmed and case-insensitive, otherwise exact', () async {
    final spaced = await addAccount('Main Cash', ' CASH ');
    final upiUpper = await addAccount('GPay', 'UPI');
    final cashAccount = await addAccount('Cash Account', 'cash account'); // not exactly "cash"
    final savings = await addAccount('Savings', 'savings');
    final noType = await addAccount('Untyped', null);
    await addEntry(spaced, 100);
    await addEntry(upiUpper, 10);
    await addEntry(cashAccount, 1000);
    await addEntry(savings, 2000);
    await addEntry(noType, 4000);

    final s = await service.watchDashboardSummary().first;
    expect(s.cashBalance, 100);
    expect(s.upiBalance, 10);
    expect(s.unclassifiedBalance, 7000);
  });

  test('missing, blank, unknown and deleted account ids are unclassified', () async {
    final deleted = await addAccount('Old Bank', 'bank');
    await addEntry(deleted, 8);
    await firestore.collection('finance_accounts').doc(deleted).delete();
    await addEntry(null, 1); // no accountId field
    await addEntry('', 2); // blank
    await addEntry('no-such-account', 4); // unknown

    final s = await service.watchDashboardSummary().first;
    expect(s.bankBalance, 0);
    expect(s.unclassifiedBalance, 15);
  });

  test('opening balances on unknown types are unclassified', () async {
    await addAccount('Wallet', 'wallet', opening: 600);
    final s = await service.watchDashboardSummary().first;
    expect(s.unclassifiedOpeningBalance, 600);
    expect(s.unclassifiedBalance, 600);
    expect(s.cashOpeningBalance + s.bankOpeningBalance + s.upiOpeningBalance, 0);
  });

  testWidgets('UAT figures with only Cash/Bank/UPI accounts: unclassified is exactly 0, so nothing is shown', (tester) async {
    await addEntry(await accountIdByType('cash'), 80000);
    await addEntry(await accountIdByType('cash'), 1100, entryType: 'expense');
    await addEntry(await accountIdByType('upi'), 100);
    await addAccount('Spare Wallet', 'wallet'); // unclassified type, but no balance or movement

    final s = await service.watchDashboardSummary().first;
    expect(s.cashBalance, 78900);
    expect(s.bankBalance, 0);
    expect(s.upiBalance, 100);
    expect(s.closingBalance, 79000);
    expect(s.unclassifiedBalance, 0);
    expect(s.unclassifiedOpeningBalance, 0);

    await pump(tester);
    expect(find.text('Unclassified'), findsNothing);
    expect(note, findsNothing);
    expect(find.text('Closing Balance ₹79000 = Cash ₹78900 + Bank ₹0 + UPI ₹100'), findsOneWidget);
  });

  testWidgets('unclassified records that net to zero are now shown at ₹0 (was the gap)', (tester) async {
    final wallet = await addAccount('Wallet', 'wallet', opening: 500);
    await addEntry(wallet, 500, entryType: 'expense');

    final s = await service.watchDashboardSummary().first;
    expect(s.unclassifiedOpeningBalance, 500);
    expect(s.unclassifiedBalance, 0);
    expect(s.hasUnclassifiedActivity, isTrue);

    await pump(tester);
    expect(find.text('Unclassified'), findsOneWidget);
    expect(note, findsOneWidget);
    await openLedger(tester);
    expect(note, findsOneWidget);
  });
}
