// Regression coverage for the ACTUAL production crash on Student → Edit
// Student:
//
//   "There should be exactly one item with [DropdownButton]'s value:
//   KNNDWfwhf4MP04Uixcxp. Either zero or 2 or more [DropdownMenuItem]s
//   were detected with the same value"
//
// An earlier investigation attributed this to the Parents tab's
// Relationship dropdown (see admin_student_form_parent_links_test.dart)
// and reported it fixed. The crash still happened afterward. The runtime
// stack trace this time pinned it exactly:
//
//   package:montessori_app/modules/admin/ui/admin_student_form.dart 798:34
//   <fn>  (new DropdownButtonFormField)
//   package:montessori_app/modules/admin/ui/admin_student_form.dart 728:27
//   <fn>  (LayoutBuilder builder)
//
// Line 798 is the *Class* DropdownButtonFormField in _buildStudentsTab —
// not the Parents tab at all, which matches the screenshot: the crash
// occurred immediately, with the Students tab selected and Parents never
// opened. Both tabs' bodies live in a single TabBarView built up front, so
// the Class dropdown's own bug threw during the very first build, before
// any tab was switched to.
//
// Root cause: `_loadClasses()` used `_classId ??= classes.isNotEmpty ?
// classes.first.id : null` — the null-aware assignment only ever fires
// when `_classId` was null to begin with. For an existing student,
// `_classId` is already set (from `initialData['classId']`) before this
// runs, so it's left completely unvalidated against the freshly loaded
// `_classes` list. `AdminStudentService.getClasses()` only returns
// `isActive: true` classes — so a student whose class was later archived
// (isActive: false, still exists) or genuinely deleted ends up with a
// `_classId` that has zero matching items in the Class dropdown, which is
// exactly what threw here. This is the same class of bug the Relationship
// dropdown had (an unvalidated stored value reaching a
// DropdownButtonFormField's initialValue) — on a different field the
// earlier investigation never checked.
//
// Fix: `_loadClasses()` now reconciles `_classId` against the loaded
// active classes. If it's missing, `AdminStudentService.getClassById` (new
// — bypasses the isActive filter) resolves it directly: if the class still
// exists (archived), it's added to the dropdown's own items so the
// student's real assignment is preserved and selectable; if it's been
// deleted entirely, `_classId` becomes null so the existing "Required"
// validator forces an explicit re-selection, rather than silently
// reassigning the student to an arbitrary different class.
//
// AdminStudentForm/AdminStudentService both already support constructor
// injection (the same DI seam AttendanceService/ParentService/
// AdminNotificationService use), so — unlike the previous investigation,
// which only unit-tested the pure sanitization functions — this file
// drives the actual widget used by Student List → Edit Student
// (student_list_screen.dart's `AdminStudentForm(studentId:, initialData:)`
// call) against a fake Firestore, reproducing the exact crash scenario and
// proving `tester.takeException()` is null after the fix.
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/admin/students/data/admin_student_service.dart';
import 'package:montessori_app/modules/admin/ui/admin_student_form.dart';

const _corruptedId = 'KNNDWfwhf4MP04Uixcxp';

Future<void> _pumpEditStudent(
  WidgetTester tester, {
  required FakeFirebaseFirestore firestore,
  required String studentId,
  required Map<String, dynamic> initialData,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: AdminStudentForm(
        studentId: studentId,
        initialData: initialData,
        service: AdminStudentService(
          firestore: firestore,
          storage: MockFirebaseStorage(),
        ),
        firestore: firestore,
      ),
    ),
  );
  // _loadClasses/_fetchUsers/_loadDocuments are async (they await
  // Firestore reads); settle so the widget actually rebuilds with real
  // data before assertions run, the same as the app would once Firestore
  // responds.
  await tester.pumpAndSettle();
}

Map<String, dynamic> _studentData({
  required String classId,
  List<Map<String, dynamic>> parentLinks = const [],
}) {
  return {
    'name': 'Aarav Kumar',
    'admissionNo': 'ADM-2026-001',
    'classId': classId,
    'section': 'A',
    'isActive': true,
    'parentLinks': parentLinks,
  };
}

void main() {
  group('AdminStudentService.getClassById', () {
    test('resolves a class that exists but is archived (isActive: false)', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('classes').doc('archived-class').set({
        'name': 'Mont 1 (2024 batch)',
        'isActive': false,
      });
      final service = AdminStudentService(
        firestore: firestore,
        storage: MockFirebaseStorage(),
      );

      final result = await service.getClassById('archived-class');

      expect(result, isNotNull);
      expect(result!.data()!['name'], 'Mont 1 (2024 batch)');
    });

    test('returns null for a class that does not exist at all', () async {
      final firestore = FakeFirebaseFirestore();
      final service = AdminStudentService(
        firestore: firestore,
        storage: MockFirebaseStorage(),
      );

      final result = await service.getClassById('never-existed');

      expect(result, isNull);
    });
  });

  group('Class dropdown — widget-level reproduction', () {
    Widget buildClassDropdown({
      required String? initialValue,
      required List<(String, String)> items,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: DropdownButtonFormField<String>(
            initialValue: initialValue,
            items: [
              for (final (id, name) in items)
                DropdownMenuItem(value: id, child: Text(name)),
            ],
            onChanged: (_) {},
          ),
        ),
      );
    }

    test('a classId absent from the active-only items list throws the exact reported assertion', () {
      // DropdownButtonFormField's "exactly one matching item" assertion
      // fires synchronously in its own constructor, before the widget is
      // ever handed to pumpWidget — so this is asserted directly, the same
      // way the reproduction of the earlier (Relationship dropdown) bug
      // was in admin_student_form_parent_links_test.dart.
      expect(
        () => buildClassDropdown(
          initialValue: _corruptedId,
          items: const [('class-mont1', 'Mont 1'), ('class-mont2', 'Mont 2')],
        ),
        throwsA(
          isA<AssertionError>().having(
            (e) => e.toString(),
            'message',
            allOf(contains(_corruptedId), contains('exactly one item with')),
          ),
        ),
      );
    });
  });

  group('AdminStudentForm — actual Edit Student route (Test F)', () {
    testWidgets('an active classId loads with no exception', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('classes').doc('class-active').set({
        'name': 'Mont 1',
        'isActive': true,
      });

      await _pumpEditStudent(
        tester,
        firestore: firestore,
        studentId: 'student-1',
        initialData: _studentData(classId: 'class-active'),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Mont 1'), findsOneWidget);
    });

    testWidgets('an archived (isActive: false) classId loads with no exception and stays selected', (
      tester,
    ) async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('classes').doc('class-archived').set({
        'name': 'Mont 1 (2024 batch)',
        'isActive': false,
      });
      await firestore.collection('classes').doc('class-active').set({
        'name': 'Mont 1',
        'isActive': true,
      });

      await _pumpEditStudent(
        tester,
        firestore: firestore,
        studentId: 'student-1',
        initialData: _studentData(classId: 'class-archived'),
      );

      expect(tester.takeException(), isNull);
      // The archived class is still shown as the selected value — the
      // student's real assignment is preserved, not silently discarded or
      // replaced by whatever the first active class happens to be.
      expect(find.text('Mont 1 (2024 batch)'), findsOneWidget);
    });

    testWidgets('a genuinely deleted classId loads with no exception (Test F — the exact crash scenario)', (
      tester,
    ) async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('classes').doc('class-active').set({
        'name': 'Mont 1',
        'isActive': true,
      });
      // No document at all for _corruptedId — it was hard-deleted.

      await _pumpEditStudent(
        tester,
        firestore: firestore,
        studentId: 'student-1',
        initialData: _studentData(
          classId: _corruptedId,
          parentLinks: [
            {'userId': _corruptedId, 'relation': _corruptedId},
          ],
        ),
      );

      // This is the exact combination from the crash report: a classId
      // and a parentLinks[0].relation that are both the same stray id.
      expect(tester.takeException(), isNull);
    });

    testWidgets('Test A — a valid relation and a valid classId together load with no exception', (
      tester,
    ) async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('classes').doc('class-active').set({
        'name': 'Mont 1',
        'isActive': true,
      });

      await _pumpEditStudent(
        tester,
        firestore: firestore,
        studentId: 'student-1',
        initialData: _studentData(
          classId: 'class-active',
          parentLinks: [
            {'userId': 'parent-a', 'name': 'Asha Rao', 'relation': 'Father'},
          ],
        ),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('Test C — a null relation on an existing parent link loads with no exception', (
      tester,
    ) async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('classes').doc('class-active').set({
        'name': 'Mont 1',
        'isActive': true,
      });

      await _pumpEditStudent(
        tester,
        firestore: firestore,
        studentId: 'student-1',
        initialData: _studentData(
          classId: 'class-active',
          parentLinks: [
            {'userId': 'parent-a', 'name': 'Asha Rao'}, // no 'relation' key
          ],
        ),
      );

      expect(tester.takeException(), isNull);
    });
  });
}
