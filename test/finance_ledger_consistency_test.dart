// Finance ledger consistency (Phase 1):
// - D5: voiding an income entry updates the income doc, its ledger entry
//   and the account balance in one transaction (all or nothing), and a
//   repeated/concurrent void never applies twice.
// - D1: changing an income entry's payment mode moves it to the matching
//   account (payment, ledger entry and both account balances together), or
//   is rejected when that account can't be determined unambiguously.
// - D3: Cash/Bank/UPI balances are classified by the linked account's
//   stored type (never its name), each entry counted exactly once; entries
//   whose account is missing or of another type are reported separately.
//
// Uses BufferedTransactionFirestore so transaction writes are buffered and
// committed all-or-nothing like real Firestore (fake_cloud_firestore's own
// transactions write immediately and never roll back).
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/finance/models/finance_income_model.dart';
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

  Future<Map<String, dynamic>> accountByType(String type) async {
    final snap = await firestore.collection('finance_accounts').where('type', isEqualTo: type).get();
    return {'id': snap.docs.single.id, ...snap.docs.single.data()};
  }

  Future<double> balanceOf(String type) async =>
      ((await accountByType(type))['currentBalance'] as num).toDouble();

  Future<String> createIncome({double amount = 5000, String mode = 'cash', String accountType = 'cash'}) async {
    final account = await accountByType(accountType);
    final cat = (await service.watchCategories().first).firstWhere((c) => c.type == 'income');
    return service.createIncome(FinanceIncomeModel(
      id: '',
      title: 'Donation',
      categoryId: cat.id,
      categoryName: cat.name,
      programType: 'other',
      studentId: '',
      studentName: '',
      classId: '',
      className: '',
      amount: amount,
      incomeDate: DateTime(2026, 8, 1),
      paymentMode: mode,
      accountId: account['id'] as String,
      accountName: account['name'] as String,
      referenceNo: 'REF-1',
      remarks: 'Original remarks',
      attachmentUrls: const [],
      ledgerEntryId: '',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      createdBy: 'admin',
    ));
  }

  Future<Map<String, dynamic>> incomeDoc(String id) async =>
      (await firestore.collection('finance_income').doc(id).get()).data()!;

  Future<Map<String, dynamic>> ledgerFor(String incomeId) async {
    final ledgerId = (await incomeDoc(incomeId))['ledgerEntryId'] as String;
    return (await firestore.collection('finance_ledger').doc(ledgerId).get()).data()!;
  }

  group('D5: atomic income void', () {
    test('a successful void updates income, ledger and account together, preserving details', () async {
      final id = await createIncome();
      final ledgerBefore = await ledgerFor(id);
      expect(await balanceOf('cash'), 5000);

      await service.voidIncome(id);

      final income = await incomeDoc(id);
      expect(income['isDeleted'], isTrue);
      expect(income['deletedAt'], isNotNull);
      expect(income['deletedBy'], isNotEmpty);
      expect(income['amount'], 5000);
      expect(income['paymentMode'], 'cash');
      expect(income['remarks'], 'Original remarks');

      final ledger = await ledgerFor(id);
      expect(ledger['status'], 'cancelled');
      for (final key in ['description', 'amount', 'paymentMode', 'accountId', 'accountName', 'referenceNo', 'title']) {
        expect(ledger[key], ledgerBefore[key], reason: key);
      }

      expect(await balanceOf('cash'), 0);
      final summary = await service.watchDashboardSummary().first;
      expect(summary.totalIncome, 0);
      expect(summary.cashBalance, 0);
    });

    test('a commit failure leaves income, ledger and account unchanged', () async {
      final id = await createIncome();
      final incomeBefore = await incomeDoc(id);
      final ledgerBefore = await ledgerFor(id);
      firestore.failCommitWhen = (path) => path.startsWith('finance_ledger/');

      await expectLater(service.voidIncome(id), throwsA(isA<FirebaseException>()));

      expect(await incomeDoc(id), incomeBefore);
      expect(await ledgerFor(id), ledgerBefore);
      expect(await balanceOf('cash'), 5000);
      expect((await service.watchDashboardSummary().first).totalIncome, 5000);
    });

    test('a read failure inside the transaction writes nothing', () async {
      final id = await createIncome();
      firestore.failReadWhen = (path) => path.startsWith('finance_accounts/');

      await expectLater(service.voidIncome(id), throwsA(isA<FirebaseException>()));

      expect((await incomeDoc(id))['isDeleted'], isNot(true));
      expect((await ledgerFor(id))['status'], 'confirmed');
      expect(await balanceOf('cash'), 5000);
    });

    test('a repeated void is rejected and does not reverse the balance twice', () async {
      final id = await createIncome();
      await service.voidIncome(id);
      await expectLater(service.voidIncome(id), throwsStateError);
      expect(await balanceOf('cash'), 0);
    });

    test('concurrent voids apply exactly once', () async {
      final id = await createIncome();
      final results = await Future.wait([
        service.voidIncome(id).then((_) => 'ok', onError: (_) => 'rejected'),
        service.voidIncome(id).then((_) => 'ok', onError: (_) => 'rejected'),
      ]);
      expect(results.where((r) => r == 'ok'), hasLength(1));
      expect(await balanceOf('cash'), 0);
      expect((await ledgerFor(id))['status'], 'cancelled');
    });

    test('fee-collection reversal is atomic and idempotent', () async {
      await service.createFeeIncomeEntry({
        'feeCollectionId': 'fc-1',
        'amount': 4500.0,
        'paymentMode': 'cash',
        'studentName': 'Adhira D',
      });
      final income = (await firestore.collection('finance_income').where('sourceId', isEqualTo: 'fc-1').get()).docs.single;
      expect(await balanceOf('cash'), 4500);

      await service.reverseFeeIncomeByCollectionId('fc-1');
      await service.reverseFeeIncomeByCollectionId('fc-1');

      expect((await incomeDoc(income.id))['isDeleted'], isTrue);
      expect((await ledgerFor(income.id))['status'], 'cancelled');
      expect(await balanceOf('cash'), 0);
    });

    test('a missing linked ledger entry or account is skipped, not recreated', () async {
      final id = await createIncome();
      final ledgerId = (await incomeDoc(id))['ledgerEntryId'] as String;
      await firestore.collection('finance_ledger').doc(ledgerId).delete();

      await service.voidIncome(id);

      expect((await incomeDoc(id))['isDeleted'], isTrue);
      expect((await firestore.collection('finance_ledger').doc(ledgerId).get()).exists, isFalse);
    });
  });

  group('D1: payment-mode edits keep the account consistent', () {
    Future<void> edit(String id, {double amount = 5000, required String mode}) => service.updateIncome(
          id: id,
          title: 'Donation',
          categoryId: 'c',
          categoryName: 'Other Income',
          amount: amount,
          date: DateTime(2026, 8, 1),
          paymentMode: mode,
          referenceNo: 'REF-1',
          remarks: 'Original remarks',
        );

    Future<void> expectConsistent(String id, String accountType, String mode) async {
      final account = await accountByType(accountType);
      final income = await incomeDoc(id);
      final ledger = await ledgerFor(id);
      expect(income['accountId'], account['id']);
      expect(income['accountName'], account['name']);
      expect(income['paymentMode'], mode);
      expect(ledger['accountId'], account['id']);
      expect(ledger['accountName'], account['name']);
      expect(ledger['paymentMode'], mode);
    }

    test('cash -> upi moves the payment, ledger entry and balance to UPI', () async {
      final id = await createIncome();
      await edit(id, mode: 'upi');
      await expectConsistent(id, 'upi', 'upi');
      expect(await balanceOf('cash'), 0);
      expect(await balanceOf('upi'), 5000);
      final summary = await service.watchDashboardSummary().first;
      expect(summary.cashBalance, 0);
      expect(summary.upiBalance, 5000);
      expect(summary.totalIncome, 5000);
    });

    test('upi -> cash moves it back', () async {
      final id = await createIncome(mode: 'upi', accountType: 'upi');
      await edit(id, mode: 'cash');
      await expectConsistent(id, 'cash', 'cash');
      expect(await balanceOf('upi'), 0);
      expect(await balanceOf('cash'), 5000);
    });

    test('a mode and amount change together: old amount leaves, new amount arrives, once', () async {
      final id = await createIncome();
      await edit(id, amount: 7000, mode: 'upi');
      expect(await balanceOf('cash'), 0);
      expect(await balanceOf('upi'), 7000);
      expect(await balanceOf('bank'), 0);
    });

    test('an unchanged mode adjusts only the same account by the amount delta', () async {
      final id = await createIncome();
      await edit(id, amount: 6000, mode: 'cash');
      await expectConsistent(id, 'cash', 'cash');
      expect(await balanceOf('cash'), 6000);
      expect(await balanceOf('upi'), 0);
    });

    test('a mode change that maps to the current account type does not move it', () async {
      final id = await createIncome(mode: 'bank_transfer', accountType: 'bank');
      await edit(id, mode: 'cheque');
      await expectConsistent(id, 'bank', 'cheque');
      expect(await balanceOf('bank'), 5000);
    });

    test('a voided entry cannot be edited or moved', () async {
      final id = await createIncome();
      await service.voidIncome(id);
      await expectLater(edit(id, mode: 'upi'), throwsStateError);
      expect(await balanceOf('cash'), 0);
      expect(await balanceOf('upi'), 0);
      expect((await incomeDoc(id))['paymentMode'], 'cash');
    });

    test('ambiguous destination (two active UPI accounts) is rejected without changes', () async {
      final id = await createIncome();
      await firestore.collection('finance_accounts').add({
        'name': 'UPI Two', 'type': 'upi', 'openingBalance': 0, 'currentBalance': 0, 'isActive': true,
      });
      await expectLater(edit(id, mode: 'upi'), throwsA(isA<StateError>().having((e) => e.message, 'message', contains('more than one'))));
      await expectConsistent(id, 'cash', 'cash');
      expect(await balanceOf('cash'), 5000);
    });

    test('no active account for the new mode is rejected without changes', () async {
      final id = await createIncome();
      final upi = await accountByType('upi');
      await firestore.collection('finance_accounts').doc(upi['id'] as String).update({'isActive': false});
      await expectLater(edit(id, mode: 'upi'), throwsA(isA<StateError>().having((e) => e.message, 'message', contains('no active'))));
      await expectConsistent(id, 'cash', 'cash');
      expect(await balanceOf('cash'), 5000);
    });

    test('a commit failure during a move leaves everything unchanged', () async {
      final id = await createIncome();
      final upiId = (await accountByType('upi'))['id'] as String;
      firestore.failCommitWhen = (path) => path == 'finance_accounts/$upiId';
      await expectLater(edit(id, mode: 'upi'), throwsA(isA<FirebaseException>()));
      await expectConsistent(id, 'cash', 'cash');
      expect(await balanceOf('cash'), 5000);
      expect(await balanceOf('upi'), 0);
    });

    test('fee collection edit cash -> upi moves the linked Finance entry', () async {
      await service.createFeeIncomeEntry({'feeCollectionId': 'fc-1', 'amount': 4500.0, 'paymentMode': 'cash'});
      final id = (await firestore.collection('finance_income').where('sourceId', isEqualTo: 'fc-1').get()).docs.single.id;
      await service.updateFeeIncomeEntry(
        feeCollectionId: 'fc-1',
        amount: 4500,
        date: DateTime(2026, 9, 1),
        paymentMode: 'upi',
        referenceNo: '',
        remarks: '',
      );
      await expectConsistent(id, 'upi', 'upi');
      expect(await balanceOf('cash'), 0);
      expect(await balanceOf('upi'), 4500);
    });

    test('a voided fee collection entry is not moved by a later edit', () async {
      await service.createFeeIncomeEntry({'feeCollectionId': 'fc-1', 'amount': 4500.0, 'paymentMode': 'cash'});
      await service.reverseFeeIncomeByCollectionId('fc-1');
      await service.updateFeeIncomeEntry(
        feeCollectionId: 'fc-1',
        amount: 4500,
        date: DateTime(2026, 9, 1),
        paymentMode: 'upi',
        referenceNo: '',
        remarks: '',
      );
      expect(await balanceOf('cash'), 0);
      expect(await balanceOf('upi'), 0);
    });

    test("an invoice payment's mode cannot be changed through income edits", () async {
      final invoiceId = await service.createExpenseInvoice({
        'partyName': 'Vendor', 'categoryName': 'Rent', 'invoiceNo': 'INV-1', 'totalAmount': 1000, 'amount': 1000,
      });
      final paymentId = (await service.payInvoice(
        invoiceId: invoiceId,
        invoiceType: 'expense',
        amount: 1000,
        paidDate: DateTime(2026, 9, 1),
        paymentMode: 'cash',
        referenceNo: '',
        remarks: '',
      ))!;
      await expectLater(edit(paymentId, amount: 1000, mode: 'upi'), throwsStateError);
      expect((await incomeDoc(paymentId))['paymentMode'], 'cash');
    });
  });

  group('D3: account balances by account type, not name', () {
    Future<String> addAccount(String name, String type) async =>
        (await firestore.collection('finance_accounts').add({
          'name': name, 'type': type, 'openingBalance': 0, 'currentBalance': 0, 'isActive': true,
        })).id;

    var seq = 0;
    Future<void> addEntry({
      required String accountId,
      required String accountName,
      required double amount,
      String entryType = 'income',
      String status = 'confirmed',
    }) async {
      seq++;
      await firestore.collection('finance_ledger').add({
        'entryType': entryType,
        'amount': amount,
        'accountId': accountId,
        'accountName': accountName,
        'status': status,
        'title': 'Entry $seq',
        'createdAt': DateTime(2026, 9, 1).add(Duration(minutes: seq)),
      });
    }

    test('standard Cash, Bank and UPI accounts', () async {
      final cash = await accountByType('cash');
      final bank = await accountByType('bank');
      final upi = await accountByType('upi');
      await addEntry(accountId: cash['id'], accountName: 'Cash', amount: 4500);
      await addEntry(accountId: cash['id'], accountName: 'Cash', amount: 5000, entryType: 'expense');
      await addEntry(accountId: bank['id'], accountName: 'Bank', amount: 1000);
      await addEntry(accountId: upi['id'], accountName: 'UPI', amount: 57500);
      await addEntry(accountId: upi['id'], accountName: 'UPI', amount: 25000, entryType: 'expense');

      final s = await service.watchDashboardSummary().first;
      expect(s.cashBalance, -500);
      expect(s.bankBalance, 1000);
      expect(s.upiBalance, 32500);
      expect(s.unclassifiedBalance, 0);
      expect(s.totalIncome, 63000);
      expect(s.totalExpenses, 30000);
      expect(s.netBalance, 33000);
    });

    test('names do not affect classification: custom and misleading names', () async {
      final hdfc = await addAccount('HDFC Savings', 'bank');
      final bankUpi = await addAccount('Bank UPI', 'upi');
      final cashLooking = await addAccount('Cash Box', 'wallet');
      await addEntry(accountId: hdfc, accountName: 'HDFC Savings', amount: 2000);
      await addEntry(accountId: bankUpi, accountName: 'Bank UPI', amount: 3000);
      await addEntry(accountId: cashLooking, accountName: 'Cash Box', amount: 700);

      final s = await service.watchDashboardSummary().first;
      expect(s.bankBalance, 2000); // HDFC Savings counted (old name rule missed it)
      expect(s.upiBalance, 3000); // Bank UPI counted once, as UPI only
      expect(s.cashBalance, 0); // 'Cash Box' is a wallet, not cash
      expect(s.unclassifiedBalance, 700);
    });

    test('missing account or unknown type is reported, not guessed', () async {
      final other = await addAccount('Petty', 'other');
      await addEntry(accountId: 'deleted-account', accountName: 'Cash', amount: 100);
      await addEntry(accountId: '', accountName: 'UPI', amount: 200);
      await addEntry(accountId: other, accountName: 'Petty', amount: 50, entryType: 'expense');

      final s = await service.watchDashboardSummary().first;
      expect(s.cashBalance, 0);
      expect(s.upiBalance, 0);
      expect(s.bankBalance, 0);
      expect(s.unclassifiedBalance, 250);
    });

    test('each entry counted exactly once; cancelled entries excluded', () async {
      final cash = await accountByType('cash');
      final upi = await accountByType('upi');
      final wallet = await addAccount('Wallet', 'wallet');
      await addEntry(accountId: cash['id'], accountName: 'Cash', amount: 4500);
      await addEntry(accountId: cash['id'], accountName: 'Cash', amount: 700, entryType: 'expense', status: 'cancelled');
      await addEntry(accountId: upi['id'], accountName: 'UPI', amount: 5000, status: 'cancelled');
      await addEntry(accountId: upi['id'], accountName: 'UPI', amount: 20000);
      await addEntry(accountId: wallet, accountName: 'Wallet', amount: 300, entryType: 'expense');

      final s = await service.watchDashboardSummary().first;
      expect(s.cashBalance, 4500);
      expect(s.upiBalance, 20000);
      expect(s.unclassifiedBalance, -300);
      expect(s.totalIncome, 24500);
      expect(s.totalExpenses, 300);
      // Net/closing policy unchanged; the buckets add up to it exactly.
      expect(s.netBalance, 24200);
      expect(s.cashBalance + s.bankBalance + s.upiBalance + s.unclassifiedBalance, s.netBalance);
    });

    testWidgets('Ledger tab reports an unclassified amount only when there is one', (tester) async {
      final cash = await accountByType('cash');
      await addEntry(accountId: cash['id'], accountName: 'Cash', amount: 4500);
      tester.view.physicalSize = const Size(1400, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      Future<void> pumpLedger() async {
        await tester.pumpWidget(ProviderScope(child: MaterialApp(home: AdminFinanceScreen(service: service))));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(ChoiceChip, 'Ledger'));
        await tester.pumpAndSettle();
      }

      await pumpLedger();
      expect(find.text('Account Balances'), findsOneWidget);
      expect(find.textContaining('is not shown in Cash, Bank or UPI'), findsNothing);

      await addEntry(accountId: 'deleted-account', accountName: 'Cash', amount: 100);
      await pumpLedger();
      expect(find.textContaining('₹100 is not shown in Cash, Bank or UPI'), findsOneWidget);
    });
  });
}
