// AY-01 regression coverage: proves introducing StudentEnrollment (and its
// `student_enrollments` collection) is additive-only — Student identity,
// Parent/student relationships, existing Class membership queries,
// Attendance, Leave, Fees, and the Academic Year feature from SETTINGS-02
// all continue to work exactly as before. Mirrors the fixture-seeding
// pattern in academic_year_architecture_regression_test.dart, extended
// with functional (not just byte-identical) checks for Class/Attendance
// since AY-01 specifically touches the Student <-> Class relationship.
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/admin/settings/data/academic_year_service.dart';
import 'package:montessori_app/modules/admin/settings/models/school_settings_model.dart';
import 'package:montessori_app/modules/admin/students/data/admin_student_service.dart';
import 'package:montessori_app/modules/admin/students/data/student_enrollment_service.dart';
import 'package:montessori_app/modules/admin/students/models/admin_student_model.dart';
import 'package:montessori_app/modules/attendance/data/attendance_service.dart';
import 'package:montessori_app/modules/classes/data/class_service.dart';
import 'package:montessori_app/modules/leave/services/leave_service.dart';

void main() {
  group('14-17. Student regression', () {
    test('14/15. Existing student still loads with name/DOB/admission/gender unchanged after enrollment writes', () async {
      final firestore = FakeFirebaseFirestore();
      final studentService = AdminStudentService(firestore: firestore, storage: MockFirebaseStorage());
      final enrollmentService = StudentEnrollmentService(firestore: firestore);

      final studentId = await studentService.createStudent(
        student: AdminStudentModel(
          id: '',
          name: 'Abdul Kareem',
          admissionNo: 'ADM-001',
          classId: 'class-mont2',
          section: 'A',
          rollNumber: '12',
          dateOfBirth: '2019-06-15',
          age: 7,
          gender: 'Male',
          bloodGroup: 'O+',
          nationality: 'Indian',
          motherTongue: 'Tamil',
          addressLine1: '', addressLine2: '', city: '', state: '', pincode: '',
          isActive: true,
          isApproved: true,
          createdAt: null,
          createdBy: 'admin-1',
          parentLinks: const [],
          documents: const [],
        ),
        createdBy: 'admin-1',
      );

      await enrollmentService.createEnrollment(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        studentId: studentId,
        academicYearId: 'ay-2026',
        classId: 'class-mont2',
        createdBy: 'admin-1',
      );

      final students = await studentService.getStudents();
      final student = AdminStudentModel.fromMap(
        students.single.id,
        students.single.data(),
      );
      expect(student.name, 'Abdul Kareem');
      expect(student.admissionNo, 'ADM-001');
      expect(student.dateOfBirth, '2019-06-15');
      expect(student.gender, 'Male');
      expect(student.bloodGroup, 'O+');
    });

    test('16. Existing current class (Student.classId) is unaffected by a non-synced (past-year) enrollment', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('students').doc('student-1').set({'name': 'Abdul', 'classId': 'class-mont3'});
      final enrollmentService = StudentEnrollmentService(firestore: firestore);

      await enrollmentService.createEnrollment(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        studentId: 'student-1',
        academicYearId: 'ay-2024',
        classId: 'class-mont1',
        createdBy: 'admin-1',
      );

      final doc = await firestore.collection('students').doc('student-1').get();
      expect(doc.data()!['classId'], 'class-mont3', reason: 'current class must be untouched by a past-year episode');
    });

    test('17. Parent/student relationship (parentLinks) is unaffected by enrollment operations', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('students').doc('student-1').set({
        'name': 'Abdul',
        'classId': 'class-mont2',
        'parentLinks': [
          {'userId': 'parent-1', 'name': 'Kavya', 'relation': 'Mother'},
        ],
      });
      final enrollmentService = StudentEnrollmentService(firestore: firestore);
      await enrollmentService.createEnrollment(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        studentId: 'student-1',
        academicYearId: 'ay-2026',
        classId: 'class-mont2',
        createdBy: 'admin-1',
      );
      await enrollmentService.assignStudentToClassForYear(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        studentId: 'student-1',
        academicYearId: 'ay-2026',
        classId: 'class-mont2b',
        syncStudentClassId: true,
        actorId: 'admin-1',
      );

      final doc = await firestore.collection('students').doc('student-1').get();
      final links = List<Map<String, dynamic>>.from(doc.data()!['parentLinks'] as List);
      expect(links, hasLength(1));
      expect(links.single['userId'], 'parent-1');
      expect(links.single['relation'], 'Mother');
    });
  });

  group('18-20. Class regression', () {
    test('18/19. ClassService.getStudentsByClassId/getStudentCountByClassId still return correct membership', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('students').doc('s1').set({'name': 'A', 'classId': 'class-mont2', 'isActive': true});
      await firestore.collection('students').doc('s2').set({'name': 'B', 'classId': 'class-mont2', 'isActive': true});
      await firestore.collection('students').doc('s3').set({'name': 'C', 'classId': 'class-mont3', 'isActive': true});
      final classService = ClassService(firestore: firestore);
      final enrollmentService = StudentEnrollmentService(firestore: firestore);

      // Populate student_enrollments with unrelated/overlapping data to
      // prove ClassService's own classId-based query is unaffected by it.
      await enrollmentService.createEnrollment(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        studentId: 's1',
        academicYearId: 'ay-2025',
        classId: 'class-mont1',
        createdBy: 'admin-1',
      );

      final roster = await classService.getStudentsByClassId('class-mont2');
      final count = await classService.getStudentCountByClassId('class-mont2');
      expect(roster.map((d) => d.id).toSet(), {'s1', 's2'});
      expect(count, 2);
    });

    test('20. No duplicate students from Class membership queries after multiple enrollment episodes exist', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('students').doc('s1').set({'name': 'A', 'classId': 'class-mont2', 'isActive': true});
      final classService = ClassService(firestore: firestore);
      final enrollmentService = StudentEnrollmentService(firestore: firestore);

      // Three enrollment episodes for the same student across different
      // years — must never cause the student to appear more than once in
      // a class roster query.
      await enrollmentService.createEnrollment(
        schoolId: kDefaultSchoolId, requesterRole: 'admin', studentId: 's1',
        academicYearId: 'ay-2024', classId: 'class-mont1', createdBy: 'admin-1',
      );
      await enrollmentService.createEnrollment(
        schoolId: kDefaultSchoolId, requesterRole: 'admin', studentId: 's1',
        academicYearId: 'ay-2025', classId: 'class-mont2', createdBy: 'admin-1',
      );
      await enrollmentService.createEnrollment(
        schoolId: kDefaultSchoolId, requesterRole: 'admin', studentId: 's1',
        academicYearId: 'ay-2026', classId: 'class-mont2', createdBy: 'admin-1',
      );

      final roster = await classService.getStudentsByClassId('class-mont2');
      expect(roster, hasLength(1));

      final enrollmentRoster = await enrollmentService.getEnrollmentsForClass(
        schoolId: kDefaultSchoolId,
        classId: 'class-mont2',
        academicYearId: 'ay-2026',
      );
      expect(enrollmentRoster.map((e) => e.studentId).toSet(), {'s1'});
    });
  });

  group('21-25. Attendance regression', () {
    test('21/23. Today attendance + class filtering still work with student_enrollments populated', () async {
      final firestore = FakeFirebaseFirestore();
      final attendanceService = AttendanceService(firestore: firestore, storage: MockFirebaseStorage());
      final enrollmentService = StudentEnrollmentService(firestore: firestore);

      await attendanceService.markStudentAttendance(
        studentId: 's1',
        studentName: 'Abdul',
        classId: 'class-mont2',
        markedBy: 'admin-1',
        status: 'present',
      );
      await enrollmentService.createEnrollment(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        studentId: 's1',
        academicYearId: 'ay-2026',
        classId: 'class-mont2',
        createdBy: 'admin-1',
      );

      final today = await attendanceService.getTodayAttendanceMap();
      expect(today['student_s1']?['status'], 'present');

      final filtered = await attendanceService.filterByClasses(classIds: ['class-mont2']);
      expect(filtered.map((d) => d.id), contains(contains('student_s1')));
    });

    test('22. Attendance history still works unaffected by enrollment writes', () async {
      final firestore = FakeFirebaseFirestore();
      final attendanceService = AttendanceService(firestore: firestore, storage: MockFirebaseStorage());
      final enrollmentService = StudentEnrollmentService(firestore: firestore);

      await attendanceService.saveAdminAttendance(
        entityType: 'student',
        entityId: 's1',
        entityName: 'Abdul',
        classId: 'class-mont2',
        status: 'present',
        selectedDate: DateTime(2026, 8, 20),
        markedBy: 'admin-1',
      );
      await enrollmentService.createEnrollment(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        studentId: 's1',
        academicYearId: 'ay-2026',
        classId: 'class-mont2',
        createdBy: 'admin-1',
      );

      final history = await attendanceService.getAttendanceHistoryMap(
        startDate: DateTime(2026, 8, 1),
        endDate: DateTime(2026, 8, 31),
      );
      expect(history['student_s1_2026-08-20']?['status'], 'present');
    });

    test('24. On Leave attendance status is unaffected by student_enrollments', () async {
      final firestore = FakeFirebaseFirestore();
      final attendanceService = AttendanceService(firestore: firestore, storage: MockFirebaseStorage());
      final enrollmentService = StudentEnrollmentService(firestore: firestore);

      await attendanceService.saveAdminAttendance(
        entityType: 'student',
        entityId: 's1',
        entityName: 'Abdul',
        classId: 'class-mont2',
        status: 'on_leave',
        selectedDate: DateTime(2026, 8, 20),
        markedBy: 'admin-1',
      );
      await enrollmentService.createEnrollment(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        studentId: 's1',
        academicYearId: 'ay-2026',
        classId: 'class-mont2',
        createdBy: 'admin-1',
      );

      final byDate = await attendanceService.getAttendanceByDate(date: DateTime(2026, 8, 20));
      expect(byDate['student_s1']?['status'], 'on_leave');
    });

    test('25. Staff attendance remains unaffected (student_enrollments never touches staff entities)', () async {
      final firestore = FakeFirebaseFirestore();
      final attendanceService = AttendanceService(firestore: firestore, storage: MockFirebaseStorage());
      final enrollmentService = StudentEnrollmentService(firestore: firestore);

      await attendanceService.markStaffAttendance(
        staffId: 'staff-1',
        staffName: 'Ms. Ananya',
        markedBy: 'admin-1',
        status: 'present',
      );
      await enrollmentService.createEnrollment(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        studentId: 's1',
        academicYearId: 'ay-2026',
        classId: 'class-mont2',
        createdBy: 'admin-1',
      );

      final today = await attendanceService.getTodayAttendanceMap();
      expect(today['staff_staff-1']?['status'], 'present');
      final snap = await firestore.collection('attendance').get();
      expect(snap.docs, hasLength(1), reason: 'enrollment writes must never create/alter attendance docs');
    });
  });

  group('26. Leave regression', () {
    test('Existing Leave submission/approval flow is unaffected by student_enrollments', () async {
      final firestore = FakeFirebaseFirestore();
      final leaveService = LeaveService(firestore: firestore);
      final enrollmentService = StudentEnrollmentService(firestore: firestore);

      final leaveId = await leaveService.submitLeaveRequest(
        requesterId: 'staff-1',
        requesterName: 'Ms. Ananya',
        leaveType: 'Sick Leave',
        startDate: DateTime(2026, 8, 10),
        endDate: DateTime(2026, 8, 11),
        reason: 'Fever',
      );
      await enrollmentService.createEnrollment(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        studentId: 's1',
        academicYearId: 'ay-2026',
        classId: 'class-mont2',
        createdBy: 'admin-1',
      );

      final leaveSnap = await firestore.collection('staff_leave_requests').doc(leaveId).get();
      expect(leaveSnap.data()!['status'], 'Pending');
      expect(leaveSnap.data()!['leaveType'], 'Sick Leave');
    });
  });

  group('27-28. Fees regression', () {
    test('Existing Fee assignment (and its free-text academicYear field) is unaffected by student_enrollments', () async {
      final firestore = FakeFirebaseFirestore();
      final feeDoc = await firestore.collection('student_fee_assignments').add({
        'studentId': 's1',
        'studentName': 'Abdul',
        'classId': 'class-mont2',
        'academicYear': '2026-2027',
        'totalFee': 50000,
        'status': 'unpaid',
      });
      final enrollmentService = StudentEnrollmentService(firestore: firestore);
      await enrollmentService.createEnrollment(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        studentId: 's1',
        academicYearId: 'ay-2026',
        classId: 'class-mont2',
        createdBy: 'admin-1',
      );

      final snap = await feeDoc.get();
      expect(snap.data()!['academicYear'], '2026-2027', reason: 'the loose free-text field must be untouched');
      expect(snap.data()!['totalFee'], 50000);
      expect(snap.data()!['status'], 'unpaid');
    });
  });

  group('29-31. Academic Year integration', () {
    test('29. Assigning uses the canonical current academic year id (via AcademicYearService), never a hardcoded string', () async {
      final firestore = FakeFirebaseFirestore();
      final academicYearService = AcademicYearService(firestore: firestore);
      final enrollmentService = StudentEnrollmentService(firestore: firestore);

      final currentId = await academicYearService.createAcademicYear(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        name: '2026-2027',
        startDate: DateTime(2026, 6, 1),
        endDate: DateTime(2027, 5, 31),
        createdBy: 'admin-1',
        setAsCurrent: true,
      );
      final current = await academicYearService.getCurrentAcademicYear(schoolId: kDefaultSchoolId);
      await enrollmentService.assignStudentToClassForYear(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        studentId: 's1',
        academicYearId: current!.id,
        classId: 'class-mont2',
        syncStudentClassId: true,
        actorId: 'admin-1',
      );

      final enrollment = (await enrollmentService.getEnrollmentsForStudent(
        schoolId: kDefaultSchoolId,
        studentId: 's1',
      )).single;
      expect(enrollment.academicYearId, currentId);
    });

    test('30. Changing the current academic year does not rewrite student identity', () async {
      final firestore = FakeFirebaseFirestore();
      final academicYearService = AcademicYearService(firestore: firestore);
      final studentService = AdminStudentService(firestore: firestore, storage: MockFirebaseStorage());

      final firstYearId = await academicYearService.createAcademicYear(
        schoolId: kDefaultSchoolId, requesterRole: 'admin', name: '2025-2026',
        startDate: DateTime(2025, 6, 1), endDate: DateTime(2026, 5, 31),
        createdBy: 'admin-1', setAsCurrent: true,
      );
      final studentId = await studentService.createStudent(
        student: AdminStudentModel(
          id: '', name: 'Abdul Kareem', admissionNo: 'ADM-001', classId: 'class-mont2',
          section: '', rollNumber: '', dateOfBirth: '2019-06-15', age: 7, gender: 'Male',
          bloodGroup: '', nationality: '', motherTongue: '', addressLine1: '', addressLine2: '',
          city: '', state: '', pincode: '', isActive: true, isApproved: true,
          createdAt: null, createdBy: 'admin-1', parentLinks: const [], documents: const [],
        ),
        createdBy: 'admin-1',
      );

      final secondYearId = await academicYearService.createAcademicYear(
        schoolId: kDefaultSchoolId, requesterRole: 'admin', name: '2026-2027',
        startDate: DateTime(2026, 6, 1), endDate: DateTime(2027, 5, 31), createdBy: 'admin-1',
      );
      await academicYearService.setCurrentAcademicYear(
        schoolId: kDefaultSchoolId, requesterRole: 'admin', id: secondYearId, updatedBy: 'admin-1',
      );

      final students = await studentService.getStudents();
      final student = AdminStudentModel.fromMap(students.single.id, students.single.data());
      expect(student.id, studentId);
      expect(student.name, 'Abdul Kareem');
      expect(student.admissionNo, 'ADM-001');
      expect(firstYearId, isNotEmpty);
    });

    test('31. Changing the current academic year does not rewrite historical enrollment', () async {
      final firestore = FakeFirebaseFirestore();
      final academicYearService = AcademicYearService(firestore: firestore);
      final enrollmentService = StudentEnrollmentService(firestore: firestore);

      final firstYearId = await academicYearService.createAcademicYear(
        schoolId: kDefaultSchoolId, requesterRole: 'admin', name: '2025-2026',
        startDate: DateTime(2025, 6, 1), endDate: DateTime(2026, 5, 31),
        createdBy: 'admin-1', setAsCurrent: true,
      );
      final enrollmentId = await enrollmentService.createEnrollment(
        schoolId: kDefaultSchoolId, requesterRole: 'admin', studentId: 's1',
        academicYearId: firstYearId, classId: 'class-mont1', createdBy: 'admin-1',
      );

      final secondYearId = await academicYearService.createAcademicYear(
        schoolId: kDefaultSchoolId, requesterRole: 'admin', name: '2026-2027',
        startDate: DateTime(2026, 6, 1), endDate: DateTime(2027, 5, 31), createdBy: 'admin-1',
      );
      await academicYearService.setCurrentAcademicYear(
        schoolId: kDefaultSchoolId, requesterRole: 'admin', id: secondYearId, updatedBy: 'admin-1',
      );

      final enrollment = await enrollmentService.getEnrollmentById(schoolId: kDefaultSchoolId, id: enrollmentId);
      expect(enrollment!.classId, 'class-mont1');
      expect(enrollment.academicYearId, firstYearId);
      expect(enrollment.status, isNot('Completed'));
    });
  });

  group('32-33. Firestore write isolation', () {
    test('32/33. Every StudentEnrollmentService write lands only in student_enrollments; Student/Class/Attendance/Leave/Fees untouched', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('students').doc('s1').set({'name': 'Abdul', 'classId': 'class-old'});
      await firestore.collection('classes').doc('class-mont2').set({'name': 'Mont 2'});
      final before = <String, Map<String, dynamic>>{
        'students': Map<String, dynamic>.from((await firestore.collection('students').doc('s1').get()).data()!),
        'classes': Map<String, dynamic>.from((await firestore.collection('classes').doc('class-mont2').get()).data()!),
      };

      final enrollmentService = StudentEnrollmentService(firestore: firestore);
      final id = await enrollmentService.createEnrollment(
        schoolId: kDefaultSchoolId, requesterRole: 'admin', studentId: 's1',
        academicYearId: 'ay-2026', classId: 'class-mont2', createdBy: 'admin-1',
      );
      await enrollmentService.updateEnrollment(
        schoolId: kDefaultSchoolId, requesterRole: 'admin', id: id,
        status: 'Completed', updatedBy: 'admin-1',
      );

      final studentsSnap = await firestore.collection('students').get();
      final classesSnap = await firestore.collection('classes').get();
      expect(studentsSnap.docs.single.data(), equals(before['students']));
      expect(classesSnap.docs.single.data(), equals(before['classes']));

      final enrollmentsSnap = await firestore.collection('student_enrollments').get();
      expect(enrollmentsSnap.docs, hasLength(1));
    });
  });
}
