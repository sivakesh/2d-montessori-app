// AY-01 coverage for StudentEnrollmentService — the data/authorization/
// business-rules layer for the Academic Year -> Class -> Student
// relationship. UI-level coverage (Academic History tab, Assign to
// Academic Year dialog, responsive) lives in student_enrollment_ui_test.dart.
// Cross-module regression (Student/Class/Attendance/Leave/Fees/Academic
// Year untouched) lives in student_enrollment_regression_test.dart.
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/admin/settings/data/academic_year_service.dart';
import 'package:montessori_app/modules/admin/settings/models/school_settings_model.dart';
import 'package:montessori_app/modules/admin/students/data/student_enrollment_service.dart';
import 'package:montessori_app/modules/admin/students/models/student_enrollment_model.dart';

StudentEnrollmentService _service(FakeFirebaseFirestore firestore) =>
    StudentEnrollmentService(firestore: firestore);

Future<String> _enroll(
  StudentEnrollmentService service, {
  String schoolId = kDefaultSchoolId,
  String role = 'admin',
  required String studentId,
  required String academicYearId,
  required String classId,
  String status = StudentEnrollmentStatus.active,
  String createdBy = 'admin-1',
}) {
  return service.createEnrollment(
    schoolId: schoolId,
    requesterRole: role,
    studentId: studentId,
    academicYearId: academicYearId,
    classId: classId,
    status: status,
    createdBy: createdBy,
  );
}

void main() {
  group('StudentEnrollmentService — create/load', () {
    test('1. Create enrollment persists it', () async {
      final service = _service(FakeFirebaseFirestore());
      final id = await _enroll(
        service,
        studentId: 'student-1',
        academicYearId: 'ay-2026',
        classId: 'class-mont2',
      );
      expect(id, isNotEmpty);
      final list = await service.getEnrollmentsForStudent(schoolId: kDefaultSchoolId, studentId: 'student-1');
      expect(list, hasLength(1));
      expect(list.single.classId, 'class-mont2');
      expect(list.single.status, StudentEnrollmentStatus.active);
    });

    test('2. Load a single enrollment by id', () async {
      final service = _service(FakeFirebaseFirestore());
      final id = await _enroll(
        service,
        studentId: 'student-1',
        academicYearId: 'ay-2026',
        classId: 'class-mont2',
      );
      final enrollment = await service.getEnrollmentById(schoolId: kDefaultSchoolId, id: id);
      expect(enrollment, isNotNull);
      expect(enrollment!.studentId, 'student-1');
      expect(enrollment.academicYearId, 'ay-2026');
    });

    test('A non-existent enrollment id resolves to null, not an error', () async {
      final service = _service(FakeFirebaseFirestore());
      final enrollment = await service.getEnrollmentById(schoolId: kDefaultSchoolId, id: 'ghost');
      expect(enrollment, isNull);
    });
  });

  group('StudentEnrollmentService — update', () {
    test('3. Update enrollment changes class/status/leavingDate', () async {
      final service = _service(FakeFirebaseFirestore());
      final id = await _enroll(
        service,
        studentId: 'student-1',
        academicYearId: 'ay-2026',
        classId: 'class-mont2',
      );

      await service.updateEnrollment(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        id: id,
        classId: 'class-mont3',
        status: StudentEnrollmentStatus.completed,
        leavingDate: DateTime(2027, 5, 31),
        updatedBy: 'admin-2',
      );

      final enrollment = await service.getEnrollmentById(schoolId: kDefaultSchoolId, id: id);
      expect(enrollment!.classId, 'class-mont3');
      expect(enrollment.status, StudentEnrollmentStatus.completed);
      expect(enrollment.leavingDate, DateTime(2027, 5, 31));
      expect(enrollment.updatedBy, 'admin-2');
    });

    test('Updating a non-existent enrollment throws StudentEnrollmentNotFoundException', () async {
      final service = _service(FakeFirebaseFirestore());
      expect(
        () => service.updateEnrollment(
          schoolId: kDefaultSchoolId,
          requesterRole: 'admin',
          id: 'ghost',
          classId: 'class-mont3',
          updatedBy: 'admin-1',
        ),
        throwsA(isA<StudentEnrollmentNotFoundException>()),
      );
    });
  });

  group('StudentEnrollmentService — one active enrollment per student/year', () {
    test('4. A student has only one enrollment per academic year under normal use', () async {
      final service = _service(FakeFirebaseFirestore());
      await _enroll(service, studentId: 'student-1', academicYearId: 'ay-2026', classId: 'class-mont2');
      final list = await service.getEnrollmentsForStudent(schoolId: kDefaultSchoolId, studentId: 'student-1');
      expect(list.where((e) => e.academicYearId == 'ay-2026'), hasLength(1));
    });

    test('5. Duplicate Active enrollment for the same student+year is rejected', () async {
      final service = _service(FakeFirebaseFirestore());
      await _enroll(service, studentId: 'student-1', academicYearId: 'ay-2026', classId: 'class-mont2');

      expect(
        () => _enroll(service, studentId: 'student-1', academicYearId: 'ay-2026', classId: 'class-mont3'),
        throwsA(isA<DuplicateActiveEnrollmentException>()),
      );
      final list = await service.getEnrollmentsForStudent(schoolId: kDefaultSchoolId, studentId: 'student-1');
      expect(list, hasLength(1), reason: 'a rejected duplicate must not write anything');
    });

    test('A non-Active enrollment (e.g. Completed) does not block a new Active one for the same year', () async {
      final service = _service(FakeFirebaseFirestore());
      final firstId = await _enroll(
        service,
        studentId: 'student-1',
        academicYearId: 'ay-2026',
        classId: 'class-mont2',
      );
      await service.updateEnrollment(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        id: firstId,
        status: StudentEnrollmentStatus.withdrawn,
        updatedBy: 'admin-1',
      );

      await expectLater(
        _enroll(service, studentId: 'student-1', academicYearId: 'ay-2026', classId: 'class-mont3'),
        completes,
      );
    });

    test('6/7. A student has enrollments across multiple academic years, with a different class each time', () async {
      final service = _service(FakeFirebaseFirestore());
      await _enroll(service, studentId: 'student-1', academicYearId: 'ay-2025', classId: 'class-mont1');
      await _enroll(service, studentId: 'student-1', academicYearId: 'ay-2026', classId: 'class-mont2');
      await _enroll(service, studentId: 'student-1', academicYearId: 'ay-2027', classId: 'class-mont3');

      final list = await service.getEnrollmentsForStudent(schoolId: kDefaultSchoolId, studentId: 'student-1');
      expect(list, hasLength(3));
      expect(
        {for (final e in list) e.academicYearId: e.classId},
        {'ay-2025': 'class-mont1', 'ay-2026': 'class-mont2', 'ay-2027': 'class-mont3'},
      );
    });

    test('8. Updating one year\'s enrollment never changes another year\'s historical episode', () async {
      final service = _service(FakeFirebaseFirestore());
      final oldId = await _enroll(
        service,
        studentId: 'student-1',
        academicYearId: 'ay-2025',
        classId: 'class-mont1',
      );
      await _enroll(service, studentId: 'student-1', academicYearId: 'ay-2026', classId: 'class-mont2');

      await service.assignStudentToClassForYear(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        studentId: 'student-1',
        academicYearId: 'ay-2026',
        classId: 'class-mont2b',
        syncStudentClassId: false,
        actorId: 'admin-1',
      );

      final oldEnrollment = await service.getEnrollmentById(schoolId: kDefaultSchoolId, id: oldId);
      expect(oldEnrollment!.classId, 'class-mont1', reason: 'the 2025 episode must be untouched by a 2026 change');
    });
  });

  group('StudentEnrollmentService — assignStudentToClassForYear', () {
    test('creates a new Active enrollment when none exists for the year', () async {
      final service = _service(FakeFirebaseFirestore());
      await service.assignStudentToClassForYear(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        studentId: 'student-1',
        academicYearId: 'ay-2026',
        classId: 'class-mont2',
        actorId: 'admin-1',
      );
      final active = await service.getActiveEnrollment(
        schoolId: kDefaultSchoolId,
        studentId: 'student-1',
        academicYearId: 'ay-2026',
      );
      expect(active, isNotNull);
      expect(active!.classId, 'class-mont2');
    });

    test('re-points the existing Active enrollment instead of creating a second one when called again for the same year', () async {
      final service = _service(FakeFirebaseFirestore());
      await service.assignStudentToClassForYear(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        studentId: 'student-1',
        academicYearId: 'ay-2026',
        classId: 'class-mont2',
        actorId: 'admin-1',
      );
      await service.assignStudentToClassForYear(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        studentId: 'student-1',
        academicYearId: 'ay-2026',
        classId: 'class-mont2b',
        actorId: 'admin-1',
      );

      final list = await service.getEnrollmentsForStudent(schoolId: kDefaultSchoolId, studentId: 'student-1');
      expect(list, hasLength(1), reason: 'must re-point, never create a duplicate active row');
      expect(list.single.classId, 'class-mont2b');
    });

    test('syncStudentClassId: true also writes Student.classId; false leaves it untouched', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      await firestore.collection('students').doc('student-1').set({'name': 'Abdul', 'classId': 'class-old'});

      await service.assignStudentToClassForYear(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        studentId: 'student-1',
        academicYearId: 'ay-2025',
        classId: 'class-mont1',
        actorId: 'admin-1',
        // syncStudentClassId defaults to false — a past year must never
        // overwrite the student's current placement.
      );
      var doc = await firestore.collection('students').doc('student-1').get();
      expect(doc.data()!['classId'], 'class-old', reason: 'a non-current-year assignment must not touch classId');

      await service.assignStudentToClassForYear(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        studentId: 'student-1',
        academicYearId: 'ay-2026',
        classId: 'class-mont2',
        syncStudentClassId: true,
        actorId: 'admin-1',
      );
      doc = await firestore.collection('students').doc('student-1').get();
      expect(doc.data()!['classId'], 'class-mont2');
    });
  });

  group('9. academicYearId is the relationship, never a free-text year string', () {
    test('StudentEnrollmentModel stores/round-trips academicYearId, with no academic-year string field at all', () async {
      final service = _service(FakeFirebaseFirestore());
      final id = await _enroll(
        service,
        studentId: 'student-1',
        academicYearId: 'ay-2026',
        classId: 'class-mont2',
      );
      final enrollment = await service.getEnrollmentById(schoolId: kDefaultSchoolId, id: id);
      expect(enrollment!.academicYearId, 'ay-2026');
      expect(enrollment.toMap().containsKey('academicYear'), isFalse);
      expect(enrollment.toMap()['academicYearId'], 'ay-2026');
    });

    test('academicYearId is used together with a real AcademicYearService-created id end-to-end', () async {
      final firestore = FakeFirebaseFirestore();
      final academicYearService = AcademicYearService(firestore: firestore);
      final enrollmentService = _service(firestore);

      final academicYearId = await academicYearService.createAcademicYear(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        name: '2026-2027',
        startDate: DateTime(2026, 6, 1),
        endDate: DateTime(2027, 5, 31),
        createdBy: 'admin-1',
      );
      await _enroll(
        enrollmentService,
        studentId: 'student-1',
        academicYearId: academicYearId,
        classId: 'class-mont2',
      );

      final enrollment = (await enrollmentService.getEnrollmentsForStudent(
        schoolId: kDefaultSchoolId,
        studentId: 'student-1',
      )).single;
      final year = await academicYearService.getAcademicYearById(schoolId: kDefaultSchoolId, id: enrollment.academicYearId);
      expect(year, isNotNull);
      expect(year!.name, '2026-2027');
    });
  });

  group('StudentEnrollmentService — authorization', () {
    test('10. Admin can create/update enrollment', () async {
      final service = _service(FakeFirebaseFirestore());
      await expectLater(
        _enroll(service, role: 'admin', studentId: 'student-1', academicYearId: 'ay-2026', classId: 'class-mont2'),
        completes,
      );
    });

    test('11. Staff can create/update enrollment (matches existing Student/Class edit permissions)', () async {
      final service = _service(FakeFirebaseFirestore());
      final id = await _enroll(
        service,
        role: 'staff',
        studentId: 'student-1',
        academicYearId: 'ay-2026',
        classId: 'class-mont2',
        createdBy: 'staff-1',
      );
      expect(id, isNotEmpty);
      await expectLater(
        service.updateEnrollment(
          schoolId: kDefaultSchoolId,
          requesterRole: 'staff',
          id: id,
          classId: 'class-mont3',
          updatedBy: 'staff-1',
        ),
        completes,
      );
    });

    test('12. Parent cannot create or update enrollment', () async {
      final service = _service(FakeFirebaseFirestore());
      final id = await _enroll(service, studentId: 'student-1', academicYearId: 'ay-2026', classId: 'class-mont2');

      expect(
        () => _enroll(
          service,
          role: 'parent',
          studentId: 'student-1',
          academicYearId: 'ay-2027',
          classId: 'class-mont3',
          createdBy: 'parent-1',
        ),
        throwsA(isA<UnauthorizedStudentEnrollmentException>()),
      );
      expect(
        () => service.updateEnrollment(
          schoolId: kDefaultSchoolId,
          requesterRole: 'parent',
          id: id,
          classId: 'class-mont3',
          updatedBy: 'parent-1',
        ),
        throwsA(isA<UnauthorizedStudentEnrollmentException>()),
      );
      expect(
        () => service.assignStudentToClassForYear(
          schoolId: kDefaultSchoolId,
          requesterRole: 'parent',
          studentId: 'student-1',
          academicYearId: 'ay-2027',
          classId: 'class-mont3',
          actorId: 'parent-1',
        ),
        throwsA(isA<UnauthorizedStudentEnrollmentException>()),
      );

      final list = await service.getEnrollmentsForStudent(schoolId: kDefaultSchoolId, studentId: 'student-1');
      expect(list, hasLength(1), reason: 'no denied mutation may have written anything');
    });

    test('Reads are never role-gated', () async {
      final service = _service(FakeFirebaseFirestore());
      await _enroll(service, studentId: 'student-1', academicYearId: 'ay-2026', classId: 'class-mont2');
      final list = await service.getEnrollmentsForStudent(schoolId: kDefaultSchoolId, studentId: 'student-1');
      expect(list, hasLength(1));
    });
  });

  group('StudentEnrollmentService — schoolId isolation', () {
    test('13. Enrollments for one schoolId are never visible under another schoolId', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);

      await _enroll(
        service,
        schoolId: 'school-a',
        studentId: 'student-1',
        academicYearId: 'ay-2026',
        classId: 'class-mont2',
      );

      final bList = await service.getEnrollmentsForStudent(schoolId: 'school-b', studentId: 'student-1');
      expect(bList, isEmpty);

      await _enroll(
        service,
        schoolId: 'school-b',
        studentId: 'student-1',
        academicYearId: 'ay-2026',
        classId: 'class-mont2',
      );

      final aList = await service.getEnrollmentsForStudent(schoolId: 'school-a', studentId: 'student-1');
      final bListAfter = await service.getEnrollmentsForStudent(schoolId: 'school-b', studentId: 'student-1');
      expect(aList, hasLength(1));
      expect(bListAfter, hasLength(1));

      final snap = await firestore.collection('student_enrollments').get();
      expect(snap.docs, hasLength(2));
    });
  });

  group('StudentEnrollmentService — validation', () {
    test('blank studentId/academicYearId/classId are rejected', () async {
      final service = _service(FakeFirebaseFirestore());
      expect(
        () => _enroll(service, studentId: '', academicYearId: 'ay-2026', classId: 'class-mont2'),
        throwsA(isA<StudentEnrollmentValidationException>()),
      );
      expect(
        () => _enroll(service, studentId: 'student-1', academicYearId: '', classId: 'class-mont2'),
        throwsA(isA<StudentEnrollmentValidationException>()),
      );
      expect(
        () => _enroll(service, studentId: 'student-1', academicYearId: 'ay-2026', classId: ''),
        throwsA(isA<StudentEnrollmentValidationException>()),
      );
    });

    test('an invalid status string is rejected', () async {
      final service = _service(FakeFirebaseFirestore());
      expect(
        () => _enroll(
          service,
          studentId: 'student-1',
          academicYearId: 'ay-2026',
          classId: 'class-mont2',
          status: 'Bogus',
        ),
        throwsA(isA<StudentEnrollmentValidationException>()),
      );
    });
  });

  group('getEnrollmentsForClass', () {
    test('returns only Active enrollments for the given class+year, excluding other years/statuses', () async {
      final service = _service(FakeFirebaseFirestore());
      final withdrawnId = await _enroll(
        service,
        studentId: 'student-1',
        academicYearId: 'ay-2026',
        classId: 'class-mont2',
      );
      await service.updateEnrollment(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        id: withdrawnId,
        status: StudentEnrollmentStatus.withdrawn,
        updatedBy: 'admin-1',
      );
      await _enroll(service, studentId: 'student-2', academicYearId: 'ay-2026', classId: 'class-mont2');
      await _enroll(service, studentId: 'student-3', academicYearId: 'ay-2025', classId: 'class-mont2');

      final roster = await service.getEnrollmentsForClass(
        schoolId: kDefaultSchoolId,
        classId: 'class-mont2',
        academicYearId: 'ay-2026',
      );
      expect(roster.map((e) => e.studentId), ['student-2']);
    });
  });
}
