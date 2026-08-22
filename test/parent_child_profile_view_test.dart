// Regression coverage for the Parent Child Profile view (Phase C, Test 1) —
// a pure display over an already-resolved AdminStudentModel, no Firestore
// access. Covers: only fields that actually exist on the model are shown,
// missing/empty fields are omitted rather than rendered as blank labels,
// and the profile renders without overflow at every required mobile width
// plus a long-name/long-class-name edge case.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/admin/students/models/admin_student_model.dart';
import 'package:montessori_app/modules/parent/ui/parent_child_profile_view.dart';

AdminStudentModel _student({
  String id = 's1',
  String name = 'Aarav Sharma',
  String admissionNo = 'ADM-2026-001',
  String classId = 'class-1',
  String section = 'A',
  String rollNumber = '',
  dynamic dateOfBirth,
  String gender = '',
  bool isActive = true,
  String profileImageUrl = '',
}) {
  return AdminStudentModel(
    id: id,
    name: name,
    admissionNo: admissionNo,
    classId: classId,
    section: section,
    rollNumber: rollNumber,
    dateOfBirth: dateOfBirth,
    age: null,
    gender: gender,
    bloodGroup: '',
    nationality: '',
    motherTongue: '',
    addressLine1: '',
    addressLine2: '',
    city: '',
    state: '',
    pincode: '',
    isActive: isActive,
    isApproved: true,
    createdAt: null,
    createdBy: null,
    parentLinks: const [],
    documents: const [],
    profileImageUrl: profileImageUrl,
  );
}

Future<void> _openProfile(
  WidgetTester tester, {
  required AdminStudentModel child,
  String className = 'Mont 1',
  String academicYear = '2026-2027',
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () => showChildProfile(
              context,
              child: child,
              className: className,
              academicYear: academicYear,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  group('Child Profile — Test 1: displays linked child information', () {
    testWidgets('shows name, admission number, class, section and academic year from the model', (
      tester,
    ) async {
      await _openProfile(tester, child: _student());

      expect(find.text('Aarav Sharma'), findsOneWidget);
      expect(find.text('ADM-2026-001'), findsOneWidget);
      expect(find.text('Mont 1'), findsWidgets);
      expect(find.text('A'), findsWidgets);
      expect(find.text('2026-2027'), findsOneWidget);
      expect(find.text('Active'), findsOneWidget);
    });

    testWidgets('shows Inactive status chip for an inactive student', (tester) async {
      await _openProfile(tester, child: _student(isActive: false));

      expect(find.text('Inactive'), findsOneWidget);
      expect(find.text('Active'), findsNothing);
    });

    testWidgets('does not render a Roll Number row when the model has none', (tester) async {
      await _openProfile(tester, child: _student(rollNumber: ''));

      expect(find.text('Roll Number'), findsNothing);
    });

    testWidgets('renders a Roll Number row when the model has one', (tester) async {
      await _openProfile(tester, child: _student(rollNumber: '12'));

      expect(find.text('Roll Number'), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
    });

    testWidgets('does not render a Gender row when the model has none', (tester) async {
      await _openProfile(tester, child: _student(gender: ''));
      expect(find.text('Gender'), findsNothing);
    });

    testWidgets('renders a Gender row when the model has one', (tester) async {
      await _openProfile(tester, child: _student(gender: 'Female'));
      expect(find.text('Gender'), findsOneWidget);
      expect(find.text('Female'), findsOneWidget);
    });

    testWidgets('falls back to initials avatar when there is no profile photo', (tester) async {
      await _openProfile(tester, child: _student(name: 'Zoe', profileImageUrl: ''));

      expect(find.text('Z'), findsOneWidget);
    });
  });

  group('Child Profile — responsive behavior', () {
    for (final size in [
      const Size(390, 844),
      const Size(400, 775),
      const Size(412, 915),
      const Size(768, 1024),
    ]) {
      testWidgets('renders without overflow at ${size.width.toInt()}x${size.height.toInt()}', (
        tester,
      ) async {
        final originalSize = tester.view.physicalSize;
        final originalDpr = tester.view.devicePixelRatio;
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.physicalSize = originalSize;
          tester.view.devicePixelRatio = originalDpr;
        });

        await _openProfile(
          tester,
          child: _student(
            name: 'Aariyanaa Balasubramaniam Krishnamurthy',
            classId: 'class-1',
            section: 'Advanced Montessori Section B',
            rollNumber: '2026-0099',
          ),
          className: 'Advanced Foundational Montessori Programme',
        );

        expect(tester.takeException(), isNull);
      });
    }
  });
}
