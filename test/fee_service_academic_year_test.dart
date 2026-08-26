// FEES-AY-IMPLEMENT-01 coverage: FeeService's compatibility-aware
// academicYearId/academicYear duplicate-detection transition (assignFee,
// updateAssignment, syncAssignmentsForFeeStructure, bulkAssignClassFees —
// see FeeService._hasDuplicateAssignment/_findExistingAssignment's own doc
// comments for the exact rule), plus historical-safety proof that a Fee
// Assignment's academic year is never re-derived from Student.classId,
// StudentEnrollment, or Class once set.
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/admin/settings/data/academic_year_service.dart';
import 'package:montessori_app/modules/admin/settings/models/school_settings_model.dart';
import 'package:montessori_app/modules/admin/students/data/student_enrollment_service.dart';
import 'package:montessori_app/modules/fees/services/fee_service.dart';

FeeService _service(FakeFirebaseFirestore firestore) => FeeService(
      firestore: firestore,
      auth: MockFirebaseAuth(),
      storage: MockFirebaseStorage(),
    );

Future<void> _seedStudent(FakeFirebaseFirestore firestore, {required String id, required String classId, String name = 'Student'}) {
  return firestore.collection('students').doc(id).set({
    'name': name,
    'admissionNo': 'ADM-$id',
    'classId': classId,
    'isActive': true,
  });
}

Future<void> _seedClass(FakeFirebaseFirestore firestore, {required String id, String name = 'Mont 1'}) {
  return firestore.collection('classes').doc(id).set({'name': name, 'isActive': true});
}

Map<String, dynamic> _assignmentPayload({
  required String studentId,
  required String feeStructureId,
  String? academicYearId,
  required String academicYear,
  String classId = 'class-1',
  double totalFee = 20000,
}) {
  return {
    'studentId': studentId,
    'studentName': 'Student $studentId',
    'admissionNo': 'ADM-$studentId',
    'classId': classId,
    'className': 'Mont 1',
    'feeStructureId': feeStructureId,
    'feeStructureName': 'Core Fees',
    if (academicYearId != null) 'academicYearId': academicYearId,
    'academicYear': academicYear,
    'totalFee': totalFee,
    'discountAmount': 0.0,
    'payableAmount': totalFee,
    'paidAmount': 0.0,
    'balanceAmount': totalFee,
    'status': 'unpaid',
  };
}

void main() {
  group('FeeService — duplicate detection compatibility (FEES-AY-IMPLEMENT-01)', () {
    test('21. Creating an assignment stores academicYearId alongside academicYear', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);

      final id = await service.assignFee(_assignmentPayload(
        studentId: 's1',
        feeStructureId: 'f1',
        academicYearId: 'ay-2026',
        academicYear: '2026-2027',
      ));

      expect(id, isNotNull);
      final doc = (await firestore.collection('student_fee_assignments').doc(id!).get()).data()!;
      expect(doc['academicYearId'], 'ay-2026');
      expect(doc['academicYear'], '2026-2027');
    });

    test('22. Canonical duplicate detection: two academicYearId-carrying assignments for the same (student, structure, year) collide', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);

      final first = await service.assignFee(_assignmentPayload(
        studentId: 's1',
        feeStructureId: 'f1',
        academicYearId: 'ay-2026',
        academicYear: '2026-2027',
      ));
      expect(first, isNotNull);

      final dup = await service.assignFee(_assignmentPayload(
        studentId: 's1',
        feeStructureId: 'f1',
        academicYearId: 'ay-2026',
        academicYear: '2026-2027',
      ));
      expect(dup, isNull);
    });

    test('23. Legacy duplicate detection: two academicYearId-less assignments for the same string year collide', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);

      final first = await service.assignFee(_assignmentPayload(
        studentId: 's1',
        feeStructureId: 'f1',
        academicYear: '2026-2027',
      ));
      expect(first, isNotNull);

      final dup = await service.assignFee(_assignmentPayload(
        studentId: 's1',
        feeStructureId: 'f1',
        academicYear: '2026-2027',
      ));
      expect(dup, isNull);
    });

    test('24. Canonical-vs-legacy: a new (id-carrying) assignment is rejected as a duplicate of an existing legacy (id-less) one', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);

      // A pre-existing legacy assignment, created before this task (no
      // academicYearId at all).
      final legacy = await service.assignFee(_assignmentPayload(
        studentId: 's1',
        feeStructureId: 'f1',
        academicYear: '2026-2027',
      ));
      expect(legacy, isNotNull);

      // A new attempt now supplies the canonical id — must still be caught
      // as a duplicate via the shared `academicYear` string, since an
      // id-only query would never find the legacy document.
      final dup = await service.assignFee(_assignmentPayload(
        studentId: 's1',
        feeStructureId: 'f1',
        academicYearId: 'ay-2026',
        academicYear: '2026-2027',
      ));
      expect(dup, isNull, reason: 'a duplicate must never slip through because one record is legacy and the other canonical');
    });

    test('Reverse direction: a legacy-shaped attempt is rejected as a duplicate of an existing canonical one', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);

      final canonical = await service.assignFee(_assignmentPayload(
        studentId: 's1',
        feeStructureId: 'f1',
        academicYearId: 'ay-2026',
        academicYear: '2026-2027',
      ));
      expect(canonical, isNotNull);

      final dup = await service.assignFee(_assignmentPayload(
        studentId: 's1',
        feeStructureId: 'f1',
        academicYear: '2026-2027',
      ));
      expect(dup, isNull);
    });

    test('Different academic years for the same student/structure are never treated as duplicates', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);

      final first = await service.assignFee(_assignmentPayload(
        studentId: 's1',
        feeStructureId: 'f1',
        academicYearId: 'ay-2025',
        academicYear: '2025-2026',
      ));
      final second = await service.assignFee(_assignmentPayload(
        studentId: 's1',
        feeStructureId: 'f1',
        academicYearId: 'ay-2026',
        academicYear: '2026-2027',
      ));

      expect(first, isNotNull);
      expect(second, isNotNull, reason: 'a genuinely different year is never a duplicate');
    });

    test('25. updateAssignment refuses to introduce a duplicate when reassigning to an already-taken (student, structure, year)', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);

      final existingId = await service.assignFee(_assignmentPayload(
        studentId: 's2',
        feeStructureId: 'f1',
        academicYearId: 'ay-2026',
        academicYear: '2026-2027',
      ));
      final movingId = await service.assignFee(_assignmentPayload(
        studentId: 's1',
        feeStructureId: 'f1',
        academicYearId: 'ay-2026',
        academicYear: '2026-2027',
      ));
      expect(existingId, isNotNull);
      expect(movingId, isNotNull);

      await expectLater(
        service.updateAssignment(movingId!, {'studentId': 's2'}),
        throwsA(isA<StateError>()),
      );
    });

    test('26. bulkAssignClassFees compatibility: skips a student who already has a legacy (id-less) assignment for that year', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      await _seedClass(firestore, id: 'class-1');
      await _seedStudent(firestore, id: 's1', classId: 'class-1');
      await _seedStudent(firestore, id: 's2', classId: 'class-1');

      // s1 already has a legacy-shaped assignment for this exact
      // (structure, year) — no academicYearId at all.
      await service.assignFee(_assignmentPayload(
        studentId: 's1',
        feeStructureId: 'f1',
        academicYear: '2026-2027',
        classId: 'class-1',
      ));

      final summary = await service.bulkAssignClassFees(
        classId: 'class-1',
        className: 'Mont 1',
        feeStructureId: 'f1',
        feeStructureName: 'Core Fees',
        academicYearId: 'ay-2026',
        academicYear: '2026-2027',
        totalFee: 20000,
        discountAmount: 0,
      );

      expect(summary['assigned'], 1, reason: 'only s2 gets a new assignment');
      expect(summary['skipped'], 1, reason: 's1 is skipped — the legacy assignment counts as an existing duplicate');
      final all = await firestore.collection('student_fee_assignments').where('feeStructureId', isEqualTo: 'f1').get();
      expect(all.docs, hasLength(2), reason: 'no duplicate created for s1');
    });

    test('27. syncAssignmentsForFeeStructure compatibility: updates a legacy (id-less) assignment in place instead of creating a duplicate', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      await _seedClass(firestore, id: 'class-1');
      await _seedStudent(firestore, id: 's1', classId: 'class-1');

      final legacyId = await service.assignFee(_assignmentPayload(
        studentId: 's1',
        feeStructureId: 'f1',
        academicYear: '2026-2027',
        classId: 'class-1',
        totalFee: 10000,
      ));
      expect(legacyId, isNotNull);

      final summary = await service.syncAssignmentsForFeeStructure(
        feeStructureId: 'f1',
        feeStructureName: 'Core Fees (revised)',
        academicYearId: 'ay-2026',
        academicYear: '2026-2027',
        totalFee: 25000,
        assignmentScope: 'class',
        classIds: const ['class-1'],
        studentIds: const [],
      );

      expect(summary['created'], 0);
      expect(summary['updated'], 1, reason: 'the legacy assignment is found and updated, not duplicated');
      final all = await firestore.collection('student_fee_assignments').where('studentId', isEqualTo: 's1').get();
      expect(all.docs, hasLength(1));
      expect(all.docs.single.data()['totalFee'], 25000.0);
      expect(all.docs.single.data()['feeStructureName'], 'Core Fees (revised)');
    });
  });

  group('Historical safety — Fee Assignment academic year never re-derives (FEES-AY-IMPLEMENT-01)', () {
    test('28. Changing Student.classId never alters an existing FeeAssignment.academicYear/academicYearId', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      await _seedClass(firestore, id: 'class-mont1', name: 'Mont 1');
      await _seedClass(firestore, id: 'class-mont2', name: 'Mont 2');
      await _seedStudent(firestore, id: 's1', classId: 'class-mont1');

      final id = await service.assignFee(_assignmentPayload(
        studentId: 's1',
        feeStructureId: 'f1',
        academicYearId: 'ay-2025',
        academicYear: '2025-2026',
        classId: 'class-mont1',
      ));
      expect(id, isNotNull);

      // The student's *current* class changes (e.g. promoted to Mont 2) —
      // FeeService/StudentEnrollment machinery for this is exercised
      // elsewhere; here we only need to prove the pre-existing assignment
      // is untouched by that change.
      await firestore.collection('students').doc('s1').update({'classId': 'class-mont2'});

      final doc = (await firestore.collection('student_fee_assignments').doc(id!).get()).data()!;
      expect(doc['academicYearId'], 'ay-2025');
      expect(doc['academicYear'], '2025-2026');
    });

    test('29. Adding a new StudentEnrollment for the student never alters an existing FeeAssignment', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      await _seedClass(firestore, id: 'class-mont1', name: 'Mont 1');
      await _seedClass(firestore, id: 'class-mont2', name: 'Mont 2');
      await _seedStudent(firestore, id: 's1', classId: 'class-mont1');

      final id = await service.assignFee(_assignmentPayload(
        studentId: 's1',
        feeStructureId: 'f1',
        academicYearId: 'ay-2025',
        academicYear: '2025-2026',
        classId: 'class-mont1',
      ));
      expect(id, isNotNull);

      // A brand-new StudentEnrollment episode for a *different* academic
      // year is created for this same student (the normal AY-01 flow).
      await AcademicYearService(firestore: firestore).createAcademicYear(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        name: '2026-2027',
        startDate: DateTime(2026, 6, 1),
        endDate: DateTime(2027, 5, 31),
        createdBy: 'admin-1',
        setAsCurrent: true,
      );
      await StudentEnrollmentService(firestore: firestore).assignStudentToClassForYear(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        studentId: 's1',
        academicYearId: 'ay-2026-real',
        classId: 'class-mont2',
        actorId: 'admin-1',
      );

      final doc = (await firestore.collection('student_fee_assignments').doc(id!).get()).data()!;
      expect(doc['academicYearId'], 'ay-2025', reason: 'the historical assignment stays pinned to its own year');
      expect(doc['academicYear'], '2025-2026');
    });

    test('30. Deactivating/changing the underlying AcademicYear never rewrites an existing FeeAssignment', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      final ayService = AcademicYearService(firestore: firestore);
      final yearId = await ayService.createAcademicYear(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        name: '2025-2026',
        startDate: DateTime(2025, 6, 1),
        endDate: DateTime(2026, 5, 31),
        createdBy: 'admin-1',
        setAsCurrent: true,
      );
      await _seedClass(firestore, id: 'class-1');
      await _seedStudent(firestore, id: 's1', classId: 'class-1');

      final id = await service.assignFee(_assignmentPayload(
        studentId: 's1',
        feeStructureId: 'f1',
        academicYearId: yearId,
        academicYear: '2025-2026',
        classId: 'class-1',
      ));
      expect(id, isNotNull);

      final newYearId = await ayService.createAcademicYear(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        name: '2026-2027',
        startDate: DateTime(2026, 6, 1),
        endDate: DateTime(2027, 5, 31),
        createdBy: 'admin-1',
      );
      await ayService.setCurrentAcademicYear(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        id: newYearId,
        updatedBy: 'admin-1',
      );
      await ayService.deactivateAcademicYear(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        id: yearId,
        updatedBy: 'admin-1',
      );

      final doc = (await firestore.collection('student_fee_assignments').doc(id!).get()).data()!;
      expect(doc['academicYearId'], yearId, reason: 'still points at the same (now-deactivated) year — never silently repointed');
      expect(doc['academicYear'], '2025-2026');
    });
  });
}
