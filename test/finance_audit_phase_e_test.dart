// Finance audit Phase E:
// - Part 1: FeeService.voidReceipt refuses a fee-linked cancellation when
//   the receipt, Finance income and ledger amounts disagree (to the paisa),
//   before any write, on every attempt; matching amounts, legacy receipts
//   without a Finance link and duplicate-link protection are unchanged.
// - Part 2: unsafe use of FinanceService.createSalaryPayment, voidIncome,
//   updateIncome and cancelLedgerEntry is refused without writes.
// - Part 3: after a Fees-step failure following a successful Finance
//   reversal, retrying from Fees -> Collections finishes the cancellation
//   without restoring or reversing anything twice.
//
// Uses BufferedTransactionFirestore: transaction writes are buffered and
// committed all-or-nothing, and failures are injected at commit. That
// simulates a failed Firestore commit deterministically; it is not a real
// Firestore/network failure.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/fees/services/fee_service.dart';
import 'package:montessori_app/modules/fees/ui/admin_fees_screen.dart';
import 'package:montessori_app/modules/finance/models/finance_income_model.dart';
import 'package:montessori_app/modules/finance/models/staff_salary_payment_model.dart';
import 'package:montessori_app/modules/finance/services/finance_service.dart';
import 'package:montessori_app/modules/finance/ui/admin_finance_screen.dart';

import 'support/buffered_transaction_firestore.dart';

/// Edits the receipt amount right after the Finance reversal, simulating a
/// concurrent edit between voidReceipt's checks and its Fees step.
class _EditDuringVoidFinanceService extends FinanceService {
  _EditDuringVoidFinanceService(this._db) : super(firestore: _db, auth: MockFirebaseAuth());
  final BufferedTransactionFirestore _db;
  bool editReceipt = false;

  @override
  Future<void> reverseFeeIncomeByCollectionId(String feeCollectionId) async {
    await super.reverseFeeIncomeByCollectionId(feeCollectionId);
    if (editReceipt) await _db.doc('fee_receipts/$feeCollectionId').update({'amount': 9999});
  }
}

void main() {
  late BufferedTransactionFirestore firestore;
  late _EditDuringVoidFinanceService finance;
  late FeeService fees;

  setUp(() async {
    firestore = BufferedTransactionFirestore();
    final auth = MockFirebaseAuth();
    finance = _EditDuringVoidFinanceService(firestore);
    await finance.ensureDefaults();
    fees = FeeService(firestore: firestore, auth: auth, storage: MockFirebaseStorage(), financeService: finance);
    await firestore.collection('classes').doc('class-1').set({'name': 'Mont 1', 'isActive': true});
    await firestore.collection('students').doc('s1').set({
      'name': 'Adhira D', 'admissionNo': 'ADM-1', 'classId': 'class-1', 'isActive': true,
    });
    await firestore.collection('student_fee_assignments').doc('a1').set({
      'studentId': 's1',
      'studentName': 'Adhira D',
      'admissionNo': 'ADM-1',
      'classId': 'class-1',
      'className': 'Mont 1',
      'feeStructureId': 'structure-1',
      'feeStructureName': 'Core Fees',
      'academicYear': '2026-2027',
      'totalFee': 20000,
      'discountAmount': 0,
      'payableAmount': 20000,
      'paidAmount': 0,
      'balanceAmount': 20000,
      'status': 'unpaid',
      'assignedAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
      'updatedAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
    });
  });

  Future<String> collect({double amount = 4500}) async => (await fees.collectFee(
        assignmentId: 'a1',
        amount: amount,
        paymentDate: DateTime(2026, 8, 1),
        paymentMode: 'cash',
        referenceNo: 'REF-1',
        remarks: '',
      ))
          .id;

  Future<QueryDocumentSnapshot<Map<String, dynamic>>> linkedIncome(String receiptId) async =>
      (await firestore.collection('finance_income').where('sourceId', isEqualTo: receiptId).get()).docs.single;

  Future<Map<String, dynamic>> doc(String path) async => (await firestore.doc(path).get()).data()!;

  Future<String> accountIdByType(String type) async =>
      (await firestore.collection('finance_accounts').where('type', isEqualTo: type).get()).docs.single.id;

  Future<double> cashBalance() async => ((await doc('finance_accounts/${await accountIdByType('cash')}'))['currentBalance'] as num).toDouble();

  const collections = [
    'fee_receipts', 'fee_transactions', 'student_fee_assignments', 'finance_income', 'finance_ledger',
    'finance_accounts', 'finance_invoices', 'staff_salary_payments',
  ];
  Future<Map<String, Map<String, dynamic>?>> snapshotAll() async => {
        for (final c in collections)
          for (final d in (await firestore.collection(c).get()).docs) '$c/${d.id}': d.data(),
      };

  Matcher refusedWith(FeeVoidFailure failure, [String? text]) => throwsA(isA<FeeVoidException>()
      .having((e) => e.failure, 'failure', failure)
      .having((e) => e.message, 'message', text == null ? anything : contains(text)));

  group('Part 1: amount mismatch', () {
    test('matching amounts (including paise) cancel normally', () async {
      final receiptId = await collect(amount: 4500.5);
      final income = await linkedIncome(receiptId);
      expect(await fees.voidReceipt(receiptId, expectedFinanceIncomeId: income.id), FeeVoidOutcome.voided);
      expect((await doc('fee_receipts/$receiptId'))['isDeleted'], isTrue);
      expect((await doc('finance_income/${income.id}'))['isDeleted'], isTrue);
      expect(await cashBalance(), 0);
      expect((await doc('student_fee_assignments/a1'))['paidAmount'], 0);
    });

    test('a sub-paisa floating-point difference is not a mismatch', () async {
      final receiptId = await collect();
      final income = await linkedIncome(receiptId);
      await firestore.doc('finance_income/${income.id}').update({'amount': 4500.0000001});
      expect(await fees.voidReceipt(receiptId), FeeVoidOutcome.voided);
    });

    test('receipt and Finance income disagree: refused before any write, every time', () async {
      final receiptId = await collect();
      final income = await linkedIncome(receiptId);
      await firestore.doc('finance_income/${income.id}').update({'amount': 4000});
      final state = await snapshotAll();

      await expectLater(
        fees.voidReceipt(receiptId, expectedFinanceIncomeId: income.id),
        refusedWith(FeeVoidFailure.amountMismatch, 'The Fee Collection amount (₹4500) does not match its Finance entry (₹4000)'),
      );
      expect(await snapshotAll(), state);
      // A retry is checked again and refused again.
      await expectLater(fees.voidReceipt(receiptId), refusedWith(FeeVoidFailure.amountMismatch, 'Nothing was changed'));
      expect(await snapshotAll(), state);
    });

    test('a one-paisa difference is refused', () async {
      final receiptId = await collect();
      final income = await linkedIncome(receiptId);
      await firestore.doc('finance_income/${income.id}').update({'amount': 4500.01});
      final state = await snapshotAll();
      await expectLater(fees.voidReceipt(receiptId), refusedWith(FeeVoidFailure.amountMismatch, '₹4500.01'));
      expect(await snapshotAll(), state);
    });

    test('Finance income and its ledger entry disagree: refused, nothing written', () async {
      final receiptId = await collect();
      final income = await linkedIncome(receiptId);
      await firestore.doc('finance_ledger/${income.data()['ledgerEntryId']}').update({'amount': 5000});
      final state = await snapshotAll();
      await expectLater(fees.voidReceipt(receiptId), refusedWith(FeeVoidFailure.amountMismatch, 'its ledger entry (₹5000)'));
      expect(await snapshotAll(), state);
    });

    test('retry paths cannot bypass the check (Finance reversed / receipt voided)', () async {
      // Receipt active, Finance already reversed with a different amount.
      final r1 = await collect();
      final i1 = await linkedIncome(r1);
      await finance.reverseFeeIncomeByCollectionId(r1);
      await firestore.doc('fee_receipts/$r1').update({'amount': 3000});
      var state = await snapshotAll();
      await expectLater(fees.voidReceipt(r1), refusedWith(FeeVoidFailure.amountMismatch));
      expect(await snapshotAll(), state);
      expect((await doc('finance_income/${i1.id}'))['isDeleted'], isTrue);

      // Receipt voided, Finance still active with a different amount.
      final r2 = await collect();
      final i2 = await linkedIncome(r2);
      await firestore.doc('fee_receipts/$r2').update({'isDeleted': true, 'amount': 1000});
      state = await snapshotAll();
      await expectLater(fees.voidReceipt(r2), refusedWith(FeeVoidFailure.amountMismatch));
      expect(await snapshotAll(), state);
      expect((await doc('finance_income/${i2.id}'))['isDeleted'], isNot(true));
    });

    test('an amount edited between the checks and the Fees step is not restored', () async {
      final receiptId = await collect();
      finance.editReceipt = true;
      await expectLater(fees.voidReceipt(receiptId), refusedWith(FeeVoidFailure.amountMismatch, 'changed while it was being voided'));
      // The Fees step wrote nothing: receipt active, assignment untouched.
      expect((await doc('fee_receipts/$receiptId'))['isDeleted'], isNot(true));
      expect((await doc('student_fee_assignments/a1'))['paidAmount'], 4500);
      // Finance was reversed (the message says it may have been); a retry
      // now sees 9999 vs 4500 and is refused, never restoring 9999.
      finance.editReceipt = false;
      await expectLater(fees.voidReceipt(receiptId), refusedWith(FeeVoidFailure.amountMismatch));
      expect((await doc('student_fee_assignments/a1'))['paidAmount'], 4500);
      expect(await cashBalance(), 0);
    });

    test('a legacy receipt without a Finance link is still voided (Fees only)', () async {
      final receiptId = await collect();
      final income = await linkedIncome(receiptId);
      await firestore.doc('finance_income/${income.id}').delete();
      await firestore.doc('fee_receipts/$receiptId').update({'amount': 4500});
      expect(await fees.voidReceipt(receiptId), FeeVoidOutcome.voided);
      expect((await doc('student_fee_assignments/a1'))['paidAmount'], 0);
      expect(await cashBalance(), 4500, reason: 'no Finance entry, so no account reversal');
    });

    test('missing receipt and missing Finance record are still refused with nothing written', () async {
      final receiptId = await collect();
      final income = await linkedIncome(receiptId);
      var state = await snapshotAll();
      await expectLater(fees.voidReceipt('nope'), refusedWith(FeeVoidFailure.collectionNotFound));
      expect(await snapshotAll(), state);

      await firestore.doc('finance_income/${income.id}').delete();
      state = await snapshotAll();
      await expectLater(
        fees.voidReceipt(receiptId, expectedFinanceIncomeId: income.id),
        refusedWith(FeeVoidFailure.financeMissing),
      );
      expect(await snapshotAll(), state);
    });

    test('duplicate Finance links are still refused', () async {
      final receiptId = await collect();
      final income = await linkedIncome(receiptId);
      await firestore.collection('finance_income').add({...income.data(), 'amount': 1});
      final state = await snapshotAll();
      await expectLater(fees.voidReceipt(receiptId), refusedWith(FeeVoidFailure.financeAmbiguous));
      expect(await snapshotAll(), state);
    });

    testWidgets('Finance -> Income shows the mismatch message and changes nothing', (tester) async {
      final receiptId = await collect();
      final income = await linkedIncome(receiptId);
      await firestore.doc('finance_income/${income.id}').update({'amount': 4000});
      final state = await snapshotAll();
      tester.view.physicalSize = const Size(1400, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(ProviderScope(child: MaterialApp(home: AdminFinanceScreen(service: finance, feeService: fees))));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Income'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Void Fee Collection'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Void'));
      await tester.pumpAndSettle();
      expect(find.textContaining('does not match its Finance entry (₹4000)'), findsOneWidget);
      expect(await snapshotAll(), state);
    });
  });

  group('Part 2: guarded service paths', () {
    StaffSalaryPaymentModel salary({required double netPayable, required double paidAmount, required String accountId}) =>
        StaffSalaryPaymentModel.fromMap('', {
          'staffName': 'Malani D',
          'netPayable': netPayable,
          'paidAmount': paidAmount,
          'paymentDate': DateTime(2026, 9, 1),
          'paymentMode': 'cash',
          'accountId': accountId,
          'accountName': 'Cash',
        });

    test('createSalaryPayment: ledger amount equals the account debit, or it is refused', () async {
      final cash = await accountIdByType('cash');
      final id = await finance.createSalaryPayment(salary(netPayable: 3000, paidAmount: 3000, accountId: cash));
      final payment = await doc('staff_salary_payments/$id');
      final ledger = await doc('finance_ledger/${payment['ledgerEntryId']}');
      expect(ledger['amount'], 3000);
      expect(await cashBalance(), -3000);

      final state = await snapshotAll();
      await expectLater(
        finance.createSalaryPayment(salary(netPayable: 5000, paidAmount: 2000, accountId: cash)),
        throwsA(isA<StateError>().having((e) => e.message, 'message', contains('ledger and account balance would disagree'))),
      );
      expect(await snapshotAll(), state);
    });

    Future<String> paidExpenseInvoicePayment() async {
      final invoiceId = await finance.createExpenseInvoice({
        'partyName': 'Vendor', 'categoryName': 'Rent', 'invoiceNo': 'INV-1', 'totalAmount': 1000, 'amount': 1000,
      });
      return (await finance.payInvoice(
        invoiceId: invoiceId,
        invoiceType: 'expense',
        amount: 1000,
        paidDate: DateTime(2026, 9, 1),
        paymentMode: 'cash',
        referenceNo: '',
        remarks: '',
      ))!;
    }

    test('voidIncome refuses an expense invoice payment (would debit the account twice)', () async {
      final paymentId = await paidExpenseInvoicePayment();
      expect(await cashBalance(), -1000);
      final state = await snapshotAll();
      await expectLater(
        finance.voidIncome(paymentId),
        throwsA(isA<StateError>().having((e) => e.message, 'message', contains('Use Reverse on the payment'))),
      );
      expect(await snapshotAll(), state);
    });

    test('voidIncome and updateIncome refuse records from an unsupported source', () async {
      final cash = await accountIdByType('cash');
      final ref = await firestore.collection('finance_income').add({
        'title': 'Imported', 'amount': 500, 'sourceModule': 'import', 'accountId': cash, 'paymentMode': 'cash',
      });
      final state = await snapshotAll();
      await expectLater(finance.voidIncome(ref.id), throwsStateError);
      await expectLater(
        finance.updateIncome(
          id: ref.id, title: 'x', categoryId: 'c', categoryName: 'C', amount: 900, date: DateTime(2026, 9, 1),
          paymentMode: 'cash', referenceNo: '', remarks: '',
        ),
        throwsStateError,
      );
      expect(await snapshotAll(), state);
    });

    test('updateIncome refuses an amount change on an invoice payment', () async {
      final paymentId = await paidExpenseInvoicePayment();
      final state = await snapshotAll();
      await expectLater(
        finance.updateIncome(
          id: paymentId, title: 'Expense Payment - Vendor', categoryId: 'expense', categoryName: 'Expense',
          amount: 400, date: DateTime(2026, 9, 1), paymentMode: 'cash', referenceNo: '', remarks: '',
        ),
        throwsA(isA<StateError>().having((e) => e.message, 'message', contains('invoice payment'))),
      );
      expect(await snapshotAll(), state);
    });

    test('manual income void and edit are unchanged', () async {
      final cash = await accountIdByType('cash');
      final id = await finance.createIncome(FinanceIncomeModel(
        id: '', title: 'Donation', categoryId: 'c', categoryName: 'Other Income', programType: 'other',
        studentId: '', studentName: '', classId: '', className: '', amount: 1000,
        incomeDate: DateTime(2026, 8, 1), paymentMode: 'cash', accountId: cash, accountName: 'Cash',
        referenceNo: '', remarks: '', attachmentUrls: const [], ledgerEntryId: '',
        createdAt: DateTime.now(), updatedAt: DateTime.now(), createdBy: 'admin',
      ));
      await finance.updateIncome(
        id: id, title: 'Donation', categoryId: 'c', categoryName: 'Other Income', amount: 1500,
        date: DateTime(2026, 8, 1), paymentMode: 'cash', referenceNo: '', remarks: '',
      );
      expect(await cashBalance(), 1500);
      await finance.voidIncome(id);
      expect(await cashBalance(), 0);
    });

    test('cancelLedgerEntry refuses a linked entry; an unlinked one keeps its description', () async {
      final paymentId = await paidExpenseInvoicePayment();
      final ledgerId = (await doc('finance_income/$paymentId'))['ledgerEntryId'] as String;
      final state = await snapshotAll();
      await expectLater(finance.cancelLedgerEntry(ledgerId, reason: 'mistake'), throwsStateError);
      expect(await snapshotAll(), state);

      final orphan = await firestore.collection('finance_ledger').add({
        'entryType': 'income', 'amount': 50, 'status': 'confirmed', 'description': 'Original note',
      });
      await finance.cancelLedgerEntry(orphan.id, reason: 'Duplicate import');
      final after = await doc('finance_ledger/${orphan.id}');
      expect(after['status'], 'cancelled');
      expect(after['description'], 'Original note');
      expect(after['cancellationReason'], 'Duplicate import');
    });
  });

  group('Part 3: retry from Fees -> Collections', () {
    testWidgets('after Finance reversal succeeded and the Fees commit failed, retrying from Fees finishes once', (tester) async {
      final first = await collect();
      await collect(); // a second collection on the same assignment, so a double restoration would show
      final income = await linkedIncome(first);
      final receiptNo = (await doc('fee_receipts/$first'))['receiptNo'] as String;
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(ProviderScope(child: MaterialApp(home: AdminFeesScreen(service: fees))));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Receipts'));
      await tester.pumpAndSettle();

      Future<void> voidFromMenu() async {
        final row = find.ancestor(
          of: find.text(receiptNo),
          matching: find.byWidgetPredicate((w) => w.runtimeType.toString() == '_FeeListCard'),
        );
        final menu = find.descendant(of: row, matching: find.byIcon(Icons.more_vert));
        await tester.ensureVisible(menu);
        await tester.tap(menu);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Void'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Void'));
        await tester.pumpAndSettle();
      }

      // Simulated commit failure of the Fees step (receipt + assignment
      // commit together, so neither is written).
      firestore.failCommitWhen = (path) => path == 'fee_receipts/$first';
      await voidFromMenu();
      firestore.failCommitWhen = null;
      expect(find.textContaining('Failed to void payment'), findsOneWidget);
      // Partial state: Finance reversed; receipt and assignment untouched.
      expect((await doc('finance_income/${income.id}'))['isDeleted'], isTrue);
      expect(await cashBalance(), 4500);
      expect((await doc('fee_receipts/$first'))['isDeleted'], isNot(true));
      expect((await doc('student_fee_assignments/a1'))['paidAmount'], 9000);

      // Retry from the same Fees -> Collections row.
      expect(find.text(receiptNo), findsOneWidget);
      await voidFromMenu();
      // SnackBars queue: the success one shows once the earlier failure one times out.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.text('Payment voided'), findsOneWidget);
      expect((await doc('fee_receipts/$first'))['isDeleted'], isTrue);
      final assignment = await doc('student_fee_assignments/a1');
      expect(assignment['paidAmount'], 4500, reason: 'restored once, not twice');
      expect(assignment['balanceAmount'], 15500);
      expect(await cashBalance(), 4500, reason: 'Finance reversed once, not twice');
      expect(find.text(receiptNo), findsNothing);
    });
  });
}
