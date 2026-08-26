// AY-02 coverage: Academic Year integration into the existing Add/Edit
// Class form (ClassFormDialog) — replacing the free-text Academic Year
// field with a canonical AcademicYearModel dropdown while continuing to
// store its selected `.name` into the still-free-text
// `AdminClassModel.academicYear`. Service-layer AcademicYearService rules
// are already covered in academic_year_service_test.dart; this file only
// checks the Class dialog loads/resolves/saves correctly through it.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/admin/settings/data/academic_year_service.dart';
import 'package:montessori_app/modules/admin/settings/models/school_settings_model.dart';
import 'package:montessori_app/modules/admin/settings/providers/academic_year_provider.dart';
import 'package:montessori_app/modules/admin/students/data/student_enrollment_service.dart';
import 'package:montessori_app/modules/attendance/data/attendance_service.dart';
import 'package:montessori_app/modules/classes/data/class_service.dart';
import 'package:montessori_app/modules/classes/ui/class_form_dialog.dart';
import 'package:montessori_app/modules/classes/ui/class_list_screen.dart';

Widget _pumpable(Widget child, {required FakeFirebaseFirestore firestore}) {
  return ProviderScope(
    overrides: [
      academicYearServiceProvider.overrideWithValue(AcademicYearService(firestore: firestore)),
    ],
    child: MaterialApp(home: Scaffold(body: child)),
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

ClassFormDialog _dialog(
  FakeFirebaseFirestore firestore, {
  String? classId,
  Map<String, dynamic>? initialData,
  Key? key,
}) {
  return ClassFormDialog(
    key: key,
    classId: classId,
    initialData: initialData,
    service: ClassService(firestore: firestore),
  );
}

void main() {
  group('ADD CLASS', () {
    testWidgets('1/2/3/4. Academic Year dropdown displayed, loads canonical years, current preselected and labelled', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedCurrentYear(firestore);
      await _seedHistoricalYear(firestore);

      await tester.pumpWidget(_pumpable(_dialog(firestore), firestore: firestore));
      await tester.pumpAndSettle();

      expect(find.text('Academic Year *'), findsOneWidget);
      expect(find.text('2026-2027 • Current'), findsOneWidget);
    });

    testWidgets('5. Historical years are visually labelled "Historical"', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedCurrentYear(firestore);
      await _seedHistoricalYear(firestore);

      await tester.pumpWidget(_pumpable(_dialog(firestore), firestore: firestore));
      await tester.pumpAndSettle();

      await tester.tap(find.text('2026-2027 • Current'));
      await tester.pumpAndSettle();
      expect(find.text('2025-2026 • Historical'), findsWidgets);
    });

    testWidgets('6. Selecting a historical year is allowed', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedCurrentYear(firestore);
      await _seedHistoricalYear(firestore);

      await tester.pumpWidget(_pumpable(_dialog(firestore), firestore: firestore));
      await tester.pumpAndSettle();

      await tester.tap(find.text('2026-2027 • Current'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2025-2026 • Historical').last);
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextFormField, 'Class Name *'), 'Pre Mont B');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      final snap = await firestore.collection('classes').get();
      expect(snap.docs.single.data()['academicYear'], '2025-2026');
    });

    testWidgets('7/8. Saving stores AcademicYearModel.name (never a hardcoded value)', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedCurrentYear(firestore, name: '2029-2030', start: DateTime(2029, 6, 1), end: DateTime(2030, 5, 31));

      await tester.pumpWidget(_pumpable(_dialog(firestore), firestore: firestore));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextFormField, 'Class Name *'), 'Mont X');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      final snap = await firestore.collection('classes').get();
      expect(snap.docs.single.data()['academicYear'], '2029-2030');
    });

    testWidgets('No academic years configured: Save is blocked, no hardcoded fallback', (tester) async {
      final firestore = FakeFirebaseFirestore();
      // No AcademicYearService.createAcademicYear call at all.

      await tester.pumpWidget(_pumpable(_dialog(firestore), firestore: firestore));
      await tester.pumpAndSettle();

      expect(find.textContaining('No academic years configured'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextFormField, 'Class Name *'), 'Mont X');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      final snap = await firestore.collection('classes').get();
      expect(snap.docs, isEmpty);
    });
  });

  group('EDIT CLASS', () {
    testWidgets('9. Existing "2026-2027" class loads with 2026-2027 selected', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedCurrentYear(firestore);
      final classDoc = await firestore.collection('classes').add({
        'name': 'Mont 2', 'academicYear': '2026-2027', 'isActive': true,
      });

      await tester.pumpWidget(_pumpable(
        _dialog(firestore, classId: classDoc.id, initialData: {'name': 'Mont 2', 'academicYear': '2026-2027'}),
        firestore: firestore,
      ));
      await tester.pumpAndSettle();

      expect(find.text('2026-2027 • Current'), findsOneWidget);
    });

    testWidgets('10. Existing historical class loads with the correct historical year', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedCurrentYear(firestore);
      await _seedHistoricalYear(firestore);
      final classDoc = await firestore.collection('classes').add({
        'name': 'Pre Mont', 'academicYear': '2025-2026', 'isActive': true,
      });

      await tester.pumpWidget(_pumpable(
        _dialog(firestore, classId: classDoc.id, initialData: {'name': 'Pre Mont', 'academicYear': '2025-2026'}),
        firestore: firestore,
      ));
      await tester.pumpAndSettle();

      expect(find.text('2025-2026 • Historical'), findsOneWidget);
    });

    testWidgets('11. Editing a class does not automatically change its academic year, even if a different year is current', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedHistoricalYear(firestore); // 2025-2026, not current
      await _seedCurrentYear(firestore); // 2026-2027, current
      final classDoc = await firestore.collection('classes').add({
        'name': 'Pre Mont', 'academicYear': '2025-2026', 'isActive': true, 'teacherName': '',
      });

      await tester.pumpWidget(_pumpable(
        _dialog(firestore, classId: classDoc.id, initialData: {'name': 'Pre Mont', 'academicYear': '2025-2026'}),
        firestore: firestore,
      ));
      await tester.pumpAndSettle();

      // Only edit an unrelated field, leave Academic Year untouched.
      await tester.enterText(find.widgetWithText(TextFormField, 'Class Teacher / Staff in charge'), 'Ms. Kavya');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      final snap = await classDoc.get();
      expect(snap.data()!['academicYear'], '2025-2026', reason: 'must stay historical, not jump to the new current year');
      expect(snap.data()!['teacherName'], 'Ms. Kavya');
    });

    testWidgets('12. Changing the selected year explicitly updates the stored academicYear', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedCurrentYear(firestore);
      await _seedHistoricalYear(firestore);
      final classDoc = await firestore.collection('classes').add({
        'name': 'Pre Mont', 'academicYear': '2026-2027', 'isActive': true,
      });

      await tester.pumpWidget(_pumpable(
        _dialog(firestore, classId: classDoc.id, initialData: {'name': 'Pre Mont', 'academicYear': '2026-2027'}),
        firestore: firestore,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('2026-2027 • Current'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2025-2026 • Historical').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      final snap = await classDoc.get();
      expect(snap.data()!['academicYear'], '2025-2026');
    });

    testWidgets('13/14. Editing a class touches no StudentEnrollment and no Student.classId', (tester) async {
      final firestore = FakeFirebaseFirestore();
      final currentYearId = await _seedCurrentYear(firestore);
      final classDoc = await firestore.collection('classes').add({
        'name': 'Mont 2', 'academicYear': '2026-2027', 'isActive': true,
      });
      await firestore.collection('students').doc('s1').set({'name': 'Abdul', 'classId': classDoc.id});
      await StudentEnrollmentService(firestore: firestore).createEnrollment(
        schoolId: kDefaultSchoolId, requesterRole: 'admin', studentId: 's1',
        academicYearId: currentYearId, classId: classDoc.id, createdBy: 'admin-1',
      );

      await tester.pumpWidget(_pumpable(
        _dialog(firestore, classId: classDoc.id, initialData: {'name': 'Mont 2', 'academicYear': '2026-2027'}),
        firestore: firestore,
      ));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, 'Section'), 'B');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      final enrollments = await StudentEnrollmentService(firestore: firestore)
          .getEnrollmentsForStudent(schoolId: kDefaultSchoolId, studentId: 's1');
      expect(enrollments, hasLength(1));
      expect(enrollments.single.classId, classDoc.id);
      final studentDoc = await firestore.collection('students').doc('s1').get();
      expect(studentDoc.data()!['classId'], classDoc.id);
    });
  });

  group('ORPHANED DATA', () {
    testWidgets('15/16/17/18. Unknown academicYear is detected, never silently substituted, admin can recover, save blocked until then', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedCurrentYear(firestore); // "2026-2027" — does NOT match "2024-2025" below.
      final classDoc = await firestore.collection('classes').add({
        'name': 'Old Class', 'academicYear': '2024-2025', 'isActive': true,
      });

      await tester.pumpWidget(_pumpable(
        _dialog(firestore, classId: classDoc.id, initialData: {'name': 'Old Class', 'academicYear': '2024-2025'}),
        firestore: firestore,
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('"2024-2025"'), findsOneWidget);
      expect(find.text('2026-2027 • Current'), findsNothing, reason: 'must never silently substitute the current year');

      // Save is blocked until the admin explicitly resolves it.
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(find.text('Required'), findsWidgets);
      var snap = await classDoc.get();
      expect(snap.data()!['academicYear'], '2024-2025', reason: 'unresolved orphan must not be overwritten');

      // Admin explicitly resolves it.
      await tester.tap(find.byKey(const ValueKey('academic_year_dropdown_none')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2026-2027 • Current').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      snap = await classDoc.get();
      expect(snap.data()!['academicYear'], '2026-2027');
    });
  });

  group('AY-IMPLEMENT-02-B — additive academicYearId (CLASS CREATE)', () {
    testWidgets('6/7/8. Selecting 2026-2027 writes both academicYearId (from AcademicYearModel.id) and academicYear (from .name)', (tester) async {
      final firestore = FakeFirebaseFirestore();
      final yearId = await _seedCurrentYear(firestore);

      await tester.pumpWidget(_pumpable(_dialog(firestore), firestore: firestore));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, 'Class Name *'), 'Mont X');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      final snap = await firestore.collection('classes').get();
      final data = snap.docs.single.data();
      expect(data['academicYearId'], yearId, reason: 'id must come from the selected AcademicYearModel, not derived from the name');
      expect(data['academicYear'], '2026-2027');
    });

    testWidgets('9. No hardcoded academic year: a differently-named/dated current year is still what gets written', (tester) async {
      final firestore = FakeFirebaseFirestore();
      final yearId = await _seedCurrentYear(
        firestore,
        name: '2031-2032',
        start: DateTime(2031, 6, 1),
        end: DateTime(2032, 5, 31),
      );

      await tester.pumpWidget(_pumpable(_dialog(firestore), firestore: firestore));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, 'Class Name *'), 'Mont X');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      final snap = await firestore.collection('classes').get();
      final data = snap.docs.single.data();
      expect(data['academicYearId'], yearId);
      expect(data['academicYear'], '2031-2032');
      expect(data['academicYearId'], isNot('2026-2027'), reason: 'never a hardcoded fallback id/value');
    });
  });

  group('AY-IMPLEMENT-02-B — additive academicYearId (CLASS EDIT)', () {
    testWidgets('10. An existing academicYearId selects the correct year (authoritative over the string)', (tester) async {
      final firestore = FakeFirebaseFirestore();
      final currentYearId = await _seedCurrentYear(firestore); // 2026-2027
      await _seedHistoricalYear(firestore); // 2025-2026
      final classDoc = await firestore.collection('classes').add({
        'name': 'Mont 2',
        // Deliberately disagreeing legacy text — the id must still win.
        'academicYear': '2025-2026',
        'academicYearId': currentYearId,
        'isActive': true,
      });

      await tester.pumpWidget(_pumpable(
        _dialog(firestore, classId: classDoc.id, initialData: {'name': 'Mont 2', 'academicYear': '2025-2026', 'academicYearId': currentYearId}),
        firestore: firestore,
      ));
      await tester.pumpAndSettle();

      expect(find.text('2026-2027 • Current'), findsOneWidget, reason: 'academicYearId is authoritative, not the disagreeing string');
    });

    testWidgets('11. Legacy Class (no academicYearId) still selects via the string-matching fallback', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedCurrentYear(firestore);
      await _seedHistoricalYear(firestore);
      final classDoc = await firestore.collection('classes').add({
        'name': 'Pre Mont', 'academicYear': '2025-2026', 'isActive': true,
      });

      await tester.pumpWidget(_pumpable(
        _dialog(firestore, classId: classDoc.id, initialData: {'name': 'Pre Mont', 'academicYear': '2025-2026'}),
        firestore: firestore,
      ));
      await tester.pumpAndSettle();

      expect(find.text('2025-2026 • Historical'), findsOneWidget);
    });

    testWidgets('12. Both fields agreeing: no mismatch warning shown', (tester) async {
      final firestore = FakeFirebaseFirestore();
      final yearId = await _seedCurrentYear(firestore);
      final classDoc = await firestore.collection('classes').add({
        'name': 'Mont 2', 'academicYear': '2026-2027', 'academicYearId': yearId, 'isActive': true,
      });

      await tester.pumpWidget(_pumpable(
        _dialog(firestore, classId: classDoc.id, initialData: {'name': 'Mont 2', 'academicYear': '2026-2027', 'academicYearId': yearId}),
        firestore: firestore,
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('does not match its stored academic year'), findsNothing);
    });

    testWidgets('13. Both fields disagreeing is surfaced as a clear warning, never silently repaired', (tester) async {
      final firestore = FakeFirebaseFirestore();
      final currentYearId = await _seedCurrentYear(firestore); // 2026-2027
      await _seedHistoricalYear(firestore); // 2025-2026
      final classDoc = await firestore.collection('classes').add({
        'name': 'Mont 2', 'academicYear': '2025-2026', 'academicYearId': currentYearId, 'isActive': true,
      });

      await tester.pumpWidget(_pumpable(
        _dialog(firestore, classId: classDoc.id, initialData: {'name': 'Mont 2', 'academicYear': '2025-2026', 'academicYearId': currentYearId}),
        firestore: firestore,
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('does not match its stored academic year'), findsOneWidget);
      expect(find.textContaining('"2025-2026"'), findsOneWidget);
    });

    testWidgets('14. No automatic correction on load: opening a mismatched Class writes nothing until Save', (tester) async {
      final firestore = FakeFirebaseFirestore();
      final currentYearId = await _seedCurrentYear(firestore); // 2026-2027
      await _seedHistoricalYear(firestore); // 2025-2026
      final classDoc = await firestore.collection('classes').add({
        'name': 'Mont 2', 'academicYear': '2025-2026', 'academicYearId': currentYearId, 'isActive': true,
      });

      await tester.pumpWidget(_pumpable(
        _dialog(firestore, classId: classDoc.id, initialData: {'name': 'Mont 2', 'academicYear': '2025-2026', 'academicYearId': currentYearId}),
        firestore: firestore,
      ));
      await tester.pumpAndSettle();
      // No Save tapped — just opening (and loading) the dialog.

      final snap = await classDoc.get();
      expect(snap.data()!['academicYear'], '2025-2026', reason: 'still exactly what it was — load never writes');
      expect(snap.data()!['academicYearId'], currentYearId, reason: 'still exactly what it was — load never writes');
    });

    testWidgets('15. Explicitly selecting a different year and saving updates both fields, resolving the mismatch', (tester) async {
      final firestore = FakeFirebaseFirestore();
      final currentYearId = await _seedCurrentYear(firestore); // 2026-2027
      final historicalYearId = await _seedHistoricalYear(firestore); // 2025-2026
      final classDoc = await firestore.collection('classes').add({
        'name': 'Mont 2', 'academicYear': '2025-2026', 'academicYearId': currentYearId, 'isActive': true,
      });

      await tester.pumpWidget(_pumpable(
        _dialog(firestore, classId: classDoc.id, initialData: {'name': 'Mont 2', 'academicYear': '2025-2026', 'academicYearId': currentYearId}),
        firestore: firestore,
      ));
      await tester.pumpAndSettle();

      // Preselected on the authoritative id's year (2026-2027) — explicitly
      // switch to the historical year instead, then save.
      await tester.tap(find.text('2026-2027 • Current'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2025-2026 • Historical').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      final snap = await classDoc.get();
      expect(snap.data()!['academicYearId'], historicalYearId);
      expect(snap.data()!['academicYear'], '2025-2026');
    });
  });

  group('CURRENT YEAR', () {
    testWidgets('19/20. Changing the canonical current Academic Year does not rewrite existing Class records', (tester) async {
      final firestore = FakeFirebaseFirestore();
      final academicYearService = AcademicYearService(firestore: firestore);
      final firstYearId = await _seedCurrentYear(firestore); // 2026-2027, current
      final classDoc = await firestore.collection('classes').add({
        'name': 'Mont 2', 'academicYear': '2026-2027', 'isActive': true,
      });

      final secondYearId = await academicYearService.createAcademicYear(
        schoolId: kDefaultSchoolId, requesterRole: 'admin', name: '2027-2028',
        startDate: DateTime(2027, 6, 1), endDate: DateTime(2028, 5, 31), createdBy: 'admin-1',
      );
      await academicYearService.setCurrentAcademicYear(
        schoolId: kDefaultSchoolId, requesterRole: 'admin', id: secondYearId, updatedBy: 'admin-1',
      );

      final snap = await classDoc.get();
      expect(snap.data()!['academicYear'], '2026-2027', reason: 'existing Class records are untouched by a current-year change');
      expect(firstYearId, isNotEmpty);
    });
  });

  group('21-30. Regression', () {
    testWidgets('21/22/23/24/25/26/27. Class Name/Section/Capacity/Teacher/Description/Active/Approval still work', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedCurrentYear(firestore);

      await tester.pumpWidget(_pumpable(_dialog(firestore), firestore: firestore));
      await tester.pumpAndSettle();

      // Class Name required.
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(find.text('Required'), findsWidgets);

      await tester.enterText(find.widgetWithText(TextFormField, 'Class Name *'), 'Mont 4');
      await tester.enterText(find.widgetWithText(TextFormField, 'Section'), 'C');
      await tester.enterText(find.widgetWithText(TextFormField, 'Capacity'), 'not-a-number');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a valid number'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextFormField, 'Capacity'), '25');
      await tester.enterText(find.widgetWithText(TextFormField, 'Class Teacher / Staff in charge'), 'Mr. Rahul');
      await tester.enterText(find.widgetWithText(TextFormField, 'Description / Notes'), 'New batch');

      await tester.ensureVisible(find.widgetWithText(SwitchListTile, 'Active'));
      await tester.tap(find.widgetWithText(SwitchListTile, 'Active'));
      await tester.pumpAndSettle();

      final approvalDropdown = find.byType(DropdownButtonFormField<String>).last;
      await tester.ensureVisible(approvalDropdown);
      await tester.tap(approvalDropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rejected').last);
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      final snap = await firestore.collection('classes').get();
      final data = snap.docs.single.data();
      expect(data['name'], 'Mont 4');
      expect(data['section'], 'C');
      expect(data['capacity'], 25);
      expect(data['teacherName'], 'Mr. Rahul');
      expect(data['description'], 'New batch');
      expect(data['isActive'], false);
      expect(data['approvalStatus'], 'Rejected');
      expect(data['academicYear'], '2026-2027');
    });

    testWidgets('28/29. Existing Class list still renders and Edit still opens with existing data', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedCurrentYear(firestore);
      await firestore.collection('classes').add({
        'name': 'Mont 2', 'section': 'A', 'academicYear': '2026-2027', 'isActive': true,
        'approvalStatus': 'Approved', 'createdAt': Timestamp.now(),
      });

      await tester.pumpWidget(_pumpable(
        ClassListScreen(service: ClassService(firestore: firestore)),
        firestore: firestore,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Mont 2'), findsOneWidget);
      expect(find.text('Academic Year 2026-2027'), findsOneWidget);

      await tester.tap(find.byTooltip('Edit'));
      await tester.pumpAndSettle();
      expect(find.text('Edit Class'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Class Name *'), findsOneWidget);
    });

    testWidgets('30. Existing Class delete behavior still works', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedCurrentYear(firestore);
      final classDoc = await firestore.collection('classes').add({
        'name': 'Mont 2', 'academicYear': '2026-2027', 'isActive': true,
        'approvalStatus': 'Approved', 'createdAt': Timestamp.now(),
      });

      await tester.pumpWidget(_pumpable(
        ClassListScreen(service: ClassService(firestore: firestore)),
        firestore: firestore,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      final snap = await firestore.collection('classes').doc(classDoc.id).get();
      expect(snap.exists, isFalse);
    });
  });

  group('Architectural regression — Student/Attendance untouched', () {
    testWidgets('Saving a Class change never touches Attendance or unrelated Student data', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedCurrentYear(firestore);
      final classDoc = await firestore.collection('classes').add({
        'name': 'Mont 2', 'academicYear': '2026-2027', 'isActive': true,
      });
      await firestore.collection('students').doc('s1').set({'name': 'Abdul', 'classId': classDoc.id});
      final attendanceService = AttendanceService(firestore: firestore, storage: MockFirebaseStorage());
      await attendanceService.markStudentAttendance(
        studentId: 's1', studentName: 'Abdul', classId: classDoc.id, markedBy: 'admin-1', status: 'present',
      );

      await tester.pumpWidget(_pumpable(
        _dialog(firestore, classId: classDoc.id, initialData: {'name': 'Mont 2', 'academicYear': '2026-2027'}),
        firestore: firestore,
      ));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, 'Capacity'), '30');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      final studentDoc = await firestore.collection('students').doc('s1').get();
      expect(studentDoc.data()!['classId'], classDoc.id);
      final attendance = await attendanceService.getTodayAttendanceMap();
      expect(attendance['student_s1']?['status'], 'present');
    });
  });

  group('Responsive layout — no overflow at required widths', () {
    const widths = <String, Size>{
      '390x844': Size(390, 844),
      '412x915': Size(412, 915),
      '768x1024': Size(768, 1024),
      '1440x900': Size(1440, 900),
    };

    testWidgets('Add/Edit Class dialog (with Academic Year dropdown) has no overflow at any required width', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedCurrentYear(firestore);
      await _seedHistoricalYear(firestore);
      final classDoc = await firestore.collection('classes').add({
        'name': 'A Fairly Long Class Name For Layout Testing', 'academicYear': '2026-2027', 'isActive': true,
      });

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
          await tester.pumpWidget(_pumpable(
            _dialog(
              firestore,
              classId: classDoc.id,
              initialData: {'name': 'A Fairly Long Class Name For Layout Testing', 'academicYear': '2026-2027'},
              key: ValueKey(entry.key),
            ),
            firestore: firestore,
          ));
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

    testWidgets('AY-IMPLEMENT-02-B: the academicYearId/academicYear mismatch warning banner has no overflow at any required width', (tester) async {
      final firestore = FakeFirebaseFirestore();
      final currentYearId = await _seedCurrentYear(firestore);
      await _seedHistoricalYear(firestore);
      final classDoc = await firestore.collection('classes').add({
        'name': 'A Fairly Long Class Name For Layout Testing',
        'academicYear': '2025-2026',
        'academicYearId': currentYearId,
        'isActive': true,
      });

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
          await tester.pumpWidget(_pumpable(
            _dialog(
              firestore,
              classId: classDoc.id,
              initialData: {
                'name': 'A Fairly Long Class Name For Layout Testing',
                'academicYear': '2025-2026',
                'academicYearId': currentYearId,
              },
              key: ValueKey('mismatch_${entry.key}'),
            ),
            firestore: firestore,
          ));
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

    testWidgets('AY-IMPLEMENT-02-B: Class list/view academic-year label (including "Unresolved") has no overflow at any required width', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedCurrentYear(firestore);
      // A class whose academicYearId doesn't resolve to any configured
      // year — exercises the longest label ("Unresolved") this UI shows.
      await firestore.collection('classes').add({
        'name': 'A Fairly Long Class Name For Layout Testing',
        'section': 'A Fairly Long Section Label',
        'academicYearId': 'does-not-exist',
        'isActive': true,
        'approvalStatus': 'Approved',
      });

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
          await tester.pumpWidget(_pumpable(
            ClassListScreen(key: ValueKey('list_${entry.key}'), service: ClassService(firestore: firestore)),
            firestore: firestore,
          ));
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
