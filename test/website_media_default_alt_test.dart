// Newly uploaded Media Library images start with the alt text
// "2D Montessori" (English; Tamil untouched): prefilled for each file in the
// upload review, and the service's default for uploads made elsewhere (an
// event's or announcement's image). It stays editable; a custom alt text is
// never put back to the default by later edits, publishing, replacing the
// file or later uploads; images already stored are never rewritten. Alt
// text says nothing about consent: publishing still needs the photograph
// confirmed. Synthetic test data only.
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
import 'package:montessori_app/modules/admin/website/ui/website_media_library.dart' show mediaLabel;
import 'package:montessori_app/modules/auth/models/app_user.dart';
import 'package:montessori_app/modules/auth/providers/auth_provider.dart';
import 'package:montessori_app/modules/public_website/content/website_content_models.dart';

class _Processor implements WebsiteImageProcessor {
  final types = <String>[];

  @override
  Future<ProcessedWebsiteImage> process(Uint8List bytes, {required String contentType}) async {
    types.add(contentType);
    return ProcessedWebsiteImage(
      width: 1600,
      height: 1200,
      display: Uint8List.fromList([1, 2, 3]),
      displayContentType: 'image/jpeg',
      thumb: Uint8List.fromList([4]),
      thumbContentType: 'image/jpeg',
    );
  }
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

PlatformFile _file(String name, {int first = 9}) => PlatformFile(name: name, size: 3, bytes: Uint8List.fromList([first, 9, 9]));
PickedWebsiteImage _image(String name) => PickedWebsiteImage(name: name, bytes: Uint8List.fromList([1, 9, 9]));

void main() {
  Finder key(String k) => find.byKey(Key(k));
  late FakeFirebaseFirestore db;
  late _Processor processor;
  late _Picker picker;
  late WebsiteContentAdminService service;

  setUp(() {
    db = FakeFirebaseFirestore();
    processor = _Processor();
    picker = _Picker();
    service = WebsiteContentAdminService(firestore: db, storage: MockFirebaseStorage(), imageProcessor: processor, filePicker: picker);
  });

  CollectionReference<Map<String, dynamic>> media() => db.collection(WebsiteCollections.media);
  Future<Map<String, dynamic>> stored(String id) async => (await media().doc(id).get()).data()!;
  Future<WebsiteMedia> reload(String id) async => (await service.getMedia(requesterRole: 'admin', mediaId: id))!;

  /// A record stored by an earlier version, without alt text.
  Future<String> existingWithoutAlt(String id, {bool consent = false}) async {
    await media().doc(id).set({
      'url': 'https://storage.example.test/$id.jpg',
      'storagePath': 'website_media/$id/1_display.jpg',
      'alt': {'en': '', 'ta': ''},
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
    tester.view.physicalSize = const Size(1200, 3000);
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

  /// Picks [files] in the library and uploads them as they are.
  Future<List<Map<String, dynamic>>> uploadInLibrary(WidgetTester tester, List<PlatformFile> files) async {
    picker.files.addAll(files);
    await pumpScreen(tester, WebsiteContentScreen(service: service));
    await tap(tester, key('website-upload'));
    for (var i = 0; i < files.length; i++) {
      await tap(tester, key('website-upload-file-$i-details'));
      expect(tester.widget<TextField>(key('website-upload-file-$i-alt')).controller!.text, WebsiteMedia.defaultAlt, reason: 'prefilled for file $i');
    }
    await tap(tester, key('website-upload-confirm'));
    expect(tester.widget<Text>(key('website-upload-status')).data, '${files.length} uploaded · 0 failed');
    return [for (final d in (await media().get()).docs) d.data()];
  }

  group('upload', () {
    testWidgets('1, 4. one image: prefilled, saved with it, still there after reload', (tester) async {
      final docs = await uploadInLibrary(tester, [_file('garden.jpg')]);
      expect(docs.single['alt'], {'en': '2D Montessori', 'ta': ''}, reason: 'English only; Tamil left empty');
      final id = (await media().get()).docs.single.id;
      expect((await reload(id)).alt.en, '2D Montessori');
      await tap(tester, key('website-upload-cancel'));
      await pumpScreen(tester, WebsiteContentScreen(service: service));
      expect(find.text('2D Montessori'), findsWidgets, reason: 'the library shows it after reopening');
    });

    testWidgets('2, 3. several images (JPEG, PNG, WebP): each its own default', (tester) async {
      final docs = await uploadInLibrary(tester, [_file('a.jpg', first: 1), _file('b.png', first: 2), _file('c.webp', first: 3)]);
      expect(docs, hasLength(3));
      expect(processor.types.toSet(), {'image/jpeg', 'image/png', 'image/webp'});
      for (final d in docs) {
        expect((d['alt'] as Map)['en'], '2D Montessori');
        expect(d['consentConfirmed'], isFalse, reason: 'alt text implies no consent');
        expect(d['status'], 'draft');
      }
    });

    testWidgets('the default can be changed (or cleared) before uploading', (tester) async {
      picker.files.addAll([_file('a.jpg', first: 1), _file('b.jpg', first: 2)]);
      await pumpScreen(tester, WebsiteContentScreen(service: service));
      await tap(tester, key('website-upload'));
      await tap(tester, key('website-upload-file-0-details'));
      await tester.enterText(key('website-upload-file-0-alt'), 'Children in the garden');
      await tap(tester, key('website-upload-file-1-details'));
      await tester.enterText(key('website-upload-file-1-alt'), '');
      await tap(tester, key('website-upload-confirm'));
      final alts = {for (final d in (await media().get()).docs) (d.data()['alt'] as Map)['en']};
      expect(alts, {'Children in the garden', ''});
    });

    test('elsewhere (an event’s or announcement’s image): the service default; an explicit value is kept', () async {
      final plain = await service.uploadMedia(requesterRole: 'admin', actor: _admin, image: _image('p.png'), inGallery: false);
      expect((await stored(plain.id))['alt'], {'en': '2D Montessori', 'ta': ''});
      final own = await service.uploadMedia(requesterRole: 'admin', actor: _admin, image: _image('o.webp'), alt: const LocalizedText(en: 'Sports day', ta: 'விளையாட்டு நாள்'));
      expect((await stored(own.id))['alt'], {'en': 'Sports day', 'ta': 'விளையாட்டு நாள்'});
      final none = await service.uploadMedia(requesterRole: 'admin', actor: _admin, image: _image('n.jpg'), alt: const LocalizedText());
      expect((await stored(none.id))['alt'], {'en': '', 'ta': ''});
    });
  });

  group('later editing', () {
    testWidgets('5, 6. edited to a custom alt text in the library; kept through edits, publishing and replacing', (tester) async {
      final uploaded = await service.uploadMedia(requesterRole: 'admin', actor: _admin, image: _image('a.jpg'));
      await pumpScreen(tester, WebsiteMediaEditorScreen(service: service, user: _admin, media: await reload(uploaded.id)));
      expect(tester.widget<TextField>(key('website-media-alt-en')).controller!.text, '2D Montessori');
      await tester.enterText(key('website-media-alt-en'), 'Children watering plants');
      await tap(tester, key('website-media-save'));
      expect((await reload(uploaded.id)).alt.en, 'Children watering plants');

      // Consent, other details, publishing, the bulk actions, replacing the
      // file and more uploads: never back to the default.
      await service.confirmConsent(requesterRole: 'admin', actor: _admin, mediaId: uploaded.id);
      final m = await reload(uploaded.id);
      await service.updateMediaDetails(
        requesterRole: 'admin', actor: _admin, mediaId: m.id, alt: m.alt, caption: const LocalizedText(en: 'Garden'),
        category: GalleryCategory.general, inGallery: false, focalX: 0.3, focalY: 0.6, consentConfirmed: true,
      );
      await service.publishMedia(requesterRole: 'admin', actor: _admin, mediaId: m.id);
      await service.applyBulk(requesterRole: 'admin', actor: _admin, action: WebsiteBulkAction.addToGallery, mediaIds: [m.id]);
      await service.replaceMediaImage(requesterRole: 'admin', actor: _admin, mediaId: m.id, image: _image('b.png'));
      await service.confirmConsent(requesterRole: 'admin', actor: _admin, mediaId: m.id);
      await service.applyBulk(requesterRole: 'admin', actor: _admin, action: WebsiteBulkAction.publish, mediaIds: [m.id]);
      await service.uploadMedia(requesterRole: 'admin', actor: _admin, image: _image('c.jpg'));
      final after = await reload(m.id);
      expect(after.alt.en, 'Children watering plants');
      expect(after.isPublished, isTrue);
    });
  });

  group('existing images', () {
    test('7. never rewritten: uploads, consent, publishing and other edits leave an empty alt text empty', () async {
      final old = await existingWithoutAlt('m_old0000001');
      await service.uploadMedia(requesterRole: 'admin', actor: _admin, image: _image('new.jpg'));
      await service.confirmConsent(requesterRole: 'admin', actor: _admin, mediaId: old);
      await service.publishMedia(requesterRole: 'admin', actor: _admin, mediaId: old);
      final m = await reload(old);
      expect(m.alt.en, '');
      expect((await stored(old))['alt'], {'en': '', 'ta': ''});
      // Still named as having none, so admins can find and describe it.
      expect(mediaLabel(m), 'Image without alt text');
    });

    testWidgets('still editable in the library', (tester) async {
      final old = await existingWithoutAlt('m_old0000002');
      await pumpScreen(tester, WebsiteMediaEditorScreen(service: service, user: _admin, media: await reload(old)));
      expect(tester.widget<TextField>(key('website-media-alt-en')).controller!.text, '', reason: 'no default put in');
      await tester.enterText(key('website-media-alt-en'), 'The art corner');
      await tap(tester, key('website-media-save'));
      expect((await reload(old)).alt.en, 'The art corner');
    });
  });

  group('publishing', () {
    test('8, 9. a new upload publishes once consent is confirmed, never before', () async {
      final m = await service.uploadMedia(requesterRole: 'admin', actor: _admin, image: _image('a.jpg'));
      expect(m.alt.en, '2D Montessori');
      expect(m.publishBlocker, WebsiteMedia.consentNotConfirmed);
      await expectLater(
        service.publishMedia(requesterRole: 'admin', actor: _admin, mediaId: m.id),
        throwsA(isA<WebsiteContentException>().having((e) => e.message, 'message', contains('consent'))),
      );
      final bulk = await service.applyBulk(requesterRole: 'admin', actor: _admin, action: WebsiteBulkAction.publish, mediaIds: [m.id]);
      expect(bulk.single.status, WebsiteBulkStatus.failed);
      expect((await reload(m.id)).status, WebsiteMediaStatus.draft);

      await service.confirmConsent(requesterRole: 'admin', actor: _admin, mediaId: m.id);
      await service.publishMedia(requesterRole: 'admin', actor: _admin, mediaId: m.id);
      expect((await reload(m.id)).isPublished, isTrue);
    });

    test('8. bulk-published: each listed by its alt text, refused only for consent', () async {
      final a = await service.uploadMedia(requesterRole: 'admin', actor: _admin, image: _image('a.jpg'));
      final b = await service.uploadMedia(requesterRole: 'admin', actor: _admin, image: _image('b.png'));
      await service.confirmConsent(requesterRole: 'admin', actor: _admin, mediaId: a.id);
      final outcomes = await service.applyBulk(requesterRole: 'admin', actor: _admin, action: WebsiteBulkAction.publish, mediaIds: [a.id, b.id]);
      expect({for (final o in outcomes) o.mediaId: o.status}, {a.id: WebsiteBulkStatus.done, b.id: WebsiteBulkStatus.failed});
      expect(outcomes.firstWhere((o) => o.mediaId == b.id).message, contains('consent'));
      expect(mediaLabel(await reload(b.id)), '2D Montessori', reason: 'no longer “Image without alt text”');
    });
  });
}
