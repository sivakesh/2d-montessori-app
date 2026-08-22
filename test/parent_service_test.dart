// Regression coverage for ParentService.getLinkedStudents — the single
// choke point every Parent-facing read (Child Profile, Attendance History,
// today's attendance, fees) goes through to resolve "which students belong
// to this parent". Phase C (Child Profile + Attendance History) relies on
// this already being correctly scoped; these tests prove Parent A can never
// resolve a student only linked to a different parent (Test 2 from the
// Phase C plan) and that a parent with no links gets an empty list rather
// than an error (Test 6 — the zero-children case).
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/parent/data/parent_service.dart';

Future<void> _seedStudent(
  FakeFirebaseFirestore firestore,
  String id, {
  required String name,
  bool isActive = true,
}) async {
  await firestore.collection('students').doc(id).set({
    'name': name,
    'admissionNo': 'ADM-$id',
    'classId': 'class-1',
    'section': 'A',
    'isActive': isActive,
    'isApproved': true,
  });
}

Future<void> _seedLink(
  FakeFirebaseFirestore firestore, {
  required String userId,
  required String studentId,
}) async {
  await firestore.collection('user_student_links').add({
    'userId': userId,
    'studentId': studentId,
  });
}

void main() {
  group('ParentService.getLinkedStudents', () {
    test('Test 2 — Parent A cannot resolve a student only linked to Parent B', () async {
      final firestore = FakeFirebaseFirestore();
      await _seedStudent(firestore, 'child-a', name: 'Child A');
      await _seedStudent(firestore, 'student-c', name: 'Student C');
      await _seedLink(firestore, userId: 'parent-a', studentId: 'child-a');
      await _seedLink(firestore, userId: 'parent-b', studentId: 'student-c');
      final service = ParentService(firestore: firestore);

      final result = await service.getLinkedStudents('parent-a');

      expect(result.map((s) => s.id), ['child-a']);
      expect(result.map((s) => s.id), isNot(contains('student-c')));
    });

    test('returns both linked children when a parent has more than one', () async {
      final firestore = FakeFirebaseFirestore();
      await _seedStudent(firestore, 'child-a', name: 'Child A');
      await _seedStudent(firestore, 'child-b', name: 'Child B');
      await _seedLink(firestore, userId: 'parent-a', studentId: 'child-a');
      await _seedLink(firestore, userId: 'parent-a', studentId: 'child-b');
      final service = ParentService(firestore: firestore);

      final result = await service.getLinkedStudents('parent-a');

      expect(result.map((s) => s.id).toSet(), {'child-a', 'child-b'});
    });

    test('Test 6 — a parent with no links resolves to an empty list, not an error', () async {
      final firestore = FakeFirebaseFirestore();
      final service = ParentService(firestore: firestore);

      final result = await service.getLinkedStudents('parent-with-no-children');

      expect(result, isEmpty);
    });

    test('excludes an inactive (soft-deleted) linked student', () async {
      final firestore = FakeFirebaseFirestore();
      await _seedStudent(firestore, 'child-a', name: 'Child A', isActive: false);
      await _seedLink(firestore, userId: 'parent-a', studentId: 'child-a');
      final service = ParentService(firestore: firestore);

      final result = await service.getLinkedStudents('parent-a');

      expect(result, isEmpty);
    });
  });
}
