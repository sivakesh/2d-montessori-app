// Finance -> Settings -> Account Settings: edit and safe delete.
// - Accounts are stored in finance_accounts (name, type, openingBalance,
//   currentBalance, isActive). Records point at them by accountId (ledger,
//   income incl. fee and invoice payments, direct expenses, salary
//   payments) and keep their own copy of the name; balances are computed by
//   id and type, never by name.
// - Edit: prefilled; name required and unique (case-insensitive); rename
//   always allowed (records keep their saved name); type and opening
//   balance only while no record uses the account (a new opening balance
//   moves the current balance by the same difference).
// - Delete: confirmation, then refused when any record (voided/cancelled
//   included) uses the account, when it holds a balance, or when new
//   payments depend on it (the only active cash/bank/upi account, or the
//   last active account); Deactivate offered where allowed.
// - Ledger totals and account balances never change except by a deliberate
//   opening-balance correction of an unused account.
// - Usage-check, save, delete and loading errors are shown, never success.
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/finance/models/finance_account_model.dart';
import 'package:montessori_app/modules/finance/models/finance_dashboard_summary_model.dart';
import 'package:montessori_app/modules/finance/models/finance_income_model.dart';
import 'package:montessori_app/modules/finance/services/finance_service.dart';
import 'package:montessori_app/modules/finance/ui/admin_finance_screen.dart';

import 'support/buffered_transaction_firestore.dart';

/// Real service with switchable failures.
class _FaultyFinanceService extends FinanceService {
  _FaultyFinanceService(BufferedTransactionFirestore firestore) : super(firestore: firestore, auth: MockFirebaseAuth());
  bool failAccountStream = false;
  bool failUsage = false;
  bool failUpdate = false;
  bool failDelete = false;

  @override
  Stream<List<FinanceAccountModel>> watchAccounts() => failAccountStream ? Stream.error(Exception('unavailable')) : super.watchAccounts();

  @override
  Future<FinanceAccountUsage> accountUsage(FinanceAccountModel account) =>
      failUsage ? Future.error(Exception('lookup failed')) : super.accountUsage(account);

  @override
  Future<void> updateAccount({required String id, required String name, required String type, required double openingBalance, required bool isActive}) =>
      failUpdate
          ? Future.error(Exception('write failed'))
          : super.updateAccount(id: id, name: name, type: type, openingBalance: openingBalance, isActive: isActive);

  @override
  Future<void> deleteAccount(String id) => failDelete ? Future.error(Exception('write failed')) : super.deleteAccount(id);
}

void main() {
  late BufferedTransactionFirestore firestore;
  late _FaultyFinanceService service;
  late String cashId; // default Cash: used by a manual income (income + ledger)
  late String upiId; // default UPI: unused, but the only active upi account
  late String hdfcId; // bank, unused, opening ₹5000
  late String walletId; // wallet, unused, zero balances: deletable
  late String pettyId; // second active cash account, used by a direct ledger line
  late String oldTillId; // cash, inactive, only voided/cancelled history

  Future<String> addAccount(String name, String type, {double opening = 0, bool active = true}) async =>
      (await firestore.collection('finance_accounts').add({
        'name': name, 'type': type, 'openingBalance': opening, 'currentBalance': opening, 'isActive': active,
        'createdAt': DateTime(2026, 1, 1), 'updatedAt': DateTime(2026, 1, 1),
      })).id;
  Future<String> idOf(String type) async => (await firestore.collection('finance_accounts').where('type', isEqualTo: type).get())
      .docs
      .firstWhere((d) => const {'Cash', 'Bank', 'UPI'}.contains(d.data()['name']))
      .id;

  setUp(() async {
    firestore = BufferedTransactionFirestore();
    service = _FaultyFinanceService(firestore);
    await service.ensureDefaults();
    cashId = await idOf('cash');
    upiId = await idOf('upi');
    hdfcId = await addAccount('HDFC Savings', 'bank', opening: 5000);
    walletId = await addAccount('Spare Wallet', 'wallet');
    pettyId = await addAccount('Petty Cash', 'cash');
    oldTillId = await addAccount('Old Till', 'cash', active: false);

    // A manual cash income and its ledger line, written directly: a
    // transaction in setUp would tie BufferedTransactionFirestore's commit
    // lock to this zone and hang later transactions inside testWidgets.
    final ledgerRef = firestore.collection('finance_ledger').doc();
    final incomeRef = firestore.collection('finance_income').doc();
    await incomeRef.set({
      ...FinanceIncomeModel(
        id: '', title: 'Annual Day tickets', categoryId: 'c', categoryName: 'Other Income', programType: 'other',
        studentId: '', studentName: '', classId: '', className: '', amount: 3000,
        incomeDate: DateTime(2026, 8, 1), paymentMode: 'cash', accountId: cashId, accountName: 'Cash',
        referenceNo: '', remarks: '', attachmentUrls: const [], ledgerEntryId: '',
        createdAt: DateTime(2026, 8, 1), updatedAt: DateTime(2026, 8, 1), createdBy: 'admin',
      ).toMap(incomeRef.id, ledgerEntryId: ledgerRef.id, createdBy: 'admin'),
    });
    await ledgerRef.set({
      'entryType': 'income', 'amount': 3000, 'accountId': cashId, 'accountName': 'Cash', 'status': 'confirmed',
      'title': 'Annual Day tickets', 'transactionDate': DateTime(2026, 8, 1), 'createdAt': DateTime(2026, 8, 1),
    });
    await firestore.doc('finance_accounts/$cashId').update({'currentBalance': 3000});
    await firestore.collection('finance_ledger').add({
      'entryType': 'expense', 'amount': 200, 'accountId': pettyId, 'accountName': 'Petty Cash', 'status': 'confirmed',
      'title': 'Stamps', 'transactionDate': DateTime(2026, 8, 3), 'createdAt': DateTime(2026, 8, 3),
    });
    // Old Till: a voided income and its cancelled ledger line only.
    await firestore.collection('finance_income').add({
      'title': 'Old sale', 'amount': 50, 'accountId': oldTillId, 'accountName': 'Old Till', 'programType': 'other', 'isDeleted': true,
    });
    await firestore.collection('finance_ledger').add({
      'entryType': 'income', 'amount': 50, 'accountId': oldTillId, 'accountName': 'Old Till', 'status': 'cancelled', 'title': 'Old sale',
    });
  });

  Future<Map<String, dynamic>?> account(String id) async => (await firestore.doc('finance_accounts/$id').get()).data();

  Future<Map<String, Map<String, dynamic>?>> records() async => {
        for (final c in ['finance_income', 'finance_ledger', 'finance_invoices', 'finance_expenses', 'staff_salary_payments'])
          for (final d in (await firestore.collection(c).get()).docs) '$c/${d.id}': d.data(),
      };

  Future<FinanceDashboardSummaryModel> summary() => service.watchDashboardSummary().first;
  void expectSameSummary(FinanceDashboardSummaryModel a, FinanceDashboardSummaryModel b) {
    expect(b.totalIncome, a.totalIncome);
    expect(b.totalExpenses, a.totalExpenses);
    expect(b.netBalance, a.netBalance);
    expect(b.openingBalance, a.openingBalance);
    expect(b.closingBalance, a.closingBalance);
    expect(b.cashBalance, a.cashBalance);
    expect(b.bankBalance, a.bankBalance);
    expect(b.upiBalance, a.upiBalance);
    expect(b.unclassifiedBalance, a.unclassifiedBalance);
  }

  Future<void> pumpSettings(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(child: MaterialApp(home: AdminFinanceScreen(service: service))));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Settings'));
    await tester.pumpAndSettle();
  }

  /// The account card titled [name].
  Finder card(String name) => find
      .ancestor(
        of: find.text(name),
        matching: find.byWidgetPredicate((w) => w is Container && w.padding == const EdgeInsets.all(16)),
      )
      .first;
  Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> cardAction(WidgetTester tester, String name, String tooltip) =>
      tapAndSettle(tester, find.descendant(of: card(name), matching: find.byTooltip(tooltip)));
  Finder field(String label) => find.widgetWithText(TextFormField, label);
  String fieldText(WidgetTester tester, String label) => tester.widget<TextFormField>(field(label)).controller!.text;
  bool fieldEnabled(WidgetTester tester, String label) => tester.widget<TextFormField>(field(label)).enabled;
  bool typeEnabled(WidgetTester tester) =>
      tester.widget<DropdownButton<String>>(find.descendant(of: find.byType(DropdownButtonFormField<String>), matching: find.byType(DropdownButton<String>))).onChanged != null;
  String? typeValue(WidgetTester tester) =>
      tester.widget<DropdownButton<String>>(find.descendant(of: find.byType(DropdownButtonFormField<String>), matching: find.byType(DropdownButton<String>))).value;
  SwitchListTile activeSwitch(WidgetTester tester) => tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, 'Active'));
  Future<void> save(WidgetTester tester) => tapAndSettle(tester, find.widgetWithText(FilledButton, 'Save'));
  void expectAmounts(String name, {required String opening, required String current}) {
    final amounts = find.descendant(of: card(name), matching: find.textContaining('₹'));
    expect(amounts, findsNWidgets(2));
    expect(find.descendant(of: card(name), matching: find.text(opening)), findsWidgets, reason: '$name opening');
    expect(find.descendant(of: card(name), matching: find.text(current)), findsWidgets, reason: '$name current');
  }

  Future<void> confirmDelete(WidgetTester tester, String name) async {
    await cardAction(tester, name, 'Delete');
    expect(find.text('Delete Account'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
  }

  testWidgets('1. Edit opens a prefilled form; locks follow what depends on the account', (tester) async {
    await pumpSettings(tester);
    expect(find.descendant(of: card('Cash'), matching: find.byTooltip('Edit')), findsOneWidget);
    expect(find.descendant(of: card('Cash'), matching: find.byTooltip('Delete')), findsOneWidget);
    expectAmounts('HDFC Savings', opening: '₹5000', current: '₹5000');

    await cardAction(tester, 'HDFC Savings', 'Edit');
    expect(find.text('Edit Account'), findsOneWidget);
    expect(fieldText(tester, 'Name'), 'HDFC Savings');
    expect(typeValue(tester), 'bank');
    expect(fieldText(tester, 'Opening Balance'), '5000');
    expect(activeSwitch(tester).value, isTrue);
    expect(fieldEnabled(tester, 'Opening Balance'), isTrue);
    expect(typeEnabled(tester), isTrue);
    expect(activeSwitch(tester).onChanged, isNotNull);
    await tapAndSettle(tester, find.widgetWithText(TextButton, 'Cancel'));

    await cardAction(tester, 'Cash', 'Edit'); // used by records
    expect(find.textContaining('Used by ledger entries, income and payment records'), findsOneWidget);
    expect(fieldEnabled(tester, 'Opening Balance'), isFalse);
    expect(typeEnabled(tester), isFalse);
    expect(activeSwitch(tester).onChanged, isNotNull, reason: 'Petty Cash also covers cash payments');
    await tapAndSettle(tester, find.widgetWithText(TextButton, 'Cancel'));

    await cardAction(tester, 'UPI', 'Edit'); // the only active upi account
    expect(activeSwitch(tester).onChanged, isNull);
    expect(find.textContaining('the only active upi account'), findsWidgets);
    expect(typeEnabled(tester), isTrue, reason: 'unused, but must keep covering upi (checked on save)');
  });

  testWidgets('2 + 8. valid edits persist and refresh the card; a rename leaves history and totals unchanged', (tester) async {
    final before = await summary();
    final recordsBefore = await records();
    await pumpSettings(tester);

    await cardAction(tester, 'Cash', 'Edit');
    await tester.enterText(field('Name'), '  Main Cash  ');
    await save(tester);
    expect(find.text('Account updated'), findsOneWidget);
    expect(find.text('Main Cash'), findsOneWidget);
    final cash = (await account(cashId))!;
    expect(cash['name'], 'Main Cash');
    expect(cash['type'], 'cash');
    expect(cash['currentBalance'], 3000);
    expect(cash['createdAt'], isNotNull, reason: 'other fields kept');
    expect(await records(), recordsBefore, reason: 'records keep accountId and their saved accountName');
    expectSameSummary(before, await summary());

    // Unused account: opening balance correction moves current by the same amount.
    await cardAction(tester, 'HDFC Savings', 'Edit');
    await tester.enterText(field('Name'), 'HDFC Current');
    await tester.enterText(field('Opening Balance'), '6500');
    await save(tester);
    expectAmounts('HDFC Current', opening: '₹6500', current: '₹6500');
    final after = await summary();
    expect(after.closingBalance, before.closingBalance + 1500);
    expect(after.bankBalance, before.bankBalance + 1500);
    expect(after.netBalance, before.netBalance);
    expect(await records(), recordsBefore);

    // Unused, non-required account: type change.
    await cardAction(tester, 'Spare Wallet', 'Edit');
    await tapAndSettle(tester, find.byType(DropdownButtonFormField<String>));
    await tester.tap(find.text('other').last);
    await tester.pumpAndSettle();
    await save(tester);
    expect((await account(walletId))!['type'], 'other');
  });

  testWidgets('3. required, numeric and duplicate-name rules; nothing saved on refusal', (tester) async {
    await pumpSettings(tester);
    final hdfcBefore = await account(hdfcId);
    await cardAction(tester, 'HDFC Savings', 'Edit');
    await tester.enterText(field('Name'), '   ');
    await save(tester);
    expect(find.text('Required'), findsOneWidget);

    await tester.enterText(field('Name'), 'HDFC Savings');
    await tester.enterText(field('Opening Balance'), 'abc');
    await save(tester);
    expect(find.text('Enter a number'), findsOneWidget);

    await tester.enterText(field('Opening Balance'), '5000');
    await tester.enterText(field('Name'), ' bank ');
    await save(tester);
    expect(find.text('Another account is already named "bank".'), findsOneWidget);
    expect(find.text('Edit Account'), findsOneWidget);
    expect(await account(hdfcId), hdfcBefore);

    // The service enforces the same rules (and the history lock) itself.
    await expectLater(service.updateAccount(id: hdfcId, name: '', type: 'bank', openingBalance: 0, isActive: true), throwsStateError);
    await expectLater(service.updateAccount(id: cashId, name: 'Cash', type: 'bank', openingBalance: 0, isActive: true), throwsStateError);
    await expectLater(service.updateAccount(id: cashId, name: 'Cash', type: 'cash', openingBalance: 100, isActive: true), throwsStateError);
    await expectLater(service.updateAccount(id: hdfcId, name: 'HDFC', type: 'crypto', openingBalance: 5000, isActive: true), throwsStateError);
    expect((await account(cashId))!['openingBalance'], 0);
    expect(await account(hdfcId), hdfcBefore);
  });

  testWidgets('4. cancelling the delete confirmation changes nothing', (tester) async {
    await pumpSettings(tester);
    await cardAction(tester, 'Spare Wallet', 'Delete');
    expect(find.text('Delete Account'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(await account(walletId), isNotNull);
    expect(find.text('Spare Wallet'), findsOneWidget);
  });

  testWidgets('5 + 8. an unused, zero-balance account is deleted; totals unchanged', (tester) async {
    final before = await summary();
    final recordsBefore = await records();
    await pumpSettings(tester);
    await confirmDelete(tester, 'Spare Wallet');
    expect(find.text('Account deleted'), findsOneWidget);
    expect(await account(walletId), isNull);
    expect(find.text('Spare Wallet'), findsNothing);
    expect(await records(), recordsBefore);
    expectSameSummary(before, await summary());
  });

  testWidgets('6 + 8. used or balance-holding accounts are not deleted; Deactivate keeps history and totals', (tester) async {
    final before = await summary();
    final recordsBefore = await records();
    await pumpSettings(tester);

    await confirmDelete(tester, 'Cash'); // ledger + income
    expect(find.text('Account In Use'), findsOneWidget);
    expect(find.textContaining('"Cash" is used by ledger entries, income and payment records'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Close'));
    await tester.pumpAndSettle();
    expect(await account(cashId), isNotNull);

    await confirmDelete(tester, 'HDFC Savings'); // opening balance only
    expect(find.text('Account In Use'), findsOneWidget);
    expect(find.textContaining('opening balance of ₹5000'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Deactivate'));
    await tester.pumpAndSettle();
    expect(find.text('Account deactivated'), findsOneWidget);
    expect((await account(hdfcId))!['isActive'], isFalse);
    expect(find.descendant(of: card('HDFC Savings'), matching: find.text('INACTIVE')), findsOneWidget);
    expectAmounts('HDFC Savings', opening: '₹5000', current: '₹5000');

    await confirmDelete(tester, 'Petty Cash'); // direct ledger line
    await tester.tap(find.widgetWithText(FilledButton, 'Deactivate'));
    await tester.pumpAndSettle();
    expect((await account(pettyId))!['isActive'], isFalse);

    await expectLater(service.deleteAccount(cashId), throwsStateError);
    await expectLater(service.deleteAccount(hdfcId), throwsStateError);
    expect(await records(), recordsBefore);
    expectSameSummary(before, await summary());
  });

  testWidgets('7. voided/cancelled history protects an account; expense and salary records count too', (tester) async {
    await pumpSettings(tester);
    await confirmDelete(tester, 'Old Till');
    expect(find.text('Account In Use'), findsOneWidget);
    expect(find.textContaining('used by ledger entries, income and payment records'), findsOneWidget);
    expect(find.textContaining('It is already inactive.'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Deactivate'), findsNothing);
    await tester.tap(find.widgetWithText(TextButton, 'Close'));
    await tester.pumpAndSettle();
    expect(await account(oldTillId), isNotNull);

    final expenseAccount = await addAccount('Expense Bank', 'bank');
    await firestore.collection('finance_expenses').add({'title': 'Repairs', 'amount': 10, 'accountId': expenseAccount, 'isDeleted': true});
    final salaryAccount = await addAccount('Salary Bank', 'bank');
    await firestore.collection('staff_salary_payments').add({'staffName': 'Staff', 'paidAmount': 10, 'accountId': salaryAccount});
    await expectLater(
      service.deleteAccount(expenseAccount),
      throwsA(isA<StateError>().having((e) => e.message, 'message', contains('expense records'))),
    );
    await expectLater(
      service.deleteAccount(salaryAccount),
      throwsA(isA<StateError>().having((e) => e.message, 'message', contains('salary payment records'))),
    );
    final usage = await service.accountUsage(FinanceAccountModel.fromMap(oldTillId, (await account(oldTillId))!));
    expect(usage.references, ['ledger entries', 'income and payment records']);
  });

  testWidgets('9. accounts new payments depend on stay active and undeleted', (tester) async {
    await pumpSettings(tester);
    await confirmDelete(tester, 'UPI'); // unused, zero, but the only active upi account
    expect(find.text('Account Required'), findsOneWidget);
    expect(find.textContaining('"UPI" is the only active upi account'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Deactivate'), findsNothing);
    await tester.tap(find.widgetWithText(TextButton, 'Close'));
    await tester.pumpAndSettle();
    expect(await account(upiId), isNotNull);

    await expectLater(service.updateAccount(id: upiId, name: 'UPI', type: 'upi', openingBalance: 0, isActive: false), throwsStateError);
    await expectLater(service.updateAccount(id: upiId, name: 'UPI', type: 'wallet', openingBalance: 0, isActive: true), throwsStateError);
    expect((await account(upiId))!['isActive'], isTrue);
    expect((await account(upiId))!['type'], 'upi');

    // Once Petty Cash is inactive, Cash is the only active cash account.
    await service.updateAccount(id: pettyId, name: 'Petty Cash', type: 'cash', openingBalance: 0, isActive: false);
    await expectLater(service.updateAccount(id: cashId, name: 'Cash', type: 'cash', openingBalance: 0, isActive: false), throwsStateError);

    // The last active account can't be deactivated or deleted.
    final solo = BufferedTransactionFirestore();
    final soloService = FinanceService(firestore: solo, auth: MockFirebaseAuth());
    final only = (await solo.collection('finance_accounts').add({'name': 'Only', 'type': 'wallet', 'openingBalance': 0, 'currentBalance': 0, 'isActive': true})).id;
    await expectLater(
      soloService.updateAccount(id: only, name: 'Only', type: 'wallet', openingBalance: 0, isActive: false),
      throwsA(isA<StateError>().having((e) => e.message, 'message', contains('last active account'))),
    );
    await expectLater(soloService.deleteAccount(only), throwsStateError);
    expect((await solo.doc('finance_accounts/$only').get()).exists, isTrue);
  });

  group('10. errors', () {
    testWidgets('a failed usage check locks the form (name still editable) and blocks delete', (tester) async {
      service.failUsage = true;
      await pumpSettings(tester);
      await cardAction(tester, 'Spare Wallet', 'Edit');
      expect(find.textContaining("Couldn't check how this account is used"), findsWidgets);
      expect(fieldEnabled(tester, 'Opening Balance'), isFalse);
      expect(typeEnabled(tester), isFalse);
      expect(activeSwitch(tester).onChanged, isNull);
      expect(fieldEnabled(tester, 'Name'), isTrue);
      await tapAndSettle(tester, find.widgetWithText(TextButton, 'Cancel'));

      await confirmDelete(tester, 'Spare Wallet');
      expect(find.textContaining("Couldn't check how this account is used, so it wasn't deleted"), findsOneWidget);
      expect(await account(walletId), isNotNull);
    });

    testWidgets('a failed save keeps the dialog open with the error; nothing changes', (tester) async {
      service.failUpdate = true;
      final before = await account(hdfcId);
      await pumpSettings(tester);
      await cardAction(tester, 'HDFC Savings', 'Edit');
      await tester.enterText(field('Name'), 'Renamed');
      await save(tester);
      expect(find.textContaining('Could not save the account'), findsOneWidget);
      expect(find.text('Edit Account'), findsOneWidget);
      expect(find.text('Account updated'), findsNothing);
      expect(await account(hdfcId), before);
    });

    testWidgets('a failed delete is reported and the account stays', (tester) async {
      service.failDelete = true;
      await pumpSettings(tester);
      await confirmDelete(tester, 'Spare Wallet');
      expect(find.textContaining('Failed to delete account'), findsOneWidget);
      expect(find.text('Account deleted'), findsNothing);
      expect(await account(walletId), isNotNull);
    });

    testWidgets('a failed account load shows an error instead of a spinner', (tester) async {
      service.failAccountStream = true;
      await pumpSettings(tester);
      expect(find.text("Couldn't load accounts. Reopen Settings to try again."), findsOneWidget);
    });
  });
}
