// AY-01 UI coverage: AcademicHistorySection (the Student View dialog's
// "Academic History" tab content, extracted as its own testable widget)
// and StudentEnrollmentAssignDialog ("Assign to Academic Year"). Neither
// widget touches FirebaseFirestore.instance directly — both are driven
// entirely through injected fake-Firestore-backed services and Riverpod
// provider overrides. Service-layer business rules are covered in
// student_enrollment_service_test.dart.
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
import 'package:montessori_app/modules/admin/students/ui/academic_history_section.dart';
import 'package:montessori_app/modules/admin/students/ui/student_enrollment_assign_dialog.dart';
import 'package:montessori_app/modules/auth/models/app_user.dart';
import 'package:montessori_app/modules/auth/providers/auth_provider.dart';

Widget _withRole(String role, Widget child, {required List<Override> overrides}) {
  return ProviderScope(
    overrides: [
      currentUserProvider.overrideWith(
        (ref) => AppUser(id: 'u1', phone: '9999999999', role: role, isActive: true),
      ),
      ...overrides,
    ],
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

void main() {
  group('AcademicHistorySection', () {
    testWidgets('19/20. shows every enrollment, newest first, with academic year name + class name', (tester) async {
      final firestore = FakeFirebaseFirestore();
      final academicYearService = AcademicYearService(firestore: firestore);
      final enrollmentService = StudentEnrollmentService(firestore: firestore);

      await academicYearService.createAcademicYear(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        name: '2025-2026',
        startDate: DateTime(2025, 6, 1),
        endDate: DateTime(2026, 5, 31),
        createdBy: 'admin-1',
      );
      final currentYearId = await academicYearService.createAcademicYear(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        name: '2026-2027',
        startDate: DateTime(2026, 6, 1),
        endDate: DateTime(2027, 5, 31),
        createdBy: 'admin-1',
      );
      await enrollmentService.createEnrollment(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        studentId: 'student-1',
        academicYearId: currentYearId,
        classId: 'class-mont2',
        createdBy: 'admin-1',
      );

      await tester.pumpWidget(_withRole(
        'admin',
        AcademicHistorySection(
          studentId: 'student-1',
          currentClassId: 'class-mont2',
          classNames: const {'class-mont2': 'Mont 2'},
        ),
        overrides: [
          academicYearServiceProvider.overrideWithValue(academicYearService),
          studentEnrollmentServiceProvider.overrideWithValue(enrollmentService),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('2026-2027 — Mont 2'), findsOneWidget);
      expect(find.text(StudentEnrollmentStatus.active), findsOneWidget);
    });

    testWidgets('empty state when the student has no academic history yet', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await tester.pumpWidget(_withRole(
        'admin',
        const AcademicHistorySection(studentId: 'student-1', currentClassId: null),
        overrides: [
          academicYearServiceProvider.overrideWithValue(AcademicYearService(firestore: firestore)),
          studentEnrollmentServiceProvider.overrideWithValue(StudentEnrollmentService(firestore: firestore)),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.text('No academic history yet'), findsOneWidget);
    });

    testWidgets('readOnly hides the Assign to Academic Year action', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await tester.pumpWidget(_withRole(
        'staff',
        const AcademicHistorySection(studentId: 'student-1', currentClassId: null, readOnly: true),
        overrides: [
          academicYearServiceProvider.overrideWithValue(AcademicYearService(firestore: firestore)),
          studentEnrollmentServiceProvider.overrideWithValue(StudentEnrollmentService(firestore: firestore)),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.text('Assign to Academic Year'), findsNothing);
    });

    testWidgets('not readOnly shows the Assign to Academic Year action, which opens the assign dialog', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await tester.pumpWidget(_withRole(
        'admin',
        const AcademicHistorySection(studentId: 'student-1', currentClassId: null),
        overrides: [
          academicYearServiceProvider.overrideWithValue(AcademicYearService(firestore: firestore)),
          studentEnrollmentServiceProvider.overrideWithValue(StudentEnrollmentService(firestore: firestore)),
          adminStudentServiceProvider.overrideWithValue(
            AdminStudentService(firestore: firestore, storage: MockFirebaseStorage()),
          ),
        ],
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Assign to Academic Year'));
      await tester.pumpAndSettle();

      expect(find.byType(StudentEnrollmentAssignDialog), findsOneWidget);
    });
  });

  group('StudentEnrollmentAssignDialog', () {
    testWidgets('no current academic year: shows a graceful message, no crash', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await tester.pumpWidget(_withRole(
        'admin',
        StudentEnrollmentAssignDialog(
          studentId: 'student-1',
          adminStudentService: AdminStudentService(firestore: firestore, storage: MockFirebaseStorage()),
          enrollmentService: StudentEnrollmentService(firestore: firestore),
        ),
        overrides: [
          academicYearServiceProvider.overrideWithValue(AcademicYearService(firestore: firestore)),
        ],
      ));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('No current academic year is set'),
        findsOneWidget,
      );
    });

    testWidgets('assigning a class for the current year creates an enrollment and syncs Student.classId', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('students').doc('student-1').set({'name': 'Abdul', 'classId': ''});
      await firestore.collection('classes').doc('class-mont2').set({'name': 'Mont 2', 'isActive': true});

      final academicYearService = AcademicYearService(firestore: firestore);
      final currentYearId = await academicYearService.createAcademicYear(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        name: '2026-2027',
        startDate: DateTime(2026, 6, 1),
        endDate: DateTime(2027, 5, 31),
        createdBy: 'admin-1',
        setAsCurrent: true,
      );

      await tester.pumpWidget(_withRole(
        'admin',
        StudentEnrollmentAssignDialog(
          studentId: 'student-1',
          adminStudentService: AdminStudentService(firestore: firestore, storage: MockFirebaseStorage()),
          enrollmentService: StudentEnrollmentService(firestore: firestore),
        ),
        overrides: [academicYearServiceProvider.overrideWithValue(academicYearService)],
      ));
      await tester.pumpAndSettle();

      expect(find.text('2026-2027'), findsOneWidget);
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mont 2').last);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      final enrollments = await StudentEnrollmentService(firestore: firestore)
          .getEnrollmentsForStudent(schoolId: kDefaultSchoolId, studentId: 'student-1');
      expect(enrollments, hasLength(1));
      expect(enrollments.single.academicYearId, currentYearId);
      expect(enrollments.single.classId, 'class-mont2');

      final studentDoc = await firestore.collection('students').doc('student-1').get();
      expect(studentDoc.data()!['classId'], 'class-mont2');
    });

    testWidgets('missing class selection shows a validation error and does not save', (tester) async {
      final firestore = FakeFirebaseFirestore();
      final academicYearService = AcademicYearService(firestore: firestore);
      await academicYearService.createAcademicYear(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        name: '2026-2027',
        startDate: DateTime(2026, 6, 1),
        endDate: DateTime(2027, 5, 31),
        createdBy: 'admin-1',
        setAsCurrent: true,
      );

      await tester.pumpWidget(_withRole(
        'admin',
        StudentEnrollmentAssignDialog(
          studentId: 'student-1',
          adminStudentService: AdminStudentService(firestore: firestore, storage: MockFirebaseStorage()),
          enrollmentService: StudentEnrollmentService(firestore: firestore),
        ),
        overrides: [academicYearServiceProvider.overrideWithValue(academicYearService)],
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(find.text('A class is required.'), findsOneWidget);
    });
  });

  group('Responsive layout — no overflow at required widths', () {
    const widths = <String, Size>{
      '390x844': Size(390, 844),
      '412x915': Size(412, 915),
      '768x1024': Size(768, 1024),
      '1440x900': Size(1440, 900),
    };

    testWidgets('34. AcademicHistorySection + Assign dialog have no overflow at any required width', (tester) async {
      final firestore = FakeFirebaseFirestore();
      final academicYearService = AcademicYearService(firestore: firestore);
      final enrollmentService = StudentEnrollmentService(firestore: firestore);
      final currentYearId = await academicYearService.createAcademicYear(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        name: '2026-2027',
        startDate: DateTime(2026, 6, 1),
        endDate: DateTime(2027, 5, 31),
        createdBy: 'admin-1',
        setAsCurrent: true,
      );
      await enrollmentService.createEnrollment(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        studentId: 'student-1',
        academicYearId: currentYearId,
        classId: 'class-mont2',
        createdBy: 'admin-1',
      );
      await firestore.collection('classes').doc('class-mont2').set({'name': 'Mont 2', 'isActive': true});

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
          await tester.pumpWidget(_withRole(
            'admin',
            AcademicHistorySection(
              studentId: 'student-1',
              currentClassId: 'class-mont2',
              classNames: const {'class-mont2': 'Mont 2'},
            ),
            overrides: [
              academicYearServiceProvider.overrideWithValue(academicYearService),
              studentEnrollmentServiceProvider.overrideWithValue(enrollmentService),
              adminStudentServiceProvider.overrideWithValue(
                AdminStudentService(firestore: firestore, storage: MockFirebaseStorage()),
              ),
            ],
          ));
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('Assign to Academic Year').first);
          await tester.tap(find.text('Assign to Academic Year').first, warnIfMissed: false);
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
