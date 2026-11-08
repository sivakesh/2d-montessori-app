// Finance Phase 2B: dated opening balances.
// - An account may store `openingBalanceDate` (a Timestamp at the day's
//   local midnight): the day its opening balance applies from. A new or
//   changed non-zero opening balance needs one; a zero one doesn't; an
//   existing undated one is kept as it is (no date assumed) and flagged.
// - Historical month-end balances include an opening balance only from its
//   date (undated ones throughout, disclosed). Current balances, All Time
//   Closing Balance, stored balances and Check balances are unchanged.
// Synthetic test data only.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/finance/models/finance_account_model.dart';
import 'package:montessori_app/modules/finance/models/finance_dashboard_summary_model.dart';
import 'package:montessori_app/modules/finance/models/finance_income_model.dart';
import 'package:montessori_app/modules/finance/models/ledger_period.dart';
import 'package:montessori_app/modules/finance/services/finance_service.dart';
import 'package:montessori_app/modules/finance/ui/admin_finance_screen.dart';
import 'package:montessori_app/modules/finance/ui/dialogs/add_account_dialog.dart';
import 'package:montessori_app/modules/finance/widgets/finance_summary_card.dart';

import 'support/buffered_transaction_firestore.dart';

void main() {
  late BufferedTransactionFirestore firestore;
  late FinanceService finance;
  late Map<String, String> ids; // type -> default account id

  setUp(() async {
    firestore = BufferedTransactionFirestore();
    finance = FinanceService(firestore: firestore, auth: MockFirebaseAuth());
    await finance.ensureDefaults();
    ids = {for (final d in (await firestore.collection('finance_accounts').get()).docs) d.data()['type'] as String: d.id};
  });

  CollectionReference<Map<String, dynamic>> accounts() => firestore.collection('finance_accounts');
  Future<Map<String, dynamic>> account(String id) async => (await accounts().doc(id).get()).data()!;
  Future<FinanceDashboardSummaryModel> monthEnd(int year, int month) => finance.dashboardSummaryAt(periodEnd: LedgerPeriod.month(year, month).lastDay!);

  Future<void> setOpening(String type, double amount, DateTime date) =>
      finance.updateAccount(id: ids[type]!, name: type == 'upi' ? 'UPI' : '${type[0].toUpperCase()}${type.substring(1)}', type: type, openingBalance: amount, isActive: true, openingBalanceDate: date);

  var seq = 0;
  Future<void> entry(String type, double amount, String accountId, DateTime date) async {
    seq++;
    await firestore.collection('finance_ledger').add({'entryType': type, 'amount': amount, 'accountId': accountId, 'status': 'confirmed', 'title': 'Entry $seq', 'transactionDate': date, 'createdAt': DateTime(2026, 1, 1).add(Duration(minutes: seq))});
  }

  group('month-end calculation', () {
    test('1, 2, 3. dated 1 June and 15 June: not in May, in June; dated 1 May: in May', () async {
      await setOpening('cash', 2000, DateTime(2026, 6, 1));
      await setOpening('bank', 15000, DateTime(2026, 6, 15));
      await setOpening('upi', 700, DateTime(2026, 5, 1));
      final may = await monthEnd(2026, 5);
      expect([may.cashBalance, may.bankBalance, may.upiBalance, may.closingBalance], [0, 0, 700, 700]);
      expect(may.openingBalanceNotYetEffective, 17000);
      expect([may.datedOpeningBalance, may.undatedOpeningBalance], [700, 0]);
      final june = await monthEnd(2026, 6);
      expect([june.cashBalance, june.bankBalance, june.upiBalance, june.closingBalance], [2000, 15000, 700, 17700]);
      expect(june.openingBalanceNotYetEffective, 0);
      final april = await monthEnd(2026, 4);
      expect(april.closingBalance, 0, reason: 'before every opening date');
      // Stored as a Timestamp at the day's local midnight.
      expect((await account(ids['bank']!))['openingBalanceDate'], Timestamp.fromDate(DateTime(2026, 6, 15)));
    });

    test('4, 5. a zero opening balance needs no date; an existing undated non-zero one counts throughout and is reported', () async {
      final zero = await finance.createAccount(FinanceAccountModel(id: '', name: 'Petty', type: 'wallet', openingBalance: 0, currentBalance: 0, isActive: true, createdAt: DateTime(2026, 6, 1), updatedAt: DateTime(2026, 6, 1)));
      expect((await account(zero)).containsKey('openingBalanceDate'), isFalse);
      // Older account: non-zero opening balance written before dates existed.
      await accounts().doc(ids['bank']).update({'openingBalance': 5000, 'currentBalance': 5000});
      final may = await monthEnd(2026, 5);
      expect([may.bankBalance, may.closingBalance], [5000, 5000], reason: 'backwards compatible');
      expect(may.undatedOpeningBalance, 5000);
      expect(may.undatedOpeningAccounts, ['Bank']);
      expect(may.datedOpeningBalance, 0);
      // Editing anything else leaves it undated, unchanged; no date is assumed.
      await finance.updateAccount(id: ids['bank']!, name: 'Main Bank', type: 'bank', openingBalance: 5000, isActive: true);
      final bank = await account(ids['bank']!);
      expect([bank['openingBalance'], bank['currentBalance'], bank.containsKey('openingBalanceDate')], [5000, 5000, false]);
      expect(FinanceAccountModel.fromMap(ids['bank']!, bank).hasUndatedOpeningBalance, isTrue);
    });

    test('6, 7. a new non-zero opening balance without a date is refused; so is changing one without a date', () async {
      final before = (await accounts().get()).docs.length;
      await expectLater(
        finance.createAccount(FinanceAccountModel(id: '', name: 'HDFC', type: 'bank', openingBalance: 500, currentBalance: 500, isActive: true, createdAt: DateTime(2026, 6, 1), updatedAt: DateTime(2026, 6, 1))),
        throwsA(isA<StateError>().having((e) => e.message, 'message', FinanceService.openingDateRequiredMessage)),
      );
      expect((await accounts().get()).docs.length, before, reason: 'nothing written');
      await expectLater(
        finance.updateAccount(id: ids['cash']!, name: 'Cash', type: 'cash', openingBalance: 1200, isActive: true),
        throwsA(isA<StateError>().having((e) => e.message, 'message', FinanceService.openingDateRequiredMessage)),
      );
      expect((await account(ids['cash']!))['openingBalance'], 0);
      await setOpening('cash', 1200, DateTime(2026, 6, 1));
      expect([(await account(ids['cash']!))['openingBalance'], (await account(ids['cash']!))['currentBalance']], [1200, 1200]);
      // Changing it again keeps its date unless another is chosen.
      await finance.updateAccount(id: ids['cash']!, name: 'Cash', type: 'cash', openingBalance: 1300, isActive: true);
      expect((await account(ids['cash']!))['openingBalanceDate'], Timestamp.fromDate(DateTime(2026, 6, 1)));
    });

    test('8, 9, 11. dating a used account’s opening balance changes no stored or current balance and no reconciliation', () async {
      await accounts().doc(ids['bank']).update({'openingBalance': 5000, 'currentBalance': 5000});
      await finance.createIncome(FinanceIncomeModel(
        id: '', title: 'Fee', categoryId: 'c', categoryName: 'Fees', programType: 'other', studentId: '', studentName: '', classId: '', className: '',
        amount: 800, incomeDate: DateTime(2026, 6, 20), paymentMode: 'bank_transfer', accountId: ids['bank']!, accountName: 'Bank', referenceNo: '',
        remarks: '', attachmentUrls: const [], ledgerEntryId: '', createdAt: DateTime(2026, 6, 20), updatedAt: DateTime(2026, 6, 20), createdBy: 'a',
      ));
      final current = await finance.watchDashboardSummary().first;
      final reconciled = await finance.reconcileAccounts();
      // The account is used, so its amount is locked — but its date can be set.
      await finance.updateAccount(id: ids['bank']!, name: 'Bank', type: 'bank', openingBalance: 5000, isActive: true, openingBalanceDate: DateTime(2027, 1, 1));
      final bank = await account(ids['bank']!);
      expect([bank['openingBalance'], bank['currentBalance']], [5000, 5800], reason: 'stored balance unchanged');
      final after = await finance.watchDashboardSummary().first;
      expect([after.bankBalance, after.closingBalance, after.openingBalance], [current.bankBalance, current.closingBalance, current.openingBalance], reason: 'current balances include it whatever its date');
      expect(after.closingBalance, 5800);
      final r = await finance.reconcileAccounts();
      final row = r.accounts.firstWhere((a) => a.accountId == ids['bank']);
      expect([row.storedBalance, row.calculatedBalance, row.difference], [5800, 5800, 0]);
      expect(r.mismatched, isEmpty);
      expect(reconciled.accounts.firstWhere((a) => a.accountId == ids['bank']).hasUndatedOpeningBalance, isTrue);
      expect(row.hasUndatedOpeningBalance, isFalse);
      expect(row.openingBalanceDate, DateTime(2027, 1, 1));
      // Historically, only the June income (the opening balance starts in 2027).
      expect((await monthEnd(2026, 6)).bankBalance, 800);
    });

    test('10. several months: an opening balance dated mid-June with transactions in May, June and July', () async {
      await setOpening('cash', 1000, DateTime(2026, 6, 15));
      await entry('income', 300, ids['cash']!, DateTime(2026, 5, 20));
      await entry('expense', 100, ids['cash']!, DateTime(2026, 6, 14));
      await entry('income', 50, ids['cash']!, DateTime(2026, 6, 30));
      await entry('expense', 400, ids['cash']!, DateTime(2026, 7, 1));
      expect((await monthEnd(2026, 5)).cashBalance, 300);
      expect((await monthEnd(2026, 6)).cashBalance, 1250);
      expect((await monthEnd(2026, 7)).cashBalance, 850);
      expect((await finance.watchDashboardSummary().first).cashBalance, 850, reason: 'current equals the latest month-end here');
      // The monthly figures don't include opening balances at all.
      final june = await finance.watchDashboardSummary(periodStart: DateTime(2026, 6, 1), periodEnd: DateTime(2026, 6, 30)).first;
      expect([june.totalIncome, june.totalExpenses], [50, 100]);
    });
  });

  group('screens', () {
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
    }

    Future<void> pump(WidgetTester tester, {String? tab}) async {
      tester.view.physicalSize = const Size(1400, 3400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(ProviderScope(child: MaterialApp(home: AdminFinanceScreen(service: finance, clock: () => DateTime(2026, 11, 6)))));
      await tester.pumpAndSettle();
      if (tab != null) {
        await tester.tap(find.widgetWithText(ChoiceChip, tab));
        await settle(tester);
      }
    }

    Future<void> tap(WidgetTester tester, Finder f) async {
      await tester.ensureVisible(f);
      await tester.pumpAndSettle();
      await tester.tap(f);
      await settle(tester);
    }

    Finder key(String k) => find.byKey(Key(k));

    Future<void> openDialog(WidgetTester tester, {FinanceAccountModel? edit}) async {
      tester.view.physicalSize = const Size(1400, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(onPressed: () => showDialog<void>(context: context, builder: (_) => AddAccountDialog(account: edit, service: finance)), child: const Text('open')),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    Future<void> pickDay(WidgetTester tester, String day) async {
      await tester.tap(key('account-opening-date-pick'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(day));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
    }

    testWidgets('6. Add Account: a non-zero opening balance without a date is refused; with a date it saves', (tester) async {
      await openDialog(tester);
      expect(find.text('Opening balance date (optional)'), findsOneWidget, reason: 'zero: optional');
      await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'HDFC');
      await tester.enterText(find.widgetWithText(TextFormField, 'Opening Balance'), '2500');
      await tester.pumpAndSettle();
      expect(find.text('Opening balance date'), findsOneWidget, reason: 'non-zero: required');
      expect(find.textContaining('Historical month-end balances include it from that day'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(find.text(FinanceService.openingDateRequiredMessage), findsOneWidget);
      expect((await accounts().where('name', isEqualTo: 'HDFC').get()).docs, isEmpty);

      await pickDay(tester, '15');
      expect(find.text(FinanceService.openingDateRequiredMessage), findsNothing);
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      final saved = (await accounts().where('name', isEqualTo: 'HDFC').get()).docs.single.data();
      expect([saved['openingBalance'], saved['currentBalance']], [2500, 2500]);
      expect((saved['openingBalanceDate'] as Timestamp).toDate().day, 15);
    });

    testWidgets('5, 8. a used account with an undated opening balance: warned; its date can be set; nothing else changes', (tester) async {
      await accounts().doc(ids['bank']).update({'openingBalance': 5000, 'currentBalance': 5000});
      await entry('income', 800, ids['bank']!, DateTime(2026, 6, 20));
      await accounts().doc(ids['bank']).update({'currentBalance': 5800});
      final model = FinanceAccountModel.fromMap(ids['bank']!, await account(ids['bank']!));
      await openDialog(tester, edit: model);
      expect(key('account-opening-date-missing'), findsOneWidget);
      expect(find.textContaining('Opening date not set'), findsOneWidget);
      expect(tester.widget<TextFormField>(find.widgetWithText(TextFormField, 'Opening Balance')).enabled, isFalse, reason: 'the amount stays locked');
      await pickDay(tester, '1');
      expect(key('account-opening-date-missing'), findsNothing);
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(find.byType(AddAccountDialog), findsNothing, reason: 'saved and closed');
      final bank = await account(ids['bank']!);
      expect([bank['openingBalance'], bank['currentBalance']], [5000, 5800]);
      expect(bank['openingBalanceDate'], isA<Timestamp>());
    });

    testWidgets('Settings lists each account’s opening date, or that it is not set', (tester) async {
      await accounts().doc(ids['bank']).update({'openingBalance': 5000, 'currentBalance': 5000});
      await setOpening('cash', 2000, DateTime(2026, 6, 1));
      await pump(tester, tab: 'Settings');
      expect(tester.widget<Text>(key('account-${ids['bank']}-opening')).data, 'Opening date not set');
      expect(tester.widget<Text>(key('account-${ids['cash']}-opening')).data, 'Opening date: 01 Jun 2026');
      expect(key('account-${ids['upi']}-opening'), findsNothing, reason: 'zero opening balance');
    });

    testWidgets('9, 12. Ledger: May leaves out openings dated later, discloses undated ones by account; current balances unchanged', (tester) async {
      await setOpening('cash', 2000, DateTime(2026, 6, 1));
      await setOpening('upi', 300, DateTime(2026, 5, 10));
      await accounts().doc(ids['bank']).update({'openingBalance': 5000, 'currentBalance': 5000}); // undated
      await entry('income', 1000, ids['cash']!, DateTime(2026, 6, 5));
      await pump(tester, tab: 'Ledger');
      expect(tester.widget<FinanceSummaryCard>(key('ledger-closing-balance')).value, '₹8300', reason: 'All openings + June income, as before');
      expect(tester.widget<FinanceSummaryCard>(key('finance-balance-cash')).value, '₹3000');

      await tap(tester, key('ledger-period-pick'));
      await tap(tester, key('ledger-month-5'));
      String v(String k) => tester.widget<FinanceSummaryCard>(key('ledger-month-end-$k')).value;
      expect([v('cash'), v('bank'), v('upi'), v('total')], ['₹0', '₹5000', '₹300', '₹5300']);
      expect(tester.widget<Text>(key('ledger-month-end-opening-dated')).data, 'Includes ₹300 of opening balances dated on or before 31 May 2026.');
      expect(tester.widget<Text>(key('ledger-month-end-opening-undated')).data,
          'Includes ₹5000 of opening balances with no date (Bank): they are counted from the beginning, so these figures are not fully date-checked. Set their opening dates in Finance → Settings → Accounts.');
      expect(tester.widget<Text>(key('ledger-month-end-opening-later')).data, '₹2000 of opening balances apply from after 31 May 2026, so they are not included.');
      expect(tester.widget<FinanceSummaryCard>(key('ledger-month-end-total')).caption, 'Includes undated opening balances');
      expect(find.textContaining('opening balances count from their opening date'), findsOneWidget);
      // Current figures are the same whatever the month.
      expect(tester.widget<FinanceSummaryCard>(key('ledger-closing-balance')).value, '₹8300');

      await tap(tester, key('ledger-period-next'));
      expect([v('cash'), v('bank'), v('upi'), v('total')], ['₹3000', '₹5000', '₹300', '₹8300']);
      expect(key('ledger-month-end-opening-later'), findsNothing);
      expect(tester.widget<Text>(key('ledger-month-end-opening-dated')).data, 'Includes ₹2300 of opening balances dated on or before 30 June 2026.');
    });

    testWidgets('a fully dated setup: no undated disclosure, a plain total', (tester) async {
      await setOpening('cash', 2000, DateTime(2026, 6, 1));
      await pump(tester, tab: 'Ledger');
      await tap(tester, key('ledger-period-pick'));
      await tap(tester, key('ledger-month-5'));
      expect(tester.widget<FinanceSummaryCard>(key('ledger-month-end-total')).value, '₹0');
      expect(key('ledger-month-end-opening-undated'), findsNothing);
      expect(tester.widget<FinanceSummaryCard>(key('ledger-month-end-total')).caption, 'at 31 May 2026');
    });

    testWidgets('Check balances notes an undated opening balance, and keeps comparing current balances only', (tester) async {
      await accounts().doc(ids['bank']).update({'openingBalance': 5000, 'currentBalance': 5000});
      await pump(tester, tab: 'Ledger');
      await tap(tester, key('finance-check-balances'));
      expect(key('finance-reconciliation-${ids['bank']}-opening-undated'), findsOneWidget);
      expect(key('finance-reconciliation-ok'), findsOneWidget, reason: 'an undated opening balance is not a mismatch');
      expect(tester.widget<Text>(key('finance-reconciliation-${ids['bank']}-difference')).data, '₹0');
    });
  });
}
