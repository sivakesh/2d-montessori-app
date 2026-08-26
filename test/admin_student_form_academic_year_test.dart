// AY-01-R1 coverage: Academic Year + Class integration into the existing
// Add/Edit Student form (AdminStudentForm). Service-layer business rules
// for AcademicYearService/StudentEnrollmentService themselves are already
// covered in academic_year_service_test.dart/student_enrollment_service_test.dart
// — this file only checks the form loads/filters/saves correctly through
// them. The pre-existing Class-dropdown-crash regression suite lives
// separately in admin_student_form_class_dropdown_test.dart and is
// unaffected by this file.
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/admin/settings/data/academic_year_service.dart';
import 'package:montessori_app/modules/admin/settings/models/school_settings_model.dart';
import 'package:montessori_app/modules/admin/settings/providers/academic_year_provider.dart';
import 'package:montessori_app/modules/admin/students/data/admin_student_service.dart';
import 'package:montessori_app/modules/admin/students/data/student_enrollment_service.dart';
import 'package:montessori_app/modules/admin/students/models/student_enrollment_model.dart';
import 'package:montessori_app/modules/admin/students/providers/student_enrollment_provider.dart';
import 'package:montessori_app/modules/admin/ui/admin_student_form.dart';
import 'package:montessori_app/modules/attendance/data/attendance_service.dart';
import 'package:montessori_app/modules/classes/data/class_service.dart';
import 'package:montessori_app/modules/auth/models/app_user.dart';
import 'package:montessori_app/modules/auth/providers/auth_provider.dart';

Widget _pumpable(
  Widget child, {
  required FakeFirebaseFirestore firestore,
  String role = 'admin',
}) {
  return ProviderScope(
    overrides: [
      currentUserProvider.overrideWith(
        (ref) => AppUser(id: 'admin-1', phone: '9999999999', role: role, isActive: true),
      ),
      academicYearServiceProvider.overrideWithValue(AcademicYearService(firestore: firestore)),
      studentEnrollmentServiceProvider.overrideWithValue(StudentEnrollmentService(firestore: firestore)),
    ],
    child: MaterialApp(home: child),
  );
}

Future<String> _seedCurrentYear(
  FakeFirebaseFirestore firestore, {
  String name = '2026-2027',
  DateTime? start,
  DateTime? end,
}) {
  return AcademicYearService(firestore: firestore).createAcademicYear(
    schoolId: kDefaultSchoolId,
    requesterRole: 'admin',
    name: name,
    startDate: start ?? DateTime(2026, 6, 1),
    endDate: end ?? DateTime(2027, 5, 31),
    createdBy: 'admin-1',
    setAsCurrent: true,
  );
}

Future<String> _seedHistoricalYear(
  FakeFirebaseFirestore firestore, {
  String name = '2025-2026',
  DateTime? start,
  DateTime? end,
}) {
  return AcademicYearService(firestore: firestore).createAcademicYear(
    schoolId: kDefaultSchoolId,
    requesterRole: 'admin',
    name: name,
    startDate: start ?? DateTime(2025, 6, 1),
    endDate: end ?? DateTime(2026, 5, 31),
    createdBy: 'admin-1',
  );
}

Future<void> _seedClass(
  FakeFirebaseFirestore firestore,
  String id,
  String name,
  String academicYear, {
  String? academicYearId,
}) {
  return firestore.collection('classes').doc(id).set({
    'name': name,
    'academicYear': academicYear,
    if (academicYearId != null) 'academicYearId': academicYearId,
    'isActive': true,
  });
}

AdminStudentForm _form(
  FakeFirebaseFirestore firestore, {
  String? studentId,
  Map<String, dynamic>? initialData,
  Key? key,
}) {
  return AdminStudentForm(
    key: key,
    studentId: studentId,
    initialData: initialData,
    service: AdminStudentService(firestore: firestore, storage: MockFirebaseStorage()),
    firestore: firestore,
    enrollmentService: StudentEnrollmentService(firestore: firestore),
  );
}

/// A complete `initialData` map for an existing student — every field
/// `_textField`'s validator requires (Full Name/Admission No/Address Line
/// 1/City/State/Pincode) is populated, matching what a real saved student
/// record already has, so Edit-flow tests can Save without needing to
/// separately re-fill unrelated fields.
Map<String, dynamic> _existingStudentData({required String name, required String classId}) {
  return {
    'name': name,
    'admissionNo': 'ADM-1',
    'classId': classId,
    'addressLine1': '12 Garden Road',
    'city': 'Coimbatore',
    'state': 'Tamil Nadu',
    'pincode': '641001',
    'isActive': true,
  };
}

void main() {
  group('ADD STUDENT', () {
    testWidgets('1/2. Current Academic Year defaults correctly and is visible', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedCurrentYear(firestore);
      await _seedClass(firestore, 'class-mont2', 'Mont 2', '2026-2027');

      await tester.pumpWidget(_pumpable(_form(firestore), firestore: firestore));
      await tester.pumpAndSettle();

      expect(find.text('Academic Year'), findsOneWidget);
      expect(find.text('2026-2027 • Current'), findsOneWidget);
    });

    testWidgets('3. Class list filters by selected Academic Year', (tester) async {
      final firestore = FakeFirebaseFirestore();
      final currentYearId = await _seedCurrentYear(firestore);
      final historicalYearId = await _seedHistoricalYear(firestore);
      await _seedClass(firestore, 'class-mont2', 'Mont 2', '2026-2027');
      await _seedClass(firestore, 'class-premont', 'Pre Mont', '2025-2026');

      await tester.pumpWidget(_pumpable(_form(firestore), firestore: firestore));
      await tester.pumpAndSettle();

      // Current year (2026-2027) selected by default: only Mont 2 offered.
      await tester.tap(find.byKey(ValueKey('class_dropdown_$currentYearId')));
      await tester.pumpAndSettle();
      expect(find.text('Mont 2'), findsWidgets);
      expect(find.text('Pre Mont'), findsNothing);
      // Close the menu by re-selecting the same value.
      await tester.tap(find.text('Mont 2').last);
      await tester.pumpAndSettle();

      // Switch to the historical year: class list must reload to that
      // year's classes, never leaving the old (now invalid) selection.
      await tester.tap(find.text('2026-2027 • Current'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2025-2026 • Historical').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(ValueKey('class_dropdown_$historicalYearId')));
      await tester.pumpAndSettle();
      expect(find.text('Pre Mont'), findsWidgets);
      expect(find.text('Mont 2'), findsNothing);
    });

    testWidgets('4/5. Creating a student creates a StudentEnrollment and syncs Student.classId (current year)', (tester) async {
      final firestore = FakeFirebaseFirestore();
      final currentYearId = await _seedCurrentYear(firestore);
      await _seedClass(firestore, 'class-mont2', 'Mont 2', '2026-2027');

      await tester.pumpWidget(_pumpable(_form(firestore), firestore: firestore));
      await tester.pumpAndSettle();

      // Fill the required fields via their labels' sibling TextFormFields.
      await _fillRequiredFields(tester);

      await tester.ensureVisible(find.widgetWithText(ElevatedButton, 'Save'));
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
      await tester.pumpAndSettle();

      final studentsSnap = await firestore.collection('students').get();
      expect(studentsSnap.docs, hasLength(1));
      final studentId = studentsSnap.docs.single.id;
      expect(studentsSnap.docs.single.data()['classId'], 'class-mont2');

      final enrollmentService = StudentEnrollmentService(firestore: firestore);
      final enrollments = await enrollmentService.getEnrollmentsForStudent(
        schoolId: kDefaultSchoolId,
        studentId: studentId,
      );
      expect(enrollments, hasLength(1));
      expect(enrollments.single.academicYearId, currentYearId);
      expect(enrollments.single.classId, 'class-mont2');
      expect(enrollments.single.status, StudentEnrollmentStatus.active);
    });

    testWidgets('6. No classes offered for a year with no matching classes: Class is required, blocking save', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedCurrentYear(firestore);
      // No class documents carry academicYear "2026-2027" at all.

      await tester.pumpWidget(_pumpable(_form(firestore), firestore: firestore));
      await tester.pumpAndSettle();

      await _fillRequiredFields(tester);

      await tester.ensureVisible(find.widgetWithText(ElevatedButton, 'Save'));
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
      await tester.pumpAndSettle();

      expect(find.text('Required'), findsWidgets);
      final studentsSnap = await firestore.collection('students').get();
      expect(studentsSnap.docs, isEmpty, reason: 'a student must never be created without a valid class selection');
    });

    testWidgets('7. With no Academic Year configured at all, Add Student behaves exactly as before AY-01-R1', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedClass(firestore, 'class-mont2', 'Mont 2', '2026-2027');
      // No AcademicYear document exists at all.

      await tester.pumpWidget(_pumpable(_form(firestore), firestore: firestore));
      await tester.pumpAndSettle();

      expect(find.text('Academic Year'), findsNothing);
      expect(find.text('Class'), findsOneWidget);

      await _fillRequiredFields(tester);

      await tester.ensureVisible(find.widgetWithText(ElevatedButton, 'Save'));
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
      await tester.pumpAndSettle();

      final studentsSnap = await firestore.collection('students').get();
      expect(studentsSnap.docs, hasLength(1));
      expect(studentsSnap.docs.single.data()['classId'], 'class-mont2');
      final enrollmentsSnap = await firestore.collection('student_enrollments').get();
      expect(enrollmentsSnap.docs, isEmpty, reason: 'no enrollment may be written when no academic year exists');
    });
  });

  group('AY-IMPLEMENT-02-B — Class filtering by academicYearId', () {
    testWidgets('16. A migrated Class (with academicYearId) is offered via the id, even with a disagreeing/absent legacy string', (tester) async {
      final firestore = FakeFirebaseFirestore();
      final currentYearId = await _seedCurrentYear(firestore); // 2026-2027
      // Legacy text deliberately does NOT match "2026-2027" — only the id does.
      await _seedClass(firestore, 'class-mont2', 'Mont 2', '2099-2100', academicYearId: currentYearId);

      await tester.pumpWidget(_pumpable(_form(firestore), firestore: firestore));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(ValueKey('class_dropdown_$currentYearId')));
      await tester.pumpAndSettle();
      expect(find.text('Mont 2'), findsWidgets, reason: 'academicYearId, not the disagreeing string, must drive the filter');
    });

    testWidgets('17. Legacy Classes (no academicYearId) still work through the string-matching fallback', (tester) async {
      final firestore = FakeFirebaseFirestore();
      final currentYearId = await _seedCurrentYear(firestore);
      await _seedClass(firestore, 'class-mont2', 'Mont 2', '2026-2027'); // no academicYearId at all

      await tester.pumpWidget(_pumpable(_form(firestore), firestore: firestore));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(ValueKey('class_dropdown_$currentYearId')));
      await tester.pumpAndSettle();
      expect(find.text('Mont 2'), findsWidgets);
    });

    testWidgets('18. Switching academic years updates Class choices for a mix of migrated and legacy Classes', (tester) async {
      final firestore = FakeFirebaseFirestore();
      final currentYearId = await _seedCurrentYear(firestore); // 2026-2027
      final historicalYearId = await _seedHistoricalYear(firestore); // 2025-2026
      await _seedClass(firestore, 'class-mont2', 'Mont 2', '2026-2027', academicYearId: currentYearId);
      await _seedClass(firestore, 'class-premont', 'Pre Mont', '2025-2026'); // legacy, string-matched

      await tester.pumpWidget(_pumpable(_form(firestore), firestore: firestore));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(ValueKey('class_dropdown_$currentYearId')));
      await tester.pumpAndSettle();
      expect(find.text('Mont 2'), findsWidgets);
      expect(find.text('Pre Mont'), findsNothing);
      await tester.tap(find.text('Mont 2').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('2026-2027 • Current'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2025-2026 • Historical').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(ValueKey('class_dropdown_$historicalYearId')));
      await tester.pumpAndSettle();
      expect(find.text('Pre Mont'), findsWidgets);
      expect(find.text('Mont 2'), findsNothing);
    });

    testWidgets('19. Switching to a year with no matching class clears the previous (now invalid) selection', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedCurrentYear(firestore); // 2026-2027
      final historicalYearId = await _seedHistoricalYear(firestore); // 2025-2026
      await _seedClass(firestore, 'class-mont2', 'Mont 2', '2026-2027');
      // No class at all offered for the historical year.

      await tester.pumpWidget(_pumpable(_form(firestore), firestore: firestore));
      await tester.pumpAndSettle();

      await tester.tap(find.text('2026-2027 • Current'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2025-2026 • Historical').last);
      await tester.pumpAndSettle();

      // The Class dropdown for the historical year has no items and no
      // selection — "Mont 2" (only valid for the previous year) must never
      // still be shown as selected.
      expect(find.byKey(ValueKey('class_dropdown_$historicalYearId')), findsOneWidget);
      expect(find.text('Mont 2'), findsNothing);
    });

    testWidgets('20. Historical-year selection via academicYearId still creates the enrollment without touching Student.classId', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedCurrentYear(firestore); // 2026-2027
      final historicalYearId = await _seedHistoricalYear(firestore); // 2025-2026
      await _seedClass(firestore, 'class-premont', 'Pre Mont', '2025-2026', academicYearId: historicalYearId);

      await tester.pumpWidget(_pumpable(_form(firestore), firestore: firestore));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2026-2027 • Current'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2025-2026 • Historical').last);
      await tester.pumpAndSettle();

      await _fillRequiredFields(tester);
      await tester.ensureVisible(find.widgetWithText(ElevatedButton, 'Save'));
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
      await tester.pumpAndSettle();

      final studentsSnap = await firestore.collection('students').get();
      expect(studentsSnap.docs.single.data()['classId'], isNot('class-premont'), reason: 'a historical-year save never syncs Student.classId');

      final enrollmentService = StudentEnrollmentService(firestore: firestore);
      final enrollments = await enrollmentService.getEnrollmentsForStudent(
        schoolId: kDefaultSchoolId,
        studentId: studentsSnap.docs.single.id,
      );
      expect(enrollments.single.academicYearId, historicalYearId);
      expect(enrollments.single.classId, 'class-premont');
    });

    testWidgets('21. Current-year save behavior is unchanged for a migrated (academicYearId) Class: Student.classId is synced', (tester) async {
      final firestore = FakeFirebaseFirestore();
      final currentYearId = await _seedCurrentYear(firestore);
      await _seedClass(firestore, 'class-mont2', 'Mont 2', '2026-2027', academicYearId: currentYearId);

      await tester.pumpWidget(_pumpable(_form(firestore), firestore: firestore));
      await tester.pumpAndSettle();
      await _fillRequiredFields(tester);
      await tester.ensureVisible(find.widgetWithText(ElevatedButton, 'Save'));
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
      await tester.pumpAndSettle();

      final studentsSnap = await firestore.collection('students').get();
      expect(studentsSnap.docs.single.data()['classId'], 'class-mont2');
    });
  });

  group('EDIT STUDENT', () {
    testWidgets('8. Existing current-year enrollment loads its own Academic Year + Class', (tester) async {
      final firestore = FakeFirebaseFirestore();
      final currentYearId = await _seedCurrentYear(firestore);
      await _seedClass(firestore, 'class-mont2', 'Mont 2', '2026-2027');
      await firestore.collection('students').doc('s1').set({
        'name': 'Abdul', 'admissionNo': 'ADM-1', 'classId': 'class-mont2', 'isActive': true,
      });
      await StudentEnrollmentService(firestore: firestore).createEnrollment(
        schoolId: kDefaultSchoolId, requesterRole: 'admin', studentId: 's1',
        academicYearId: currentYearId, classId: 'class-mont2', createdBy: 'admin-1',
      );

      await tester.pumpWidget(_pumpable(
        _form(firestore, studentId: 's1', initialData: _existingStudentData(name: 'Abdul', classId: 'class-mont2')),
        firestore: firestore,
      ));
      await tester.pumpAndSettle();

      expect(find.text('2026-2027 • Current'), findsOneWidget);
      expect(find.text('Editing historical academic-year placement'), findsNothing);
    });

    testWidgets('9. Student without a current-year enrollment falls back to Student.classId', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedCurrentYear(firestore);
      await _seedClass(firestore, 'class-mont2', 'Mont 2', '2026-2027');
      await firestore.collection('students').doc('s1').set({
        'name': 'Abdul', 'admissionNo': 'ADM-1', 'classId': 'class-mont2', 'isActive': true,
      });
      // No StudentEnrollment exists for this student at all — expected
      // for pre-existing UAT data.

      await tester.pumpWidget(_pumpable(
        _form(firestore, studentId: 's1', initialData: _existingStudentData(name: 'Abdul', classId: 'class-mont2')),
        firestore: firestore,
      ));
      await tester.pumpAndSettle();

      expect(find.text('2026-2027 • Current'), findsOneWidget);
      // The Class dropdown falls back to the student's existing classId —
      // asserted indirectly via a successful save establishing exactly
      // one enrollment for class-mont2 below.
      await tester.ensureVisible(find.widgetWithText(ElevatedButton, 'Save'));
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
      await tester.pumpAndSettle();

      final enrollments = await StudentEnrollmentService(firestore: firestore)
          .getEnrollmentsForStudent(schoolId: kDefaultSchoolId, studentId: 's1');
      expect(enrollments, hasLength(1));
      expect(enrollments.single.classId, 'class-mont2');
    });

    testWidgets('10/11/16/17. Editing current-year class updates StudentEnrollment and Student.classId, reflected immediately', (tester) async {
      final firestore = FakeFirebaseFirestore();
      final currentYearId = await _seedCurrentYear(firestore);
      await _seedClass(firestore, 'class-mont2', 'Mont 2', '2026-2027');
      await _seedClass(firestore, 'class-mont3', 'Mont 3', '2026-2027');
      await firestore.collection('students').doc('s1').set({
        'name': 'Abdul', 'admissionNo': 'ADM-1', 'classId': 'class-mont2', 'isActive': true,
      });
      await StudentEnrollmentService(firestore: firestore).createEnrollment(
        schoolId: kDefaultSchoolId, requesterRole: 'admin', studentId: 's1',
        academicYearId: currentYearId, classId: 'class-mont2', createdBy: 'admin-1',
      );

      await tester.pumpWidget(_pumpable(
        _form(firestore, studentId: 's1', initialData: _existingStudentData(name: 'Abdul', classId: 'class-mont2')),
        firestore: firestore,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Mont 2'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mont 3').last);
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.widgetWithText(ElevatedButton, 'Save'));
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
      await tester.pumpAndSettle();

      final studentDoc = await firestore.collection('students').doc('s1').get();
      expect(studentDoc.data()!['classId'], 'class-mont3');

      final enrollments = await StudentEnrollmentService(firestore: firestore)
          .getEnrollmentsForStudent(schoolId: kDefaultSchoolId, studentId: 's1');
      expect(enrollments, hasLength(1), reason: 'must update, never duplicate');
      expect(enrollments.single.classId, 'class-mont3');
      expect(enrollments.single.academicYearId, currentYearId);
    });

    testWidgets('12/13/14/15/18. Historical enrollment can be edited without touching Student.classId or the current-year row', (tester) async {
      final firestore = FakeFirebaseFirestore();
      final currentYearId = await _seedCurrentYear(firestore);
      final historicalYearId = await _seedHistoricalYear(firestore);
      await _seedClass(firestore, 'class-mont2', 'Mont 2', '2026-2027');
      await _seedClass(firestore, 'class-premont', 'Pre Mont', '2025-2026');
      await _seedClass(firestore, 'class-mont1', 'Mont 1', '2025-2026');
      await firestore.collection('students').doc('s1').set({
        'name': 'Abdul', 'admissionNo': 'ADM-1', 'classId': 'class-mont2', 'isActive': true,
      });
      final enrollmentService = StudentEnrollmentService(firestore: firestore);
      await enrollmentService.createEnrollment(
        schoolId: kDefaultSchoolId, requesterRole: 'admin', studentId: 's1',
        academicYearId: currentYearId, classId: 'class-mont2', createdBy: 'admin-1',
      );
      await enrollmentService.createEnrollment(
        schoolId: kDefaultSchoolId, requesterRole: 'admin', studentId: 's1',
        academicYearId: historicalYearId, classId: 'class-premont', createdBy: 'admin-1',
      );

      await tester.pumpWidget(_pumpable(
        _form(firestore, studentId: 's1', initialData: _existingStudentData(name: 'Abdul', classId: 'class-mont2')),
        firestore: firestore,
      ));
      await tester.pumpAndSettle();

      // Switch to the historical year.
      await tester.tap(find.text('2026-2027 • Current'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2025-2026 • Historical').last);
      await tester.pumpAndSettle();

      expect(find.text('Editing historical academic-year placement'), findsOneWidget);
      // Its existing historical class (Pre Mont) loads.
      expect(find.text('Pre Mont'), findsOneWidget);

      await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Pre Mont'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mont 1').last);
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.widgetWithText(ElevatedButton, 'Save'));
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
      await tester.pumpAndSettle();

      final studentDoc = await firestore.collection('students').doc('s1').get();
      expect(studentDoc.data()!['classId'], 'class-mont2', reason: 'a historical edit must never change Student.classId');

      final enrollments = await enrollmentService.getEnrollmentsForStudent(
        schoolId: kDefaultSchoolId,
        studentId: 's1',
      );
      expect(enrollments, hasLength(2), reason: 'must update the existing historical row, never duplicate it');
      final historical = enrollments.firstWhere((e) => e.academicYearId == historicalYearId);
      final current = enrollments.firstWhere((e) => e.academicYearId == currentYearId);
      expect(historical.classId, 'class-mont1');
      expect(current.classId, 'class-mont2', reason: 'the current-year row must be untouched by a historical edit');
    });
  });

  group('19-22. Regression', () {
    testWidgets('19/20/21. Profile/Parents/Documents tabs still render without error', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedCurrentYear(firestore);
      await _seedClass(firestore, 'class-mont2', 'Mont 2', '2026-2027');
      await firestore.collection('students').doc('s1').set({
        'name': 'Abdul', 'admissionNo': 'ADM-1', 'classId': 'class-mont2', 'isActive': true,
      });

      await tester.pumpWidget(_pumpable(
        _form(firestore, studentId: 's1', initialData: _existingStudentData(name: 'Abdul', classId: 'class-mont2')),
        firestore: firestore,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Full Name'), findsOneWidget);
      final nameField = tester.widget<TextFormField>(find.byType(TextFormField).at(0));
      expect(nameField.controller!.text, 'Abdul');

      await tester.tap(find.text('Parents'));
      await tester.pumpAndSettle();
      expect(find.text('Linked Parents'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Documents'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('22. ClassService.getStudentsByClassId reflects a class change made through the form', (tester) async {
      final firestore = FakeFirebaseFirestore();
      final currentYearId = await _seedCurrentYear(firestore);
      await _seedClass(firestore, 'class-mont2', 'Mont 2', '2026-2027');
      await _seedClass(firestore, 'class-mont3', 'Mont 3', '2026-2027');
      await firestore.collection('students').doc('s1').set({
        'name': 'Abdul', 'admissionNo': 'ADM-1', 'classId': 'class-mont2', 'isActive': true,
      });
      await StudentEnrollmentService(firestore: firestore).createEnrollment(
        schoolId: kDefaultSchoolId, requesterRole: 'admin', studentId: 's1',
        academicYearId: currentYearId, classId: 'class-mont2', createdBy: 'admin-1',
      );

      await tester.pumpWidget(_pumpable(
        _form(firestore, studentId: 's1', initialData: _existingStudentData(name: 'Abdul', classId: 'class-mont2')),
        firestore: firestore,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Mont 2'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mont 3').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.widgetWithText(ElevatedButton, 'Save'));
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
      await tester.pumpAndSettle();

      final classService = ClassService(firestore: firestore);
      expect((await classService.getStudentsByClassId('class-mont2')), isEmpty);
      expect((await classService.getStudentsByClassId('class-mont3')).map((d) => d.id), ['s1']);
    });

    testWidgets('Attendance/Fees data is unaffected by saving through the form', (tester) async {
      final firestore = FakeFirebaseFirestore();
      final currentYearId = await _seedCurrentYear(firestore);
      await _seedClass(firestore, 'class-mont2', 'Mont 2', '2026-2027');
      await firestore.collection('students').doc('s1').set({
        'name': 'Abdul', 'admissionNo': 'ADM-1', 'classId': 'class-mont2', 'isActive': true,
      });
      final feeDoc = await firestore.collection('student_fee_assignments').add({
        'studentId': 's1', 'academicYear': '2026-2027', 'totalFee': 50000, 'status': 'unpaid',
      });
      final attendanceService = AttendanceService(firestore: firestore, storage: MockFirebaseStorage());
      await attendanceService.markStudentAttendance(
        studentId: 's1', studentName: 'Abdul', classId: 'class-mont2', markedBy: 'admin-1', status: 'present',
      );

      await tester.pumpWidget(_pumpable(
        _form(firestore, studentId: 's1', initialData: _existingStudentData(name: 'Abdul', classId: 'class-mont2')),
        firestore: firestore,
      ));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.widgetWithText(ElevatedButton, 'Save'));
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
      await tester.pumpAndSettle();

      final feeSnap = await feeDoc.get();
      expect(feeSnap.data()!['academicYear'], '2026-2027');
      expect(feeSnap.data()!['totalFee'], 50000);
      final attendance = await attendanceService.getTodayAttendanceMap();
      expect(attendance['student_s1']?['status'], 'present');
      expect(currentYearId, isNotEmpty);
    });
  });

  group('Responsive layout — no overflow at required widths', () {
    const widths = <String, Size>{
      '390x844': Size(390, 844),
      '412x915': Size(412, 915),
      '768x1024': Size(768, 1024),
      '1440x900': Size(1440, 900),
    };

    testWidgets('Add Student form (with Academic Year + Class) has no overflow at any required width', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedCurrentYear(firestore);
      await _seedHistoricalYear(firestore);
      await _seedClass(firestore, 'class-mont2', 'Mont 2', '2026-2027');

      for (final entry in widths.entries) {
        final originalSize = tester.view.physicalSize;
        final originalDpr = tester.view.devicePixelRatio;
        tester.view.physicalSize = entry.value;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.physicalSize = originalSize;
          tester.view.devicePixelRatio = originalDpr;
        });

        final errors = <FlutterErrorDetails>[];
        final previousOnError = FlutterError.onError;
        FlutterError.onError = (details) => errors.add(details);
        try {
          await tester.pumpWidget(_pumpable(_form(firestore), firestore: firestore));
          await tester.pumpAndSettle();
        } finally {
          FlutterError.onError = previousOnError;
        }
        expect(
          errors,
          isEmpty,
          reason: 'Overflow/render error at ${entry.key}: ${errors.map((e) => e.exceptionAsString()).join(', ')}',
        );
      }
    });

    testWidgets('Edit Student form (historical selection + label) has no overflow at any required width', (tester) async {
      final firestore = FakeFirebaseFirestore();
      final currentYearId = await _seedCurrentYear(firestore);
      await _seedHistoricalYear(firestore);
      await _seedClass(firestore, 'class-mont2', 'Mont 2', '2026-2027');
      await firestore.collection('students').doc('s1').set({
        'name': 'A Reasonably Long Student Name', 'admissionNo': 'ADM-1', 'classId': 'class-mont2', 'isActive': true,
      });
      await StudentEnrollmentService(firestore: firestore).createEnrollment(
        schoolId: kDefaultSchoolId, requesterRole: 'admin', studentId: 's1',
        academicYearId: currentYearId, classId: 'class-mont2', createdBy: 'admin-1',
      );

      for (final entry in widths.entries) {
        final originalSize = tester.view.physicalSize;
        final originalDpr = tester.view.devicePixelRatio;
        tester.view.physicalSize = entry.value;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.physicalSize = originalSize;
          tester.view.devicePixelRatio = originalDpr;
        });

        final errors = <FlutterErrorDetails>[];
        final previousOnError = FlutterError.onError;
        FlutterError.onError = (details) => errors.add(details);
        try {
          // Keyed per width so each loop iteration mounts a brand-new
          // Element/State — otherwise Flutter's widget diffing reuses the
          // *same* AdminStudentForm State across pumpWidget calls (same
          // type/position, no key), so the previous iteration's "switch to
          // historical year" tap would still be in effect here instead of
          // each iteration starting fresh.
          await tester.pumpWidget(_pumpable(
            _form(
              firestore,
              studentId: 's1',
              initialData: _existingStudentData(name: 'A Reasonably Long Student Name', classId: 'class-mont2'),
              key: ValueKey(entry.key),
            ),
            firestore: firestore,
          ));
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('2026-2027 • Current'));
          await tester.tap(find.text('2026-2027 • Current'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('2025-2026 • Historical').last);
          await tester.pumpAndSettle();
        } finally {
          FlutterError.onError = previousOnError;
        }
        expect(
          errors,
          isEmpty,
          reason: 'Overflow/render error at ${entry.key}: ${errors.map((e) => e.exceptionAsString()).join(', ')}',
        );
      }
    });
  });
}

/// Fills every required `TextFormField` on the Students tab
/// (`_textField`'s own validator requires Full Name/Admission No/Address
/// Line 1/City/State/Pincode) by stable position. Every Academic
/// Year/Class/Gender/Blood Group field is a `DropdownButtonFormField`, not
/// a `TextFormField`, so this ordering — Full Name(0), Admission No(1),
/// Section(2), Roll Number(3), DOB(4), Age(5), Nationality(6), Mother
/// Tongue(7), Address Line 1(8), Address Line 2(9), City(10), State(11),
/// Pincode(12) — holds regardless of whether the Academic Year feature is
/// enabled for a given test.
Future<void> _fillRequiredFields(
  WidgetTester tester, {
  String name = 'Aarav Kumar',
  String admissionNo = 'ADM-2026-100',
}) async {
  final fields = find.byType(TextFormField);
  await tester.enterText(fields.at(0), name); // Full Name
  await tester.enterText(fields.at(1), admissionNo); // Admission No
  await tester.enterText(fields.at(8), '12 Garden Road'); // Address Line 1
  await tester.enterText(fields.at(10), 'Coimbatore'); // City
  await tester.enterText(fields.at(11), 'Tamil Nadu'); // State
  await tester.enterText(fields.at(12), '641001'); // Pincode
}
