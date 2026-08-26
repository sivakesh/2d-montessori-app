// FEES-AY-IMPLEMENT-01 coverage: Academic Year integration into the Add/Edit
// Fee Structure form (FeeStructureDialog) — replacing the free-text Academic
// Year field with a canonical AcademicYearModel dropdown, mirroring
// ClassFormDialog's own (AY-IMPLEMENT-02-B) resolution exactly. Service-layer
// duplicate-detection/compatibility rules are covered separately in
// fee_service_academic_year_test.dart; this file only checks the dialog
// loads/resolves/saves correctly through them.
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
import 'package:montessori_app/modules/fees/ui/dialogs/fee_structure_dialog.dart';

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

FeeService _feeService(FakeFirebaseFirestore firestore) => FeeService(
      firestore: firestore,
      auth: MockFirebaseAuth(),
      storage: MockFirebaseStorage(),
    );

Future<void> _addOneComponent(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(TextButton, 'Add Component'));
  await tester.pumpAndSettle();
  await tester.enterText(find.widgetWithText(TextField, 'Component Name *'), 'Tuition');
  await tester.enterText(find.widgetWithText(TextField, 'Amount *'), '5000');
  await tester.tap(find.widgetWithText(FilledButton, 'Add'));
  await tester.pumpAndSettle();
}

void main() {
  group('ADD FEE STRUCTURE', () {
    testWidgets('4. Current Academic Year defaults correctly and is visible', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedCurrentYear(firestore);
      await _seedHistoricalYear(firestore);

      await tester.pumpWidget(_pumpable(
        FeeStructureDialog(service: _feeService(firestore)),
        firestore: firestore,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Academic Year *'), findsOneWidget);
      expect(find.text('2026-2027 • Current'), findsOneWidget);
    });

    testWidgets('5. Historical year is selectable', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedCurrentYear(firestore);
      await _seedHistoricalYear(firestore);

      await tester.pumpWidget(_pumpable(
        FeeStructureDialog(service: _feeService(firestore)),
        firestore: firestore,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('2026-2027 • Current'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2025-2026 • Historical').last);
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextFormField, 'Fee Structure Name *'), 'Old Fees');
      await _addOneComponent(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      final snap = await firestore.collection('fee_structures').get();
      expect(snap.docs.single.data()['academicYear'], '2025-2026');
    });

    testWidgets('6/7. Saving writes both academicYearId (from AcademicYearModel.id) and academicYear (never a hardcoded value)', (tester) async {
      final firestore = FakeFirebaseFirestore();
      final yearId = await _seedCurrentYear(firestore, name: '2031-2032', start: DateTime(2031, 6, 1), end: DateTime(2032, 5, 31));

      await tester.pumpWidget(_pumpable(
        FeeStructureDialog(service: _feeService(firestore)),
        firestore: firestore,
      ));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextFormField, 'Fee Structure Name *'), 'Custom Fees');
      await _addOneComponent(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      final snap = await firestore.collection('fee_structures').get();
      final data = snap.docs.single.data();
      expect(data['academicYearId'], yearId);
      expect(data['academicYear'], '2031-2032');
      expect(data['academicYearId'], isNot('2026-2027'), reason: 'never a hardcoded fallback');
    });

    testWidgets('No academic years configured: Save is blocked, no hardcoded fallback', (tester) async {
      final firestore = FakeFirebaseFirestore();

      await tester.pumpWidget(_pumpable(
        FeeStructureDialog(service: _feeService(firestore)),
        firestore: firestore,
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('No academic years configured'), findsOneWidget);

      final snap = await firestore.collection('fee_structures').get();
      expect(snap.docs, isEmpty);
    });
  });

  group('EDIT FEE STRUCTURE', () {
    testWidgets('8. Existing academicYearId selects the correct year (authoritative over a disagreeing string)', (tester) async {
      final firestore = FakeFirebaseFirestore();
      final currentYearId = await _seedCurrentYear(firestore); // 2026-2027
      await _seedHistoricalYear(firestore); // 2025-2026
      final structureDoc = await firestore.collection('fee_structures').add({
        'name': 'Core Fees',
        'description': '',
        'components': [],
        'totalAmount': 5000,
        'academicYear': '2025-2026',
        'academicYearId': currentYearId,
        'isActive': true,
        'createdBy': 'admin',
      });

      await tester.pumpWidget(_pumpable(
        FeeStructureDialog(
          structure: (await _feeService(firestore).getFeeStructures()).firstWhere((s) => s.id == structureDoc.id),
          service: _feeService(firestore),
        ),
        firestore: firestore,
      ));
      await tester.pumpAndSettle();

      expect(find.text('2026-2027 • Current'), findsOneWidget, reason: 'academicYearId is authoritative, not the disagreeing string');
      expect(find.textContaining('does not match its stored academic year'), findsOneWidget);
    });

    testWidgets('9. Legacy structure (no academicYearId) selects via the string-matching fallback', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedCurrentYear(firestore);
      await _seedHistoricalYear(firestore);
      final structureDoc = await firestore.collection('fee_structures').add({
        'name': 'Old Fees',
        'description': '',
        'components': [],
        'totalAmount': 5000,
        'academicYear': '2025-2026',
        'isActive': true,
        'createdBy': 'admin',
      });

      await tester.pumpWidget(_pumpable(
        FeeStructureDialog(
          structure: (await _feeService(firestore).getFeeStructures()).firstWhere((s) => s.id == structureDoc.id),
          service: _feeService(firestore),
        ),
        firestore: firestore,
      ));
      await tester.pumpAndSettle();

      expect(find.text('2025-2026 • Historical'), findsOneWidget);
    });

    testWidgets('10. An orphaned academicYear (matches nothing) never silently defaults to the current year', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedCurrentYear(firestore); // "2026-2027" — does NOT match "2024-2025" below.
      final structureDoc = await firestore.collection('fee_structures').add({
        'name': 'Very Old Fees',
        'description': '',
        'components': [],
        'totalAmount': 5000,
        'academicYear': '2024-2025',
        'isActive': true,
        'createdBy': 'admin',
      });

      await tester.pumpWidget(_pumpable(
        FeeStructureDialog(
          structure: (await _feeService(firestore).getFeeStructures()).firstWhere((s) => s.id == structureDoc.id),
          service: _feeService(firestore),
        ),
        firestore: firestore,
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('"2024-2025"'), findsOneWidget);
      expect(find.text('2026-2027 • Current'), findsNothing, reason: 'must never silently substitute the current year');
    });

    testWidgets('11. Unresolved year blocks Save until the admin explicitly resolves it', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedCurrentYear(firestore);
      final structureDoc = await firestore.collection('fee_structures').add({
        'name': 'Very Old Fees',
        'description': '',
        'components': [
          {'name': 'Tuition', 'amount': 5000, 'frequency': 'monthly', 'isOptional': false},
        ],
        'totalAmount': 5000,
        'academicYear': '2024-2025',
        'isActive': true,
        'createdBy': 'admin',
      });

      await tester.pumpWidget(_pumpable(
        FeeStructureDialog(
          structure: (await _feeService(firestore).getFeeStructures()).firstWhere((s) => s.id == structureDoc.id),
          service: _feeService(firestore),
        ),
        firestore: firestore,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      var snap = await structureDoc.get();
      expect(snap.data()!['academicYear'], '2024-2025', reason: 'unresolved orphan must not be overwritten');

      // Admin explicitly resolves it.
      await tester.tap(find.byKey(const ValueKey('fee_structure_academic_year_dropdown_none')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2026-2027 • Current').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      snap = await structureDoc.get();
      expect(snap.data()!['academicYear'], '2026-2027');
    });
  });

  group('Responsive layout — no overflow at required widths', () {
    const widths = <String, Size>{
      '390x844': Size(390, 844),
      '412x915': Size(412, 915),
      '768x1024': Size(768, 1024),
      '1440x900': Size(1440, 900),
    };

    testWidgets('12. Add/Edit Fee Structure dialog (with Academic Year dropdown) has no overflow at any required width', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedCurrentYear(firestore);
      await _seedHistoricalYear(firestore);

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
            FeeStructureDialog(key: ValueKey(entry.key), service: _feeService(firestore)),
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
