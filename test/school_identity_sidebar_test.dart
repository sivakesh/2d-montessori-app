// SETTINGS-01 UAT-fix coverage: AppSidebar/AdminSidebar now show the saved
// School Settings identity (name + logo) via schoolIdentityProvider,
// replacing the hardcoded "2D Montessori"/assets/logo.png — while keeping
// that hardcoded pair as the safe fallback whenever nothing has been
// saved. Covers: default fallback, saved identity appearing in both
// sidebars, live updates after save/replace/remove with no app restart
// (via schoolIdentityProvider invalidation), a broken logo URL falling
// back safely, and no overflow with a very long saved name.
//
// Other retained SETTINGS-01 coverage lives in:
//  - school_settings_service_test.dart (load/save/create-vs-update/
//    validation/authorization/schoolId isolation/logo Storage lifecycle)
//  - admin_settings_navigation_test.dart (Settings -> School navigation,
//    Admin/Staff/Parent UI access, form behaviour, responsive/no-overflow)
import 'dart:convert';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/core/layout/sidebar.dart';
import 'package:montessori_app/core/widgets/school_brand_mark.dart';
import 'package:montessori_app/modules/admin/settings/data/school_settings_service.dart';
import 'package:montessori_app/modules/admin/settings/models/school_settings_model.dart';
import 'package:montessori_app/modules/admin/settings/providers/school_identity_provider.dart';
import 'package:montessori_app/modules/admin/ui/admin_sidebar.dart';

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

const String _tinyPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';

int _logoCounter = 0;

PlatformFile _fakeLogo() {
  _logoCounter++;
  final bytes = base64Decode(_tinyPngBase64);
  return PlatformFile(name: 'logo_$_logoCounter.png', size: bytes.length, bytes: bytes);
}

SchoolSettingsService _service(FakeFirebaseFirestore firestore) => SchoolSettingsService(
      firestore: firestore,
      storage: MockFirebaseStorage(),
      filePicker: _StubFilePicker(null),
    );

/// Points schoolIdentityProvider at [service] (a fake-Firestore-backed
/// instance) instead of its real default — the same override technique
/// currentUserProvider is already overridden with elsewhere in this test
/// suite, applied to a FutureProvider so each (re)computation re-reads
/// [service]'s current state, including after container.invalidate(...).
ProviderContainer _containerFor(SchoolSettingsService service) {
  return ProviderContainer(
    overrides: [
      schoolIdentityProvider.overrideWith((ref) => service.getSchoolIdentity(schoolId: kDefaultSchoolId)),
    ],
  );
}

Widget _hostedIn(ProviderContainer container, Widget child) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

// The *outer*, first-matched Image in tree order is always the one
// SchoolBrandMark itself constructs (Image.network(logoUrl, ...) or
// Image.asset(defaultLogoAsset, ...)) — its own configured `.image` is
// what this checks. flutter_test's TestWidgetsFlutterBinding makes every
// HTTP request (including image fetches) fail with a 400, so once settled
// a NetworkImage's own errorBuilder has *also* already fired for real,
// nesting its Image.asset fallback as a second, later match — `.first`
// is what isolates "what URL/asset did the widget actually configure"
// from "what ended up on screen after this environment's network always
// fails".
Image _logoImageIn(WidgetTester tester, Finder ancestor) {
  return tester
      .widgetList<Image>(find.descendant(of: ancestor, matching: find.byType(Image)))
      .first;
}

void main() {
  group('1. Default identity when no settings exist', () {
    testWidgets('AppSidebar shows the existing hardcoded default identity', (tester) async {
      final container = _containerFor(_service(FakeFirebaseFirestore()));
      addTearDown(container.dispose);

      await tester.pumpWidget(_hostedIn(container, AppSidebar(selectedIndex: 0, onItemTapped: (_) {})));
      await tester.pumpAndSettle();

      expect(find.text('2D Montessori'), findsOneWidget);
      final image = _logoImageIn(tester, find.byType(AppSidebar));
      expect(image.image, isA<AssetImage>());
      expect((image.image as AssetImage).assetName, 'assets/logo.png');
    });

    testWidgets('AdminSidebar shows the existing hardcoded default identity', (tester) async {
      final container = _containerFor(_service(FakeFirebaseFirestore()));
      addTearDown(container.dispose);

      await tester.pumpWidget(_hostedIn(container, AdminSidebar(selectedIndex: 0, onDestinationSelected: (_) {})));
      await tester.pumpAndSettle();

      expect(find.text('2D Montessori'), findsOneWidget);
      final image = _logoImageIn(tester, find.byType(AdminSidebar));
      expect(image.image, isA<AssetImage>());
      expect((image.image as AssetImage).assetName, 'assets/logo.png');
    });

    testWidgets('Existing users never see a blank sidebar while the identity is still loading', (tester) async {
      final container = _containerFor(_service(FakeFirebaseFirestore()));
      addTearDown(container.dispose);

      await tester.pumpWidget(_hostedIn(container, AppSidebar(selectedIndex: 0, onItemTapped: (_) {})));
      // Deliberately no pumpAndSettle yet — the FutureProvider's first read
      // is still pending here, so this asserts the *loading-frame* state.
      await tester.pump();

      expect(find.text('2D Montessori'), findsOneWidget, reason: 'default identity shown while loading');
      expect(find.byType(AppSidebar), findsOneWidget);
    });
  });

  group('2, 3 & 4. Saved identity appears in both sidebars', () {
    testWidgets('Saved School Name and Logo appear in AppSidebar', (tester) async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      final logoUrl = await service.uploadLogo(schoolId: kDefaultSchoolId, requesterRole: 'admin', file: _fakeLogo());
      await service.saveSettings(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        name: 'Sunshine Montessori',
        logoUrl: logoUrl,
        updatedBy: 'admin-1',
        updatedByName: 'Asha',
      );

      final container = _containerFor(service);
      addTearDown(container.dispose);
      await tester.pumpWidget(_hostedIn(container, AppSidebar(selectedIndex: 0, onItemTapped: (_) {})));
      await tester.pumpAndSettle();

      expect(find.text('Sunshine Montessori'), findsOneWidget);
      expect(find.text('2D Montessori'), findsNothing);
      final image = _logoImageIn(tester, find.byType(AppSidebar));
      expect(image.image, isA<NetworkImage>());
      expect((image.image as NetworkImage).url, logoUrl);
    });

    testWidgets('4. AdminSidebar uses the saved identity too', (tester) async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      final logoUrl = await service.uploadLogo(schoolId: kDefaultSchoolId, requesterRole: 'admin', file: _fakeLogo());
      await service.saveSettings(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        name: 'Sunshine Montessori',
        logoUrl: logoUrl,
        updatedBy: 'admin-1',
        updatedByName: 'Asha',
      );

      final container = _containerFor(service);
      addTearDown(container.dispose);
      await tester.pumpWidget(_hostedIn(container, AdminSidebar(selectedIndex: 0, onDestinationSelected: (_) {})));
      await tester.pumpAndSettle();

      expect(find.text('Sunshine Montessori'), findsOneWidget);
      expect(find.text('2D Montessori'), findsNothing);
      final image = _logoImageIn(tester, find.byType(AdminSidebar));
      expect(image.image, isA<NetworkImage>());
      expect((image.image as NetworkImage).url, logoUrl);
    });
  });

  group('5, 6 & 7. Live updates after save/replace/remove (no app restart needed)', () {
    testWidgets('5. Updating School Name updates the sidebar once saved', (tester) async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      final container = _containerFor(service);
      addTearDown(container.dispose);

      await tester.pumpWidget(_hostedIn(container, AppSidebar(selectedIndex: 0, onItemTapped: (_) {})));
      await tester.pumpAndSettle();
      expect(find.text('2D Montessori'), findsOneWidget);

      await service.saveSettings(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        name: 'Bright Beginnings Montessori',
        updatedBy: 'admin-1',
        updatedByName: 'Asha',
      );
      // The same invalidation SchoolSettingsScreen performs after a save.
      container.invalidate(schoolIdentityProvider);
      await tester.pumpAndSettle();

      expect(find.text('Bright Beginnings Montessori'), findsOneWidget);
      expect(find.text('2D Montessori'), findsNothing);
    });

    testWidgets('6. Replacing the logo updates the sidebar to the new logo', (tester) async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      final firstUrl = await service.uploadLogo(schoolId: kDefaultSchoolId, requesterRole: 'admin', file: _fakeLogo());
      await service.saveSettings(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        name: 'Sunshine Montessori',
        logoUrl: firstUrl,
        updatedBy: 'admin-1',
        updatedByName: 'Asha',
      );

      final container = _containerFor(service);
      addTearDown(container.dispose);
      await tester.pumpWidget(_hostedIn(container, AppSidebar(selectedIndex: 0, onItemTapped: (_) {})));
      await tester.pumpAndSettle();
      expect((_logoImageIn(tester, find.byType(AppSidebar)).image as NetworkImage).url, firstUrl);

      final secondUrl = await service.uploadLogo(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        file: _fakeLogo(),
        previousLogoUrl: firstUrl,
      );
      await service.saveSettings(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        name: 'Sunshine Montessori',
        logoUrl: secondUrl,
        updatedBy: 'admin-1',
        updatedByName: 'Asha',
      );
      container.invalidate(schoolIdentityProvider);
      await tester.pumpAndSettle();

      final updatedImage = _logoImageIn(tester, find.byType(AppSidebar));
      expect(updatedImage.image, isA<NetworkImage>());
      expect((updatedImage.image as NetworkImage).url, secondUrl);
      expect(updatedImage.image, isNot(equals(NetworkImage(firstUrl))));
    });

    testWidgets('7. Removing the logo restores the default application logo in the sidebar', (tester) async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      final logoUrl = await service.uploadLogo(schoolId: kDefaultSchoolId, requesterRole: 'admin', file: _fakeLogo());
      await service.saveSettings(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        name: 'Sunshine Montessori',
        logoUrl: logoUrl,
        updatedBy: 'admin-1',
        updatedByName: 'Asha',
      );

      final container = _containerFor(service);
      addTearDown(container.dispose);
      await tester.pumpWidget(_hostedIn(container, AppSidebar(selectedIndex: 0, onItemTapped: (_) {})));
      await tester.pumpAndSettle();
      expect(_logoImageIn(tester, find.byType(AppSidebar)).image, isA<NetworkImage>());

      await service.removeLogo(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        logoUrl: logoUrl,
        updatedBy: 'admin-1',
        updatedByName: 'Asha',
      );
      container.invalidate(schoolIdentityProvider);
      await tester.pumpAndSettle();

      final restoredImage = _logoImageIn(tester, find.byType(AppSidebar));
      expect(restoredImage.image, isA<AssetImage>());
      expect((restoredImage.image as AssetImage).assetName, 'assets/logo.png');
      // The name (saved separately from the logo) is untouched by removing
      // just the logo.
      expect(find.text('Sunshine Montessori'), findsOneWidget);
    });
  });

  group('8. Missing/broken logo falls back safely', () {
    testWidgets('a logo URL that fails to load falls back to the default asset logo, not a broken-image glyph', (tester) async {
      final brokenIdentity = SchoolSettingsModel(
        schoolId: kDefaultSchoolId,
        name: 'Sunshine Montessori',
        logoUrl: 'https://firebasestorage.googleapis.com/v0/b/some-bucket/o/never-actually-uploaded.png',
        address: '',
        phone: '',
        email: '',
        website: '',
        description: '',
        updatedAt: null,
        updatedBy: null,
        updatedByName: null,
      );
      final container = ProviderContainer(
        overrides: [schoolIdentityProvider.overrideWith((ref) async => brokenIdentity)],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(_hostedIn(container, const SchoolBrandMark()));
      await tester.pumpAndSettle();

      // SchoolBrandMark itself configured the (broken) network URL...
      final images = tester.widgetList<Image>(find.byType(Image)).toList();
      expect(images.first.image, isA<NetworkImage>());
      expect((images.first.image as NetworkImage).url, brokenIdentity.logoUrl);

      // ...but this environment fails every HTTP request (flutter_test's
      // binding returns 400 for all of them), which already exercises the
      // *real* errorBuilder path end to end — no manual simulation needed.
      // What's actually on screen after that is the default asset logo,
      // never a broken-image glyph.
      expect(images.last.image, isA<AssetImage>());
      expect((images.last.image as AssetImage).assetName, 'assets/logo.png');
    });
  });

  group('Responsive — a very long saved name does not overflow the sidebar', () {
    testWidgets('AppSidebar and AdminSidebar truncate a long name instead of overflowing', (tester) async {
      const longName = 'A Montessori School With An Extremely Long Full Legal Name That Would Never Realistically Fit';
      final container = ProviderContainer(
        overrides: [
          schoolIdentityProvider.overrideWith((ref) async => const SchoolSettingsModel(
                schoolId: kDefaultSchoolId,
                name: longName,
                logoUrl: '',
                address: '',
                phone: '',
                email: '',
                website: '',
                description: '',
                updatedAt: null,
                updatedBy: null,
                updatedByName: null,
              )),
        ],
      );
      addTearDown(container.dispose);

      final errors = <FlutterErrorDetails>[];
      final previousOnError = FlutterError.onError;
      FlutterError.onError = (details) => errors.add(details);
      try {
        await tester.pumpWidget(_hostedIn(container, AppSidebar(selectedIndex: 0, onItemTapped: (_) {})));
        await tester.pumpAndSettle();
        await tester.pumpWidget(_hostedIn(container, AdminSidebar(selectedIndex: 0, onDestinationSelected: (_) {})));
        await tester.pumpAndSettle();
      } finally {
        FlutterError.onError = previousOnError;
      }
      expect(errors, isEmpty);
    });
  });
}
