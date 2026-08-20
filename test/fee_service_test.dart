// Regression coverage for the "Pending Fees" data path used by the Admin
// Dashboard KPI. The dashboard previously queried nonexistent collections
// ('fees', 'fee_collections', 'student_fees') and always returned 0; it now
// reuses FeeService.getAssignments() and counts assignments with an
// outstanding balance, matching the Fees module's own Dues/Collections
// tabs. This test exercises that exact call path against an in-memory
// Firestore.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/fees/services/fee_service.dart';

Future<void> _seedAssignment(
  FakeFirebaseFirestore firestore, {
  required String id,
  required double balanceAmount,
  required String status,
  bool isDeleted = false,
}) async {
  await firestore.collection('student_fee_assignments').doc(id).set({
    'studentId': 'student-$id',
    'studentName': 'Student $id',
    'admissionNo': 'ADM$id',
    'classId': 'class-1',
    'className': 'Mont 1',
    'feeStructureId': 'structure-1',
    'feeStructureName': 'Core Fees',
    'academicYear': '2026-2027',
    'totalFee': 30000,
    'discountAmount': 0,
    'payableAmount': 30000,
    'paidAmount': 30000 - balanceAmount,
    'balanceAmount': balanceAmount,
    'status': status,
    'isDeleted': isDeleted,
    'assignedAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  });
}

void main() {
  late FakeFirebaseFirestore firestore;
  late FeeService service;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    service = FeeService(
      firestore: firestore,
      auth: MockFirebaseAuth(),
      storage: MockFirebaseStorage(),
    );
  });

  test('pending-fees count matches assignments with an outstanding balance', () async {
    await _seedAssignment(firestore, id: 'a1', balanceAmount: 30000, status: 'unpaid');
    await _seedAssignment(firestore, id: 'a2', balanceAmount: 12000, status: 'partial');
    await _seedAssignment(firestore, id: 'a3', balanceAmount: 0, status: 'paid');
    await _seedAssignment(firestore, id: 'a4', balanceAmount: 0, status: 'paid');

    final assignments = await service.getAssignments();
    final pending = assignments.where((a) => a.balanceAmount > 0).length;

    expect(assignments, hasLength(4));
    expect(pending, 2);
  });

  test('soft-deleted assignments are excluded from the pending-fees count', () async {
    await _seedAssignment(firestore, id: 'a1', balanceAmount: 30000, status: 'unpaid');
    await _seedAssignment(firestore, id: 'a2', balanceAmount: 15000, status: 'unpaid', isDeleted: true);

    final assignments = await service.getAssignments();
    final pending = assignments.where((a) => a.balanceAmount > 0).length;

    expect(assignments, hasLength(1));
    expect(pending, 1);
  });

  test('no outstanding assignments yields zero pending fees, not an error', () async {
    await _seedAssignment(firestore, id: 'a1', balanceAmount: 0, status: 'paid');

    final assignments = await service.getAssignments();
    final pending = assignments.where((a) => a.balanceAmount > 0).length;

    expect(pending, 0);
  });
}
