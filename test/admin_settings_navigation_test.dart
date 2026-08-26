// SETTINGS-01 coverage for the School Settings UI: AdminLayout navigation
// wiring (desktop sidebar + mobile "More Modules" sheet), Admin/Staff/
// Parent access at the UI layer (AccessRestrictedView), the logo
// pick/preview/remove interaction, save feedback, and responsive/no-overflow
// at the four required widths. Service-layer behavior (load/save/create-vs-
// update/validation/authorization/schoolId isolation/Storage) is covered in
// school_settings_service_test.dart — this file never re-derives that, it
// only checks the screen renders and wires it correctly.
import 'dart:convert';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/admin/settings/data/school_settings_service.dart';
import 'package:montessori_app/modules/admin/settings/models/school_settings_model.dart';
import 'package:montessori_app/modules/admin/settings/ui/access_restricted_view.dart';
import 'package:montessori_app/modules/admin/settings/ui/admin_settings_screen.dart';
import 'package:montessori_app/modules/admin/settings/ui/school_settings_screen.dart';
import 'package:montessori_app/modules/admin/ui/admin_layout.dart';
import 'package:montessori_app/modules/auth/models/app_user.dart';
import 'package:montessori_app/modules/auth/providers/auth_provider.dart';

class _StubFilePicker extends FilePicker {
  _StubFilePicker(this.result);
  final FilePickerResult? result;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async =>
      result;
}

// A real (decodable) 1x1 transparent PNG — Image.memory needs valid image
// bytes to render a preview without an image-codec error, unlike Storage
// (which just stores/retrieves bytes and doesn't care about their format).
const String _tinyPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';

PlatformFile _fakeLogo() {
  final bytes = base64Decode(_tinyPngBase64);
  return PlatformFile(name: 'logo.png', size: bytes.length, bytes: bytes);
}

SchoolSettingsService _service(
  FakeFirebaseFirestore firestore, {
  FilePicker? filePicker,
}) =>
    SchoolSettingsService(
      firestore: firestore,
      storage: MockFirebaseStorage(),
      filePicker: filePicker ?? _StubFilePicker(null),
    );

Widget _withRole(String role, Widget child) {
  return ProviderScope(
    overrides: [
      currentUserProvider.overrideWith(
        (ref) => AppUser(id: 'u1', phone: '9999999999', role: role, isActive: true),
      ),
    ],
    child: MaterialApp(home: child),
  );
}

void main() {
  group('Navigation — Settings -> School', () {
    testWidgets('desktop sidebar: Settings opens the Settings hub, which lists School', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _withRole(
          'admin',
          AdminLayout(selectedIndex: 9, title: 'Login Logs', body: const SizedBox.shrink()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Settings'));
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      expect(find.byType(AdminSettingsScreen), findsOneWidget);
      expect(find.text('School'), findsOneWidget);
    });

    testWidgets('Settings hub -> School opens the School Settings form', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await tester.pumpWidget(_withRole('admin', AdminSettingsScreen(service: _service(firestore))));
      await tester.pumpAndSettle();

      await tester.tap(find.text('School'));
      await tester.pumpAndSettle();

      expect(find.byType(SchoolSettingsScreen), findsOneWidget);
      expect(find.text('School Settings'), findsOneWidget);
      expect(find.text('School Name *'), findsOneWidget);
    });

    testWidgets('mobile "More Modules" sheet: Settings navigates instead of showing coming-soon', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _withRole(
          'admin',
          AdminLayout(selectedIndex: 0, title: 'Dashboard', body: const SizedBox.shrink()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();
      // 'Settings' is near the bottom of the "More Modules" sheet's list —
      // not yet built until scrolled into view (a plain, non-.builder
      // ListView still only builds on-screen children).
      for (var i = 0; i < 8 && find.text('Settings').evaluate().isEmpty; i++) {
        await tester.drag(find.byType(ListView).first, const Offset(0, -200));
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      expect(find.text('Settings is coming soon'), findsNothing);
      expect(find.byType(AdminSettingsScreen), findsOneWidget);
    });

    testWidgets('Reports remains a coming-soon placeholder (out of SETTINGS-01 scope)', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _withRole(
          'admin',
          AdminLayout(selectedIndex: 9, title: 'Login Logs', body: const SizedBox.shrink()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Reports'));
      await tester.tap(find.text('Reports'));
      await tester.pumpAndSettle();

      expect(find.text('Reports is coming soon'), findsOneWidget);
    });
  });

  group('Access control (UI layer)', () {
    testWidgets('Admin sees the Settings hub and the School Settings form', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await tester.pumpWidget(_withRole('admin', const AdminSettingsScreen()));
      await tester.pumpAndSettle();
      expect(find.byType(AccessRestrictedView), findsNothing);
      expect(find.text('School'), findsOneWidget);

      await tester.pumpWidget(_withRole('admin', SchoolSettingsScreen(service: _service(firestore))));
      await tester.pumpAndSettle();
      expect(find.byType(AccessRestrictedView), findsNothing);
      expect(find.text('School Name *'), findsOneWidget);
    });

    testWidgets('Staff is denied the Settings hub and the School Settings form', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await tester.pumpWidget(_withRole('staff', const AdminSettingsScreen()));
      await tester.pumpAndSettle();
      expect(find.byType(AccessRestrictedView), findsOneWidget);
      expect(find.text('School'), findsNothing);

      await tester.pumpWidget(_withRole('staff', SchoolSettingsScreen(service: _service(firestore))));
      await tester.pumpAndSettle();
      expect(find.byType(AccessRestrictedView), findsOneWidget);
      expect(find.text('School Name *'), findsNothing);
    });

    testWidgets('Parent is denied the Settings hub and the School Settings form', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await tester.pumpWidget(_withRole('parent', const AdminSettingsScreen()));
      await tester.pumpAndSettle();
      expect(find.byType(AccessRestrictedView), findsOneWidget);
      expect(find.text('School'), findsNothing);

      await tester.pumpWidget(_withRole('parent', SchoolSettingsScreen(service: _service(firestore))));
      await tester.pumpAndSettle();
      expect(find.byType(AccessRestrictedView), findsOneWidget);
      expect(find.text('School Name *'), findsNothing);
    });
  });

  group('School Settings form — behaviour', () {
    testWidgets('empty/default form when no settings exist yet', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await tester.pumpWidget(_withRole('admin', SchoolSettingsScreen(service: _service(firestore))));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextFormField, 'School Name *'), findsOneWidget);
      final nameField = tester.widget<TextFormField>(find.widgetWithText(TextFormField, 'School Name *'));
      expect(nameField.controller!.text, isEmpty);
      expect(find.text('Upload Logo'), findsOneWidget);
      expect(find.text('Remove'), findsNothing);
    });

    testWidgets('existing settings load into the form', (tester) async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      await service.saveSettings(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        name: 'Sunshine Montessori',
        address: '12 Garden Road',
        phone: '080-1234567',
        email: 'hello@sunshine.example',
        website: 'https://sunshine.example',
        description: 'A calm learning space.',
        updatedBy: 'admin-1',
        updatedByName: 'Asha',
      );

      await tester.pumpWidget(_withRole('admin', SchoolSettingsScreen(service: service)));
      await tester.pumpAndSettle();

      // Appears twice: the field itself, and the live Identity Preview
      // card above it (which mirrors the current form state).
      expect(find.text('Sunshine Montessori'), findsNWidgets(2));
      expect(find.text('12 Garden Road'), findsOneWidget);
      expect(find.text('080-1234567'), findsOneWidget);
      expect(find.text('hello@sunshine.example'), findsOneWidget);
      expect(find.text('https://sunshine.example'), findsOneWidget);
      expect(find.text('A calm learning space.'), findsOneWidget);
    });

    testWidgets('blank school name shows a validation error and does not save', (tester) async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      await tester.pumpWidget(_withRole('admin', SchoolSettingsScreen(service: service)));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(find.text('School Name is required.'), findsOneWidget);
      final snap = await firestore.collection('school_settings').get();
      expect(snap.docs, isEmpty);
    });

    testWidgets('invalid email shows a validation error and does not save', (tester) async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      await tester.pumpWidget(_withRole('admin', SchoolSettingsScreen(service: service)));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextFormField, 'School Name *'), 'Sunshine Montessori');
      await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'not-an-email');
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(find.text('Enter a valid email address.'), findsOneWidget);
      final snap = await firestore.collection('school_settings').get();
      expect(snap.docs, isEmpty);
    });

    testWidgets('valid save shows success feedback and persists via the service', (tester) async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      await tester.pumpWidget(_withRole('admin', SchoolSettingsScreen(service: service)));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextFormField, 'School Name *'), 'Sunshine Montessori');
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(find.text('School settings saved'), findsOneWidget);
      final snap = await firestore.collection('school_settings').get();
      expect(snap.docs, hasLength(1));
      expect(snap.docs.single.data()['name'], 'Sunshine Montessori');
    });

    testWidgets('picking a logo shows a local preview and enables Replace/Remove', (tester) async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore, filePicker: _StubFilePicker(FilePickerResult([_fakeLogo()])));
      await tester.pumpWidget(_withRole('admin', SchoolSettingsScreen(service: service)));
      await tester.pumpAndSettle();

      expect(find.text('Upload Logo'), findsOneWidget);
      await tester.tap(find.text('Upload Logo'));
      await tester.pumpAndSettle();

      expect(find.byType(Image), findsWidgets);
      expect(find.text('Replace Logo'), findsOneWidget);
      expect(find.text('Remove'), findsOneWidget);

      // Nothing is uploaded to Storage merely by picking — only on Save.
      final snap = await firestore.collection('school_settings').get();
      expect(snap.docs, isEmpty);
    });

    testWidgets('removing a freshly-picked (unsaved) logo discards it locally, no service call needed', (tester) async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore, filePicker: _StubFilePicker(FilePickerResult([_fakeLogo()])));
      await tester.pumpWidget(_withRole('admin', SchoolSettingsScreen(service: service)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Upload Logo'));
      await tester.pumpAndSettle();
      expect(find.text('Replace Logo'), findsOneWidget);

      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();

      expect(find.text('Upload Logo'), findsOneWidget);
      expect(find.text('Remove'), findsNothing);
      // Nothing was ever uploaded, and removing an unsaved pick doesn't
      // touch Firestore either.
      final snap = await firestore.collection('school_settings').get();
      expect(snap.docs, isEmpty);
    });

    // Removing an already-persisted logo (Storage delete + Firestore field
    // clear) is exercised end-to-end at the service layer in
    // school_settings_service_test.dart (11d) — deliberately not repeated
    // here through Image.network, which would require real network access
    // in a widget test.
  });

  group('Responsive layout — no overflow at required widths', () {
    const widths = <String, Size>{
      '390x844': Size(390, 844),
      '412x915': Size(412, 915),
      '768x1024': Size(768, 1024),
      '1440x900': Size(1440, 900),
    };

    testWidgets('School Settings form has no overflow at any required width', (tester) async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      await service.saveSettings(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        name: 'A Montessori School With A Reasonably Long Display Name',
        address: '123 A Fairly Long Street Name, Some Neighborhood, A City With A Long Name, 560001',
        phone: '+91 80 1234 5678',
        email: 'contact@a-fairly-long-school-domain-name.example',
        website: 'https://a-fairly-long-school-domain-name.example/about-us',
        description:
            'A calm, child-led Montessori learning environment serving toddlers through '
            'elementary-age children, with a strong emphasis on independence, practical '
            'life skills, and mixed-age classrooms.',
        updatedBy: 'admin-1',
        updatedByName: 'Asha',
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
          await tester.pumpWidget(_withRole('admin', SchoolSettingsScreen(service: service)));
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

    testWidgets('Settings hub has no overflow at any required width', (tester) async {
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
          await tester.pumpWidget(_withRole('admin', const AdminSettingsScreen()));
          await tester.pumpAndSettle();
        } finally {
          FlutterError.onError = previousOnError;
        }
        expect(errors, isEmpty, reason: 'Overflow/render error at ${entry.key}');
      }
    });
  });
}
