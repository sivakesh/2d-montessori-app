// Website content administration (Settings -> Website):
// - Only Admin may list, upload, edit, publish, hide, reorder or delete
//   media, or save/publish pages (service-level check; Staff/Parent get the
//   locked screen).
// - Uploads are drafts with neutral Storage paths under website_media/{id}/
//   (no original file name, no uploader identity on the publicly readable
//   record; who did what goes to the admin-only audit subcollection), with
//   a display image and a thumbnail and long-lived cache headers.
// - Publishing needs English alt text and consent; withdrawing consent or
//   replacing the file takes an image off the site; an image a live page
//   shows can't be hidden or deleted.
// - Page drafts are never public; publishing copies only the visitor-facing
//   fields to the live page and needs a published image; unpublishing
//   returns the page to its built-in content.
// - Gallery order is saved and drives the public order.
// - Admin UI: publish an image, reorder the gallery, edit/preview/publish a
//   page, and the Settings hub links to it.
import 'dart:typed_data';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/admin/settings/ui/access_restricted_view.dart';
import 'package:montessori_app/modules/admin/settings/ui/admin_settings_screen.dart';
import 'package:montessori_app/modules/admin/website/data/website_content_admin_service.dart';
import 'package:montessori_app/modules/admin/website/data/website_image_processor.dart';
import 'package:montessori_app/modules/admin/website/ui/website_content_screen.dart';
import 'package:montessori_app/modules/auth/models/app_user.dart';
import 'package:montessori_app/modules/auth/providers/auth_provider.dart';
import 'package:montessori_app/modules/public_website/content/website_content_models.dart';
import 'package:montessori_app/modules/public_website/content/website_content_repository.dart';

class _FakeProcessor implements WebsiteImageProcessor {
  bool fail = false;

  @override
  Future<ProcessedWebsiteImage> process(Uint8List bytes, {required String contentType}) async {
    if (fail) throw StateError('undecodable');
    return ProcessedWebsiteImage(
      width: 2000,
      height: 1500,
      display: Uint8List.fromList([1, 2, 3, 4]),
      displayContentType: 'image/jpeg',
      thumb: Uint8List.fromList([5, 6]),
      thumbContentType: 'image/jpeg',
    );
  }
}

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

AppUser _user(String role) => AppUser(id: '9000000001', phone: '9000000001', role: role, isActive: true, name: 'Test $role');
final _admin = _user('admin');
PickedWebsiteImage _image([String name = 'Asha_and_Ravi_birthday.jpg']) => PickedWebsiteImage(name: name, bytes: Uint8List.fromList([9, 9, 9]));

void main() {
  late FakeFirebaseFirestore firestore;
  late MockFirebaseStorage storage;
  late _FakeProcessor processor;
  late WebsiteContentAdminService service;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    storage = MockFirebaseStorage();
    processor = _FakeProcessor();
    service = WebsiteContentAdminService(firestore: firestore, storage: storage, imageProcessor: processor);
  });

  Future<WebsiteMedia> upload({String alt = 'Children at work', bool consent = true, bool publish = false, bool inGallery = true}) async {
    final media = await service.uploadMedia(requesterRole: 'admin', actor: _admin, image: _image(), inGallery: inGallery);
    await service.updateMediaDetails(
      requesterRole: 'admin',
      actor: _admin,
      mediaId: media.id,
      alt: LocalizedText(en: alt),
      caption: const LocalizedText(),
      category: GalleryCategory.classroom,
      inGallery: inGallery,
      focalX: 0.5,
      focalY: 0.5,
      consentConfirmed: consent,
    );
    if (publish) await service.publishMedia(requesterRole: 'admin', actor: _admin, mediaId: media.id);
    return (await service.getMedia(requesterRole: 'admin', mediaId: media.id))!;
  }

  WebsiteContentRepository publicRepository() => WebsiteContentRepository(firestore: firestore);

  group('authorisation', () {
    for (final role in ['staff', 'parent', 'teacher', '']) {
      test('"$role" cannot read or change website content', () async {
        final existing = await upload(publish: true);
        final calls = <Future<void> Function()>[
          () => service.listMedia(requesterRole: role),
          () => service.getMedia(requesterRole: role, mediaId: existing.id),
          () => service.uploadMedia(requesterRole: role, actor: _user(role), image: _image()),
          () => service.replaceMediaImage(requesterRole: role, actor: _user(role), mediaId: existing.id, image: _image()),
          () => service.updateMediaDetails(
                requesterRole: role,
                actor: _user(role),
                mediaId: existing.id,
                alt: const LocalizedText(en: 'x'),
                caption: const LocalizedText(),
                category: GalleryCategory.general,
                inGallery: true,
                focalX: 0.5,
                focalY: 0.5,
                consentConfirmed: true,
              ),
          () => service.publishMedia(requesterRole: role, actor: _user(role), mediaId: existing.id),
          () => service.hideMedia(requesterRole: role, actor: _user(role), mediaId: existing.id),
          () => service.deleteMedia(requesterRole: role, actor: _user(role), mediaId: existing.id),
          () => service.reorderGallery(requesterRole: role, actor: _user(role), orderedIds: [existing.id]),
          () => service.getDraft(requesterRole: role, slot: WebsitePageSlot.home),
          () => service.saveDraft(requesterRole: role, actor: _user(role), content: const WebsitePageContent(slot: WebsitePageSlot.home)),
          () => service.publishPage(requesterRole: role, actor: _user(role), content: const WebsitePageContent(slot: WebsitePageSlot.home)),
          () => service.unpublishPage(requesterRole: role, actor: _user(role), slot: WebsitePageSlot.home),
        ];
        for (final call in calls) {
          await expectLater(call(), throwsA(isA<UnauthorizedWebsiteContentException>()));
        }
        final media = await publicRepository().publishedMedia();
        expect(media.single.id, existing.id, reason: 'nothing changed');
        expect(await firestore.collection(WebsiteCollections.livePages).get().then((s) => s.docs), isEmpty);
      });
    }

    test('role check is case-insensitive for Admin', () async {
      expect(await service.listMedia(requesterRole: 'Admin'), isEmpty);
    });
  });

  group('upload', () {
    test('creates a private draft with neutral paths, both sizes, cache headers and an audit entry', () async {
      final media = await service.uploadMedia(requesterRole: 'admin', actor: _admin, image: _image());
      expect(media.status, WebsiteMediaStatus.draft);
      expect(media.consentConfirmed, isFalse);
      expect(media.width, 2000);
      expect(media.height, 1500);
      expect(media.storagePath, startsWith('website_media/${media.id}/'));
      expect(media.storagePath, endsWith('_display.jpg'));
      expect(media.thumbStoragePath, endsWith('_thumb.jpg'));
      expect(media.storagePath, isNot(contains('Asha')), reason: 'original file name may identify a child');
      expect(storage.storedDataMap.containsKey(media.storagePath), isTrue);
      expect(storage.storedDataMap.containsKey(media.thumbStoragePath), isTrue);
      expect(storage.storedSettableMetadataMap[media.storagePath]?['cacheControl'], contains('max-age=31536000'));
      expect(media.url, isNotEmpty);
      expect(media.thumbUrl, isNotEmpty);

      final raw = (await firestore.collection(WebsiteCollections.media).doc(media.id).get()).data()!;
      for (final field in ['fileName', 'updatedBy', 'updatedByName', 'uploadedBy', 'createdBy']) {
        expect(raw.containsKey(field), isFalse, reason: 'the public record must not hold $field');
      }
      expect(raw.values.whereType<String>().any((v) => v.contains('Asha') || v.contains(_admin.phone)), isFalse);

      final audit = await firestore.collection(WebsiteCollections.media).doc(media.id).collection('audit').get();
      expect(audit.docs.single.data()['action'], 'uploaded');
      expect(audit.docs.single.data()['byName'], 'Test admin');

      expect(await publicRepository().publishedMedia(), isEmpty, reason: 'drafts are not public');
    });

    test('new uploads go last in the gallery order', () async {
      final a = await service.uploadMedia(requesterRole: 'admin', actor: _admin, image: _image());
      final b = await service.uploadMedia(requesterRole: 'admin', actor: _admin, image: _image());
      expect(b.galleryOrder, greaterThan(a.galleryOrder));
    });

    test('rejects unsupported, empty and oversized files, and unreadable images', () async {
      expect(() => WebsiteContentAdminService.validateImageFile('notes.pdf', 10), throwsA(isA<WebsiteContentException>()));
      expect(() => WebsiteContentAdminService.validateImageFile('photo.gif', 10), throwsA(isA<WebsiteContentException>()));
      expect(() => WebsiteContentAdminService.validateImageFile('photo.jpg', 0), throwsA(isA<WebsiteContentException>()));
      expect(() => WebsiteContentAdminService.validateImageFile('photo.JPG', WebsiteContentAdminService.maxUploadBytes + 1), throwsA(isA<WebsiteContentException>()));
      WebsiteContentAdminService.validateImageFile('photo.WebP', 1000);

      processor.fail = true;
      await expectLater(service.uploadMedia(requesterRole: 'admin', actor: _admin, image: _image()), throwsA(isA<WebsiteContentException>()));
      expect(storage.storedDataMap.keys.where((k) => k.startsWith('website_media')), isEmpty);
      expect((await firestore.collection(WebsiteCollections.media).get()).docs, isEmpty);
    });

    test('the picker returns the chosen image and validates it', () async {
      final bytes = Uint8List.fromList([1, 2, 3]);
      final picking = WebsiteContentAdminService(
        firestore: firestore,
        storage: storage,
        imageProcessor: processor,
        filePicker: _StubFilePicker(FilePickerResult([PlatformFile(name: 'garden.png', size: 3, bytes: bytes)])),
      );
      expect((await picking.pickImage())?.name, 'garden.png');
      final cancelled = WebsiteContentAdminService(firestore: firestore, storage: storage, imageProcessor: processor, filePicker: _StubFilePicker(null));
      expect(await cancelled.pickImage(), isNull);
      final wrong = WebsiteContentAdminService(
        firestore: firestore,
        storage: storage,
        imageProcessor: processor,
        filePicker: _StubFilePicker(FilePickerResult([PlatformFile(name: 'doc.pdf', size: 3, bytes: bytes)])),
      );
      await expectLater(wrong.pickImage(), throwsA(isA<WebsiteContentException>()));
    });
  });

  group('publish, hide, consent', () {
    test('publishing needs English alt text and consent', () async {
      final noAlt = await upload(alt: '');
      await expectLater(service.publishMedia(requesterRole: 'admin', actor: _admin, mediaId: noAlt.id), throwsA(isA<WebsiteContentException>()));
      final noConsent = await upload(consent: false);
      await expectLater(service.publishMedia(requesterRole: 'admin', actor: _admin, mediaId: noConsent.id), throwsA(isA<WebsiteContentException>()));
      expect(await publicRepository().publishedMedia(), isEmpty);

      final ok = await upload(publish: true);
      expect(ok.status, WebsiteMediaStatus.published);
      expect((await publicRepository().publishedMedia()).map((m) => m.id), [ok.id]);
    });

    test('hiding takes an image off the website; it can be published again', () async {
      final media = await upload(publish: true);
      await service.hideMedia(requesterRole: 'admin', actor: _admin, mediaId: media.id);
      expect(await publicRepository().publishedMedia(), isEmpty);
      expect((await service.getMedia(requesterRole: 'admin', mediaId: media.id))!.status, WebsiteMediaStatus.hidden);
      await service.publishMedia(requesterRole: 'admin', actor: _admin, mediaId: media.id);
      expect(await publicRepository().publishedMedia(), hasLength(1));
    });

    test('withdrawing consent on a published image hides it', () async {
      final media = await upload(publish: true);
      await service.updateMediaDetails(
        requesterRole: 'admin',
        actor: _admin,
        mediaId: media.id,
        alt: media.alt,
        caption: media.caption,
        category: media.category,
        inGallery: true,
        focalX: 0.2,
        focalY: 0.8,
        consentConfirmed: false,
      );
      final updated = (await service.getMedia(requesterRole: 'admin', mediaId: media.id))!;
      expect(updated.status, WebsiteMediaStatus.hidden);
      expect(updated.focalX, 0.2);
      expect(await publicRepository().publishedMedia(), isEmpty);
    });

    test('a published image keeps English alt text', () async {
      final media = await upload(publish: true);
      await expectLater(
        service.updateMediaDetails(
          requesterRole: 'admin',
          actor: _admin,
          mediaId: media.id,
          alt: const LocalizedText(),
          caption: const LocalizedText(),
          category: GalleryCategory.general,
          inGallery: true,
          focalX: 0.5,
          focalY: 0.5,
          consentConfirmed: true,
        ),
        throwsA(isA<WebsiteContentException>()),
      );
    });

    test('replacing the file keeps the id, needs fresh consent, unpublishes and removes the old files', () async {
      final media = await upload(publish: true);
      final replaced = await service.replaceMediaImage(requesterRole: 'admin', actor: _admin, mediaId: media.id, image: _image('new.png'));
      expect(replaced.id, media.id);
      expect(replaced.status, WebsiteMediaStatus.draft);
      expect(replaced.consentConfirmed, isFalse);
      expect(replaced.storagePath, isNot(media.storagePath));
      expect(storage.storedDataMap.containsKey(media.storagePath), isFalse);
      expect(storage.storedDataMap.containsKey(media.thumbStoragePath), isFalse);
      expect(storage.storedDataMap.containsKey(replaced.storagePath), isTrue);
      expect(await publicRepository().publishedMedia(), isEmpty);
    });

    test('an image shown by a live page cannot be hidden or deleted; a draft-only use blocks delete', () async {
      final media = await upload(publish: true);
      await service.publishPage(requesterRole: 'admin', actor: _admin, content: WebsitePageContent(slot: WebsitePageSlot.admissions, imageMediaId: media.id));
      await expectLater(service.hideMedia(requesterRole: 'admin', actor: _admin, mediaId: media.id), throwsA(isA<WebsiteContentException>()));
      await expectLater(service.deleteMedia(requesterRole: 'admin', actor: _admin, mediaId: media.id), throwsA(isA<WebsiteContentException>()));
      expect(await publicRepository().publishedMedia(), hasLength(1));

      await service.unpublishPage(requesterRole: 'admin', actor: _admin, slot: WebsitePageSlot.admissions);
      await service.hideMedia(requesterRole: 'admin', actor: _admin, mediaId: media.id);
      await expectLater(service.deleteMedia(requesterRole: 'admin', actor: _admin, mediaId: media.id), throwsA(isA<WebsiteContentException>()), reason: 'the draft still uses it');

      await service.saveDraft(requesterRole: 'admin', actor: _admin, content: const WebsitePageContent(slot: WebsitePageSlot.admissions));
      await service.deleteMedia(requesterRole: 'admin', actor: _admin, mediaId: media.id);
      expect(await service.getMedia(requesterRole: 'admin', mediaId: media.id), isNull);
      expect(storage.storedDataMap.containsKey(media.storagePath), isFalse);
      expect((await firestore.collection(WebsiteCollections.media).doc(media.id).collection('audit').get()).docs, isEmpty);
    });
  });

  test('gallery order is saved and drives the public order', () async {
    final a = await upload(publish: true);
    final b = await upload(publish: true);
    final c = await upload(publish: true);
    await service.reorderGallery(requesterRole: 'admin', actor: _admin, orderedIds: [c.id, a.id, b.id]);
    expect((await publicRepository().publishedMedia()).map((m) => m.id), [c.id, a.id, b.id]);
  });

  group('pages', () {
    test('drafts stay private; publishing copies only visitor-facing fields; unpublishing restores built-in content', () async {
      final media = await upload(publish: true, inGallery: false);
      final content = WebsitePageContent(
        slot: WebsitePageSlot.home,
        imageMediaId: media.id,
        headline: const LocalizedText(en: 'Welcome', ta: 'வரவேற்பு'),
        intro: const LocalizedText(en: 'Intro'),
      );
      await service.saveDraft(requesterRole: 'admin', actor: _admin, content: content);
      expect(await publicRepository().livePages(), isEmpty, reason: 'a saved draft is not public');
      expect((await service.getDraft(requesterRole: 'admin', slot: WebsitePageSlot.home)).sameContentAs(content), isTrue);

      await service.publishPage(requesterRole: 'admin', actor: _admin, content: content);
      final live = await publicRepository().livePages();
      expect(live[WebsitePageSlot.home]!.sameContentAs(content), isTrue);
      final raw = (await firestore.collection(WebsiteCollections.livePages).doc('home').get()).data()!;
      expect(raw.keys.toSet(), {'slot', 'imageMediaId', 'mediaIds', 'headline', 'intro', 'publishedAt'});
      expect(raw['mediaIds'], [media.id]);

      // A later draft edit doesn't change what visitors see.
      await service.saveDraft(requesterRole: 'admin', actor: _admin, content: content.copyWith(headline: const LocalizedText(en: 'Changed')));
      expect((await publicRepository().livePages())[WebsitePageSlot.home]!.headline.en, 'Welcome');

      await service.unpublishPage(requesterRole: 'admin', actor: _admin, slot: WebsitePageSlot.home);
      expect(await publicRepository().livePages(), isEmpty);
      expect((await service.getDraft(requesterRole: 'admin', slot: WebsitePageSlot.home)).headline.en, 'Changed', reason: 'draft kept');
    });

    test('a page can only be published with a published image', () async {
      final draftImage = await upload();
      await expectLater(
        service.publishPage(requesterRole: 'admin', actor: _admin, content: WebsitePageContent(slot: WebsitePageSlot.programs, imageMediaId: draftImage.id)),
        throwsA(isA<WebsiteContentException>()),
      );
      expect(await publicRepository().livePages(), isEmpty);
      await service.publishPage(requesterRole: 'admin', actor: _admin, content: const WebsitePageContent(slot: WebsitePageSlot.programs));
      expect((await publicRepository().livePages()).keys, [WebsitePageSlot.programs]);
    });

    test('text limits, and Tamil text needs its English counterpart', () async {
      await expectLater(
        service.saveDraft(requesterRole: 'admin', actor: _admin, content: WebsitePageContent(slot: WebsitePageSlot.home, headline: LocalizedText(en: 'x' * 121))),
        throwsA(isA<WebsiteContentException>()),
      );
      await expectLater(
        service.saveDraft(requesterRole: 'admin', actor: _admin, content: const WebsitePageContent(slot: WebsitePageSlot.home, intro: LocalizedText(ta: 'தமிழ் மட்டும்'))),
        throwsA(isA<WebsiteContentException>()),
      );
    });
  });

  group('admin UI', () {
    Future<void> pumpScreen(WidgetTester tester, String role, Widget child, {Size size = const Size(1200, 1000)}) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(ProviderScope(
        overrides: [currentUserProvider.overrideWith((ref) => _user(role))],
        child: MaterialApp(home: child),
      ));
      await tester.pumpAndSettle();
    }

    Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
      // A previous action's SnackBar can sit over the bottom buttons.
      for (final messenger in tester.stateList<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))) {
        messenger.removeCurrentSnackBar();
      }
      await tester.pumpAndSettle();
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    for (final role in ['staff', 'parent']) {
      testWidgets('$role sees the locked view', (tester) async {
        await upload(publish: true);
        await pumpScreen(tester, role, WebsiteContentScreen(service: service));
        expect(find.byType(AccessRestrictedView), findsOneWidget);
        expect(find.byKey(const Key('website-upload')), findsNothing);
      });
    }

    testWidgets('admin: open an image, add alt text and consent, publish', (tester) async {
      final media = await service.uploadMedia(requesterRole: 'admin', actor: _admin, image: _image());
      await pumpScreen(tester, 'admin', WebsiteContentScreen(service: service));
      expect(find.byKey(Key('website-media-${media.id}')), findsOneWidget);
      expect(find.text('Draft'), findsOneWidget);

      await tapAndSettle(tester, find.byKey(Key('website-media-${media.id}')));
      expect(find.byKey(const Key('website-media-crops')), findsOneWidget);
      await tapAndSettle(tester, find.byKey(const Key('website-media-publish')));
      expect(find.textContaining('alt text'), findsWidgets, reason: 'refused without alt text');
      expect((await service.getMedia(requesterRole: 'admin', mediaId: media.id))!.status, WebsiteMediaStatus.draft);

      await tester.enterText(find.byKey(const Key('website-media-alt-en')), 'Children watering plants');
      await tester.enterText(find.byKey(const Key('website-media-caption-en')), 'Garden time');
      await tapAndSettle(tester, find.byKey(const Key('website-media-consent')));
      await tapAndSettle(tester, find.byKey(const Key('website-media-publish')));
      final saved = (await service.getMedia(requesterRole: 'admin', mediaId: media.id))!;
      expect(saved.status, WebsiteMediaStatus.published);
      expect(saved.alt.en, 'Children watering plants');
      expect(saved.caption.en, 'Garden time');
      expect(find.byKey(const Key('website-media-hide')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('admin: move a gallery image down', (tester) async {
      final a = await upload(publish: true);
      final b = await upload(publish: true);
      await pumpScreen(tester, 'admin', WebsiteContentScreen(service: service));
      await tapAndSettle(tester, find.byKey(const Key('website-tab-gallery')));
      await tapAndSettle(tester, find.byKey(Key('website-gallery-down-${a.id}')));
      expect((await publicRepository().publishedMedia()).map((m) => m.id), [b.id, a.id]);
    });

    testWidgets('admin: edit the homepage, preview it, publish', (tester) async {
      final media = await upload(publish: true, inGallery: false);
      await pumpScreen(tester, 'admin', WebsiteContentScreen(service: service));
      await tapAndSettle(tester, find.byKey(const Key('website-tab-pages')));
      await tapAndSettle(tester, find.byKey(const Key('website-page-home')));

      expect(tester.widget<Text>(find.byKey(const Key('website-preview-title'))).data, 'A calm, thoughtful place to learn and grow', reason: 'built-in text by default');
      await tester.enterText(find.byKey(const Key('website-page-headline-en')), 'Welcome to our school');
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('website-preview-title'))).data, 'Welcome to our school', reason: 'live preview');

      await tapAndSettle(tester, find.byKey(const Key('website-page-choose-image')));
      await tapAndSettle(tester, find.byKey(Key('website-choose-${media.id}')));
      await tapAndSettle(tester, find.byKey(const Key('website-page-save-draft')));
      expect(await publicRepository().livePages(), isEmpty, reason: 'draft only');

      await tapAndSettle(tester, find.byKey(const Key('website-page-publish')));
      final live = (await publicRepository().livePages())[WebsitePageSlot.home]!;
      expect(live.headline.en, 'Welcome to our school');
      expect(live.imageMediaId, media.id);
      expect(find.byKey(const Key('website-page-unpublish')), findsOneWidget);

      await tapAndSettle(tester, find.byKey(const Key('website-page-unpublish')));
      expect(await publicRepository().livePages(), isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('mobile width: the screens fit', (tester) async {
      await upload(publish: true);
      await pumpScreen(tester, 'admin', WebsiteContentScreen(service: service), size: const Size(360, 740));
      expect(tester.takeException(), isNull);
      await tapAndSettle(tester, find.byKey(const Key('website-tab-gallery')));
      expect(tester.takeException(), isNull);
      await tapAndSettle(tester, find.byKey(const Key('website-tab-pages')));
      await tapAndSettle(tester, find.byKey(const Key('website-page-admissions')));
      expect(tester.takeException(), isNull);
    });

    testWidgets('Settings hub links admins to Website content', (tester) async {
      await pumpScreen(tester, 'admin', AdminSettingsScreen(websiteService: service));
      await tapAndSettle(tester, find.byKey(const Key('settings-website')));
      expect(find.byType(WebsiteContentScreen), findsOneWidget);
      expect(find.byKey(const Key('website-upload')), findsOneWidget);
    });
  });
}
