// Finance -> Income: voiding an entry generated from a Fee Collection.
// - The Income card offers "Void Fee Collection" for an active fee-linked
//   entry; confirming runs the Fees module's own void (FeeService
//   .voidReceipt), so the fee receipt, fee assignment, Finance income,
//   ledger entry and account balance all end up consistent.
// - A collection already voided in Fees whose Finance entry was left active
//   is reconciled on the Finance side only, without touching Fees again.
// - A missing linked collection is reported and nothing changes.
// - Manual income voiding is unchanged; voided entries offer no action.
// - Recovery (Phase C): FeeService.voidReceipt checks both sides before
//   writing, so retries after a partial failure complete only the missing
//   step, balances are never reversed or restored twice, and missing,
//   ambiguous or inconsistent records are refused with nothing written.
//
// Uses BufferedTransactionFirestore so transactional merge writes keep
// other fields, as real Firestore does.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/fees/services/fee_service.dart';
import 'package:montessori_app/modules/finance/models/finance_income_model.dart';
import 'package:montessori_app/modules/finance/services/finance_service.dart';
import 'package:montessori_app/modules/finance/ui/admin_finance_screen.dart';

import 'support/buffered_transaction_firestore.dart';

void main() {
  late BufferedTransactionFirestore firestore;
  late FinanceService finance;
  late FeeService fees;

  setUp(() async {
    firestore = BufferedTransactionFirestore();
    final auth = MockFirebaseAuth();
    finance = FinanceService(firestore: firestore, auth: auth);
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

  Future<double> cashBalance() async {
    final snap = await firestore.collection('finance_accounts').where('type', isEqualTo: 'cash').get();
    return (snap.docs.single.data()['currentBalance'] as num).toDouble();
  }

  Future<void> pumpIncomeTab(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(home: AdminFinanceScreen(service: finance, feeService: fees)),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Income'));
    await tester.pumpAndSettle();
  }

  testWidgets('an active fee-linked entry offers "Void Fee Collection"; confirming voids Fees and Finance together', (tester) async {
    final receiptId = await collect();
    final income = await linkedIncome(receiptId);
    final ledgerId = income.data()['ledgerEntryId'] as String;
    expect(await cashBalance(), 4500);
    await pumpIncomeTab(tester);

    expect(find.byTooltip('Void Fee Collection'), findsOneWidget);
    await tester.tap(find.byTooltip('Void Fee Collection'));
    await tester.pumpAndSettle();
    expect(find.text('Void Fee Collection'), findsWidgets); // dialog title
    expect(find.textContaining('Adhira D'), findsWidgets);
    await tester.tap(find.widgetWithText(FilledButton, 'Void'));
    await tester.pumpAndSettle();
    expect(find.text('Fee Collection voided'), findsOneWidget);

    // Fees side (via FeeService.voidReceipt): receipt voided, balance restored.
    expect((await doc('fee_receipts/$receiptId'))['isDeleted'], isTrue);
    final assignment = await doc('student_fee_assignments/a1');
    expect(assignment['paidAmount'], 0);
    expect(assignment['balanceAmount'], 20000);
    // Finance side: income voided, ledger cancelled, account reversed.
    expect((await doc('finance_income/${income.id}'))['isDeleted'], isTrue);
    expect((await doc('finance_ledger/$ledgerId'))['status'], 'cancelled');
    expect(await cashBalance(), 0);
    final summary = await finance.watchDashboardSummary().first;
    expect(summary.totalIncome, 0);
    expect(summary.cashBalance, 0);
    // Voided entries are no longer listed, so no further action is offered.
    expect(find.byTooltip('Void Fee Collection'), findsNothing);
  });

  testWidgets('cancelling the confirmation changes nothing', (tester) async {
    final receiptId = await collect();
    final income = await linkedIncome(receiptId);
    await pumpIncomeTab(tester);

    await tester.tap(find.byTooltip('Void Fee Collection'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect((await doc('fee_receipts/$receiptId'))['isDeleted'], isNot(true));
    expect((await doc('finance_income/${income.id}'))['isDeleted'], isNot(true));
    expect(await cashBalance(), 4500);
    expect(find.byTooltip('Void Fee Collection'), findsOneWidget);
  });

  testWidgets('a collection already voided in Fees with its Finance entry left active is reconciled once', (tester) async {
    final receiptId = await collect();
    final income = await linkedIncome(receiptId);
    // Simulate the stuck state: Fees side voided (receipt + assignment),
    // Finance side never reversed.
    await firestore.doc('fee_receipts/$receiptId').update({'isDeleted': true});
    await firestore.doc('student_fee_assignments/a1').update({'paidAmount': 0, 'balanceAmount': 20000, 'status': 'unpaid'});
    final receiptBefore = await doc('fee_receipts/$receiptId');
    await pumpIncomeTab(tester);

    await tester.tap(find.byTooltip('Void Fee Collection'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Void'));
    await tester.pumpAndSettle();
    expect(find.textContaining('already voided; this Finance entry has now been voided to match'), findsOneWidget);

    expect((await doc('finance_income/${income.id}'))['isDeleted'], isTrue);
    expect(await cashBalance(), 0);
    // Fees side not touched again: no second balance restoration.
    expect(await doc('fee_receipts/$receiptId'), receiptBefore);
    expect((await doc('student_fee_assignments/a1'))['paidAmount'], 0);

    // Repeating via the service is a safe no-op.
    await finance.reverseFeeIncomeByCollectionId(receiptId);
    expect(await cashBalance(), 0);
  });

  testWidgets('a missing linked collection is reported and nothing changes', (tester) async {
    final receiptId = await collect();
    final income = await linkedIncome(receiptId);
    final ledgerId = income.data()['ledgerEntryId'] as String;
    await firestore.doc('fee_receipts/$receiptId').delete();
    await pumpIncomeTab(tester);

    await tester.tap(find.byTooltip('Void Fee Collection'));
    await tester.pumpAndSettle();

    expect(find.textContaining('linked Fee Collection could not be found'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Void'), findsNothing); // no confirmation offered
    expect((await doc('finance_income/${income.id}'))['isDeleted'], isNot(true));
    expect((await doc('finance_ledger/$ledgerId'))['status'], 'confirmed');
    expect(await cashBalance(), 4500);
    expect((await doc('student_fee_assignments/a1'))['paidAmount'], 4500);
  });

  testWidgets('voiding the same collection twice cannot apply twice', (tester) async {
    final receiptId = await collect();
    await fees.voidReceipt(receiptId);
    await expectLater(fees.voidReceipt(receiptId), throwsStateError);
    expect(await cashBalance(), 0);
    expect((await doc('student_fee_assignments/a1'))['paidAmount'], 0);
    await pumpIncomeTab(tester);
    expect(find.byTooltip('Void Fee Collection'), findsNothing);
  });

  testWidgets('manual income voiding is unchanged', (tester) async {
    final cash = (await firestore.collection('finance_accounts').where('type', isEqualTo: 'cash').get()).docs.single;
    final cat = (await finance.watchCategories().first).firstWhere((c) => c.name == 'Other Income');
    final id = await finance.createIncome(FinanceIncomeModel(
      id: '', title: 'Donation', categoryId: cat.id, categoryName: cat.name, programType: 'other',
      studentId: '', studentName: '', classId: '', className: '', amount: 1000,
      incomeDate: DateTime(2026, 8, 1), paymentMode: 'cash', accountId: cash.id, accountName: 'Cash',
      referenceNo: '', remarks: '', attachmentUrls: const [], ledgerEntryId: '',
      createdAt: DateTime.now(), updatedAt: DateTime.now(), createdBy: 'admin',
    ));
    await pumpIncomeTab(tester);

    expect(find.byTooltip('Void'), findsOneWidget);
    await tester.tap(find.byTooltip('Void'));
    await tester.pumpAndSettle();
    expect(find.text('Void Income Entry'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Void'));
    await tester.pumpAndSettle();
    expect(find.text('Income entry voided'), findsOneWidget);
    expect((await doc('finance_income/$id'))['isDeleted'], isTrue);
  });

  group('recovery and status checks', () {
    const collections = ['fee_receipts', 'student_fee_assignments', 'finance_income', 'finance_ledger', 'finance_accounts'];

    /// Every document in the collections a void can touch, for
    /// "nothing was written" assertions.
    Future<Map<String, Map<String, dynamic>?>> snapshotAll() async => {
          for (final c in collections)
            for (final d in (await firestore.collection(c).get()).docs) '$c/${d.id}': d.data(),
        };

    Matcher refusedWith(FeeVoidFailure failure) =>
        throwsA(isA<FeeVoidException>().having((e) => e.failure, 'failure', failure));

    test('normal cancellation voids both sides and keeps the receipt details', () async {
      final receiptId = await collect();
      final income = await linkedIncome(receiptId);
      final before = await doc('fee_receipts/$receiptId');

      expect(await fees.voidReceipt(receiptId, expectedFinanceIncomeId: income.id), FeeVoidOutcome.voided);

      final after = await doc('fee_receipts/$receiptId');
      expect(after['isDeleted'], isTrue);
      for (final key in ['amount', 'receiptNo', 'studentName', 'assignmentId', 'transactionId']) {
        expect(after[key], before[key], reason: key);
      }
      expect((await doc('student_fee_assignments/a1'))['paidAmount'], 0);
      expect((await doc('finance_income/${income.id}'))['isDeleted'], isTrue);
      expect(await cashBalance(), 0);
    });

    test('repeated cancellation is refused and writes nothing', () async {
      final receiptId = await collect();
      await fees.voidReceipt(receiptId);
      final state = await snapshotAll();

      await expectLater(fees.voidReceipt(receiptId), refusedWith(FeeVoidFailure.alreadyVoided));
      expect(await snapshotAll(), state);
      expect(await cashBalance(), 0);
    });

    test('retry after the Finance reversal succeeded but the receipt update failed', () async {
      final receiptId = await collect();
      final income = await linkedIncome(receiptId);
      firestore.failCommitWhen = (path) => path.startsWith('fee_receipts/');

      await expectLater(fees.voidReceipt(receiptId), throwsA(isA<FirebaseException>()));
      // Partial state: Finance reversed, Fees step rolled back as a whole.
      expect((await doc('finance_income/${income.id}'))['isDeleted'], isTrue);
      expect(await cashBalance(), 0);
      expect((await doc('fee_receipts/$receiptId'))['isDeleted'], isNot(true));
      expect((await doc('student_fee_assignments/a1'))['paidAmount'], 4500);

      firestore.failCommitWhen = null;
      expect(await fees.voidReceipt(receiptId), FeeVoidOutcome.voided);
      expect((await doc('fee_receipts/$receiptId'))['isDeleted'], isTrue);
      final assignment = await doc('student_fee_assignments/a1');
      expect(assignment['paidAmount'], 0);
      expect(assignment['balanceAmount'], 20000);
      expect(await cashBalance(), 0, reason: 'Finance must not be reversed a second time');

      await expectLater(fees.voidReceipt(receiptId), refusedWith(FeeVoidFailure.alreadyVoided));
      expect(await cashBalance(), 0);
    });

    test('retry when the receipt is already voided but Finance reversal is incomplete', () async {
      final receiptId = await collect();
      final income = await linkedIncome(receiptId);
      await firestore.doc('fee_receipts/$receiptId').update({'isDeleted': true});
      await firestore.doc('student_fee_assignments/a1').update({'paidAmount': 0, 'balanceAmount': 20000, 'status': 'unpaid'});
      final receiptBefore = await doc('fee_receipts/$receiptId');

      expect(await fees.voidReceipt(receiptId, expectedFinanceIncomeId: income.id), FeeVoidOutcome.financeReconciled);
      expect((await doc('finance_income/${income.id}'))['isDeleted'], isTrue);
      expect((await doc('finance_ledger/${income.data()['ledgerEntryId']}'))['status'], 'cancelled');
      expect(await cashBalance(), 0);
      expect(await doc('fee_receipts/$receiptId'), receiptBefore);
      expect((await doc('student_fee_assignments/a1'))['paidAmount'], 0);

      await expectLater(fees.voidReceipt(receiptId), refusedWith(FeeVoidFailure.alreadyVoided));
      expect(await cashBalance(), 0);
    });

    test('a missing linked Finance record is refused when Finance started the void', () async {
      final receiptId = await collect();
      final income = await linkedIncome(receiptId);
      await firestore.doc('finance_income/${income.id}').delete();
      final state = await snapshotAll();

      await expectLater(
        fees.voidReceipt(receiptId, expectedFinanceIncomeId: income.id),
        refusedWith(FeeVoidFailure.financeMissing),
      );
      expect(await snapshotAll(), state);
    });

    test('a Finance entry other than the one being voided is refused', () async {
      final receiptId = await collect();
      final state = await snapshotAll();
      await expectLater(
        fees.voidReceipt(receiptId, expectedFinanceIncomeId: 'some-other-entry'),
        refusedWith(FeeVoidFailure.financeMismatch),
      );
      expect(await snapshotAll(), state);
    });

    test('a missing receipt is refused with nothing written', () async {
      final state = await snapshotAll();
      await expectLater(fees.voidReceipt('no-such-receipt'), refusedWith(FeeVoidFailure.collectionNotFound));
      expect(await snapshotAll(), state);
    });

    test('concurrent voids never restore or reverse a balance twice', () async {
      final first = await collect();
      await collect(); // second 4500 collection on the same assignment
      expect(await cashBalance(), 9000);
      expect((await doc('student_fee_assignments/a1'))['paidAmount'], 9000);

      final results = await Future.wait([
        fees.voidReceipt(first).then<Object>((o) => o, onError: (Object e) => e),
        fees.voidReceipt(first).then<Object>((o) => o, onError: (Object e) => e),
      ]);
      expect(results.whereType<FeeVoidOutcome>(), [FeeVoidOutcome.voided]);
      expect(results.whereType<FeeVoidException>().single.failure, FeeVoidFailure.alreadyVoided);

      expect(await cashBalance(), 4500);
      final assignment = await doc('student_fee_assignments/a1');
      expect(assignment['paidAmount'], 4500);
      expect(assignment['balanceAmount'], 15500);
    });

    test('Finance entry active but its ledger entry cancelled: refused, nothing written', () async {
      final receiptId = await collect();
      final income = await linkedIncome(receiptId);
      await firestore.doc('finance_ledger/${income.data()['ledgerEntryId']}').update({'status': 'cancelled'});
      final state = await snapshotAll();

      await expectLater(fees.voidReceipt(receiptId), refusedWith(FeeVoidFailure.financeInconsistent));
      expect(await snapshotAll(), state);
      // The Finance reversal itself also refuses this state inside its transaction.
      await expectLater(finance.reverseFeeIncomeByCollectionId(receiptId), throwsStateError);
      expect(await snapshotAll(), state);
    });

    test('Finance entry voided but its ledger entry still active: refused, nothing written', () async {
      final receiptId = await collect();
      final income = await linkedIncome(receiptId);
      await firestore.doc('finance_income/${income.id}').update({'isDeleted': true});
      final state = await snapshotAll();

      await expectLater(fees.voidReceipt(receiptId), refusedWith(FeeVoidFailure.financeInconsistent));
      expect(await snapshotAll(), state);
    });

    test('two Finance entries linked to one collection: refused, nothing written', () async {
      final receiptId = await collect();
      final income = await linkedIncome(receiptId);
      await firestore.collection('finance_income').add({...income.data(), 'title': 'Duplicate'});
      final state = await snapshotAll();

      await expectLater(fees.voidReceipt(receiptId), refusedWith(FeeVoidFailure.financeAmbiguous));
      await expectLater(finance.reverseFeeIncomeByCollectionId(receiptId), throwsStateError);
      expect(await snapshotAll(), state);
    });

    testWidgets('the Finance UI shows the actionable refusal and changes nothing', (tester) async {
      final receiptId = await collect();
      final income = await linkedIncome(receiptId);
      await firestore.doc('finance_ledger/${income.data()['ledgerEntryId']}').update({'status': 'cancelled'});
      final state = await snapshotAll();
      await pumpIncomeTab(tester);

      await tester.tap(find.byTooltip('Void Fee Collection'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Void'));
      await tester.pumpAndSettle();

      expect(find.textContaining('ledger entry is already cancelled'), findsOneWidget);
      expect(find.textContaining('Nothing was changed'), findsOneWidget);
      expect(await snapshotAll(), state);
      expect(find.byTooltip('Void Fee Collection'), findsOneWidget);
    });
  });
}
