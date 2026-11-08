// Photo approval and consent while uploading several images. The record has
// one combined confirmation (`consentConfirmed`: the photograph is
// school-approved and consent was obtained), so each image has one control.
// It is never set automatically: only ticked per image, or for every image
// of this upload through an explicit statement the admin agrees to; any image
// can be left or put back unticked. Saved through the library's own
// confirmation (with its audit entry); other images are never touched.
// Publishing still requires it, and refusals say what is missing. Alt text
// ("2D Montessori" by default) is independent. Synthetic test data only.
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/admin/website/data/website_content_admin_service.dart';
import 'package:montessori_app/modules/admin/website/data/website_image_processor.dart';
import 'package:montessori_app/modules/admin/website/ui/website_content_editors.dart';
import 'package:montessori_app/modules/admin/website/ui/website_content_screen.dart';
import 'package:montessori_app/modules/admin/website/ui/website_media_library.dart' show uploadConsentStatement;
import 'package:montessori_app/modules/auth/models/app_user.dart';
import 'package:montessori_app/modules/auth/providers/auth_provider.dart';
import 'package:montessori_app/modules/public_website/content/website_content_models.dart';

class _Processor implements WebsiteImageProcessor {
  @override
  Future<ProcessedWebsiteImage> process(Uint8List bytes, {required String contentType}) async => ProcessedWebsiteImage(
        width: 1600,
        height: 1200,
        display: Uint8List.fromList([1, 2, 3]),
        displayContentType: 'image/jpeg',
        thumb: Uint8List.fromList([4]),
        thumbContentType: 'image/jpeg',
      );
}

class _Picker extends FilePicker {
  final files = <PlatformFile>[];

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
      files.isEmpty ? null : FilePickerResult(files);
}

final _admin = AppUser(id: '9000000001', phone: '9000000001', role: 'admin', isActive: true, name: 'Test admin');

PlatformFile _file(String name, int first) => PlatformFile(name: name, size: 3, bytes: Uint8List.fromList([first, 9, 9]));
final _three = [_file('one.jpg', 1), _file('two.png', 2), _file('three.webp', 3)];

void main() {
  Finder key(String k) => find.byKey(Key(k));
  late FakeFirebaseFirestore db;
  late _Picker picker;
  late WebsiteContentAdminService service;

  setUp(() {
    db = FakeFirebaseFirestore();
    picker = _Picker();
    service = WebsiteContentAdminService(firestore: db, storage: MockFirebaseStorage(), imageProcessor: _Processor(), filePicker: picker);
  });

  CollectionReference<Map<String, dynamic>> media() => db.collection(WebsiteCollections.media);
  Future<WebsiteMedia> reload(String id) async => (await service.getMedia(requesterRole: 'admin', mediaId: id))!;
  Future<List<Map<String, dynamic>>> audit(String id) async => [for (final d in (await media().doc(id).collection('audit').get()).docs) d.data()];

  Future<String> existing(String id, {required bool consent, String alt = ''}) async {
    await media().doc(id).set({
      'url': 'https://storage.example.test/$id.jpg',
      'storagePath': 'website_media/$id/1_display.jpg',
      'alt': {'en': alt, 'ta': ''},
      'caption': {'en': ''},
      'category': 'classroom',
      'status': 'draft',
      'inGallery': true,
      'galleryOrder': 0,
      'consentConfirmed': consent,
    });
    return id;
  }

  Future<void> pumpScreen(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(1200, 3600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
      key: UniqueKey(),
      overrides: [currentUserProvider.overrideWith((ref) => _admin)],
      child: MaterialApp(home: screen),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder f) async {
    for (final messenger in tester.stateList<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))) {
      messenger.removeCurrentSnackBar();
    }
    await tester.pumpAndSettle();
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  bool ticked(WidgetTester tester, int i) => tester.widget<CheckboxListTile>(key('website-upload-file-$i-consent')).value!;
  String text(WidgetTester tester, String k) => tester.widget<Text>(key(k)).data!;

  Future<void> openReview(WidgetTester tester, List<PlatformFile> files) async {
    picker.files.addAll(files);
    await pumpScreen(tester, WebsiteContentScreen(service: service));
    await tap(tester, key('website-upload'));
  }

  Future<void> upload(WidgetTester tester) async {
    await tap(tester, key('website-upload-confirm'));
    expect(text(tester, 'website-upload-status'), startsWith('3 uploaded · 0 failed'));
  }

  /// The uploaded records by the first byte of their file (1, 2, 3), via
  /// their stored order.
  Future<List<WebsiteMedia>> uploaded() async {
    final docs = (await media().get()).docs.where((d) => !d.id.startsWith('m_old')).toList()
      ..sort((a, b) => (a.data()['galleryOrder'] as int).compareTo(b.data()['galleryOrder'] as int));
    return [for (final d in docs) WebsiteMedia.fromMap(d.id, d.data())];
  }

  Future<void> confirmAll(WidgetTester tester) async {
    await tap(tester, key('website-upload-consent-all'));
    await tap(tester, key('website-upload-consent-all-confirm'));
  }

  group('the review', () {
    testWidgets('1, 10. each image: thumbnail, file name, alt text “2D Montessori”, its own unticked approval and consent', (tester) async {
      await openReview(tester, _three);
      for (final (i, f) in _three.indexed) {
        expect(key('website-upload-file-$i-thumb'), findsOneWidget);
        expect(find.descendant(of: key('website-upload-file-$i'), matching: find.text(f.name)), findsOneWidget);
        expect(find.descendant(of: key('website-upload-file-$i'), matching: find.text('Alt text: 2D Montessori')), findsOneWidget);
        await tap(tester, key('website-upload-file-$i-details'));
        expect(tester.widget<TextField>(key('website-upload-file-$i-alt')).controller!.text, '2D Montessori');
        expect(ticked(tester, i), isFalse, reason: 'never ticked automatically');
        expect(text(tester, 'website-upload-file-$i-consent-state'), contains('Not confirmed'));
      }
      expect(text(tester, 'website-upload-consent-summary'), '0 of 3 images confirmed · 3 not confirmed');
      expect(tester.takeException(), isNull);
    });

    testWidgets('3. confirming all needs the statement agreed to; Cancel changes nothing', (tester) async {
      await openReview(tester, _three);
      await tap(tester, key('website-upload-consent-all'));
      expect(key('website-upload-consent-all-dialog'), findsOneWidget);
      expect(text(tester, 'website-upload-consent-all-statement'), uploadConsentStatement);
      expect(uploadConsentStatement, 'I confirm that all selected photographs are approved by the school and that the required consent has been obtained.');
      expect(find.textContaining('in this upload only'), findsOneWidget);
      await tap(tester, key('website-upload-consent-all-cancel'));
      expect([for (var i = 0; i < 3; i++) ticked(tester, i)], [false, false, false]);

      await confirmAll(tester);
      expect([for (var i = 0; i < 3; i++) ticked(tester, i)], [true, true, true]);
      expect(text(tester, 'website-upload-consent-summary'), '3 of 3 images confirmed · 0 not confirmed');
    });

    testWidgets('a file left out isn’t counted or confirmed', (tester) async {
      await openReview(tester, _three);
      await tap(tester, key('website-upload-file-2-remove'));
      await confirmAll(tester);
      expect(text(tester, 'website-upload-consent-summary'), '2 of 2 images confirmed · 0 not confirmed');
      await tap(tester, key('website-upload-confirm'));
      expect((await media().get()).docs, hasLength(2));
    });
  });

  group('saved with each image', () {
    testWidgets('2, 8. ticked one by one: saved for those only, through the audited confirmation; kept after reload', (tester) async {
      await openReview(tester, _three);
      await tap(tester, key('website-upload-file-0-consent'));
      await tap(tester, key('website-upload-file-2-consent'));
      expect(text(tester, 'website-upload-consent-summary'), '2 of 3 images confirmed · 1 not confirmed');
      await upload(tester);
      expect(text(tester, 'website-upload-file-0-status'), contains('Approval and consent confirmed.'));
      expect(text(tester, 'website-upload-file-1-status'), contains('not confirmed: it can’t be published'));
      final m = await uploaded();
      expect([for (final x in m) x.consentConfirmed], [true, false, true]);
      expect([for (final x in m) x.status], everyElement(WebsiteMediaStatus.draft), reason: 'confirming publishes nothing');
      final a = await audit(m[0].id);
      expect(a.map((e) => e['action']), containsAll(['uploaded', 'consent-confirmed']));
      expect(a.firstWhere((e) => e['action'] == 'consent-confirmed').containsKey('bulk'), isFalse);
      expect((await audit(m[1].id)).map((e) => e['action']), isNot(contains('consent-confirmed')));

      // Reloaded, and in the image's own editor.
      await tap(tester, key('website-upload-cancel'));
      await pumpScreen(tester, WebsiteMediaEditorScreen(service: service, user: _admin, media: await reload(m[1].id)));
      expect(tester.widget<CheckboxListTile>(key('website-media-consent')).value, isFalse);
      await pumpScreen(tester, WebsiteMediaEditorScreen(service: service, user: _admin, media: await reload(m[2].id)));
      expect(tester.widget<CheckboxListTile>(key('website-media-consent')).value, isTrue);
    });

    testWidgets('4, 5, 6, 9. all confirmed, one unticked again and one corrected back: this upload only; other images untouched', (tester) async {
      final unconfirmed = await existing('m_old0000001', consent: false);
      final confirmed = await existing('m_old0000002', consent: true, alt: 'The art corner');
      await openReview(tester, _three);
      await confirmAll(tester);
      await tap(tester, key('website-upload-file-1-consent'));
      expect(ticked(tester, 1), isFalse, reason: 'left unconfirmed after the bulk action');
      expect(text(tester, 'website-upload-consent-summary'), '2 of 3 images confirmed · 1 not confirmed');
      await tap(tester, key('website-upload-file-2-consent'));
      await tap(tester, key('website-upload-file-2-consent'));
      expect(ticked(tester, 2), isTrue, reason: 'corrected back');
      await upload(tester);

      final m = await uploaded();
      expect([for (final x in m) x.consentConfirmed], [true, false, true]);
      final bulk = (await audit(m[0].id)).firstWhere((e) => e['action'] == 'consent-confirmed');
      expect(bulk['bulk'], isTrue, reason: 'recorded as the bulk confirmation');
      expect((await audit(m[2].id)).firstWhere((e) => e['action'] == 'consent-confirmed').containsKey('bulk'), isFalse, reason: 'ticked by hand');
      expect((await reload(unconfirmed)).consentConfirmed, isFalse, reason: 'outside this upload');
      expect((await reload(confirmed)).consentConfirmed, isTrue);
      expect((await reload(confirmed)).alt.en, 'The art corner');
      expect(await audit(unconfirmed), isEmpty);
    });

    testWidgets('7. uploaded without ticking anything: nothing approved', (tester) async {
      await openReview(tester, _three);
      await upload(tester);
      final m = await uploaded();
      expect([for (final x in m) x.consentConfirmed], [false, false, false]);
      expect([for (final x in m) x.alt.en], everyElement('2D Montessori'), reason: 'alt text is not consent');
      for (var i = 0; i < 3; i++) {
        expect(text(tester, 'website-upload-file-$i-status'), contains('Approval and consent not confirmed'));
      }
    });
  });

  group('alt text and publishing', () {
    testWidgets('11. a custom alt text survives the confirmation and publishing', (tester) async {
      await openReview(tester, _three.take(1).toList());
      await tap(tester, key('website-upload-file-0-details'));
      await tester.enterText(key('website-upload-file-0-alt'), 'Children planting seedlings');
      await tap(tester, key('website-upload-file-0-consent'));
      await tap(tester, key('website-upload-confirm'));
      final m = (await uploaded()).single;
      expect(m.consentConfirmed, isTrue);
      await service.publishMedia(requesterRole: 'admin', actor: _admin, mediaId: m.id);
      final after = await reload(m.id);
      expect(after.alt.en, 'Children planting seedlings');
      expect(after.isPublished, isTrue);
    });

    testWidgets('12, 13, 14. bulk publishing: confirmed ones published; the others refused, naming what is missing', (tester) async {
      await openReview(tester, _three);
      await tap(tester, key('website-upload-file-0-consent'));
      await upload(tester);
      final m = await uploaded();
      final noFile = await existing('m_old0000003', consent: true, alt: 'Garden');
      await media().doc(noFile).update({'url': ''});
      await tap(tester, key('website-upload-cancel'));
      await pumpScreen(tester, WebsiteContentScreen(service: service));

      for (final id in [m[0].id, m[1].id, noFile]) {
        await tap(tester, key('website-media-$id-select'));
      }
      await tap(tester, key('website-media-bulk'));
      await tester.tap(key('website-media-bulk-publish'));
      await tester.pumpAndSettle();
      expect(text(tester, 'website-bulk-summary'), '1 done · 0 unchanged · 2 failed');
      Finder row(String id, String t) => find.descendant(of: key('website-bulk-result-$id'), matching: find.text(t));
      // Each row named by its alt text; the reason is the real one.
      expect(row(m[1].id, '2D Montessori'), findsOneWidget);
      expect(row(m[1].id, WebsiteMedia.consentNotConfirmed), findsOneWidget);
      expect(row(noFile, 'The image file is missing.'), findsOneWidget);
      expect(find.descendant(of: key('website-bulk-results'), matching: find.textContaining('without alt text')), findsNothing);
      await tap(tester, key('website-bulk-results-close'));

      expect((await reload(m[0].id)).isPublished, isTrue);
      expect((await reload(m[1].id)).status, WebsiteMediaStatus.draft);
      await expectLater(
        service.publishMedia(requesterRole: 'admin', actor: _admin, mediaId: m[1].id),
        throwsA(isA<WebsiteContentException>().having((e) => e.message, 'message', WebsiteMedia.consentNotConfirmed)),
      );
      await service.confirmConsent(requesterRole: 'admin', actor: _admin, mediaId: m[1].id);
      await service.publishMedia(requesterRole: 'admin', actor: _admin, mediaId: m[1].id);
      expect((await reload(m[1].id)).isPublished, isTrue);
    });
  });
}
