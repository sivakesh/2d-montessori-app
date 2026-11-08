// Media library upgrade, phase 1: several images uploaded at once (each
// file checked on its own, shared defaults and per-image settings, each
// file's progress and result, retry of failures only, no duplicates),
// optional alt text and decorative images, bulk actions through the
// single-image workflow (consent, publish, unpublish, gallery, delete with
// the image-in-use checks) with per-image results, and albums (admin-only
// organisation: membership on the album, never on the image). Existing
// media records, their ids and unknown fields are kept. Synthetic test
// data only.
import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/admin/settings/models/school_settings_model.dart' show kDefaultSchoolId;
import 'package:montessori_app/modules/admin/website/data/website_albums_service.dart';
import 'package:montessori_app/modules/admin/website/data/website_content_admin_service.dart';
import 'package:montessori_app/modules/admin/website/data/website_image_processor.dart';
import 'package:montessori_app/modules/admin/website/ui/website_content_screen.dart';
import 'package:montessori_app/modules/auth/models/app_user.dart';
import 'package:montessori_app/modules/auth/providers/auth_provider.dart';
import 'package:montessori_app/modules/public_website/content/website_content_models.dart';
import 'package:montessori_app/modules/public_website/content/website_content_repository.dart';
import 'package:montessori_app/modules/public_website/widgets/public_website_image.dart';

/// Fails (once) for files whose first byte is in [failOnce].
class _FlakyProcessor implements WebsiteImageProcessor {
  final Set<int> failOnce = {};
  int calls = 0;

  /// While set, each image waits for it (an upload in progress).
  Completer<void>? hold;

  @override
  Future<ProcessedWebsiteImage> process(Uint8List bytes, {required String contentType}) async {
    calls++;
    if (hold != null) await hold!.future;
    if (bytes.isNotEmpty && failOnce.remove(bytes.first)) throw StateError('undecodable');
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

class _StubFilePicker extends FilePicker {
  _StubFilePicker(this.files);
  final List<PlatformFile> files;
  bool? askedForMultiple;
  List<String>? askedExtensions;

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
  }) async {
    askedForMultiple = allowMultiple;
    askedExtensions = allowedExtensions;
    return files.isEmpty ? null : FilePickerResult(files);
  }
}

final _admin = AppUser(id: '9000000001', phone: '9000000001', role: 'admin', isActive: true, name: 'Test admin');
AppUser _staff() => AppUser(id: '9000000003', phone: '9000000003', role: 'staff', isActive: true, name: 'Test staff');

PlatformFile _file(String name, {int first = 9, int size = 3}) => PlatformFile(name: name, size: size, bytes: size == 0 ? Uint8List(0) : Uint8List.fromList([first, ...List.filled(size - 1, 9)]));

PickedWebsiteImage _image(String name, {int first = 9}) => PickedWebsiteImage(name: name, bytes: Uint8List.fromList([first, 9, 9]));

void main() {
  Finder key(String k) => find.byKey(Key(k));
  late FakeFirebaseFirestore db;
  late MockFirebaseStorage storage;
  late _FlakyProcessor processor;
  late _StubFilePicker picker;
  late WebsiteContentAdminService service;

  setUp(() {
    db = FakeFirebaseFirestore();
    storage = MockFirebaseStorage();
    processor = _FlakyProcessor();
    picker = _StubFilePicker([]);
    service = WebsiteContentAdminService(firestore: db, storage: storage, imageProcessor: processor, filePicker: picker);
  });

  CollectionRef media() => db.collection(WebsiteCollections.media);

  /// A stored media record as an earlier version wrote it (no `decorative`)
  /// with a property this version doesn't know.
  Future<String> legacy(String id, {bool consent = true, String status = 'draft', String alt = 'Children at work', bool inGallery = true}) async {
    await media().doc(id).set({
      'url': 'https://storage.example.test/$id.jpg',
      'storagePath': 'website_media/$id/1_display.jpg',
      'thumbUrl': 'https://storage.example.test/${id}_t.jpg',
      'thumbStoragePath': 'website_media/$id/1_thumb.jpg',
      'alt': {'en': alt, 'ta': 'குழந்தைகள்'},
      'caption': {'en': ''},
      'category': 'classroom',
      'status': status,
      'inGallery': inGallery,
      'galleryOrder': 0,
      'consentConfirmed': consent,
      'futureProperty': {'kept': true},
    });
    return id;
  }

  Future<Map<String, dynamic>> stored(String id) async => (await media().doc(id).get()).data()!;

  Future<List<WebsiteBulkOutcome>> bulk(WebsiteBulkAction action, List<String> ids) => service.applyBulk(requesterRole: 'admin', actor: _admin, action: action, mediaIds: ids);

  Map<String, WebsiteBulkStatus> statuses(List<WebsiteBulkOutcome> outcomes) => {for (final o in outcomes) o.mediaId: o.status};

  // ------------------------------------------------------------ upload
  group('several images at once', () {
    test('one picker for several files; each checked on its own: JPEG, PNG, WebP, at most 15 MB, not empty', () async {
      picker.files.addAll([
        _file('a.jpg'),
        _file('b.PNG'),
        _file('c.webp'),
        _file('d.gif'),
        _file('e.jpeg', size: 0),
        PlatformFile(name: 'f.jpg', size: WebsiteContentAdminService.maxUploadBytes + 1, bytes: Uint8List(WebsiteContentAdminService.maxUploadBytes + 1)),
        PlatformFile(name: 'g.jpg', size: 10),
      ]);
      final files = await service.pickImages();
      expect(picker.askedForMultiple, isTrue);
      expect(picker.askedExtensions, ['jpg', 'jpeg', 'png', 'webp']);
      expect(files.map((f) => f.name), ['a.jpg', 'b.PNG', 'c.webp', 'd.gif', 'e.jpeg', 'f.jpg', 'g.jpg'], reason: 'none dropped');
      expect([for (final f in files) f.problem], [
        null,
        null,
        null,
        'Choose a JPEG, PNG or WebP image.',
        'The selected file is empty.',
        'Choose an image smaller than 15 MB.',
        'The file could not be read.',
      ]);
      expect(files.take(3).every((f) => f.image != null), isTrue);
      expect(files.skip(3).every((f) => f.image == null), isTrue);
      picker.files.clear();
      expect(await service.pickImages(), isEmpty, reason: 'cancelled');
    });

    test('a reserved id makes an upload idempotent: retried or sent twice, one record and one set of files', () async {
      final id = service.newMediaId();
      final first = await service.uploadMedia(requesterRole: 'admin', actor: _admin, image: _image('Asha.jpg'), mediaId: id, decorative: true);
      final again = await service.uploadMedia(requesterRole: 'admin', actor: _admin, image: _image('Asha.jpg'), mediaId: id);
      expect(first.id, id);
      expect(again.id, id);
      expect((await media().get()).docs, hasLength(1));
      expect(processor.calls, 1, reason: 'the second call uploads nothing');
      final data = await stored(id);
      expect(data['decorative'], isTrue);
      expect(data['consentConfirmed'], isFalse, reason: 'never confirmed on upload');
      expect(data['status'], 'draft');
      expect(data.toString(), isNot(contains('Asha')), reason: 'the file name is never stored');
    });

    test('a failed file leaves no record or files; retrying it (same id) makes exactly one', () async {
      processor.failOnce.add(7);
      final id = service.newMediaId();
      await expectLater(service.uploadMedia(requesterRole: 'admin', actor: _admin, image: _image('x.jpg', first: 7), mediaId: id), throwsA(isA<WebsiteContentException>()));
      expect((await media().get()).docs, isEmpty);
      await service.uploadMedia(requesterRole: 'admin', actor: _admin, image: _image('x.jpg', first: 7), mediaId: id);
      expect((await media().get()).docs.map((d) => d.id), [id]);
    });
  });

  // ------------------------------------------------------------ alt text
  group('optional alt text and decorative images', () {
    test('publishing needs consent and the file, not alt text', () async {
      final noAlt = await legacy('m_noalt0001', alt: '');
      final noConsent = await legacy('m_nocons001', consent: false);
      await service.publishMedia(requesterRole: 'admin', actor: _admin, mediaId: noAlt);
      await expectLater(service.publishMedia(requesterRole: 'admin', actor: _admin, mediaId: noConsent), throwsA(isA<WebsiteContentException>().having((e) => e.message, 'message', contains('consent'))));
      final shown = await WebsiteContentRepository(firestore: db).publishedMedia();
      expect(shown.map((m) => m.id), [noAlt], reason: 'visitors see the alt-free image, never the unconsented one');
      expect(const WebsiteMedia(id: 'x', url: '', storagePath: '', consentConfirmed: true).publishBlocker, 'The image file is missing.');
    });

    test('decorative: set and cleared explicitly; kept when not given; alt text and unknown properties kept', () async {
      final id = await legacy('m_deco00001');
      expect(WebsiteMedia.fromMap(id, await stored(id)).decorative, isFalse, reason: 'an earlier record is not decorative');
      Future<void> save({bool? decorative, String alt = 'Children at work'}) => service.updateMediaDetails(
            requesterRole: 'admin',
            actor: _admin,
            mediaId: id,
            alt: LocalizedText(en: alt, ta: 'குழந்தைகள்'),
            caption: const LocalizedText(),
            category: GalleryCategory.classroom,
            inGallery: true,
            focalX: 0.5,
            focalY: 0.5,
            consentConfirmed: true,
            decorative: decorative,
          );
      await save();
      expect((await stored(id)).containsKey('decorative'), isFalse, reason: 'nothing new stored unless chosen');
      await save(decorative: true);
      expect((await stored(id))['decorative'], isTrue);
      await save();
      expect((await stored(id))['decorative'], isTrue, reason: 'kept when the form doesn’t say');
      await save(decorative: false, alt: '');
      final data = await stored(id);
      expect(data['decorative'], isFalse);
      expect(data['alt'], {'en': '', 'ta': 'குழந்தைகள்'});
      expect(data['futureProperty'], {'kept': true});
      expect(data['storagePath'], 'website_media/m_deco00001/1_display.jpg', reason: 'storage reference unchanged');
    });

    testWidgets('an image without alt text, or decorative, is drawn as usual and skipped by screen readers', (tester) async {
      final semantics = tester.ensureSemantics();
      for (final (label, decorative, skipped) in [('', false, true), ('Children reading', false, false), ('Children reading', true, true)]) {
        final m = WebsiteMedia(id: 'm1', url: 'https://storage.example.test/m1.jpg', storagePath: 'p', alt: const LocalizedText(en: 'Children reading'), decorative: decorative);
        expect(PublicWebsiteImage.skipsSemantics(m, label), skipped);
        await tester.pumpWidget(MaterialApp(home: SizedBox(width: 200, child: PublicWebsiteImage(media: m, aspectRatio: 1, semanticLabel: label))));
        final image = tester.widget<Image>(find.byType(Image));
        expect(image.excludeFromSemantics, skipped);
        expect(image.semanticLabel, skipped ? isNull : label);
      }
      // A use with its own description is read even for a decorative image.
      const deco = WebsiteMedia(id: 'm2', url: 'u', storagePath: 'p', alt: LocalizedText(en: 'Library alt'), decorative: true);
      expect(PublicWebsiteImage.skipsSemantics(deco, 'Our garden in spring'), isFalse);
      semantics.dispose();
    });
  });

  // ------------------------------------------------------------ bulk
  group('bulk actions', () {
    test('publish: only consented images; each image reported; nothing skipped silently', () async {
      final ok = await legacy('m_ok000001');
      final noConsent = await legacy('m_nocons001', consent: false);
      final already = await legacy('m_pub00001', status: 'published');
      final outcomes = await bulk(WebsiteBulkAction.publish, [ok, noConsent, already, 'm_missing01']);
      expect(outcomes, hasLength(4));
      expect(statuses(outcomes), {ok: WebsiteBulkStatus.done, noConsent: WebsiteBulkStatus.failed, already: WebsiteBulkStatus.unchanged, 'm_missing01': WebsiteBulkStatus.failed});
      expect(outcomes.firstWhere((o) => o.mediaId == noConsent).message, contains('consent'));
      expect(outcomes.firstWhere((o) => o.mediaId == 'm_missing01').message, 'This image no longer exists.');
      expect((await stored(ok))['status'], 'published');
      expect((await stored(noConsent))['status'], 'draft');
    });

    test('confirm consent in bulk: recorded per image as bulk; publishes nothing', () async {
      final a = await legacy('m_a0000001', consent: false);
      final b = await legacy('m_b0000001', consent: true);
      final outcomes = await bulk(WebsiteBulkAction.confirmConsent, [a, b]);
      expect(statuses(outcomes), {a: WebsiteBulkStatus.done, b: WebsiteBulkStatus.unchanged});
      expect((await stored(a))['consentConfirmed'], isTrue);
      expect((await stored(a))['status'], 'draft');
      final audit = await media().doc(a).collection('audit').get();
      expect(audit.docs.map((d) => (d.data()['action'], d.data()['bulk'], d.data()['byId'])), contains(('consent-confirmed', true, _admin.id)));
    });

    test('unpublish: refused for an image a published page shows (with where); others hidden; drafts unchanged', () async {
      final shown = await legacy('m_shown001', status: 'published');
      final free = await legacy('m_free0001', status: 'published');
      final draft = await legacy('m_draft001');
      await db.collection(WebsiteCollections.livePages).doc('home').set({'mediaIds': [shown], 'headline': {'en': 'Welcome'}});
      final outcomes = await bulk(WebsiteBulkAction.unpublish, [shown, free, draft]);
      expect(statuses(outcomes), {shown: WebsiteBulkStatus.failed, free: WebsiteBulkStatus.done, draft: WebsiteBulkStatus.unchanged});
      expect(outcomes.first.message, contains('Homepage hero'));
      expect((await stored(shown))['status'], 'published');
      expect((await stored(free))['status'], 'hidden');
    });

    test('gallery in and out: only the gallery listing changes, never publication or consent', () async {
      final a = await legacy('m_a0000001', status: 'published', inGallery: false);
      final b = await legacy('m_b0000001', inGallery: true, consent: false);
      expect(statuses(await bulk(WebsiteBulkAction.addToGallery, [a, b])), {a: WebsiteBulkStatus.done, b: WebsiteBulkStatus.unchanged});
      expect(statuses(await bulk(WebsiteBulkAction.removeFromGallery, [a, b])), {a: WebsiteBulkStatus.done, b: WebsiteBulkStatus.done});
      expect([(await stored(a))['inGallery'], (await stored(a))['status'], (await stored(a))['consentConfirmed']], [false, 'published', true]);
      expect([(await stored(b))['inGallery'], (await stored(b))['status'], (await stored(b))['consentConfirmed']], [false, 'draft', false]);
      expect((await stored(a))['futureProperty'], {'kept': true});
    });

    test('delete: images in use (draft page, form, template check) are kept and listed; others deleted and taken out of albums', () async {
      final onDraft = await legacy('m_draft001');
      final onForm = await legacy('m_form0001');
      final free = await legacy('m_free0001');
      await db.collection(WebsiteCollections.pageDrafts).doc('admissions').set({'mediaIds': [onDraft]});
      await db.collection('website_forms').doc('f1').set({'mediaIds': [onForm], 'title': {'en': 'Enquiry'}});
      final album = await service.albums.create(requesterRole: 'admin', actor: _admin, name: 'Annual day');
      await service.albums.addMedia(requesterRole: 'admin', actor: _admin, albumId: album.id, mediaIds: [onDraft, free]);
      final outcomes = await bulk(WebsiteBulkAction.delete, [onDraft, onForm, free]);
      expect(statuses(outcomes), {onDraft: WebsiteBulkStatus.failed, onForm: WebsiteBulkStatus.failed, free: WebsiteBulkStatus.done});
      expect(outcomes[0].message, contains('Admissions'));
      expect(outcomes[1].message, contains('Enquiry'));
      expect((await media().doc(onDraft).get()).exists, isTrue);
      expect((await media().doc(free).get()).exists, isFalse);
      final after = (await service.albums.list(requesterRole: 'admin')).single;
      expect(after.mediaIds, [onDraft], reason: 'a deleted image leaves its albums');
    });

    test('only admins', () async {
      final id = await legacy('m_a0000001');
      await expectLater(service.applyBulk(requesterRole: 'staff', actor: _staff(), action: WebsiteBulkAction.publish, mediaIds: [id]), throwsA(isA<UnauthorizedWebsiteContentException>()));
      await expectLater(service.albums.list(requesterRole: 'staff'), throwsA(isA<UnauthorizedWebsiteContentException>()));
      await expectLater(service.albums.create(requesterRole: 'parent', actor: _staff(), name: 'X'), throwsA(isA<UnauthorizedWebsiteContentException>()));
    });
  });

  // ------------------------------------------------------------ albums
  group('albums', () {
    WebsiteAlbumsService albums() => service.albums;

    test('create (name required), rename and describe, delete keeping the images; unknown properties kept', () async {
      await expectLater(albums().create(requesterRole: 'admin', actor: _admin, name: '   '), throwsA(isA<WebsiteContentException>()));
      await expectLater(albums().create(requesterRole: 'admin', actor: _admin, name: 'x' * 81), throwsA(isA<WebsiteContentException>()));
      await expectLater(albums().create(requesterRole: 'admin', actor: _admin, name: 'Ok', description: 'd' * 301), throwsA(isA<WebsiteContentException>()));
      final a = await albums().create(requesterRole: 'admin', actor: _admin, name: '  Annual day 2026 ', description: '');
      expect(a.name, 'Annual day 2026');
      expect(a.schoolId, kDefaultSchoolId);
      final raw = (await db.collection(WebsiteCollections.albums).doc(a.id).get()).data()!;
      expect(raw.containsKey('description'), isFalse);
      await db.collection(WebsiteCollections.albums).doc(a.id).update({'futureProperty': 1});

      await albums().update(requesterRole: 'admin', actor: _admin, albumId: a.id, name: 'Annual day', description: 'Stage and garden');
      var list = await albums().list(requesterRole: 'admin');
      expect([list.single.name, list.single.description], ['Annual day', 'Stage and garden']);
      await albums().update(requesterRole: 'admin', actor: _admin, albumId: a.id, name: 'Annual day', description: '');
      expect((await albums().list(requesterRole: 'admin')).single.description, '');
      expect((await db.collection(WebsiteCollections.albums).doc(a.id).get()).data()!['futureProperty'], 1);

      final img = await legacy('m_a0000001');
      await albums().addMedia(requesterRole: 'admin', actor: _admin, albumId: a.id, mediaIds: [img]);
      final before = await stored(img);
      await albums().delete(requesterRole: 'admin', albumId: a.id);
      list = await albums().list(requesterRole: 'admin');
      expect(list, isEmpty);
      expect(await stored(img), before, reason: 'the image is untouched');
    });

    test('several images in, several out; an image in several albums; membership never touches the image', () async {
      final ids = [for (var i = 0; i < 4; i++) await legacy('m_img0000$i')];
      final before = {for (final id in ids) id: await stored(id)};
      final a = await albums().create(requesterRole: 'admin', actor: _admin, name: 'Classroom');
      final b = await albums().create(requesterRole: 'admin', actor: _admin, name: 'Outdoors');
      expect(await albums().addMedia(requesterRole: 'admin', actor: _admin, albumId: a.id, mediaIds: ids.take(3)), 3);
      expect(await albums().addMedia(requesterRole: 'admin', actor: _admin, albumId: a.id, mediaIds: ids), 1, reason: 'only the new one');
      await albums().addMedia(requesterRole: 'admin', actor: _admin, albumId: b.id, mediaIds: [ids[0], ids[1]]);
      expect(await albums().removeMedia(requesterRole: 'admin', actor: _admin, albumId: a.id, mediaIds: [ids[1], ids[2], 'm_notin001']), 2);
      final list = {for (final x in await albums().list(requesterRole: 'admin')) x.name: x.mediaIds};
      expect(list, {
        'Classroom': [ids[0], ids[3]],
        'Outdoors': [ids[0], ids[1]],
      });
      for (final id in ids) {
        expect(await stored(id), before[id], reason: 'publication, consent and gallery unchanged');
      }
    });

    test('counts leave out deleted images; search by name or description; another school’s albums are never seen', () async {
      final kept = await legacy('m_kept0001');
      final a = await albums().create(requesterRole: 'admin', actor: _admin, name: 'Garden', description: 'Spring planting');
      await db.collection(WebsiteCollections.albums).doc(a.id).update({'mediaIds': [kept, 'm_gone0001']});
      final library = await service.listMedia(requesterRole: 'admin');
      final album = (await albums().list(requesterRole: 'admin')).single;
      expect(album.availableIn(library), [kept]);
      expect([album.matches('gard'), album.matches('PLANT'), album.matches(''), album.matches('beach')], [true, true, true, false]);

      await db.collection(WebsiteCollections.albums).doc('other').set({'schoolId': 'another_school', 'name': 'Theirs', 'mediaIds': [kept]});
      expect((await albums().list(requesterRole: 'admin')).map((x) => x.name), ['Garden']);
      await expectLater(albums().update(requesterRole: 'admin', actor: _admin, albumId: 'other', name: 'Mine', description: ''), throwsA(isA<WebsiteContentException>()));
      await expectLater(albums().delete(requesterRole: 'admin', albumId: 'other'), throwsA(isA<WebsiteContentException>()));
      expect((await db.collection(WebsiteCollections.albums).doc('other').get()).exists, isTrue);
    });

    test('albums are never public: published image records carry no album data', () async {
      final id = await legacy('m_pub00001', status: 'published');
      final a = await albums().create(requesterRole: 'admin', actor: _admin, name: 'Events');
      await albums().addMedia(requesterRole: 'admin', actor: _admin, albumId: a.id, mediaIds: [id]);
      final public = await media().where('status', isEqualTo: 'published').get();
      expect(public.docs.single.data().keys.where((k) => k.toLowerCase().contains('album')), isEmpty);
    });
  });

  // ------------------------------------------------------------ screens
  group('in the media library', () {
    Future<void> pump(WidgetTester tester, {Size size = const Size(1200, 2400)}) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(ProviderScope(
        overrides: [currentUserProvider.overrideWith((ref) => _admin)],
        child: MaterialApp(home: WebsiteContentScreen(service: service)),
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

    String text(WidgetTester tester, String k) => tester.widget<Text>(key(k)).data!;

    testWidgets('review, shared defaults, per-image alt text, upload with each file’s result, retry the failed one only; no duplicates', (tester) async {
      final album = await service.albums.create(requesterRole: 'admin', actor: _admin, name: 'Annual day');
      picker.files.addAll([_file('one.jpg', first: 1), _file('two.png', first: 2), _file('three.webp', first: 3), _file('four.gif')]);
      processor.failOnce.add(2);
      await pump(tester);
      await tap(tester, key('website-upload'));

      expect(key('website-upload-review'), findsOneWidget);
      expect(text(tester, 'website-upload-summary'), startsWith('3 ready to upload, 1 can’t be uploaded'));
      expect(text(tester, 'website-upload-file-3-status'), contains('Choose a JPEG, PNG or WebP image.'));
      expect(key('website-upload-consent-note'), findsOneWidget);

      // Shared defaults: Outdoors, out of the gallery, the album.
      await tap(tester, key('website-upload-default-category'));
      await tester.tap(find.text('Outdoors').last);
      await tester.pumpAndSettle();
      await tap(tester, key('website-upload-default-gallery'));
      await tap(tester, key('website-upload-default-album-${album.id}'));
      // Image one: its own alt text and category.
      await tap(tester, key('website-upload-file-0-details'));
      await tester.enterText(key('website-upload-file-0-alt'), 'Children planting seedlings');
      await tap(tester, key('website-upload-file-0-category'));
      await tester.tap(find.text('Campus').last);
      await tester.pumpAndSettle();

      // Sent twice in a row: still one upload each.
      await tester.ensureVisible(key('website-upload-confirm'));
      await tester.tap(key('website-upload-confirm'));
      await tester.tap(key('website-upload-confirm'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(text(tester, 'website-upload-status'), '2 uploaded · 1 failed');
      expect(text(tester, 'website-upload-file-1-status'), contains('could not be read'));
      expect(text(tester, 'website-upload-file-0-status'), contains('Uploaded (draft).'));
      expect((await media().get()).docs, hasLength(2));
      final callsBefore = processor.calls;

      await tap(tester, key('website-upload-retry-failed'));
      expect(text(tester, 'website-upload-status'), '3 uploaded · 0 failed');
      expect(processor.calls, callsBefore + 1, reason: 'only the failed file is sent again');
      final docs = (await media().get()).docs;
      expect(docs, hasLength(3), reason: 'no duplicates');
      final byAlt = {for (final d in docs) (d.data()['alt'] as Map)['en']: d.data()};
      // The ones left as they were keep the default alt text.
      expect(byAlt.keys, containsAll(['Children planting seedlings', WebsiteMedia.defaultAlt]));
      expect(byAlt['Children planting seedlings']!['category'], 'campus');
      expect(docs.where((d) => d.data()['category'] == 'outdoors'), hasLength(2), reason: 'the shared default');
      expect(docs.every((d) => d.data()['inGallery'] == false && d.data()['consentConfirmed'] == false && d.data()['status'] == 'draft'), isTrue);
      expect((await service.albums.list(requesterRole: 'admin')).single.mediaIds.toSet(), {for (final d in docs) d.id});

      await tap(tester, key('website-upload-cancel'));
      expect(key('website-upload-review'), findsNothing);
      for (final d in docs) {
        expect(key('website-media-${d.id}'), findsOneWidget);
      }
    });

    testWidgets('stop during an upload: the rest are cancelled, not lost; retry sends only those', (tester) async {
      picker.files.addAll([_file('a.jpg', first: 1), _file('b.jpg', first: 2), _file('c.jpg', first: 3)]);
      await pump(tester);
      await tap(tester, key('website-upload'));
      processor.hold = Completer<void>();
      await tester.tap(key('website-upload-confirm'));
      await tester.pump();
      expect(key('website-upload-stop'), findsOneWidget, reason: 'the first image is uploading');
      expect(find.textContaining('Uploading…'), findsWidgets);
      await tester.tap(key('website-upload-stop'));
      await tester.pump();
      expect(find.text('Stopping after this image…'), findsOneWidget);
      processor.hold!.complete();
      processor.hold = null;
      await tester.pumpAndSettle();
      expect((await media().get()).docs, hasLength(1), reason: 'the image in progress finished');
      expect(find.textContaining('Not uploaded: cancelled.'), findsNWidgets(2));
      expect(text(tester, 'website-upload-status'), '1 uploaded · 0 failed · 2 cancelled');
      await tap(tester, key('website-upload-retry-failed'));
      expect((await media().get()).docs, hasLength(3));
      expect(text(tester, 'website-upload-status'), '3 uploaded · 0 failed');
    });

    testWidgets('select one by one, all shown, clear; bulk publish reports each image; bulk consent asks first', (tester) async {
      final ok = await legacy('m_ok000001');
      final noConsent = await legacy('m_nocons001', consent: false, alt: '');
      await legacy('m_other001');
      await pump(tester);
      expect(text(tester, 'website-media-selection-count'), '0 selected');
      expect(tester.widget<PopupMenuButton<String>>(key('website-media-bulk')).enabled, isFalse, reason: 'select images first');
      await tap(tester, key('website-media-select-all'));
      expect(text(tester, 'website-media-selection-count'), '3 selected');
      await tap(tester, key('website-media-clear-selection'));
      expect(text(tester, 'website-media-selection-count'), '0 selected');
      await tap(tester, key('website-media-$ok-select'));
      await tap(tester, key('website-media-$noConsent-select'));
      expect(text(tester, 'website-media-selection-count'), '2 selected');

      await tap(tester, key('website-media-bulk'));
      expect(find.textContaining('1 image can be published; 1 image need consent confirmed first'), findsOneWidget, reason: 'explained before acting');
      await tester.tap(key('website-media-bulk-publish'));
      await tester.pumpAndSettle();
      expect(key('website-bulk-results'), findsOneWidget);
      expect(text(tester, 'website-bulk-summary'), '1 done · 0 unchanged · 1 failed');
      expect(find.descendant(of: key('website-bulk-result-$noConsent'), matching: find.textContaining('consent')), findsOneWidget);
      await tap(tester, key('website-bulk-results-close'));
      expect((await stored(ok))['status'], 'published');

      // Consent for the other one, in bulk, after the warning.
      await tap(tester, key('website-media-bulk'));
      await tester.tap(key('website-media-bulk-confirmConsent'));
      await tester.pumpAndSettle();
      expect(find.textContaining('consent has been obtained for each child'), findsOneWidget);
      await tap(tester, key('website-bulk-consent-confirm-cancel'));
      expect((await stored(noConsent))['consentConfirmed'], isFalse, reason: 'Cancel changes nothing');
      await tap(tester, key('website-media-bulk'));
      await tester.tap(key('website-media-bulk-confirmConsent'));
      await tester.pumpAndSettle();
      await tap(tester, key('website-bulk-consent-confirm'));
      expect(text(tester, 'website-bulk-summary'), '1 done · 1 unchanged · 0 failed');
      await tap(tester, key('website-bulk-results-close'));
      expect((await stored(noConsent))['consentConfirmed'], isTrue);
      expect((await stored(noConsent))['status'], 'draft', reason: 'confirming consent publishes nothing');
    });

    testWidgets('bulk delete asks first and keeps images in use', (tester) async {
      final used = await legacy('m_used0001');
      final free = await legacy('m_free0001');
      await db.collection(WebsiteCollections.pageDrafts).doc('home').set({'mediaIds': [used]});
      await pump(tester);
      await tap(tester, key('website-media-select-all'));
      await tap(tester, key('website-media-bulk'));
      await tester.tap(key('website-media-bulk-delete'));
      await tester.pumpAndSettle();
      await tap(tester, key('website-bulk-delete-confirm-cancel'));
      expect((await media().get()).docs, hasLength(2));
      await tap(tester, key('website-media-bulk'));
      await tester.tap(key('website-media-bulk-delete'));
      await tester.pumpAndSettle();
      await tap(tester, key('website-bulk-delete-confirm'));
      expect(text(tester, 'website-bulk-summary'), '1 done · 0 unchanged · 1 failed');
      expect(find.descendant(of: key('website-bulk-result-$used'), matching: find.textContaining('Homepage hero')), findsOneWidget);
      await tap(tester, key('website-bulk-results-close'));
      expect(key('website-media-$free'), findsNothing);
      expect(key('website-media-$used'), findsOneWidget);
      expect(text(tester, 'website-media-selection-count'), '1 selected', reason: 'the deleted one leaves the selection');
    });

    testWidgets('albums: create, search, rename, delete (images kept); add and remove several; filter by album and “not in an album”', (tester) async {
      final ids = [await legacy('m_img00000'), await legacy('m_img00001'), await legacy('m_img00002')];
      await pump(tester);
      await tap(tester, key('website-albums-manage'));
      expect(key('website-albums-empty'), findsOneWidget);
      for (final (name, description) in [('Annual day', 'Stage'), ('Garden', 'Spring planting')]) {
        await tap(tester, key('website-albums-create'));
        await tap(tester, key('website-album-save'));
        expect(find.text('Enter a name for the album.'), findsOneWidget, reason: 'a name is required');
        await tester.enterText(key('website-album-name'), name);
        await tester.enterText(key('website-album-description'), description);
        await tap(tester, key('website-album-save'));
      }
      final albums = {for (final a in await service.albums.list(requesterRole: 'admin')) a.name: a};
      await tester.enterText(key('website-albums-search'), 'planting');
      await tester.pumpAndSettle();
      expect(key('website-album-${albums['Garden']!.id}'), findsOneWidget);
      expect(key('website-album-${albums['Annual day']!.id}'), findsNothing);
      await tester.enterText(key('website-albums-search'), '');
      await tester.pumpAndSettle();
      await tap(tester, key('website-album-${albums['Annual day']!.id}-edit'));
      await tester.enterText(key('website-album-name'), 'Annual day 2026');
      await tap(tester, key('website-album-save'));
      expect(find.text('Annual day 2026'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      // Two images into Annual day, all three into Garden, one out again.
      Future<void> toAlbum(String action, String albumId, List<String> select) async {
        if (text(tester, 'website-media-selection-count') != '0 selected') await tap(tester, key('website-media-clear-selection'));
        for (final id in select) {
          await tap(tester, key('website-media-$id-select'));
        }
        await tap(tester, key('website-media-bulk'));
        await tester.tap(key('website-media-bulk-$action'));
        await tester.pumpAndSettle();
        await tap(tester, key('website-album-pick-$albumId'));
        await tap(tester, key('website-bulk-results-close'));
      }

      final annual = albums['Annual day']!.id;
      final garden = albums['Garden']!.id;
      await toAlbum('add-album', annual, ids.take(2).toList());
      await toAlbum('add-album', garden, ids);
      await toAlbum('remove-album', garden, [ids[2]]);
      final saved = {for (final a in await service.albums.list(requesterRole: 'admin')) a.id: a.mediaIds.toSet()};
      expect(saved, {annual: {ids[0], ids[1]}, garden: {ids[0], ids[1]}});
      expect(key('website-media-${ids[0]}-album-$annual'), findsOneWidget, reason: 'shown on the image');

      // Filter.
      await tap(tester, key('website-media-album-filter'));
      await tester.tap(find.text('Not in an album (1)').last);
      await tester.pumpAndSettle();
      expect(key('website-media-${ids[2]}'), findsOneWidget);
      expect(key('website-media-${ids[0]}'), findsNothing);
      await tap(tester, key('website-media-album-filter'));
      await tester.tap(find.text('Annual day 2026 (2)').last);
      await tester.pumpAndSettle();
      expect(key('website-media-${ids[2]}'), findsNothing);
      expect(key('website-media-${ids[1]}'), findsOneWidget);
      await tap(tester, key('website-media-select-all'));
      expect(text(tester, 'website-media-selection-count'), '2 selected', reason: 'all shown, not all');

      // Delete an album: its images stay.
      await tap(tester, key('website-albums-manage'));
      await tap(tester, key('website-album-$annual-delete'));
      await tap(tester, key('website-album-delete-confirm'));
      expect(key('website-album-$annual'), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect((await media().get()).docs, hasLength(3));
      expect(find.text('All images (3)'), findsOneWidget, reason: 'the filter of a deleted album goes back to all');
    });

    testWidgets('existing images shown and edited as before; album errors don’t block the library; narrow screen fits', (tester) async {
      final id = await legacy('m_legacy01', alt: '');
      await pump(tester, size: const Size(360, 1600));
      expect(tester.takeException(), isNull);
      expect(key('website-media-$id'), findsOneWidget);
      expect(find.text('No alt text (optional)'), findsOneWidget);
      await tap(tester, key('website-media-$id-select'));
      await tap(tester, key('website-media-bulk'));
      await tester.tap(key('website-media-bulk-removeFromGallery'));
      await tester.pumpAndSettle();
      await tap(tester, key('website-bulk-results-close'));
      final data = await stored(id);
      expect(data['inGallery'], isFalse);
      expect(data['futureProperty'], {'kept': true});
      expect(data['storagePath'], 'website_media/m_legacy01/1_display.jpg');
      expect(tester.takeException(), isNull);
    });
  });
}

typedef CollectionRef = CollectionReference<Map<String, dynamic>>;
