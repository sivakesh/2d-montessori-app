// FEES-AY-IMPLEMENT-01 coverage: the Fee Assignment form (FeeAssignmentDialog)
// no longer offers a manually-typed Academic Year field — the Fee Structure
// selected is the sole, authoritative source of the assignment's Academic
// Year (see fee_assignment_dialog.dart's own doc comments). Service-layer
// duplicate-detection/compatibility rules are covered separately in
// fee_service_academic_year_test.dart.
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/admin/settings/data/academic_year_service.dart';
import 'package:montessori_app/modules/admin/settings/models/school_settings_model.dart';
import 'package:montessori_app/modules/admin/settings/providers/academic_year_provider.dart';
import 'package:montessori_app/modules/fees/services/fee_service.dart';
import 'package:montessori_app/modules/fees/ui/dialogs/fee_assignment_dialog.dart';

Widget _pumpable(Widget child, {required FakeFirebaseFirestore firestore}) {
  return ProviderScope(
    overrides: [
      academicYearServiceProvider.overrideWithValue(AcademicYearService(firestore: firestore)),
    ],
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

Future<String> _seedCurrentYear(FakeFirebaseFirestore firestore, {String name = '2026-2027'}) {
  return AcademicYearService(firestore: firestore).createAcademicYear(
    schoolId: kDefaultSchoolId,
    requesterRole: 'admin',
    name: name,
    startDate: DateTime(2026, 6, 1),
    endDate: DateTime(2027, 5, 31),
    createdBy: 'admin-1',
    setAsCurrent: true,
  );
}

Future<String> _seedHistoricalYear(FakeFirebaseFirestore firestore, {String name = '2025-2026'}) {
  return AcademicYearService(firestore: firestore).createAcademicYear(
    schoolId: kDefaultSchoolId,
    requesterRole: 'admin',
    name: name,
    startDate: DateTime(2025, 6, 1),
    endDate: DateTime(2026, 5, 31),
    createdBy: 'admin-1',
  );
}

Future<void> _seedClass(FakeFirebaseFirestore firestore, {String id = 'class-1', String name = 'Mont 1'}) {
  return firestore.collection('classes').doc(id).set({'name': name, 'isActive': true});
}

Future<void> _seedStudent(FakeFirebaseFirestore firestore, {required String id, required String classId, String name = 'Student'}) {
  return firestore.collection('students').doc(id).set({
    'name': name,
    'admissionNo': 'ADM-$id',
    'classId': classId,
    'isActive': true,
  });
}

Future<void> _seedStructure(
  FakeFirebaseFirestore firestore, {
  required String id,
  String name = 'Core Fees',
  double totalAmount = 20000,
  String? academicYearId,
  String academicYear = '2026-2027',
}) {
  return firestore.collection('fee_structures').doc(id).set({
    'name': name,
    'description': '',
    'components': [],
    'totalAmount': totalAmount,
    'academicYear': academicYear,
    if (academicYearId != null) 'academicYearId': academicYearId,
    'isActive': true,
    'createdBy': 'test',
  });
}

FeeService _feeService(FakeFirebaseFirestore firestore) => FeeService(
      firestore: firestore,
      auth: MockFirebaseAuth(),
      storage: MockFirebaseStorage(),
    );

void main() {
  group('Fee Assignment — Academic Year derivation (FEES-AY-IMPLEMENT-01)', () {
    testWidgets('13. No free-text Academic Year field exists on the form', (tester) async {
      final firestore = FakeFirebaseFirestore();
      final yearId = await _seedCurrentYear(firestore);
      await _seedClass(firestore);
      await _seedStudent(firestore, id: 's1', classId: 'class-1');
      await _seedStructure(firestore, id: 'f1', academicYearId: yearId);

      await tester.pumpWidget(_pumpable(
        FeeAssignmentDialog(service: _feeService(firestore)),
        firestore: firestore,
      ));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextFormField, 'Academic Year *'), findsNothing);
      expect(find.byType(TextFormField), findsOneWidget, reason: 'only the Discount Amount field remains as free text');
    });

    testWidgets('14/18. Selecting a Fee Structure determines the displayed and saved Academic Year (canonical id flows through)', (tester) async {
      final firestore = FakeFirebaseFirestore();
      final yearId = await _seedCurrentYear(firestore);
      await _seedClass(firestore);
      await _seedStudent(firestore, id: 's1', classId: 'class-1');
      await _seedStructure(firestore, id: 'f1', academicYearId: yearId);

      await tester.pumpWidget(_pumpable(
        FeeAssignmentDialog(service: _feeService(firestore)),
        firestore: firestore,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Select Class *'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mont 1').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Select Student *'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Student').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Fee Structure *'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Core Fees').last);
      await tester.pumpAndSettle();

      expect(find.text('2026-2027 • Current'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      final snap = await firestore.collection('student_fee_assignments').get();
      final data = snap.docs.single.data();
      expect(data['academicYearId'], yearId);
      expect(data['academicYear'], '2026-2027');
    });

    testWidgets('15. Changing the selected Fee Structure updates the displayed Academic Year', (tester) async {
      final firestore = FakeFirebaseFirestore();
      final currentYearId = await _seedCurrentYear(firestore);
      final historicalYearId = await _seedHistoricalYear(firestore);
      await _seedClass(firestore);
      await _seedStudent(firestore, id: 's1', classId: 'class-1');
      await _seedStructure(firestore, id: 'f1', name: 'Current Fees', academicYearId: currentYearId, academicYear: '2026-2027');
      await _seedStructure(firestore, id: 'f2', name: 'Historical Fees', academicYearId: historicalYearId, academicYear: '2025-2026');

      await tester.pumpWidget(_pumpable(
        FeeAssignmentDialog(service: _feeService(firestore)),
        firestore: firestore,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Select Class *'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mont 1').last);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Fee Structure *'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Current Fees').last);
      await tester.pumpAndSettle();
      expect(find.text('2026-2027 • Current'), findsOneWidget);

      await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Fee Structure *'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Historical Fees').last);
      await tester.pumpAndSettle();

      expect(find.text('2025-2026 • Historical'), findsOneWidget, reason: '16. historical FeeStructure displays historical year');
      expect(find.text('2026-2027 • Current'), findsNothing);
    });

    testWidgets('17. An unresolved Fee Structure year blocks Save with a clear message', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedCurrentYear(firestore); // "2026-2027" — does NOT match "2024-2025" below.
      await _seedClass(firestore);
      await _seedStudent(firestore, id: 's1', classId: 'class-1');
      await _seedStructure(firestore, id: 'f1', name: 'Orphaned Fees', academicYear: '2024-2025');

      await tester.pumpWidget(_pumpable(
        FeeAssignmentDialog(service: _feeService(firestore)),
        firestore: firestore,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Select Class *'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mont 1').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Select Student *'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Student').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Fee Structure *'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Orphaned Fees').last);
      await tester.pumpAndSettle();

      expect(find.textContaining('does not match any'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(find.textContaining('resolvable Academic Year'), findsOneWidget);
      final snap = await firestore.collection('student_fee_assignments').get();
      expect(snap.docs, isEmpty, reason: 'never invents a year to let the save through');
    });

    testWidgets('19. A legacy Fee Structure (no academicYearId, string matches) resolves and saves correctly', (tester) async {
      final firestore = FakeFirebaseFirestore();
      final yearId = await _seedCurrentYear(firestore); // 2026-2027
      await _seedClass(firestore);
      await _seedStudent(firestore, id: 's1', classId: 'class-1');
      // No academicYearId at all — legacy-shaped structure.
      await _seedStructure(firestore, id: 'f1', name: 'Legacy Fees', academicYear: '2026-2027');

      await tester.pumpWidget(_pumpable(
        FeeAssignmentDialog(service: _feeService(firestore)),
        firestore: firestore,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Select Class *'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mont 1').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Select Student *'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Student').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Fee Structure *'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Legacy Fees').last);
      await tester.pumpAndSettle();

      expect(find.text('2026-2027 • Current'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      final snap = await firestore.collection('student_fee_assignments').get();
      final data = snap.docs.single.data();
      expect(data['academicYearId'], yearId, reason: 'resolved via the legacy-string fallback, still upgraded to a canonical id');
      expect(data['academicYear'], '2026-2027');
    });
  });

  group('Responsive layout — no overflow at required widths', () {
    const widths = <String, Size>{
      '390x844': Size(390, 844),
      '412x915': Size(412, 915),
      '768x1024': Size(768, 1024),
      '1440x900': Size(1440, 900),
    };

    testWidgets('20. Assign Fee dialog (with derived Academic Year info) has no overflow at any required width', (tester) async {
      final firestore = FakeFirebaseFirestore();
      final yearId = await _seedCurrentYear(firestore);
      await _seedClass(firestore, name: 'A Fairly Long Class Name For Layout Testing');
      await _seedStudent(firestore, id: 's1', classId: 'class-1', name: 'A Fairly Long Student Name For Layout Testing');
      await _seedStructure(firestore, id: 'f1', name: 'A Fairly Long Fee Structure Name For Layout Testing', academicYearId: yearId);

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
            FeeAssignmentDialog(key: ValueKey(entry.key), service: _feeService(firestore)),
            firestore: firestore,
          ));
          await tester.pumpAndSettle();
          await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Select Class *'));
          await tester.pumpAndSettle();
          await tester.tap(find.textContaining('A Fairly Long Class Name').last);
          await tester.pumpAndSettle();
          await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Fee Structure *'));
          await tester.pumpAndSettle();
          await tester.tap(find.textContaining('A Fairly Long Fee Structure Name').last);
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
