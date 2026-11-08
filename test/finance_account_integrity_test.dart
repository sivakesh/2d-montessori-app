// Finance Phase 1, account balance integrity:
// - Money goes only to a valid, active account: an explicit one for manual
//   income (refused when missing, deleted or inactive), and for fee
//   collections and invoice payments one of the payment mode's own type —
//   never another account when that type has none.
// - Each movement changes its account's stored balance once, and the
//   ledger gives the same figure; voids and reversals undo it exactly once,
//   retries included.
// - FinanceService.reconcileAccounts compares stored and ledger balances,
//   lists entries whose account is missing, and corrects nothing.
// - Negative Cash / Bank / UPI balances are marked and explained.
// Synthetic test data only.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/fees/services/fee_service.dart';
import 'package:montessori_app/modules/finance/models/finance_expense_model.dart';
import 'package:montessori_app/modules/finance/models/finance_income_model.dart';
import 'package:montessori_app/modules/finance/services/finance_service.dart';
import 'package:montessori_app/modules/finance/ui/admin_finance_screen.dart';
import 'package:montessori_app/modules/finance/widgets/finance_summary_card.dart';

import 'support/buffered_transaction_firestore.dart';

/// [BufferedTransactionFirestore] that can run [beforeTransaction] once,
/// just before the next transaction starts (another user's write landing
/// between a method's first reads and its transaction).
class _HookedFirestore extends BufferedTransactionFirestore {
  Future<void> Function()? beforeTransaction;

  @override
  Future<T> runTransaction<T>(TransactionHandler<T> transactionHandler, {Duration timeout = const Duration(seconds: 30), int maxAttempts = 5}) async {
    final hook = beforeTransaction;
    beforeTransaction = null;
    if (hook != null) await hook();
    return super.runTransaction(transactionHandler, timeout: timeout, maxAttempts: maxAttempts);
  }
}

void main() {
  late _HookedFirestore firestore;
  late FinanceService finance;
  late FeeService fees;
  late Map<String, String> ids; // type -> account id

  setUp(() async {
    firestore = _HookedFirestore();
    final auth = MockFirebaseAuth();
    finance = FinanceService(firestore: firestore, auth: auth);
    await finance.ensureDefaults();
    fees = FeeService(firestore: firestore, auth: auth, storage: MockFirebaseStorage(), financeService: finance);
    ids = {for (final d in (await firestore.collection('finance_accounts').get()).docs) d.data()['type'] as String: d.id};
    await firestore.collection('student_fee_assignments').doc('a1').set({
      'studentId': 's1', 'studentName': 'Child A', 'admissionNo': 'A1', 'classId': 'c', 'className': 'Mont 1',
      'feeStructureId': 'f', 'feeStructureName': 'Core', 'academicYear': '2026-2027', 'totalFee': 100000, 'discountAmount': 0,
      'payableAmount': 100000, 'paidAmount': 0, 'balanceAmount': 100000, 'status': 'unpaid',
      'assignedAt': Timestamp.fromDate(DateTime(2026, 1, 1)), 'updatedAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
    });
  });

  Future<Map<String, dynamic>?> account(String id) async => (await firestore.collection('finance_accounts').doc(id).get()).data();
  Future<double> stored(String type) async => ((await account(ids[type]!))!['currentBalance'] as num).toDouble();
  Future<int> count(String c) async => (await firestore.collection(c).get()).docs.length;
  Future<void> setActive(String type, bool active) => firestore.collection('finance_accounts').doc(ids[type]).update({'isActive': active});

  FinanceIncomeModel income({required String accountId, double amount = 1000, String name = 'Cash'}) => FinanceIncomeModel(
        id: '', title: 'Donation', categoryId: 'c', categoryName: 'Other Income', programType: 'other', studentId: '', studentName: '',
        classId: '', className: '', amount: amount, incomeDate: DateTime(2026, 11, 2), paymentMode: 'cash', accountId: accountId,
        accountName: name, referenceNo: '', remarks: 'நன்கொடை', attachmentUrls: const [], ledgerEntryId: '',
        createdAt: DateTime(2026, 11, 2), updatedAt: DateTime(2026, 11, 2), createdBy: 'admin',
      );

  Future<String> invoice(double total, {String type = 'expense'}) => type == 'expense'
      ? finance.createExpenseInvoice({'partyName': 'Vendor', 'totalAmount': total, 'amount': total, 'invoiceNo': 'E-1', 'invoiceDate': DateTime(2026, 11, 1)})
      : finance.createSalaryInvoice({'partyName': 'Teacher', 'totalAmount': total, 'amount': total, 'invoiceNo': 'S-1', 'invoiceDate': DateTime(2026, 11, 1)});

  Future<String?> pay(String invoiceId, double amount, String mode, {String type = 'expense'}) =>
      finance.payInvoice(invoiceId: invoiceId, invoiceType: type, amount: amount, paidDate: DateTime(2026, 11, 5), paymentMode: mode, referenceNo: '', remarks: '');

  Future<void> expectReconciled() async {
    final r = await finance.reconcileAccounts();
    expect(r.mismatched, isEmpty, reason: 'stored balances match the ledger');
    expect(r.problems, isEmpty);
    final s = await finance.watchDashboardSummary().first;
    expect(s.cashBalance + s.bankBalance + s.upiBalance + s.unclassifiedBalance, s.closingBalance);
  }

  group('account selection', () {
    test('manual income goes to its chosen active account, once, ledger and balance together', () async {
      final id = await finance.createIncome(income(accountId: ids['upi']!, name: 'UPI'));
      expect(await stored('upi'), 1000);
      expect(await stored('cash'), 0);
      final ledger = (await firestore.collection('finance_ledger').get()).docs.single.data();
      expect(ledger['accountId'], ids['upi']);
      expect((await firestore.collection('finance_income').doc(id).get()).data()!['remarks'], 'நன்கொடை');
      expect((await finance.watchDashboardSummary().first).upiBalance, 1000);
      await expectReconciled();
    });

    test('manual income with no, a deleted or an inactive account is refused; nothing is written, no account is created', () async {
      await expectLater(finance.createIncome(income(accountId: '')), throwsA(isA<StateError>().having((e) => e.message, 'message', contains('Choose the account'))));
      await expectLater(finance.createIncome(income(accountId: 'gone-account')), throwsA(isA<StateError>().having((e) => e.message, 'message', contains('no longer exists'))));
      expect(await account('gone-account'), isNull, reason: 'no account record appears from the balance update');
      await setActive('cash', false);
      await expectLater(finance.createIncome(income(accountId: ids['cash']!)), throwsA(isA<StateError>().having((e) => e.message, 'message', contains('inactive'))));
      expect([await count('finance_income'), await count('finance_ledger')], [0, 0]);
      expect(await stored('cash'), 0);
    });

    test('direct expenses (not used by the app) check their account the same way', () async {
      FinanceExpenseModel expense(String accountId) => FinanceExpenseModel.fromMap('', {'title': 'Chalk', 'amount': 50, 'accountId': accountId, 'accountName': 'x', 'expenseDate': DateTime(2026, 11, 2)});
      await expectLater(finance.createExpense(expense('')), throwsA(isA<StateError>()));
      await expectLater(finance.createExpense(expense('gone')), throwsA(isA<StateError>()));
      await finance.createExpense(expense(ids['bank']!));
      expect(await stored('bank'), -50);
      expect(await account('gone'), isNull);
    });

    test('invoice payments go to the mode’s own account type; with none active, refused — never another account', () async {
      final inv = await invoice(5000);
      await pay(inv, 1000, 'bank_transfer');
      await pay(inv, 500, 'cheque');
      await pay(inv, 200, 'upi');
      await pay(inv, 300, 'cash');
      expect([await stored('bank'), await stored('upi'), await stored('cash')], [-1500, -200, -300]);

      await setActive('bank', false);
      final before = [await count('finance_ledger'), await count('finance_income')];
      await expectLater(pay(inv, 400, 'bank_transfer'), throwsA(isA<StateError>().having((e) => e.message, 'message', allOf(contains('No active Bank account'), contains('not recorded')))));
      expect([await count('finance_ledger'), await count('finance_income')], before, reason: 'nothing written');
      expect([await stored('cash'), await stored('upi')], [-300, -200], reason: 'no other account was used');
      expect((await firestore.collection('finance_invoices').doc(inv).get()).data()!['paidAmount'], 2000);
      await expectReconciled();
    });

    test('fee collections: the mode’s own account; with none active, the collection is refused before Fees writes anything', () async {
      await fees.collectFee(assignmentId: 'a1', amount: 4000, paymentDate: DateTime(2026, 11, 3), paymentMode: 'upi', referenceNo: '', remarks: '');
      expect(await stored('upi'), 4000);
      await setActive('upi', false);
      await expectLater(
        fees.collectFee(assignmentId: 'a1', amount: 1000, paymentDate: DateTime(2026, 11, 3), paymentMode: 'upi', referenceNo: '', remarks: ''),
        throwsA(isA<StateError>().having((e) => e.toString(), 'message', contains('No active UPI account'))),
      );
      expect(await count('fee_receipts'), 1, reason: 'no second collection');
      expect((await firestore.collection('student_fee_assignments').doc('a1').get()).data()!['paidAmount'], 4000);
      expect([await stored('cash'), await stored('bank')], [0, 0]);
      await expectReconciled();
    });

    test('several active accounts of the type: the same one every time (exact type, then name)', () async {
      final other = await firestore.collection('finance_accounts').add({'name': 'A Savings', 'type': 'bank', 'isActive': true, 'openingBalance': 0, 'currentBalance': 0});
      final inv = await invoice(1000);
      await pay(inv, 100, 'bank_transfer');
      await pay(inv, 100, 'bank_transfer');
      final ledger = (await firestore.collection('finance_ledger').get()).docs.map((d) => d.data()['accountId']).toSet();
      expect(ledger, {other.id}, reason: '"A Savings" comes before "Bank" by name');
      expect((await account(other.id))!['currentBalance'], -200);
      await expectReconciled();
    });

    test('an income’s saved account is kept when edited; its amount can’t change once that account is gone', () async {
      final id = await finance.createIncome(income(accountId: ids['cash']!));
      await setActive('cash', false);
      await finance.updateIncome(id: id, title: 'Donation', categoryId: 'c', categoryName: 'Other Income', amount: 1200, date: DateTime(2026, 11, 2), paymentMode: 'cash', referenceNo: '', remarks: '');
      expect(await stored('cash'), 1200, reason: 'an inactive saved account still follows the edit');
      await firestore.collection('finance_accounts').doc(ids['cash']).delete();
      await expectLater(
        finance.updateIncome(id: id, title: 'Donation', categoryId: 'c', categoryName: 'Other Income', amount: 1500, date: DateTime(2026, 11, 2), paymentMode: 'cash', referenceNo: '', remarks: ''),
        throwsA(isA<StateError>().having((e) => e.message, 'message', contains('no longer exists'))),
      );
      final ledger = (await firestore.collection('finance_ledger').get()).docs.single.data();
      expect(ledger['amount'], 1200, reason: 'nothing changed');
      expect(await account(ids['cash']!), isNull, reason: 'not recreated');
    });
  });

  group('exactly once', () {
    test('void income: reversed once; a repeat is refused', () async {
      final id = await finance.createIncome(income(accountId: ids['cash']!));
      await finance.voidIncome(id);
      await expectLater(finance.voidIncome(id), throwsA(isA<StateError>()));
      expect(await stored('cash'), 0);
      await expectReconciled();
    });

    test('reverse a payment: restored once; a repeat is refused', () async {
      final inv = await invoice(800);
      final payment = (await pay(inv, 800, 'cash'))!;
      await finance.reverseExpenseInvoicePayment(paymentId: payment, reason: 'recorded twice');
      await expectLater(finance.reverseExpenseInvoicePayment(paymentId: payment, reason: 'again'), throwsA(isA<StateError>()));
      expect(await stored('cash'), 0);
      expect((await firestore.collection('finance_invoices').doc(inv).get()).data()!['paidAmount'], 0);
      await expectReconciled();
    });

    test('void a fee collection: reversed once, retries change nothing more', () async {
      final receipt = await fees.collectFee(assignmentId: 'a1', amount: 2500, paymentDate: DateTime(2026, 11, 3), paymentMode: 'cash', referenceNo: '', remarks: '');
      await fees.voidReceipt(receipt.id);
      await finance.reverseFeeIncomeByCollectionId(receipt.id);
      await finance.reverseFeeIncomeByCollectionId(receipt.id);
      expect(await stored('cash'), 0);
      expect((await firestore.collection('student_fee_assignments').doc('a1').get()).data()!['balanceAmount'], 100000);
      await expectReconciled();
    });

    test('a fee income entry is created once per collection, even when asked again', () async {
      final entry = {'feeCollectionId': 'fc-1', 'amount': 700.0, 'paymentMode': 'cash'};
      final first = await finance.createFeeIncomeEntry(entry);
      final again = await finance.createFeeIncomeEntry(entry);
      expect(again, first);
      expect([await count('finance_income'), await count('finance_ledger')], [1, 1]);
      expect(await stored('cash'), 700);
    });

    test('paying more than is left is refused, including a second submission of the same payment', () async {
      final inv = await invoice(1000);
      await pay(inv, 1000, 'cash');
      await expectLater(pay(inv, 1000, 'cash'), throwsA(isA<StateError>()));
      expect(await count('finance_ledger'), 1);
      expect(await stored('cash'), -1000);
      final salary = await invoice(600, type: 'salary');
      await pay(salary, 600, 'upi', type: 'salary');
      expect(await stored('upi'), -600);
      await expectReconciled();
    });

    test('the balance check inside the payment: an invoice paid meanwhile can’t be overpaid', () async {
      final inv = await invoice(1000);
      // The invoice as payInvoice first reads it, then paid by someone else
      // before its transaction runs.
      firestore.beforeTransaction = () async {
        await firestore.collection('finance_invoices').doc(inv).update({'paidAmount': 900, 'balanceAmount': 100, 'status': 'partial'});
      };
      await expectLater(pay(inv, 500, 'cash'), throwsA(isA<StateError>().having((e) => e.message, 'message', contains('balance is now'))));
      expect(await count('finance_ledger'), 0);
      expect(await stored('cash'), 0);
    });

    test('the outstanding balance uses the invoice total as read inside the payment', () async {
      final inv = await invoice(1000);
      // The total is corrected to ₹1,200 after payInvoice first reads the
      // invoice and before its transaction runs.
      firestore.beforeTransaction = () async {
        await firestore.collection('finance_invoices').doc(inv).update({'totalAmount': 1200, 'balanceAmount': 1200});
      };
      await pay(inv, 1000, 'cash');
      final saved = (await firestore.collection('finance_invoices').doc(inv).get()).data()!;
      expect([saved['totalAmount'], saved['paidAmount'], saved['balanceAmount'], saved['status']], [1200, 1000, 200, 'partial'],
          reason: 'not "paid" from the ₹1,000 total read before the transaction');
      expect(await stored('cash'), -1000);
      await expectReconciled();
    });
  });

  group('legacy accounts without isActive', () {
    // Older accounts may have no `isActive` field (or null): active, as the
    // account model reads them. Only an explicit `false` is inactive.
    Future<void> dropActive(String type, {bool asNull = false}) =>
        firestore.collection('finance_accounts').doc(ids[type]).update({'isActive': asNull ? null : FieldValue.delete()});

    test('missing or null isActive is active for manual income, invoice payments, fee collections and reconciliation', () async {
      await dropActive('cash');
      await dropActive('upi', asNull: true);

      await finance.createIncome(income(accountId: ids['cash']!, amount: 700));
      final inv = await invoice(3000);
      await pay(inv, 400, 'cash');
      await fees.collectFee(assignmentId: 'a1', amount: 2500, paymentDate: DateTime(2026, 11, 3), paymentMode: 'upi', referenceNo: '', remarks: '');
      expect([await stored('cash'), await stored('upi'), await stored('bank')], [300, 2500, 0], reason: 'each went to its own legacy account');

      final r = await finance.reconcileAccounts();
      expect({for (final a in r.accounts) a.type: a.isActive}, {'cash': true, 'bank': true, 'upi': true});
      await expectReconciled();
      // The stored documents are not rewritten.
      expect((await account(ids['cash']!))!.containsKey('isActive'), isFalse);
      expect((await account(ids['upi']!))!['isActive'], isNull);
    });

    test('an explicitly inactive account stays inactive', () async {
      await dropActive('cash');
      await setActive('bank', false);
      final inv = await invoice(3000);
      await expectLater(pay(inv, 400, 'bank_transfer'), throwsA(isA<StateError>().having((e) => e.message, 'message', contains('No active Bank account'))));
      await expectLater(finance.createIncome(income(accountId: ids['bank']!, name: 'Bank')), throwsA(isA<StateError>().having((e) => e.message, 'message', contains('is inactive'))));
      expect(await stored('bank'), 0);
      final r = await finance.reconcileAccounts();
      expect({for (final a in r.accounts) a.type: a.isActive}, {'cash': true, 'bank': false, 'upi': true});
      expect((await account(ids['bank']!))!['isActive'], isFalse, reason: 'never reactivated');
      // The legacy Cash account still takes cash.
      await pay(inv, 400, 'cash');
      expect(await stored('cash'), -400);
    });
  });

  group('reconciliation', () {
    test('stored and calculated balances, the difference, negative accounts and missing accounts; nothing corrected', () async {
      // A non-zero opening balance now needs its date (Phase 2B).
      await finance.updateAccount(id: ids['bank']!, name: 'Bank', type: 'bank', openingBalance: 5000, isActive: true, openingBalanceDate: DateTime(2026, 1, 1));
      await finance.createIncome(income(accountId: ids['cash']!, amount: 300));
      final inv = await invoice(2000);
      await pay(inv, 2000, 'cash');
      // Synthetic damage: a stored balance off by ₹50, and entries with no
      // account and with a deleted one.
      await firestore.collection('finance_accounts').doc(ids['upi']).update({'currentBalance': 50});
      await firestore.collection('finance_ledger').add({'entryType': 'income', 'amount': 90, 'status': 'confirmed', 'title': 'Orphan', 'accountId': ''});
      await firestore.collection('finance_ledger').add({'entryType': 'expense', 'amount': 40, 'status': 'confirmed', 'title': 'Old account', 'accountId': 'deleted-acc', 'accountName': 'Petty cash'});
      await firestore.collection('finance_ledger').add({'entryType': 'expense', 'amount': 999, 'status': 'cancelled', 'title': 'Cancelled', 'accountId': 'deleted-acc'});

      final r = await finance.reconcileAccounts();
      final byType = {for (final a in r.accounts) a.type: a};
      expect([for (final a in r.accounts) a.group], ['Cash', 'Bank', 'UPI']);
      expect([byType['cash']!.storedBalance, byType['cash']!.calculatedBalance, byType['cash']!.difference], [-1700, -1700, 0]);
      expect(byType['cash']!.isNegative, isTrue);
      expect([byType['bank']!.storedBalance, byType['bank']!.calculatedBalance], [5000, 5000]);
      expect([byType['upi']!.storedBalance, byType['upi']!.calculatedBalance, byType['upi']!.difference], [50, 0, 50]);
      expect(r.mismatched.map((a) => a.type), ['upi']);
      expect(r.negative.map((a) => a.type), ['cash']);
      expect(r.problems.map((p) => p.title).toSet(), {'Orphan', 'Old account'}, reason: 'cancelled entries are not problems');
      expect(r.problems.firstWhere((p) => p.title == 'Orphan').hasNoAccount, isTrue);
      // Read only.
      expect(await stored('upi'), 50);
      // The calculated figures are exactly what Finance shows.
      final s = await finance.watchDashboardSummary().first;
      expect([s.cashBalance, s.bankBalance, s.upiBalance, s.unclassifiedBalance], [-1700, 5000, 0, 50]);
    });
  });

  group('screens', () {
    Future<void> pump(WidgetTester tester, String tab) async {
      tester.view.physicalSize = const Size(1400, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(ProviderScope(child: MaterialApp(home: AdminFinanceScreen(service: finance, feeService: fees, clock: () => DateTime(2026, 11, 6)))));
      await tester.pumpAndSettle();
      if (tab != 'Dashboard') {
        await tester.tap(find.widgetWithText(ChoiceChip, tab));
        await tester.pumpAndSettle();
      }
    }

    for (final tab in ['Dashboard', 'Ledger']) {
      testWidgets('$tab: a negative account is marked and explained; the others are not', (tester) async {
        await finance.createIncome(income(accountId: ids['upi']!, amount: 47300, name: 'UPI'));
        await finance.createIncome(income(accountId: ids['cash']!, amount: 3000));
        await pay(await invoice(4500), 4500, 'cash');
        await pump(tester, tab);
        final cash = tester.widget<FinanceSummaryCard>(find.byKey(const Key('finance-balance-cash')));
        expect(cash.value, '₹-1500', reason: 'the figure itself is unchanged');
        expect(cash.caption, 'Negative balance');
        expect(cash.valueColor, const Color(0xFFD32F2F));
        expect(tester.widget<FinanceSummaryCard>(find.byKey(const Key('finance-balance-upi'))).caption, isNull);
        expect(find.byKey(const Key('finance-negative-warning')), findsOneWidget);
        expect(find.textContaining('Cash is ₹-1500'), findsOneWidget);
        expect(find.textContaining('UPI is'), findsNothing);
      });
    }

    testWidgets('no warning when every balance is zero or above; Check balances opens the read-only check', (tester) async {
      await finance.createIncome(income(accountId: ids['cash']!, amount: 3000));
      await firestore.collection('finance_accounts').doc(ids['bank']).update({'currentBalance': 25});
      await pump(tester, 'Ledger');
      expect(find.byKey(const Key('finance-negative-warning')), findsNothing);
      await tester.ensureVisible(find.byKey(const Key('finance-check-balances')));
      await tester.tap(find.byKey(const Key('finance-check-balances')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('finance-reconciliation')), findsOneWidget);
      expect(find.byKey(const Key('finance-reconciliation-issues')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(Key('finance-reconciliation-${ids['bank']}-difference'))).data, '₹25');
      expect(tester.widget<Text>(find.byKey(Key('finance-reconciliation-${ids['cash']}-difference'))).data, '₹0');
      expect(await stored('bank'), 25, reason: 'nothing corrected');

      await firestore.collection('finance_accounts').doc(ids['bank']).update({'currentBalance': 0});
      await tester.tap(find.byKey(const Key('finance-reconciliation-refresh')));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget, reason: 'a new check, not the previous result');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('finance-reconciliation-ok')), findsOneWidget);
      await tester.tap(find.byKey(const Key('finance-reconciliation-close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('finance-reconciliation')), findsNothing);
    });
  });
}
