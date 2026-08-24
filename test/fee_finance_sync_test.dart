// P1 coverage for Fee Collection <-> Finance Income synchronization.
//
// Root cause this exercises: FeeService.updateCollection (added in the
// prior Fees CRUD task) correctly updated the Fees-side records but never
// touched the linked Finance income entry, because FinanceService had no
// "update by amount" method and createFeeIncomeEntry's dedup-by-sourceId
// guard made a naive reverse+recreate a no-op. FinanceService now has
// updateFeeIncomeEntry, an in-place field update on the SAME income doc
// found via the exact sourceModule=='fees'+sourceId relationship
// createFeeIncomeEntry/reverseFeeIncomeByCollectionId already use — no new
// relationship, no duplicate entries, no changed dedup logic.
//
// Voiding (FeeService.voidReceipt) already called
// FinanceService.reverseFeeIncomeByCollectionId correctly before this
// task; these tests confirm that path still works unchanged and interacts
// correctly with the new Edit sync (an edited-then-voided collection ends
// up in the exact state a never-edited voided collection would).
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/fees/services/fee_service.dart';
import 'package:montessori_app/modules/finance/services/finance_service.dart';

Future<void> _seedClass(FakeFirebaseFirestore firestore, {String id = 'class-1'}) async {
  await firestore.collection('classes').doc(id).set({'name': 'Mont 1', 'isActive': true});
}

Future<void> _seedStudent(FakeFirebaseFirestore firestore, {required String id, String classId = 'class-1'}) async {
  await firestore.collection('students').doc(id).set({
    'name': 'Student $id',
    'admissionNo': 'ADM-$id',
    'classId': classId,
    'isActive': true,
  });
}

Future<void> _seedAssignment(
  FakeFirebaseFirestore firestore, {
  required String id,
  required String studentId,
  double totalFee = 20000,
  double paidAmount = 0,
}) async {
  final balance = totalFee - paidAmount;
  await firestore.collection('student_fee_assignments').doc(id).set({
    'studentId': studentId,
    'studentName': 'Student $studentId',
    'admissionNo': 'ADM-$studentId',
    'classId': 'class-1',
    'className': 'Mont 1',
    'feeStructureId': 'structure-1',
    'feeStructureName': 'Core Fees',
    'academicYear': '2026-2027',
    'totalFee': totalFee,
    'discountAmount': 0,
    'payableAmount': totalFee,
    'paidAmount': paidAmount,
    'balanceAmount': balance,
    'status': balance <= 0 ? 'paid' : paidAmount > 0 ? 'partial' : 'unpaid',
    'assignedAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
    'updatedAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
  });
}

class _Services {
  _Services(this.firestore, this.fee, this.finance);
  final FakeFirebaseFirestore firestore;
  final FeeService fee;
  final FinanceService finance;
}

Future<_Services> _setup() async {
  final firestore = FakeFirebaseFirestore();
  final auth = MockFirebaseAuth();
  final finance = FinanceService(firestore: firestore, auth: auth);
  await finance.ensureDefaults();
  final fee = FeeService(
    firestore: firestore,
    auth: auth,
    storage: MockFirebaseStorage(),
    financeService: finance,
  );
  await _seedClass(firestore);
  return _Services(firestore, fee, finance);
}

Future<Map<String, dynamic>?> _linkedIncomeDoc(FakeFirebaseFirestore firestore, String feeCollectionId) async {
  final snap = await firestore
      .collection('finance_income')
      .where('sourceModule', isEqualTo: 'fees')
      .where('sourceId', isEqualTo: feeCollectionId)
      .limit(1)
      .get();
  return snap.docs.isEmpty ? null : snap.docs.first.data();
}

void main() {
  group('Fee -> Finance', () {
    test('11. Fee collection creates the expected Finance income', () async {
      final s = await _setup();
      await _seedStudent(s.firestore, id: 's1');
      await _seedAssignment(s.firestore, id: 'a1', studentId: 's1', totalFee: 20000);

      final receipt = await s.fee.collectFee(
        assignmentId: 'a1',
        amount: 5000,
        paymentDate: DateTime(2026, 8, 1),
        paymentMode: 'cash',
        referenceNo: 'REF-1',
        remarks: 'first payment',
      );

      final income = await _linkedIncomeDoc(s.firestore, receipt.id);
      expect(income, isNotNull);
      expect(income!['amount'], 5000.0);
      expect(income['sourceModule'], 'fees');
      expect(income['sourceId'], receipt.id);
      final summary = await s.finance.watchDashboardSummary().first;
      expect(summary.totalIncome, 5000.0);
    });

    test('12. Editing a Fee Collection updates the linked Finance income', () async {
      final s = await _setup();
      await _seedStudent(s.firestore, id: 's1');
      await _seedAssignment(s.firestore, id: 'a1', studentId: 's1', totalFee: 20000);
      final receipt = await s.fee.collectFee(
        assignmentId: 'a1',
        amount: 5000,
        paymentDate: DateTime(2026, 8, 1),
        paymentMode: 'cash',
        referenceNo: 'REF-1',
        remarks: 'first payment',
      );

      await s.fee.updateCollection(
        receiptId: receipt.id,
        amount: 7000,
        paymentDate: DateTime(2026, 8, 10),
        paymentMode: 'upi',
        referenceNo: 'REF-2',
        remarks: 'corrected',
      );

      final income = await _linkedIncomeDoc(s.firestore, receipt.id);
      expect(income!['amount'], 7000.0);
      expect(income['paymentMode'], 'upi');
      expect(income['referenceNo'], 'REF-2');
      expect(income['remarks'], 'corrected');
      final summary = await s.finance.watchDashboardSummary().first;
      expect(summary.totalIncome, 7000.0);
    });

    test('13. Editing a Fee Collection does not create a duplicate Finance income', () async {
      final s = await _setup();
      await _seedStudent(s.firestore, id: 's1');
      await _seedAssignment(s.firestore, id: 'a1', studentId: 's1', totalFee: 20000);
      final receipt = await s.fee.collectFee(
        assignmentId: 'a1',
        amount: 5000,
        paymentDate: DateTime(2026, 8, 1),
        paymentMode: 'cash',
        referenceNo: '',
        remarks: '',
      );

      await s.fee.updateCollection(
        receiptId: receipt.id,
        amount: 6000,
        paymentDate: DateTime(2026, 8, 10),
        paymentMode: 'cash',
        referenceNo: '',
        remarks: '',
      );
      await s.fee.updateCollection(
        receiptId: receipt.id,
        amount: 6500,
        paymentDate: DateTime(2026, 8, 12),
        paymentMode: 'cash',
        referenceNo: '',
        remarks: '',
      );

      final snap = await s.firestore
          .collection('finance_income')
          .where('sourceModule', isEqualTo: 'fees')
          .where('sourceId', isEqualTo: receipt.id)
          .get();
      expect(snap.docs, hasLength(1));
      expect(snap.docs.single.data()['amount'], 6500.0);
    });

    test('14. Voiding a Fee Collection reverses/voids the linked Finance income', () async {
      final s = await _setup();
      await _seedStudent(s.firestore, id: 's1');
      await _seedAssignment(s.firestore, id: 'a1', studentId: 's1', totalFee: 20000);
      final receipt = await s.fee.collectFee(
        assignmentId: 'a1',
        amount: 5000,
        paymentDate: DateTime(2026, 8, 1),
        paymentMode: 'cash',
        referenceNo: '',
        remarks: '',
      );

      await s.fee.voidReceipt(receipt.id);

      final income = await _linkedIncomeDoc(s.firestore, receipt.id);
      expect(income!['isDeleted'], true);
      final summary = await s.finance.watchDashboardSummary().first;
      expect(summary.totalIncome, 0.0);
    });

    test('15. Voiding a Fee Collection does not create duplicate reversals', () async {
      final s = await _setup();
      await _seedStudent(s.firestore, id: 's1');
      await _seedAssignment(s.firestore, id: 'a1', studentId: 's1', totalFee: 20000);
      final receipt = await s.fee.collectFee(
        assignmentId: 'a1',
        amount: 5000,
        paymentDate: DateTime(2026, 8, 1),
        paymentMode: 'cash',
        referenceNo: '',
        remarks: '',
      );
      final accountsBefore = await s.finance.watchAccounts().first;
      final cashBefore = accountsBefore.firstWhere((a) => a.type == 'cash').currentBalance;
      expect(cashBefore, 5000.0);

      await s.fee.voidReceipt(receipt.id);
      // A second void attempt is refused by FeeService's own guard —
      // proving the account balance is never reversed twice.
      await expectLater(s.fee.voidReceipt(receipt.id), throwsA(isA<StateError>()));

      final accountsAfter = await s.finance.watchAccounts().first;
      final cashAfter = accountsAfter.firstWhere((a) => a.type == 'cash').currentBalance;
      expect(cashAfter, 0.0, reason: 'exactly one reversal of 5000, not two');
    });

    test('16. Multiple collections remain correctly represented in Finance', () async {
      final s = await _setup();
      await _seedStudent(s.firestore, id: 's1');
      await _seedAssignment(s.firestore, id: 'a1', studentId: 's1', totalFee: 20000);
      final r1 = await s.fee.collectFee(
        assignmentId: 'a1',
        amount: 5000,
        paymentDate: DateTime(2026, 8, 1),
        paymentMode: 'cash',
        referenceNo: '',
        remarks: '',
      );
      final r2 = await s.fee.collectFee(
        assignmentId: 'a1',
        amount: 5000,
        paymentDate: DateTime(2026, 8, 5),
        paymentMode: 'upi',
        referenceNo: '',
        remarks: '',
      );

      final income1 = await _linkedIncomeDoc(s.firestore, r1.id);
      final income2 = await _linkedIncomeDoc(s.firestore, r2.id);
      expect(income1!['amount'], 5000.0);
      expect(income2!['amount'], 5000.0);
      expect(income1['sourceId'], isNot(income2['sourceId']));
      final summary = await s.finance.watchDashboardSummary().first;
      expect(summary.totalIncome, 10000.0);
    });

    test('17. Editing one collection does not affect the Finance entry for another', () async {
      final s = await _setup();
      await _seedStudent(s.firestore, id: 's1');
      await _seedAssignment(s.firestore, id: 'a1', studentId: 's1', totalFee: 20000);
      final r1 = await s.fee.collectFee(
        assignmentId: 'a1',
        amount: 5000,
        paymentDate: DateTime(2026, 8, 1),
        paymentMode: 'cash',
        referenceNo: '',
        remarks: '',
      );
      final r2 = await s.fee.collectFee(
        assignmentId: 'a1',
        amount: 5000,
        paymentDate: DateTime(2026, 8, 5),
        paymentMode: 'cash',
        referenceNo: '',
        remarks: '',
      );

      await s.fee.updateCollection(
        receiptId: r2.id,
        amount: 7000,
        paymentDate: DateTime(2026, 8, 6),
        paymentMode: 'cash',
        referenceNo: '',
        remarks: '',
      );

      final income1 = await _linkedIncomeDoc(s.firestore, r1.id);
      final income2 = await _linkedIncomeDoc(s.firestore, r2.id);
      expect(income1!['amount'], 5000.0, reason: 'untouched');
      expect(income2!['amount'], 7000.0);
    });
  });

  group('Regression', () {
    test('21. Fee Assignment balance remains correct after an edit that also syncs Finance', () async {
      final s = await _setup();
      await _seedStudent(s.firestore, id: 's1');
      await _seedAssignment(s.firestore, id: 'a1', studentId: 's1', totalFee: 20000);
      final receipt = await s.fee.collectFee(
        assignmentId: 'a1',
        amount: 5000,
        paymentDate: DateTime(2026, 8, 1),
        paymentMode: 'cash',
        referenceNo: '',
        remarks: '',
      );

      await s.fee.updateCollection(
        receiptId: receipt.id,
        amount: 8000,
        paymentDate: DateTime(2026, 8, 10),
        paymentMode: 'cash',
        referenceNo: '',
        remarks: '',
      );

      final assignmentDoc = await s.firestore.collection('student_fee_assignments').doc('a1').get();
      expect(assignmentDoc.data()!['paidAmount'], 8000.0);
      expect(assignmentDoc.data()!['balanceAmount'], 12000.0);
    });

    test('22. Parent Dashboard fee totals (getAssignmentsForStudent) remain correct through edit + void', () async {
      final s = await _setup();
      await _seedStudent(s.firestore, id: 'parent-child');
      await _seedAssignment(s.firestore, id: 'a1', studentId: 'parent-child', totalFee: 20000);
      final r1 = await s.fee.collectFee(
        assignmentId: 'a1',
        amount: 5000,
        paymentDate: DateTime(2026, 8, 1),
        paymentMode: 'cash',
        referenceNo: '',
        remarks: '',
      );
      final r2 = await s.fee.collectFee(
        assignmentId: 'a1',
        amount: 5000,
        paymentDate: DateTime(2026, 8, 5),
        paymentMode: 'cash',
        referenceNo: '',
        remarks: '',
      );
      await s.fee.updateCollection(
        receiptId: r2.id,
        amount: 7000,
        paymentDate: DateTime(2026, 8, 6),
        paymentMode: 'cash',
        referenceNo: '',
        remarks: '',
      );
      await s.fee.voidReceipt(r2.id);

      final assignments = await s.fee.getAssignmentsForStudent('parent-child');
      expect(assignments, hasLength(1));
      final a = assignments.single;
      expect(a.payableAmount, 20000.0, reason: 'Total fee');
      expect(a.paidAmount, 5000.0, reason: 'Paid (only r1 remains active)');
      expect(a.balanceAmount, 15000.0, reason: 'Due / Outstanding');

      // And Finance agrees: only r1's income is active.
      final income1 = await _linkedIncomeDoc(s.firestore, r1.id);
      final income2 = await _linkedIncomeDoc(s.firestore, r2.id);
      expect(income1!['isDeleted'], isNot(true));
      expect(income2!['isDeleted'], true);
      final summary = await s.finance.watchDashboardSummary().first;
      expect(summary.totalIncome, 5000.0);
    });
  });

  group('Atomicity / partial-failure handling', () {
    test(
      'a Finance sync failure during collection edit surfaces distinctly and leaves the Fees-side correction intact',
      () async {
        final s = await _setup();
        await _seedStudent(s.firestore, id: 's1');
        await _seedAssignment(s.firestore, id: 'a1', studentId: 's1', totalFee: 20000);
        final receipt = await s.fee.collectFee(
          assignmentId: 'a1',
          amount: 5000,
          paymentDate: DateTime(2026, 8, 1),
          paymentMode: 'cash',
          referenceNo: '',
          remarks: '',
        );
        final throwingFinance = _ThrowingSyncFinanceService(s.firestore);
        final feeWithBrokenFinance = FeeService(
          firestore: s.firestore,
          auth: MockFirebaseAuth(),
          storage: MockFirebaseStorage(),
          financeService: throwingFinance,
        );

        await expectLater(
          feeWithBrokenFinance.updateCollection(
            receiptId: receipt.id,
            amount: 8000,
            paymentDate: DateTime(2026, 8, 10),
            paymentMode: 'cash',
            referenceNo: '',
            remarks: '',
          ),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('linked Finance record could not be synced'),
            ),
          ),
        );

        // The Fees-side write already committed before the Finance call —
        // it is not rolled back (see updateCollection's doc comment).
        final receiptDoc = await s.firestore.collection('fee_receipts').doc(receipt.id).get();
        expect(receiptDoc.data()!['amount'], 8000.0);
        final assignmentDoc = await s.firestore.collection('student_fee_assignments').doc('a1').get();
        expect(assignmentDoc.data()!['paidAmount'], 8000.0);
      },
    );
  });
}

class _ThrowingSyncFinanceService extends FinanceService {
  _ThrowingSyncFinanceService(FirebaseFirestore firestore) : super(firestore: firestore, auth: MockFirebaseAuth());

  @override
  Future<void> updateFeeIncomeEntry({
    required String feeCollectionId,
    required double amount,
    required DateTime date,
    required String paymentMode,
    required String referenceNo,
    required String remarks,
  }) async {
    throw Exception('finance transaction failed');
  }
}
