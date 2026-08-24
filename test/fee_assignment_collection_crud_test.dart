// P1 coverage for Fee Assignment / Fee Collection Edit and Fee Collection
// Void — previously unavailable (FeeService only had assignFee/
// deleteAssignment and collectFee/deleteReceipt, no update path for either,
// and no status-based void; only a hard "delete" that also happened to be
// a soft-delete under the hood). See FeeService.updateAssignment/
// updateCollection/voidReceipt for the implementation this exercises.
//
// Groups, matching the task's numbered test list:
//  - 'Assignment edit'      — cases 1-5
//  - 'Collection edit'      — cases 6-8
//  - 'Collection void'      — cases 9, 11, 13
//  - 'AdminFeesScreen void UX' — cases 12, 14 (confirmation/cancel/failure
//    feedback, which the pure service layer can't observe)
//  - 'Part E worked example' — the exact 20000/5000+5000/edit-to-7000/void
//    scenario from the task description, end to end
//  - 'Regression'           — cases 15-18
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/fees/services/fee_service.dart';
import 'package:montessori_app/modules/fees/ui/admin_fees_screen.dart';
import 'package:montessori_app/modules/finance/services/finance_service.dart';

/// FinanceService's own constructor eagerly touches
/// FirebaseFirestore.instance when no firestore is supplied, so every
/// stand-in below must be constructed with `firestore:` pointed at the
/// same fake store FeeService uses — never left to its own default.
class _CountingFinanceService extends FinanceService {
  _CountingFinanceService(FirebaseFirestore firestore) : super(firestore: firestore, auth: MockFirebaseAuth());
  int createCalls = 0;
  int reverseCalls = 0;

  @override
  Future<String?> createFeeIncomeEntry(Map<String, dynamic> entry) async {
    createCalls++;
    return 'stub-income-id';
  }

  @override
  Future<void> reverseFeeIncomeByCollectionId(String feeCollectionId) async {
    reverseCalls++;
  }
}

class _ThrowingReverseFinanceService extends FinanceService {
  _ThrowingReverseFinanceService(FirebaseFirestore firestore) : super(firestore: firestore, auth: MockFirebaseAuth());

  @override
  Future<void> reverseFeeIncomeByCollectionId(String feeCollectionId) async {
    throw Exception('finance reversal failed');
  }
}

FeeService _service(FakeFirebaseFirestore firestore, {FinanceService? finance}) => FeeService(
      firestore: firestore,
      auth: MockFirebaseAuth(),
      storage: MockFirebaseStorage(),
      financeService: finance ?? _CountingFinanceService(firestore),
    );

Future<void> _seedClass(FakeFirebaseFirestore firestore, {String id = 'class-1', String name = 'Mont 1'}) async {
  await firestore.collection('classes').doc(id).set({'name': name, 'isActive': true});
}

Future<void> _seedStudent(
  FakeFirebaseFirestore firestore, {
  required String id,
  required String classId,
  String name = 'Student',
  String admissionNo = 'ADM1',
}) async {
  await firestore.collection('students').doc(id).set({
    'name': name,
    'admissionNo': admissionNo,
    'classId': classId,
    'isActive': true,
  });
}

Future<void> _seedStructure(
  FakeFirebaseFirestore firestore, {
  required String id,
  String name = 'Core Fees',
  double totalAmount = 20000,
  bool isActive = true,
}) async {
  await firestore.collection('fee_structures').doc(id).set({
    'name': name,
    'description': '',
    'components': [],
    'totalAmount': totalAmount,
    'academicYear': '2026-2027',
    'isActive': isActive,
    'createdBy': 'test',
    'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
  });
}

Future<void> _seedAssignment(
  FakeFirebaseFirestore firestore, {
  required String id,
  required String studentId,
  required String feeStructureId,
  String classId = 'class-1',
  double totalFee = 20000,
  double discountAmount = 0,
  double paidAmount = 0,
  double? balanceAmount,
  String academicYear = '2026-2027',
}) async {
  final payable = totalFee - discountAmount;
  final balance = balanceAmount ?? (payable - paidAmount);
  final status = balance <= 0 ? 'paid' : paidAmount > 0 ? 'partial' : 'unpaid';
  await firestore.collection('student_fee_assignments').doc(id).set({
    'studentId': studentId,
    'studentName': 'Student $studentId',
    'admissionNo': 'ADM-$studentId',
    'classId': classId,
    'className': 'Mont 1',
    'feeStructureId': feeStructureId,
    'feeStructureName': 'Core Fees',
    'academicYear': academicYear,
    'totalFee': totalFee,
    'discountAmount': discountAmount,
    'payableAmount': payable,
    'paidAmount': paidAmount,
    'balanceAmount': balance,
    'status': status,
    'assignedAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
    'updatedAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
  });
}

/// Seeds a paired fee_transactions + fee_receipts doc directly (the exact
/// shape collectFee's batch writes), the same way the rest of this
/// codebase's fee tests seed fixtures directly rather than going through
/// creation flows with unrelated side effects.
Future<String> _seedCollection(
  FakeFirebaseFirestore firestore, {
  required String receiptId,
  required String assignmentId,
  required String studentId,
  required double amount,
  String paymentMode = 'cash',
  String referenceNo = 'REF1',
  String remarks = '',
  DateTime? paymentDate,
}) async {
  final txId = '$receiptId-tx';
  final date = paymentDate ?? DateTime(2026, 8, 1);
  await firestore.collection('fee_transactions').doc(txId).set({
    'assignmentId': assignmentId,
    'studentId': studentId,
    'studentName': 'Student $studentId',
    'admissionNo': 'ADM-$studentId',
    'classId': 'class-1',
    'className': 'Mont 1',
    'feeStructureId': 'structure-1',
    'feeStructureName': 'Core Fees',
    'amount': amount,
    'paymentDate': Timestamp.fromDate(date),
    'paymentMode': paymentMode,
    'referenceNo': referenceNo,
    'remarks': remarks,
    'collectedBy': 'Admin',
    'createdAt': Timestamp.fromDate(date),
  });
  await firestore.collection('fee_receipts').doc(receiptId).set({
    'receiptNo': 'REC-$receiptId',
    'transactionId': txId,
    'assignmentId': assignmentId,
    'studentId': studentId,
    'studentName': 'Student $studentId',
    'admissionNo': 'ADM-$studentId',
    'className': 'Mont 1',
    'feeStructureName': 'Core Fees',
    'feeStructureId': 'structure-1',
    'amount': amount,
    'paymentMode': paymentMode,
    'paymentDate': Timestamp.fromDate(date),
    'referenceNo': referenceNo,
    'createdAt': Timestamp.fromDate(date),
    'createdBy': 'Admin',
    'pdfUrl': '',
    'pdfPath': '',
    'pdfGeneratedAt': null,
    'isDeleted': false,
  });
  return receiptId;
}

Future<Map<String, dynamic>> _assignmentDoc(FakeFirebaseFirestore firestore, String id) async {
  final snap = await firestore.collection('student_fee_assignments').doc(id).get();
  return snap.data()!;
}

void main() {
  group('Assignment edit', () {
    test('1. Edit an assignment successfully', () async {
      final firestore = FakeFirebaseFirestore();
      await _seedAssignment(firestore, id: 'a1', studentId: 's1', feeStructureId: 'f1');
      final service = _service(firestore);

      await service.updateAssignment('a1', {'academicYear': '2027-2028', 'discountAmount': 2000.0});

      final doc = await _assignmentDoc(firestore, 'a1');
      expect(doc['academicYear'], '2027-2028');
      expect(doc['discountAmount'], 2000.0);
      expect(doc['payableAmount'], 18000.0);
    });

    test('2. Existing collections remain intact after assignment edit', () async {
      final firestore = FakeFirebaseFirestore();
      await _seedAssignment(firestore, id: 'a1', studentId: 's1', feeStructureId: 'f1', paidAmount: 5000, balanceAmount: 15000);
      await _seedCollection(firestore, receiptId: 'r1', assignmentId: 'a1', studentId: 's1', amount: 5000, referenceNo: 'ORIGINAL-REF');
      final service = _service(firestore);

      await service.updateAssignment('a1', {'academicYear': '2027-2028'});

      final receiptSnap = await firestore.collection('fee_receipts').doc('r1').get();
      final txSnap = await firestore.collection('fee_transactions').doc('r1-tx').get();
      expect(receiptSnap.data()!['amount'], 5000.0);
      expect(receiptSnap.data()!['referenceNo'], 'ORIGINAL-REF');
      expect(txSnap.data()!['amount'], 5000.0);
    });

    test('3. Assignment balance remains correct after editing', () async {
      final firestore = FakeFirebaseFirestore();
      await _seedAssignment(firestore, id: 'a1', studentId: 's1', feeStructureId: 'f1', totalFee: 20000, paidAmount: 12000, balanceAmount: 8000);
      final service = _service(firestore);

      await service.updateAssignment('a1', {'discountAmount': 3000.0});

      final doc = await _assignmentDoc(firestore, 'a1');
      // payable = 20000 - 3000 = 17000; paidAmount untouched at 12000.
      expect(doc['payableAmount'], 17000.0);
      expect(doc['paidAmount'], 12000.0);
      expect(doc['balanceAmount'], 5000.0);
      expect(doc['status'], 'partial');
    });

    test('4. Assignment with no collections can be edited (including student/fee structure)', () async {
      final firestore = FakeFirebaseFirestore();
      await _seedClass(firestore);
      await _seedStudent(firestore, id: 's2', classId: 'class-1', name: 'New Student');
      await _seedStructure(firestore, id: 'f2', name: 'Alt Fees', totalAmount: 25000);
      await _seedAssignment(firestore, id: 'a1', studentId: 's1', feeStructureId: 'f1', paidAmount: 0, balanceAmount: 20000);
      final service = _service(firestore);

      await service.updateAssignment('a1', {
        'studentId': 's2',
        'studentName': 'New Student',
        'feeStructureId': 'f2',
        'feeStructureName': 'Alt Fees',
        'totalFee': 25000.0,
      });

      final doc = await _assignmentDoc(firestore, 'a1');
      expect(doc['studentId'], 's2');
      expect(doc['feeStructureId'], 'f2');
      expect(doc['totalFee'], 25000.0);
      expect(doc['payableAmount'], 25000.0);
      expect(doc['balanceAmount'], 25000.0);
    });

    test('5. Assignment with partial payment can be edited safely (identity locked, discount allowed)', () async {
      final firestore = FakeFirebaseFirestore();
      await _seedAssignment(firestore, id: 'a1', studentId: 's1', feeStructureId: 'f1', totalFee: 20000, paidAmount: 5000, balanceAmount: 15000);
      await _seedCollection(firestore, receiptId: 'r1', assignmentId: 'a1', studentId: 's1', amount: 5000);
      final service = _service(firestore);

      // Changing the identity/amount-basis fields is refused once a
      // payment exists.
      await expectLater(
        service.updateAssignment('a1', {'studentId': 's2'}),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        service.updateAssignment('a1', {'feeStructureId': 'f2'}),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        service.updateAssignment('a1', {'totalFee': 30000.0}),
        throwsA(isA<StateError>()),
      );

      // Discount (and other non-identity fields) are still safely editable.
      await service.updateAssignment('a1', {'discountAmount': 1000.0});
      final doc = await _assignmentDoc(firestore, 'a1');
      expect(doc['studentId'], 's1');
      expect(doc['totalFee'], 20000.0);
      expect(doc['payableAmount'], 19000.0);
      expect(doc['paidAmount'], 5000.0);
      expect(doc['balanceAmount'], 14000.0);

      // The collection is still there, completely untouched.
      final receiptSnap = await firestore.collection('fee_receipts').doc('r1').get();
      expect(receiptSnap.data()!['amount'], 5000.0);
      expect(receiptSnap.data()!['isDeleted'], false);
    });
  });

  group('Collection edit', () {
    test('6. Edit a collection successfully', () async {
      final firestore = FakeFirebaseFirestore();
      await _seedAssignment(firestore, id: 'a1', studentId: 's1', feeStructureId: 'f1', totalFee: 20000, paidAmount: 5000, balanceAmount: 15000);
      await _seedCollection(firestore, receiptId: 'r1', assignmentId: 'a1', studentId: 's1', amount: 5000, paymentMode: 'cash', referenceNo: 'OLD-REF');
      final service = _service(firestore);

      await service.updateCollection(
        receiptId: 'r1',
        amount: 6000,
        paymentDate: DateTime(2026, 8, 10),
        paymentMode: 'upi',
        referenceNo: 'NEW-REF',
        remarks: 'corrected amount',
      );

      final receipt = (await firestore.collection('fee_receipts').doc('r1').get()).data()!;
      final tx = (await firestore.collection('fee_transactions').doc('r1-tx').get()).data()!;
      expect(receipt['amount'], 6000.0);
      expect(receipt['paymentMode'], 'upi');
      expect(receipt['referenceNo'], 'NEW-REF');
      expect(tx['amount'], 6000.0);
      expect(tx['remarks'], 'corrected amount');
    });

    test('7. Edited collection updates the assignment balance', () async {
      final firestore = FakeFirebaseFirestore();
      await _seedAssignment(firestore, id: 'a1', studentId: 's1', feeStructureId: 'f1', totalFee: 20000, paidAmount: 5000, balanceAmount: 15000);
      await _seedCollection(firestore, receiptId: 'r1', assignmentId: 'a1', studentId: 's1', amount: 5000);
      final service = _service(firestore);

      await service.updateCollection(
        receiptId: 'r1',
        amount: 8000,
        paymentDate: DateTime(2026, 8, 10),
        paymentMode: 'cash',
        referenceNo: '',
        remarks: '',
      );

      final doc = await _assignmentDoc(firestore, 'a1');
      expect(doc['paidAmount'], 8000.0);
      expect(doc['balanceAmount'], 12000.0);
      expect(doc['status'], 'partial');
    });

    test('8. Multiple collections remain correctly calculated after editing one', () async {
      final firestore = FakeFirebaseFirestore();
      await _seedAssignment(firestore, id: 'a1', studentId: 's1', feeStructureId: 'f1', totalFee: 20000, paidAmount: 10000, balanceAmount: 10000);
      await _seedCollection(firestore, receiptId: 'r1', assignmentId: 'a1', studentId: 's1', amount: 5000);
      await _seedCollection(firestore, receiptId: 'r2', assignmentId: 'a1', studentId: 's1', amount: 5000);
      final service = _service(firestore);

      // Edit second collection 5000 -> 7000 (matches the task's worked
      // example: 20000 total, 5000+5000 collected, edit second to 7000).
      await service.updateCollection(
        receiptId: 'r2',
        amount: 7000,
        paymentDate: DateTime(2026, 8, 10),
        paymentMode: 'cash',
        referenceNo: '',
        remarks: '',
      );

      final assignment = await _assignmentDoc(firestore, 'a1');
      expect(assignment['paidAmount'], 12000.0);
      expect(assignment['balanceAmount'], 8000.0);
      final r1 = (await firestore.collection('fee_receipts').doc('r1').get()).data()!;
      expect(r1['amount'], 5000.0, reason: 'the other collection must be untouched');

      // Editing an amount past the remaining payable is refused.
      await expectLater(
        service.updateCollection(
          receiptId: 'r1',
          amount: 20000,
          paymentDate: DateTime(2026, 8, 10),
          paymentMode: 'cash',
          referenceNo: '',
          remarks: '',
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('Collection void', () {
    test('9. Void a collection successfully', () async {
      final firestore = FakeFirebaseFirestore();
      await _seedAssignment(firestore, id: 'a1', studentId: 's1', feeStructureId: 'f1', totalFee: 20000, paidAmount: 5000, balanceAmount: 15000);
      await _seedCollection(firestore, receiptId: 'r1', assignmentId: 'a1', studentId: 's1', amount: 5000);
      final finance = _CountingFinanceService(firestore);
      final service = _service(firestore, finance: finance);

      await service.voidReceipt('r1');

      final receipt = (await firestore.collection('fee_receipts').doc('r1').get()).data()!;
      expect(receipt['isDeleted'], true);
      expect(finance.reverseCalls, 1);
    });

    test('10. Voided collection no longer contributes to paid amount', () async {
      final firestore = FakeFirebaseFirestore();
      await _seedAssignment(firestore, id: 'a1', studentId: 's1', feeStructureId: 'f1', totalFee: 20000, paidAmount: 5000, balanceAmount: 15000);
      await _seedCollection(firestore, receiptId: 'r1', assignmentId: 'a1', studentId: 's1', amount: 5000);
      final service = _service(firestore);

      await service.voidReceipt('r1');

      final doc = await _assignmentDoc(firestore, 'a1');
      expect(doc['paidAmount'], 0.0);
    });

    test('11. Voided collection causes outstanding balance to recalculate correctly', () async {
      final firestore = FakeFirebaseFirestore();
      await _seedAssignment(firestore, id: 'a1', studentId: 's1', feeStructureId: 'f1', totalFee: 20000, paidAmount: 5000, balanceAmount: 15000);
      await _seedCollection(firestore, receiptId: 'r1', assignmentId: 'a1', studentId: 's1', amount: 5000);
      final service = _service(firestore);

      await service.voidReceipt('r1');

      final doc = await _assignmentDoc(firestore, 'a1');
      expect(doc['balanceAmount'], 20000.0);
      expect(doc['status'], 'unpaid');
    });

    test('13. Voiding one collection does not affect another collection', () async {
      final firestore = FakeFirebaseFirestore();
      await _seedAssignment(firestore, id: 'a1', studentId: 's1', feeStructureId: 'f1', totalFee: 20000, paidAmount: 10000, balanceAmount: 10000);
      await _seedCollection(firestore, receiptId: 'r1', assignmentId: 'a1', studentId: 's1', amount: 5000);
      await _seedCollection(firestore, receiptId: 'r2', assignmentId: 'a1', studentId: 's1', amount: 5000);
      final service = _service(firestore);

      await service.voidReceipt('r1');

      final r2 = (await firestore.collection('fee_receipts').doc('r2').get()).data()!;
      expect(r2['isDeleted'], false);
      expect(r2['amount'], 5000.0);
      final doc = await _assignmentDoc(firestore, 'a1');
      expect(doc['paidAmount'], 5000.0);
      expect(doc['balanceAmount'], 15000.0);

      // Double-voiding the same receipt is refused, not silently re-applied.
      await expectLater(service.voidReceipt('r1'), throwsA(isA<StateError>()));
    });
  });

  group('AdminFeesScreen void UX', () {
    Future<void> pumpScreen(WidgetTester tester, FeeService service) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(child: MaterialApp(home: AdminFeesScreen(service: service))),
      );
      await tester.pumpAndSettle();
      // Receipts tab.
      await tester.tap(find.text('Receipts'));
      await tester.pumpAndSettle();
    }

    testWidgets('12. Canceling the void confirmation leaves the collection unchanged', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedAssignment(firestore, id: 'a1', studentId: 's1', feeStructureId: 'f1', totalFee: 20000, paidAmount: 5000, balanceAmount: 15000);
      await _seedCollection(firestore, receiptId: 'r1', assignmentId: 'a1', studentId: 's1', amount: 5000);
      final service = _service(firestore);
      await pumpScreen(tester, service);

      final menuButton = find.byIcon(Icons.more_vert);
      await tester.ensureVisible(menuButton);
      await tester.tap(menuButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Void'));
      await tester.pumpAndSettle();

      expect(find.text('Void Payment'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      final receipt = (await firestore.collection('fee_receipts').doc('r1').get()).data()!;
      expect(receipt['isDeleted'], false);
      final assignment = await _assignmentDoc(firestore, 'a1');
      expect(assignment['paidAmount'], 5000.0);
    });

    testWidgets(
      '14. Failure during void produces user-visible feedback and does not leave partial/corrupt state',
      (tester) async {
        final firestore = FakeFirebaseFirestore();
        await _seedAssignment(firestore, id: 'a1', studentId: 's1', feeStructureId: 'f1', totalFee: 20000, paidAmount: 5000, balanceAmount: 15000);
        await _seedCollection(firestore, receiptId: 'r1', assignmentId: 'a1', studentId: 's1', amount: 5000);
        final service = _service(firestore, finance: _ThrowingReverseFinanceService(firestore));
        await pumpScreen(tester, service);

        final menuButton = find.byIcon(Icons.more_vert);
        await tester.ensureVisible(menuButton);
        await tester.tap(menuButton);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Void'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Void'));
        await tester.pumpAndSettle();

        expect(find.textContaining('Failed to void payment'), findsOneWidget);
        // Neither the receipt nor the assignment was touched — Finance
        // reversal (which threw) runs before either write.
        final receipt = (await firestore.collection('fee_receipts').doc('r1').get()).data()!;
        expect(receipt['isDeleted'], false);
        final assignment = await _assignmentDoc(firestore, 'a1');
        expect(assignment['paidAmount'], 5000.0);
        expect(assignment['balanceAmount'], 15000.0);
      },
    );
  });

  group('Part E worked example (task-specified numbers)', () {
    test('20000 total, 5000+5000 collected, edit second to 7000, then void it', () async {
      final firestore = FakeFirebaseFirestore();
      await _seedAssignment(firestore, id: 'a1', studentId: 's1', feeStructureId: 'f1', totalFee: 20000);
      final service = _service(firestore);

      // Two 5000 collections -> paid 10000, outstanding 10000.
      await _seedCollection(firestore, receiptId: 'r1', assignmentId: 'a1', studentId: 's1', amount: 5000);
      await _seedCollection(firestore, receiptId: 'r2', assignmentId: 'a1', studentId: 's1', amount: 5000);
      await firestore.collection('student_fee_assignments').doc('a1').set(
        {'paidAmount': 10000.0, 'balanceAmount': 10000.0, 'status': 'partial'},
        SetOptions(merge: true),
      );
      var doc = await _assignmentDoc(firestore, 'a1');
      expect(doc['balanceAmount'], 10000.0);

      // Edit second collection 5000 -> 7000: outstanding becomes 8000.
      await service.updateCollection(
        receiptId: 'r2',
        amount: 7000,
        paymentDate: DateTime(2026, 8, 10),
        paymentMode: 'cash',
        referenceNo: '',
        remarks: '',
      );
      doc = await _assignmentDoc(firestore, 'a1');
      expect(doc['paidAmount'], 12000.0);
      expect(doc['balanceAmount'], 8000.0);

      // Void that 7000 collection: outstanding becomes 15000.
      await service.voidReceipt('r2');
      doc = await _assignmentDoc(firestore, 'a1');
      expect(doc['paidAmount'], 5000.0);
      expect(doc['balanceAmount'], 15000.0);

      // The untouched 5000 collection (r1) is still valid.
      final r1 = (await firestore.collection('fee_receipts').doc('r1').get()).data()!;
      expect(r1['isDeleted'], false);
      expect(r1['amount'], 5000.0);
    });
  });

  group('Regression', () {
    test('15. Existing fee assignment creation (assignFee) still works', () async {
      final firestore = FakeFirebaseFirestore();
      await _seedClass(firestore);
      await _seedStudent(firestore, id: 's1', classId: 'class-1');
      final service = _service(firestore);

      final id = await service.assignFee({
        'studentId': 's1',
        'studentName': 'Student s1',
        'admissionNo': 'ADM-s1',
        'classId': 'class-1',
        'className': 'Mont 1',
        'feeStructureId': 'f1',
        'feeStructureName': 'Core Fees',
        'academicYear': '2026-2027',
        'totalFee': 20000.0,
        'discountAmount': 0.0,
        'payableAmount': 20000.0,
        'paidAmount': 0.0,
        'balanceAmount': 20000.0,
        'status': 'unpaid',
      });

      expect(id, isNotNull);
      final doc = await _assignmentDoc(firestore, id!);
      expect(doc['studentId'], 's1');
      expect(doc['balanceAmount'], 20000.0);

      // Duplicate (same student/structure/year) is refused, unchanged.
      final dup = await service.assignFee({
        'studentId': 's1',
        'feeStructureId': 'f1',
        'academicYear': '2026-2027',
      });
      expect(dup, isNull);
    });

    test('16. Existing collection creation (collectFee) still works', () async {
      final firestore = FakeFirebaseFirestore();
      await _seedAssignment(firestore, id: 'a1', studentId: 's1', feeStructureId: 'f1', totalFee: 20000);
      final finance = _CountingFinanceService(firestore);
      final service = _service(firestore, finance: finance);

      final receipt = await service.collectFee(
        assignmentId: 'a1',
        amount: 5000,
        paymentDate: DateTime(2026, 8, 1),
        paymentMode: 'cash',
        referenceNo: 'REF-NEW',
        remarks: '',
      );

      expect(receipt.amount, 5000.0);
      final doc = await _assignmentDoc(firestore, 'a1');
      expect(doc['paidAmount'], 5000.0);
      expect(doc['balanceAmount'], 15000.0);
      expect(finance.createCalls, 1, reason: 'collectFee must still record a Finance income entry');
    });

    test('17. Parent fee summary (getAssignmentsForStudent) reflects corrected data after edit + void', () async {
      final firestore = FakeFirebaseFirestore();
      await _seedAssignment(firestore, id: 'a1', studentId: 'parent-child', feeStructureId: 'f1', totalFee: 20000);
      await _seedCollection(firestore, receiptId: 'r1', assignmentId: 'a1', studentId: 'parent-child', amount: 5000);
      await _seedCollection(firestore, receiptId: 'r2', assignmentId: 'a1', studentId: 'parent-child', amount: 5000);
      await firestore.collection('student_fee_assignments').doc('a1').set(
        {'paidAmount': 10000.0, 'balanceAmount': 10000.0, 'status': 'partial'},
        SetOptions(merge: true),
      );
      final service = _service(firestore);
      await service.updateCollection(
        receiptId: 'r2',
        amount: 7000,
        paymentDate: DateTime(2026, 8, 10),
        paymentMode: 'cash',
        referenceNo: '',
        remarks: '',
      );
      await service.voidReceipt('r2');

      // This is exactly parent_dashboard.dart's own data source
      // (FeeService.getAssignmentsForStudent) — Total/Paid/Due read
      // straight off these fields with no separate parent-side
      // calculation, so this proves the Parent Dashboard sees corrected
      // values.
      final assignments = await service.getAssignmentsForStudent('parent-child');
      expect(assignments, hasLength(1));
      final a = assignments.single;
      expect(a.payableAmount, 20000.0, reason: 'Total fee');
      expect(a.paidAmount, 5000.0, reason: 'Paid');
      expect(a.balanceAmount, 15000.0, reason: 'Due / Outstanding');
    });

    test('18. Existing fee dashboard summary (getDashboardSummary) remains correct', () async {
      final firestore = FakeFirebaseFirestore();
      await _seedAssignment(firestore, id: 'a1', studentId: 's1', feeStructureId: 'f1', totalFee: 20000, paidAmount: 5000, balanceAmount: 15000);
      await _seedAssignment(firestore, id: 'a2', studentId: 's2', feeStructureId: 'f1', totalFee: 10000, paidAmount: 10000, balanceAmount: 0);
      await _seedCollection(firestore, receiptId: 'r1', assignmentId: 'a1', studentId: 's1', amount: 5000);
      final service = _service(firestore);

      final summary = await service.getDashboardSummary();

      expect(summary['totalExpected'], 30000.0);
      expect(summary['totalCollected'], 15000.0);
      expect(summary['outstanding'], 15000.0);

      // Void the one collection and re-check the summary reflects it.
      await service.voidReceipt('r1');
      final after = await service.getDashboardSummary();
      expect(after['totalCollected'], 10000.0);
      expect(after['outstanding'], 20000.0);
    });
  });
}
