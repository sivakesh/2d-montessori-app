// SETTINGS-02 coverage for the Academic Year UI: AdminSettingsScreen hub
// wiring, Admin/Staff/Parent access at the UI layer, list rendering
// (CURRENT/Historical/Inactive), the Add/Edit/Set-as-Current interactions,
// validation errors, the confirmation dialog before changing the current
// year, and responsive/no-overflow at the four required widths.
// Service-layer business rules (overlap/duplicate/authorization/isolation)
// are covered in academic_year_service_test.dart — this file never
// re-derives that, it only checks the screen renders and wires it
// correctly.
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/admin/settings/data/academic_year_service.dart';
import 'package:montessori_app/modules/admin/settings/models/school_settings_model.dart';
import 'package:montessori_app/modules/admin/settings/providers/academic_year_provider.dart'
    show academicYearServiceProvider;
import 'package:montessori_app/modules/admin/settings/ui/academic_year_screen.dart';
import 'package:montessori_app/modules/admin/settings/ui/admin_settings_screen.dart';
import 'package:montessori_app/modules/admin/ui/admin_layout.dart';
import 'package:montessori_app/modules/auth/models/app_user.dart';
import 'package:montessori_app/modules/auth/providers/auth_provider.dart';

AcademicYearService _service(FakeFirebaseFirestore firestore) =>
    AcademicYearService(firestore: firestore);

Widget _withRole(String role, Widget child, {List<Override> extraOverrides = const []}) {
  return ProviderScope(
    overrides: [
      currentUserProvider.overrideWith(
        (ref) => AppUser(id: 'u1', phone: '9999999999', role: role, isActive: true),
      ),
      ...extraOverrides,
    ],
    child: MaterialApp(home: child),
  );
}

void main() {
  group('Navigation — Settings -> Academic Year', () {
    testWidgets('19. Settings hub lists Academic Year, which opens the Academic Year screen', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await tester.pumpWidget(
        _withRole('admin', AdminSettingsScreen(academicYearService: _service(firestore))),
      );
      await tester.pumpAndSettle();

      expect(find.text('Academic Year'), findsOneWidget);
      await tester.tap(find.text('Academic Year'));
      await tester.pumpAndSettle();

      expect(find.byType(AcademicYearScreen), findsOneWidget);
      expect(find.text('Add Academic Year'), findsOneWidget);
    });

    testWidgets('desktop sidebar: Settings -> Academic Year is reachable end-to-end from AdminLayout', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // AdminLayout constructs AdminSettingsScreen() internally with no DI
      // hook, so the real Firebase-backed AcademicYearService would be
      // built via academicYearServiceProvider — override that provider
      // itself with a fake-Firestore-backed instance instead.
      await tester.pumpWidget(
        _withRole(
          'admin',
          AdminLayout(selectedIndex: 9, title: 'Login Logs', body: const SizedBox.shrink()),
          extraOverrides: [
            academicYearServiceProvider.overrideWithValue(_service(FakeFirebaseFirestore())),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Settings'));
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Academic Year'));
      await tester.pumpAndSettle();

      expect(find.byType(AcademicYearScreen), findsOneWidget);
    });
  });

  group('Access control (UI layer)', () {
    testWidgets('Admin sees the Academic Year screen', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await tester.pumpWidget(_withRole('admin', AcademicYearScreen(service: _service(firestore))));
      await tester.pumpAndSettle();
      expect(find.text('You do not have access to this section.'), findsNothing);
      expect(find.text('Add Academic Year'), findsOneWidget);
    });

    testWidgets('Staff is denied the Academic Year screen', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await tester.pumpWidget(_withRole('staff', AcademicYearScreen(service: _service(firestore))));
      await tester.pumpAndSettle();
      expect(find.text('You do not have access to this section.'), findsOneWidget);
      expect(find.text('Add Academic Year'), findsNothing);
    });

    testWidgets('Parent is denied the Academic Year screen', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await tester.pumpWidget(_withRole('parent', AcademicYearScreen(service: _service(firestore))));
      await tester.pumpAndSettle();
      expect(find.text('You do not have access to this section.'), findsOneWidget);
      expect(find.text('Add Academic Year'), findsNothing);
    });

    testWidgets('Staff/Parent do not see Academic Year in the Settings hub', (tester) async {
      for (final role in ['staff', 'parent']) {
        await tester.pumpWidget(_withRole(role, const AdminSettingsScreen()));
        await tester.pumpAndSettle();
        expect(find.text('Academic Year'), findsNothing, reason: '$role must not see the Settings hub at all');
      }
    });
  });

  group('20/21. Existing years display, CURRENT clearly identified', () {
    testWidgets('lists years newest first, showing CURRENT badge and Historical/Inactive status', (tester) async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      await service.createAcademicYear(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        name: '2025-2026',
        startDate: DateTime(2025, 6, 1),
        endDate: DateTime(2026, 5, 31),
        createdBy: 'admin-1',
      );
      final currentId = await service.createAcademicYear(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        name: '2026-2027',
        startDate: DateTime(2026, 6, 1),
        endDate: DateTime(2027, 5, 31),
        createdBy: 'admin-1',
        setAsCurrent: true,
      );

      await tester.pumpWidget(_withRole('admin', AcademicYearScreen(service: service)));
      await tester.pumpAndSettle();

      // Current year name appears twice: the "Current Academic Year" hero
      // card at the top, and the year's own list card below it.
      expect(find.text('2026-2027'), findsNWidgets(2));
      expect(find.text('2025-2026'), findsOneWidget);
      expect(find.text('CURRENT'), findsOneWidget);
      expect(find.text('Historical'), findsOneWidget);

      // Newest-first ordering: 2026-2027's card precedes 2025-2026's.
      final firstCardOffset = tester.getTopLeft(find.text('2026-2027').last);
      final secondCardOffset = tester.getTopLeft(find.text('2025-2026'));
      expect(firstCardOffset.dy, lessThan(secondCardOffset.dy));

      expect(currentId, isNotEmpty);
    });

    testWidgets('a deactivated year shows as Inactive and offers no Set as Current/Deactivate action', (tester) async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      final id = await service.createAcademicYear(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        name: '2023-2024',
        startDate: DateTime(2023, 6, 1),
        endDate: DateTime(2024, 5, 31),
        createdBy: 'admin-1',
      );
      await service.deactivateAcademicYear(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        id: id,
        updatedBy: 'admin-1',
      );

      await tester.pumpWidget(_withRole('admin', AcademicYearScreen(service: service)));
      await tester.pumpAndSettle();

      expect(find.text('Inactive'), findsOneWidget);
      expect(find.text('Activate'), findsOneWidget);
      expect(find.text('Deactivate'), findsNothing);
    });

    testWidgets('empty state is shown when no academic year exists yet', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await tester.pumpWidget(_withRole('admin', AcademicYearScreen(service: _service(firestore))));
      await tester.pumpAndSettle();

      expect(find.text('No academic years yet'), findsOneWidget);
      expect(find.text('No current academic year set'), findsOneWidget);
    });
  });

  group('23. Edit flow', () {
    testWidgets('editing an existing year pre-fills its fields and persists the change', (tester) async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      await service.createAcademicYear(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        name: '2026-2027',
        startDate: DateTime(2026, 6, 1),
        endDate: DateTime(2027, 5, 31),
        createdBy: 'admin-1',
      );

      await tester.pumpWidget(_withRole('admin', AcademicYearScreen(service: service)));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(OutlinedButton, 'Edit'));
      await tester.pumpAndSettle();

      expect(find.text('Edit Academic Year'), findsOneWidget);
      final nameField = find.widgetWithText(TextFormField, 'Academic Year Name *');
      expect(tester.widget<TextFormField>(nameField).controller!.text, '2026-2027');

      await tester.enterText(nameField, '2026-2027 (Revised)');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(find.text('Academic year updated'), findsOneWidget);
      expect(find.text('2026-2027 (Revised)'), findsOneWidget);

      final years = await service.getAllAcademicYears(schoolId: kDefaultSchoolId);
      expect(years.single.name, '2026-2027 (Revised)');
    });
  });

  group('22. Create flow', () {
    testWidgets('picking a start and end date and saving creates the academic year', (tester) async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      await tester.pumpWidget(_withRole('admin', AcademicYearScreen(service: service)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add Academic Year'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextFormField, 'Academic Year Name *'), '2026-2027');

      // Start date: accept the picker's default initial date (today).
      await tester.tap(find.text('Select date').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      // End date: the second picker also defaults to today — advance two
      // months forward (well clear of any month-end edge case) and pick
      // day 15, which exists in every month and is always after start.
      await tester.tap(find.text('Select date').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Next month'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Next month'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('15').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(find.text('Academic year created'), findsOneWidget);
      final years = await service.getAllAcademicYears(schoolId: kDefaultSchoolId);
      expect(years, hasLength(1));
      expect(years.single.name, '2026-2027');
      expect(years.single.endDate.isAfter(years.single.startDate), isTrue);
    });
  });

  group('24/26. Set as Current flow, with confirmation', () {
    testWidgets('Set as Current shows a confirmation dialog; Cancel makes no change', (tester) async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      await service.createAcademicYear(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        name: '2026-2027',
        startDate: DateTime(2026, 6, 1),
        endDate: DateTime(2027, 5, 31),
        createdBy: 'admin-1',
      );

      await tester.pumpWidget(_withRole('admin', AcademicYearScreen(service: service)));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(OutlinedButton, 'Set as Current'));
      await tester.pumpAndSettle();

      expect(find.text('Set as Current Academic Year?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      final years = await service.getAllAcademicYears(schoolId: kDefaultSchoolId);
      expect(years.single.isCurrent, isFalse, reason: 'Cancel must not change the current year');
      expect(find.text('CURRENT'), findsNothing);
    });

    testWidgets('Set as Current, confirmed, updates the badge and the hero card', (tester) async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      await service.createAcademicYear(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        name: '2026-2027',
        startDate: DateTime(2026, 6, 1),
        endDate: DateTime(2027, 5, 31),
        createdBy: 'admin-1',
      );

      await tester.pumpWidget(_withRole('admin', AcademicYearScreen(service: service)));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(OutlinedButton, 'Set as Current'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Set as Current'));
      await tester.pumpAndSettle();

      expect(find.text('CURRENT'), findsOneWidget);
      expect(find.text('No current academic year set'), findsNothing);

      final years = await service.getAllAcademicYears(schoolId: kDefaultSchoolId);
      expect(years.single.isCurrent, isTrue);
    });
  });

  group('25. Validation errors', () {
    testWidgets('blank name shows a validation error and does not save', (tester) async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      await tester.pumpWidget(_withRole('admin', AcademicYearScreen(service: service)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add Academic Year'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(find.text('Academic Year name is required.'), findsOneWidget);
      final years = await service.getAllAcademicYears(schoolId: kDefaultSchoolId);
      expect(years, isEmpty);
    });

    testWidgets('missing dates show a validation error and do not save', (tester) async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      await tester.pumpWidget(_withRole('admin', AcademicYearScreen(service: service)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add Academic Year'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, 'Academic Year Name *'), '2026-2027');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(find.text('Start date is required.'), findsOneWidget);
      final years = await service.getAllAcademicYears(schoolId: kDefaultSchoolId);
      expect(years, isEmpty);
    });
  });

  group('Responsive layout — no overflow at required widths', () {
    const widths = <String, Size>{
      '390x844': Size(390, 844),
      '412x915': Size(412, 915),
      '768x1024': Size(768, 1024),
      '1440x900': Size(1440, 900),
    };

    testWidgets('27. Academic Year screen has no overflow at any required width', (tester) async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      await service.createAcademicYear(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        name: 'A Fairly Long Academic Year Display Name For Layout Testing',
        startDate: DateTime(2026, 6, 1),
        endDate: DateTime(2027, 5, 31),
        createdBy: 'admin-1',
        setAsCurrent: true,
      );
      await service.createAcademicYear(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        name: '2025-2026',
        startDate: DateTime(2025, 6, 1),
        endDate: DateTime(2026, 5, 31),
        createdBy: 'admin-1',
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
          await tester.pumpWidget(_withRole('admin', AcademicYearScreen(service: service)));
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

    testWidgets('Add/Edit dialog has no overflow at any required width', (tester) async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);

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
          await tester.pumpWidget(_withRole('admin', AcademicYearScreen(service: service)));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Add Academic Year'));
          await tester.pumpAndSettle();
        } finally {
          FlutterError.onError = previousOnError;
        }
        expect(
          errors,
          isEmpty,
          reason: 'Overflow/render error at ${entry.key}: ${errors.map((e) => e.exceptionAsString()).join(', ')}',
        );
        Navigator.of(tester.element(find.byType(AcademicYearScreen))).popUntil((r) => r.isFirst);
      }
    });
  });
}
