// Website page editing and additional pages (Settings -> Website -> Pages):
// Part A — built-in pages' editor:
// - With nothing saved, the heading/introduction fields hold the exact
//   built-in English and Tamil copy; saved/published text loads as is.
// - The editor says whether it is showing built-in content, a draft or the
//   published content; the preview shows the version being edited or the
//   live one, in English or Tamil, and follows edits.
// - Saving a draft never changes the live site; text left as built-in is
//   stored blank ("use built-in"); Reset to built-in content restores the
//   built-in copy (and removes the image) in the editor only.
// Part B — additional pages at /pages/<slug>:
// - Admin-only create/edit/publish/unpublish/archive/restore and
//   navigation order; slug format and uniqueness (archived slugs stay
//   reserved); safe link targets; images must be published.
// - Published pages render without login (sections, English/Tamil);
//   drafts, unpublished, archived, unknown and malformed slugs get "page
//   not found"; only visitor-facing fields are public.
// - Navigation lists published pages the admin chose, in their order,
//   before Contact; built-in routes are unchanged.
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/main.dart';
import 'package:montessori_app/modules/admin/website/data/website_content_admin_service.dart';
import 'package:montessori_app/modules/admin/website/data/website_image_processor.dart';
import 'package:montessori_app/modules/admin/website/ui/website_content_editors.dart';
import 'package:montessori_app/modules/admin/website/ui/website_content_screen.dart';
import 'package:montessori_app/modules/admin/website/ui/website_custom_page_editor.dart';
import 'package:montessori_app/modules/auth/models/app_user.dart';
import 'package:montessori_app/modules/auth/providers/auth_provider.dart';
import 'package:montessori_app/modules/auth/providers/auth_state_provider.dart';
import 'package:montessori_app/modules/public_website/content/blocks/website_block.dart';
import 'package:montessori_app/modules/public_website/content/website_content_models.dart';
import 'package:montessori_app/modules/public_website/content/website_content_repository.dart';
import 'package:montessori_app/modules/public_website/content/website_custom_page.dart';
import 'package:montessori_app/modules/public_website/public_routes.dart';
import 'package:montessori_app/modules/public_website/public_strings.dart';
import 'package:montessori_app/modules/public_website/ui/public_custom_page.dart';
import 'package:montessori_app/modules/public_website/ui/public_home_page.dart';
import 'package:montessori_app/modules/public_website/ui/public_section_page.dart';

class _FakeProcessor implements WebsiteImageProcessor {
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

AppUser _user(String role) => AppUser(id: '9000000002', phone: '9000000002', role: role, isActive: true, name: 'Test $role');
final _admin = _user('admin');

final _en = PublicStrings.of(PublicLanguage.english);

void main() {
  late FakeFirebaseFirestore firestore;
  late MockFirebaseStorage storage;
  late WebsiteContentAdminService service;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    storage = MockFirebaseStorage();
    service = WebsiteContentAdminService(firestore: firestore, storage: storage, imageProcessor: _FakeProcessor());
  });

  WebsiteContentRepository publicRepository() => WebsiteContentRepository(firestore: firestore);

  Future<WebsiteMedia> publishedImage({String alt = 'Children reading'}) async {
    final media = await service.uploadMedia(requesterRole: 'admin', actor: _admin, image: PickedWebsiteImage(name: 'a.jpg', bytes: Uint8List.fromList([1])));
    await service.updateMediaDetails(
      requesterRole: 'admin',
      actor: _admin,
      mediaId: media.id,
      alt: LocalizedText(en: alt),
      caption: const LocalizedText(en: 'Reading corner'),
      category: GalleryCategory.classroom,
      inGallery: false,
      focalX: 0.5,
      focalY: 0.5,
      consentConfirmed: true,
    );
    await service.publishMedia(requesterRole: 'admin', actor: _admin, mediaId: media.id);
    return (await service.getMedia(requesterRole: 'admin', mediaId: media.id))!;
  }

  /// A page made of sections, as pages were before the page builder: new
  /// pages are built with blocks, so its draft's blocks are removed.
  Future<CustomPage> createPage(String slug, {String title = 'Open Day', String titleTa = ''}) async {
    final created = await service.createCustomPage(requesterRole: 'admin', actor: _admin, title: LocalizedText(en: title, ta: titleTa), slug: slug);
    await firestore.collection(WebsiteCollections.pageDrafts).doc(created.id).update({'schemaVersion': FieldValue.delete(), 'blocks': FieldValue.delete()});
    return created.copyWith(blocks: () => null);
  }

  Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
    for (final messenger in tester.stateList<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))) {
      messenger.removeCurrentSnackBar();
    }
    await tester.pumpAndSettle();
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  String fieldText(WidgetTester tester, String key) => tester.widget<TextField>(find.byKey(Key(key))).controller!.text;
  String? text(WidgetTester tester, String key) => tester.widget<Text>(find.byKey(Key(key))).data;

  Future<void> pumpAdmin(WidgetTester tester, Widget child, {String role = 'admin', Size size = const Size(1200, 1000)}) async {
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

  Future<void> pumpSite(WidgetTester tester, {String? route, Size size = const Size(1400, 1000)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authStateProvider.overrideWith((ref) => Stream.value(null)),
        websiteContentRepositoryProvider.overrideWithValue(publicRepository()),
      ],
      child: const MontessoriApp(),
    ));
    await tester.pumpAndSettle();
    if (route != null) {
      tester.state<NavigatorState>(find.byType(Navigator).first).pushNamed(route);
      await tester.pumpAndSettle();
    }
  }

  // ------------------------------------------------------------ Part A

  group('built-in page editor', () {
    testWidgets('nothing saved: fields hold the exact built-in English copy; no Tamil fields', (tester) async {
      await pumpAdmin(tester, WebsitePageEditorScreen(service: service, user: _admin, slot: WebsitePageSlot.home));
      expect(fieldText(tester, 'website-page-headline-en'), _en.heroTitle);
      expect(fieldText(tester, 'website-page-intro-en'), _en.heroBody);
      expect(find.byKey(const Key('website-page-headline-ta')), findsNothing, reason: 'English only');
      expect(find.byKey(const Key('website-page-intro-ta')), findsNothing);
      expect(find.byKey(const Key('website-preview-ta')), findsNothing, reason: 'no preview-language switch');
      expect(text(tester, 'website-edit-source-text'), contains('built-in content'));
      expect(find.text('Built-in text'), findsNWidgets(2));
      expect(text(tester, 'website-preview-title'), _en.heroTitle);
      expect(find.byKey(const Key('website-page-unsaved')), findsNothing);
    });

    for (final (slot, route) in [
      (WebsitePageSlot.admissions, PublicRoutes.admissions),
      (WebsitePageSlot.teacherTraining, PublicRoutes.teacherTraining),
      (WebsitePageSlot.programs, PublicRoutes.programs),
    ]) {
      testWidgets('${slot.adminLabel}: built-in title and introduction prefilled in English', (tester) async {
        await pumpAdmin(tester, WebsitePageEditorScreen(service: service, user: _admin, slot: slot));
        expect(fieldText(tester, 'website-page-headline-en'), _en.labelFor(route));
        expect(fieldText(tester, 'website-page-intro-en'), _en.introFor(route));
        expect(find.byKey(const Key('website-page-headline-ta')), findsNothing);
      });
    }

    testWidgets('published content loads as published; its stored Tamil is kept when English is edited', (tester) async {
      await service.publishPage(
        requesterRole: 'admin',
        actor: _admin,
        content: const WebsitePageContent(slot: WebsitePageSlot.home, headline: LocalizedText(en: 'Welcome families'), intro: LocalizedText(en: 'A new introduction', ta: 'புதிய அறிமுகம்')),
      );
      await pumpAdmin(tester, WebsitePageEditorScreen(service: service, user: _admin, slot: WebsitePageSlot.home));
      expect(fieldText(tester, 'website-page-headline-en'), 'Welcome families');
      expect(find.byKey(const Key('website-page-intro-ta')), findsNothing);
      expect(text(tester, 'website-edit-source-text'), contains('published content'));
      await tester.enterText(find.byKey(const Key('website-page-headline-en')), 'Welcome, families');
      await tester.pumpAndSettle();
      await tapAndSettle(tester, find.byKey(const Key('website-page-save-draft')));
      final saved = (await service.getSavedDraft(requesterRole: 'admin', slot: WebsitePageSlot.home))!;
      expect(saved.headline.en, 'Welcome, families');
      expect(saved.intro.ta, 'புதிய அறிமுகம்', reason: 'Tamil already stored is kept, not cleared');
      expect(saved.headline.ta, '', reason: 'saved blank Tamil is not replaced by built-in Tamil');
    });

    testWidgets('draft vs published: the editor loads the draft; the preview switches between it and the live version', (tester) async {
      await service.publishPage(requesterRole: 'admin', actor: _admin, content: const WebsitePageContent(slot: WebsitePageSlot.programs, headline: LocalizedText(en: 'Live heading')));
      await service.saveDraft(requesterRole: 'admin', actor: _admin, content: const WebsitePageContent(slot: WebsitePageSlot.programs, headline: LocalizedText(en: 'Draft heading')));
      await pumpAdmin(tester, WebsitePageEditorScreen(service: service, user: _admin, slot: WebsitePageSlot.programs));

      expect(fieldText(tester, 'website-page-headline-en'), 'Draft heading');
      expect(text(tester, 'website-edit-source-text'), contains('unpublished changes'));
      expect(text(tester, 'website-preview-title'), 'Draft heading');

      await tapAndSettle(tester, find.byKey(const Key('website-preview-live')));
      expect(text(tester, 'website-preview-title'), 'Live heading');
      expect(text(tester, 'website-preview-intro'), _en.introFor(PublicRoutes.programs), reason: 'blank live intro = built-in');

      await tapAndSettle(tester, find.byKey(const Key('website-preview-editing')));
      await tester.enterText(find.byKey(const Key('website-page-headline-en')), 'Edited now');
      await tester.pumpAndSettle();
      expect(text(tester, 'website-preview-title'), 'Edited now', reason: 'preview follows edits');
      expect(find.byKey(const Key('website-page-unsaved')), findsOneWidget);

      expect(find.byKey(const Key('website-preview-ta')), findsNothing, reason: 'English-only preview');

      await tapAndSettle(tester, find.byKey(const Key('website-page-save-draft')));
      expect((await publicRepository().livePages())[WebsitePageSlot.programs]!.headline.en, 'Live heading', reason: 'saving a draft leaves the live site alone');
      expect((await service.getSavedDraft(requesterRole: 'admin', slot: WebsitePageSlot.programs))!.headline.en, 'Edited now');
    });

    testWidgets('Reset to built-in content: editor only until published; then the site shows built-in text again', (tester) async {
      final image = await publishedImage();
      await service.publishPage(
        requesterRole: 'admin',
        actor: _admin,
        content: WebsitePageContent(slot: WebsitePageSlot.admissions, imageMediaId: image.id, headline: const LocalizedText(en: 'Join us'), intro: const LocalizedText(en: 'Custom intro')),
      );
      await pumpAdmin(tester, WebsitePageEditorScreen(service: service, user: _admin, slot: WebsitePageSlot.admissions));
      expect(fieldText(tester, 'website-page-headline-en'), 'Join us');

      await tapAndSettle(tester, find.byKey(const Key('website-page-reset')));
      await tapAndSettle(tester, find.byKey(const Key('website-page-reset-confirm')));
      expect(fieldText(tester, 'website-page-headline-en'), _en.admissions);
      expect(fieldText(tester, 'website-page-intro-en'), _en.introFor(PublicRoutes.admissions));
      expect(find.byKey(const Key('website-page-remove-image')), findsNothing, reason: 'image removed');
      expect((await publicRepository().livePages())[WebsitePageSlot.admissions]!.headline.en, 'Join us', reason: 'nothing published yet');

      await tapAndSettle(tester, find.byKey(const Key('website-page-publish')));
      // Content is already published: publishing over it is confirmed.
      await tapAndSettle(tester, find.byKey(const Key('website-page-publish-confirm')));
      final live = (await publicRepository().livePages())[WebsitePageSlot.admissions]!;
      expect(live.headline.isEmpty, isTrue, reason: 'stored as "use built-in"');
      expect(live.intro.isEmpty, isTrue);
      expect(live.imageMediaId, isNull);
      expect(find.byKey(const Key('website-page-reset')), findsOneWidget);
      expect(tester.widget<TextButton>(find.byKey(const Key('website-page-reset'))).onPressed, isNull, reason: 'already built-in');
    });

    test('text left exactly as built-in is stored blank; an edit in either language is kept', () async {
      final slot = WebsitePageSlot.home;
      await service.saveDraft(requesterRole: 'admin', actor: _admin, content: WebsitePageContent(slot: slot, headline: slot.builtInHeadline, intro: slot.builtInIntro));
      final saved = (await service.getSavedDraft(requesterRole: 'admin', slot: slot))!;
      expect(saved.headline.isEmpty && saved.intro.isEmpty, isTrue);

      await service.saveDraft(requesterRole: 'admin', actor: _admin, content: WebsitePageContent(slot: slot, headline: LocalizedText(en: slot.builtInHeadline.en, ta: 'புதிய தலைப்பு')));
      final edited = (await service.getSavedDraft(requesterRole: 'admin', slot: slot))!;
      expect(edited.headline.en, slot.builtInHeadline.en);
      expect(edited.headline.ta, 'புதிய தலைப்பு');
    });
  });

  // ------------------------------------------------------------ Part B

  group('additional pages: service', () {
    test('only Admin can create, read or change additional pages', () async {
      final page = await createPage('open-day');
      for (final role in ['staff', 'parent', '']) {
        final calls = <Future<void> Function()>[
          () => service.listCustomPages(requesterRole: role),
          () => service.getCustomPage(requesterRole: role, pageId: page.id),
          () => service.createCustomPage(requesterRole: role, actor: _user(role), title: const LocalizedText(en: 'X'), slug: 'x-page'),
          () => service.saveCustomPageDraft(requesterRole: role, actor: _user(role), page: page),
          () => service.publishCustomPage(requesterRole: role, actor: _user(role), page: page),
          () => service.unpublishCustomPage(requesterRole: role, actor: _user(role), pageId: page.id),
          () => service.archiveCustomPage(requesterRole: role, actor: _user(role), pageId: page.id),
          () => service.restoreCustomPage(requesterRole: role, actor: _user(role), pageId: page.id),
          () => service.reorderCustomPages(requesterRole: role, actor: _user(role), orderedIds: [page.id]),
        ];
        for (final call in calls) {
          await expectLater(call(), throwsA(isA<UnauthorizedWebsiteContentException>()), reason: role);
        }
      }
      expect(await publicRepository().liveCustomPages(), isEmpty);
    });

    test('slug format and uniqueness (archived pages keep theirs)', () async {
      for (final bad in ['', 'a', 'Open-Day', 'open day', 'open--day', '-open', 'open-', '../app', 'open/day', 'x' * 61]) {
        await expectLater(createPage(bad), throwsA(isA<WebsiteContentException>()), reason: '"$bad"');
      }
      final first = await createPage('open-day');
      await expectLater(createPage('open-day', title: 'Another'), throwsA(isA<WebsiteContentException>()));
      await service.archiveCustomPage(requesterRole: 'admin', actor: _admin, pageId: first.id);
      await expectLater(createPage('open-day', title: 'Another'), throwsA(isA<WebsiteContentException>()), reason: 'archived slug stays reserved');

      final second = await createPage('sports-day');
      await expectLater(
        service.saveCustomPageDraft(requesterRole: 'admin', actor: _admin, page: second.copyWith(slug: 'open-day')),
        throwsA(isA<WebsiteContentException>()),
        reason: 'renaming onto a used slug',
      );
      await service.saveCustomPageDraft(requesterRole: 'admin', actor: _admin, page: second.copyWith(slug: 'sports-day-2026'));
      expect((await service.getCustomPage(requesterRole: 'admin', pageId: second.id))!.draft.slug, 'sports-day-2026');
      expect(CustomPage.slugify('Open Day 2026!'), 'open-day-2026');
      expect(await createPage('needs-title', title: '  ').then((_) => 'created', onError: (_) => 'refused'), 'refused');
    });

    test('safe link targets and route parsing', () {
      for (final ok in ['/', '/admissions', '/gallery', '/pages/open-day', 'https://example.org/form', 'mailto:office@example.org', 'tel:+911234567890']) {
        expect(SafeLinkTarget.validate(ok), isNull, reason: ok);
      }
      for (final bad in ['', 'javascript:alert(1)', 'http://example.org', '/app', '/admin_dashboard', '/pages/Bad Slug', 'https://', 'ftp://x', 'data:text/html,x']) {
        expect(SafeLinkTarget.validate(bad), isNotNull, reason: bad);
      }
      expect(PublicRoutes.slugFromRoute('/pages/open-day'), 'open-day');
      expect(PublicRoutes.slugFromRoute('/pages/open-day/'), 'open-day');
      expect(PublicRoutes.slugFromRoute('/pages/Open-Day?x=1'), 'open-day');
      expect(PublicRoutes.slugFromRoute('/pages/a/b'), isNull);
      expect(PublicRoutes.slugFromRoute('/pages/'), isNull);
      expect(PublicRoutes.slugFromRoute('/admissions'), isNull);
    });

    test('drafts are private; publishing exposes only visitor-facing fields; images must be published', () async {
      final page = await createPage('open-day', titleTa: 'திறந்த நாள்');
      expect(await publicRepository().liveCustomPages(), isEmpty, reason: 'a new page is a draft');

      final media = await service.uploadMedia(requesterRole: 'admin', actor: _admin, image: PickedWebsiteImage(name: 'b.jpg', bytes: Uint8List.fromList([1])));
      final withDraftImage = page.copyWith(sections: [
        const CustomPageSection(id: 's1', type: CustomSectionType.text, heading: LocalizedText(en: 'About')),
        CustomPageSection(id: 's2', type: CustomSectionType.imageGrid, mediaIds: [media.id]),
      ]);
      await expectLater(service.publishCustomPage(requesterRole: 'admin', actor: _admin, page: withDraftImage), throwsA(isA<WebsiteContentException>()));
      expect(await publicRepository().liveCustomPages(), isEmpty);

      final image = await publishedImage();
      final ready = page.copyWith(sections: [
        const CustomPageSection(id: 's1', type: CustomSectionType.text, heading: LocalizedText(en: 'About')),
        CustomPageSection(id: 's2', type: CustomSectionType.imageGrid, mediaIds: [image.id]),
      ]);
      await service.publishCustomPage(requesterRole: 'admin', actor: _admin, page: ready);
      final live = await publicRepository().liveCustomPages();
      expect(live.single.slug, 'open-day');
      expect(live.single.title.ta, 'திறந்த நாள்');
      final raw = (await firestore.collection(WebsiteCollections.livePages).doc(page.id).get()).data()!;
      expect(raw.keys.toSet(), {'kind', 'slug', 'title', 'intro', 'heroMediaId', 'sections', 'showInNavigation', 'navOrder', 'mediaIds', 'publishedAt'});
      expect(raw.values.whereType<String>().any((v) => v.contains(_admin.phone)), isFalse);

      // The image is now in use by a live page.
      await expectLater(service.hideMedia(requesterRole: 'admin', actor: _admin, mediaId: image.id), throwsA(isA<WebsiteContentException>()));

      // Drafts don't change the live page.
      await service.saveCustomPageDraft(requesterRole: 'admin', actor: _admin, page: ready.copyWith(title: const LocalizedText(en: 'Changed')));
      expect((await publicRepository().liveCustomPages()).single.title.en, 'Open Day');
    });

    test('unpublish, archive and restore', () async {
      final page = await createPage('open-day');
      await service.publishCustomPage(requesterRole: 'admin', actor: _admin, page: page);
      expect(await publicRepository().liveCustomPages(), hasLength(1));
      await service.unpublishCustomPage(requesterRole: 'admin', actor: _admin, pageId: page.id);
      expect(await publicRepository().liveCustomPages(), isEmpty);

      await service.publishCustomPage(requesterRole: 'admin', actor: _admin, page: page);
      await service.archiveCustomPage(requesterRole: 'admin', actor: _admin, pageId: page.id);
      expect(await publicRepository().liveCustomPages(), isEmpty);
      await expectLater(service.publishCustomPage(requesterRole: 'admin', actor: _admin, page: page), throwsA(isA<WebsiteContentException>()));
      await service.restoreCustomPage(requesterRole: 'admin', actor: _admin, pageId: page.id);
      final restored = (await service.getCustomPage(requesterRole: 'admin', pageId: page.id))!;
      expect(restored.draft.archived, isFalse);
      expect(restored.live, isNull, reason: 'restored as an unpublished draft');
    });

    test('built-in content and additional pages share the live collection without mixing', () async {
      await service.publishPage(requesterRole: 'admin', actor: _admin, content: const WebsitePageContent(slot: WebsitePageSlot.home, headline: LocalizedText(en: 'Hello')));
      final page = await createPage('open-day');
      await service.publishCustomPage(requesterRole: 'admin', actor: _admin, page: page);
      final content = await publicRepository().liveContent();
      expect(content.pages.keys, [WebsitePageSlot.home]);
      expect(content.customPages.single.id, page.id);
    });
  });

  group('additional pages: public site', () {
    Future<CustomPage> publishRichPage({bool inNav = false}) async {
      final image = await publishedImage(alt: 'Children planting seeds');
      final page = await createPage('open-day', titleTa: 'திறந்த நாள்');
      final full = page.copyWith(
        intro: const LocalizedText(en: 'Visit our classrooms.', ta: 'எங்கள் வகுப்பறைகளைப் பாருங்கள்.'),
        heroMediaId: () => image.id,
        showInNavigation: inNav,
        sections: [
          const CustomPageSection(id: 'txt', type: CustomSectionType.text, heading: LocalizedText(en: 'What to expect'), body: LocalizedText(en: 'First paragraph.\n\nSecond paragraph.')),
          CustomPageSection(id: 'img', type: CustomSectionType.imageText, mediaId: image.id, heading: const LocalizedText(en: 'Our garden'), body: const LocalizedText(en: 'Children grow vegetables.')),
          CustomPageSection(id: 'grid', type: CustomSectionType.imageGrid, heading: const LocalizedText(en: 'Photographs'), mediaIds: [image.id]),
          const CustomPageSection(
            id: 'cta',
            type: CustomSectionType.callToAction,
            heading: LocalizedText(en: 'Ready to apply?'),
            buttonLabel: LocalizedText(en: 'See admissions', ta: 'சேர்க்கை'),
            target: '/admissions',
          ),
        ],
      );
      await service.publishCustomPage(requesterRole: 'admin', actor: _admin, page: full);
      return full;
    }

    testWidgets('a published page renders without login, with its sections, in English and Tamil', (tester) async {
      await publishRichPage();
      await pumpSite(tester, route: '/pages/open-day');
      expect(find.byType(PublicCustomPage), findsOneWidget);
      expect(text(tester, 'public-page-title'), 'Open Day');
      expect(text(tester, 'public-page-intro'), 'Visit our classrooms.');
      expect(find.byKey(const Key('public-page-hero')), findsOneWidget);
      expect(find.text('What to expect'), findsOneWidget);
      expect(find.text('Second paragraph.'), findsOneWidget);
      expect(find.text('Our garden'), findsOneWidget);
      expect(find.text('Reading corner'), findsOneWidget, reason: 'grid caption from the media library');
      expect(tester.takeException(), isNull);

      await tapAndSettle(tester, find.text('தமிழ்'));
      expect(text(tester, 'public-page-title'), 'திறந்த நாள்');
      expect(text(tester, 'public-page-intro'), 'எங்கள் வகுப்பறைகளைப் பாருங்கள்.');
      expect(find.text('What to expect'), findsOneWidget, reason: 'no Tamil entered: English shown');

      await tapAndSettle(tester, find.byKey(const Key('public-page-cta-cta')));
      expect(find.byType(PublicSectionPage), findsOneWidget, reason: 'internal call to action');
    });

    testWidgets('mobile layout fits', (tester) async {
      await publishRichPage();
      await pumpSite(tester, route: '/pages/open-day', size: const Size(360, 780));
      expect(tester.takeException(), isNull);
      await tester.drag(find.byType(SingleChildScrollView).first, const Offset(0, -3000));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    for (final (name, route) in [('unknown', '/pages/no-such-page'), ('malformed', '/pages/Bad_Slug!'), ('nested', '/pages/open-day/extra')]) {
      testWidgets('$name address: page not found, no draft content', (tester) async {
        await createPage('no-such-page', title: 'Secret draft title');
        await pumpSite(tester, route: route);
        expect(tester.takeException(), isNull);
        expect(find.byType(PublicCustomPage), findsOneWidget);
        expect(find.byKey(const Key('public-page-not-found')), findsOneWidget);
        expect(find.text('Secret draft title'), findsNothing);
      });
    }

    testWidgets('unpublished and archived pages are not shown to visitors', (tester) async {
      final page = await publishRichPage();
      await service.unpublishCustomPage(requesterRole: 'admin', actor: _admin, pageId: page.id);
      await pumpSite(tester, route: '/pages/open-day');
      expect(find.byKey(const Key('public-page-not-found')), findsOneWidget);
      expect(find.text('What to expect'), findsNothing);

      await service.publishCustomPage(requesterRole: 'admin', actor: _admin, page: page);
      await service.archiveCustomPage(requesterRole: 'admin', actor: _admin, pageId: page.id);
      await pumpSite(tester, route: '/pages/open-day');
      expect(find.byKey(const Key('public-page-not-found')), findsOneWidget);
    });

    testWidgets('navigation: only listed published pages, in order, before Contact; built-in routes unchanged', (tester) async {
      final a = await createPage('open-day', title: 'Open Day');
      final b = await createPage('parents', title: 'Parents');
      final c = await createPage('hidden', title: 'Not listed');
      final d = await createPage('draft-only', title: 'Draft listed');
      await service.publishCustomPage(requesterRole: 'admin', actor: _admin, page: a.copyWith(showInNavigation: true));
      await service.publishCustomPage(requesterRole: 'admin', actor: _admin, page: b.copyWith(showInNavigation: true));
      await service.publishCustomPage(requesterRole: 'admin', actor: _admin, page: c);
      await service.saveCustomPageDraft(requesterRole: 'admin', actor: _admin, page: d.copyWith(showInNavigation: true));
      await service.reorderCustomPages(requesterRole: 'admin', actor: _admin, orderedIds: [b.id, a.id, c.id, d.id]);

      await pumpSite(tester, size: const Size(375, 800));
      await tapAndSettle(tester, find.byKey(const Key('public-menu-button')));
      double y(String route) => tester.getTopLeft(find.byKey(Key('public-menu-$route'))).dy;
      expect(find.byKey(const Key('public-menu-/pages/hidden')), findsNothing);
      expect(find.byKey(const Key('public-menu-/pages/draft-only')), findsNothing);
      expect(y('/gallery'), lessThan(y('/pages/parents')));
      expect(y('/pages/parents'), lessThan(y('/pages/open-day')));
      expect(y('/pages/open-day'), lessThan(y('/contact')));
      for (final route in PublicRoutes.sections) {
        expect(find.byKey(Key('public-menu-$route')), findsOneWidget, reason: route);
      }

      await tapAndSettle(tester, find.byKey(const Key('public-menu-/pages/open-day')));
      expect(text(tester, 'public-page-title'), 'Open Day');
      await tapAndSettle(tester, find.byKey(const Key('public-footer-/pages/parents')));
      expect(text(tester, 'public-page-title'), 'Parents');
      await tapAndSettle(tester, find.byKey(const Key('public-footer-/')));
      expect(find.byType(PublicHomePage), findsOneWidget);
    });
  });

  group('additional pages: admin UI', () {
    testWidgets('staff cannot open the editor screens', (tester) async {
      await pumpAdmin(tester, WebsiteContentScreen(service: service), role: 'staff');
      expect(find.byKey(const Key('website-new-page')), findsNothing);
    });

    testWidgets('create with a suggested address, reject a duplicate, build and publish a page', (tester) async {
      await createPage('open-day');
      await pumpAdmin(tester, WebsiteContentScreen(service: service));
      await tapAndSettle(tester, find.byKey(const Key('website-tab-pages')));
      expect(find.textContaining('Open Day'), findsOneWidget);

      await tapAndSettle(tester, find.byKey(const Key('website-new-page')));
      await tester.enterText(find.byKey(const Key('website-new-page-title-en')), 'Open Day');
      await tester.pumpAndSettle();
      expect(fieldText(tester, 'website-new-page-slug'), 'open-day', reason: 'suggested from the title');
      await tapAndSettle(tester, find.byKey(const Key('website-new-page-create')));
      expect(find.byKey(const Key('website-new-page-error')), findsOneWidget, reason: 'duplicate address');

      await tester.enterText(find.byKey(const Key('website-new-page-slug')), 'Bad Slug');
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(find.byKey(const Key('website-new-page-create'))).onPressed, isNull);

      await tester.enterText(find.byKey(const Key('website-new-page-slug')), 'visit-us');
      expect(find.byKey(const Key('website-new-page-title-ta')), findsNothing, reason: 'English only');
      await tester.pumpAndSettle();
      await tapAndSettle(tester, find.byKey(const Key('website-new-page-create')));
      expect(find.byType(WebsiteCustomPageEditorScreen), findsOneWidget);
      expect(text(tester, 'website-edit-source-text'), contains('not published'));

      // A new page is built with blocks.
      expect(find.byKey(const Key('website-custom-uses-blocks')), findsOneWidget);
      expect(find.byKey(const Key('website-custom-add-section')), findsNothing);
      await tapAndSettle(tester, find.byKey(const Key('website-blocks-add-quick-text')));
      final headingField = find.byWidgetPredicate((w) => w is TextFormField && w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.contains('-heading-en-'));
      await tester.enterText(headingField, 'Welcome visitors');
      await tester.pumpAndSettle();
      expect(find.descendant(of: find.byKey(const Key('website-custom-preview')), matching: find.text('Welcome visitors')), findsOneWidget, reason: 'live preview');
      expect(find.byKey(const Key('website-preview-ta')), findsNothing);

      await tapAndSettle(tester, find.byKey(const Key('website-inspector-close')));
      await tapAndSettle(tester, find.byKey(const Key('website-custom-show-in-nav')));
      await tapAndSettle(tester, find.byKey(const Key('website-custom-save-draft')));
      expect(await publicRepository().liveCustomPages(), isEmpty, reason: 'draft only');

      await tapAndSettle(tester, find.byKey(const Key('website-preview-live')));
      expect(find.byKey(const Key('website-custom-preview-not-live')), findsOneWidget);

      await tapAndSettle(tester, find.byKey(const Key('website-custom-publish')));
      final live = (await publicRepository().liveCustomPages()).single;
      expect(live.slug, 'visit-us');
      expect(live.showInNavigation, isTrue);
      expect((live.blocks!.single as StructuredBlock).text('heading').en, 'Welcome visitors');
      expect(live.sections.single.heading.en, 'Welcome visitors', reason: 'the sections copy for older versions');
      expect(text(tester, 'website-edit-source-text'), contains('published page'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('an unsafe button link is flagged and cannot be saved', (tester) async {
      final page = await createPage('open-day');
      await pumpAdmin(tester, WebsiteCustomPageEditorScreen(service: service, user: _admin, pageId: page.id));
      await tapAndSettle(tester, find.byKey(const Key('website-custom-add-section')));
      await tapAndSettle(tester, find.byKey(const Key('website-custom-add-cta')));
      Finder field(String suffix) => find.byWidgetPredicate((w) => w is TextFormField && w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.endsWith(suffix));
      await tester.enterText(field('-button-en'), 'Go');
      await tester.enterText(field('-target'), 'javascript:alert(1)');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('website-custom-errors')), findsOneWidget);
      await tapAndSettle(tester, find.byKey(const Key('website-custom-save-draft')));
      expect((await service.getCustomPage(requesterRole: 'admin', pageId: page.id))!.draft.sections, isEmpty, reason: 'refused');
    });
  });

  // ------------------------------------------- consent withdrawal (privacy)

  group('consent withdrawal', () {
    /// One published photograph used everywhere it can be: the gallery, the
    /// homepage hero, the Admissions banner, and an additional page's banner
    /// and image grid.
    Future<({WebsiteMedia image, CustomPage page})> useEverywhere() async {
      final image = await publishedImage(alt: 'Children at the sand tray');
      await service.updateMediaDetails(
        requesterRole: 'admin',
        actor: _admin,
        mediaId: image.id,
        alt: image.alt,
        caption: const LocalizedText(en: 'Sand tray'),
        category: GalleryCategory.classroom,
        inGallery: true,
        focalX: 0.5,
        focalY: 0.5,
        consentConfirmed: true,
      );
      await service.publishPage(requesterRole: 'admin', actor: _admin, content: WebsitePageContent(slot: WebsitePageSlot.home, imageMediaId: image.id, headline: const LocalizedText(en: 'Hello families')));
      await service.publishPage(requesterRole: 'admin', actor: _admin, content: WebsitePageContent(slot: WebsitePageSlot.admissions, imageMediaId: image.id));
      final page = (await createPage('open-day')).copyWith(
        heroMediaId: () => image.id,
        intro: const LocalizedText(en: 'Come and see.'),
        sections: [
          CustomPageSection(id: 'grid', type: CustomSectionType.imageGrid, heading: const LocalizedText(en: 'Photographs'), mediaIds: [image.id]),
          const CustomPageSection(id: 'txt', type: CustomSectionType.text, body: LocalizedText(en: 'Unrelated text stays.')),
        ],
      );
      await service.publishCustomPage(requesterRole: 'admin', actor: _admin, page: page);
      return (image: (await service.getMedia(requesterRole: 'admin', mediaId: image.id))!, page: page);
    }

    Future<void> withdraw(WebsiteMedia image) => service.updateMediaDetails(
          requesterRole: 'admin',
          actor: _admin,
          mediaId: image.id,
          alt: image.alt,
          caption: image.caption,
          category: image.category,
          inGallery: image.inGallery,
          focalX: image.focalX,
          focalY: image.focalY,
          consentConfirmed: false,
        );

    test('takes effect at once even while live pages use the image; pages stay published; audited; files kept', () async {
      final (:image, :page) = await useEverywhere();
      // Hiding (editorial) is still refused while live pages show it.
      await expectLater(service.hideMedia(requesterRole: 'admin', actor: _admin, mediaId: image.id), throwsA(isA<WebsiteContentException>()));

      await withdraw(image);

      final after = (await service.getMedia(requesterRole: 'admin', mediaId: image.id))!;
      expect(after.status, WebsiteMediaStatus.hidden);
      expect(after.consentConfirmed, isFalse);
      expect(await publicRepository().publishedMedia(), isEmpty, reason: 'no public usage can resolve it');

      final live = await publicRepository().liveContent();
      expect(live.pages[WebsitePageSlot.home]!.headline.en, 'Hello families', reason: 'page stays published, other content intact');
      expect(live.pages[WebsitePageSlot.admissions], isNotNull);
      expect(live.customPages.single.sections.last.body.en, 'Unrelated text stays.');

      final audit = await firestore.collection(WebsiteCollections.media).doc(image.id).collection('audit').where('action', isEqualTo: 'consent-withdrawn').get();
      final entry = audit.docs.single.data();
      expect(entry['byName'], 'Test admin');
      expect(entry['wasPublished'], isTrue);
      expect(entry['affectedPages'], containsAll(['Homepage hero', 'Admissions', 'the “Open Day” page']));
      final raw = (await firestore.collection(WebsiteCollections.media).doc(image.id).get()).data()!;
      expect(raw.containsKey('consentWithdrawnAt'), isTrue);

      expect(storage.storedDataMap.containsKey(image.storagePath), isTrue, reason: 'not silently deleted');
      expect(storage.storedDataMap.containsKey(image.thumbStoragePath), isTrue);

      // The image can't come back without fresh consent, nor be republished on a page.
      await expectLater(service.publishMedia(requesterRole: 'admin', actor: _admin, mediaId: image.id), throwsA(isA<WebsiteContentException>()));
      await expectLater(
        service.publishPage(requesterRole: 'admin', actor: _admin, content: WebsitePageContent(slot: WebsitePageSlot.admissions, imageMediaId: image.id)),
        throwsA(isA<WebsiteContentException>()),
      );
      await expectLater(service.publishCustomPage(requesterRole: 'admin', actor: _admin, page: page), throwsA(isA<WebsiteContentException>()));
    });

    testWidgets('every public usage falls back: gallery, homepage hero, section banner, page banner and grid', (tester) async {
      final (:image, page: _) = await useEverywhere();

      await pumpSite(tester);
      expect(find.byKey(const Key('public-hero-image')), findsOneWidget, reason: 'shown before withdrawal');

      await withdraw(image);
      await pumpSite(tester);
      expect(find.byKey(const Key('public-hero-image')), findsNothing);
      expect(find.byKey(const Key('public-hero-ornament')), findsOneWidget);
      expect(find.text('Hello families'), findsOneWidget, reason: 'page text unchanged');

      await pumpSite(tester, route: PublicRoutes.gallery);
      expect(find.byKey(Key('public-gallery-item-${image.id}')), findsNothing);
      expect(find.byKey(const Key('public-gallery-empty')), findsOneWidget);

      await pumpSite(tester, route: PublicRoutes.admissions);
      expect(find.byKey(const Key('public-section-image')), findsNothing);
      expect(find.byKey(const Key('public-section-placeholder')), findsOneWidget);

      await pumpSite(tester, route: '/pages/open-day');
      expect(find.byKey(const Key('public-page-not-found')), findsNothing, reason: 'the page stays published');
      expect(text(tester, 'public-page-title'), 'Open Day');
      expect(find.byKey(const Key('public-page-hero')), findsNothing);
      expect(find.byKey(ValueKey('public-image-${image.id}')), findsNothing, reason: 'not in the grid either');
      expect(find.text('Unrelated text stays.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('admin: unticking consent asks first, names the affected pages, then flags them in the Pages list', (tester) async {
      final (:image, page: _) = await useEverywhere();
      await pumpAdmin(tester, WebsiteMediaEditorScreen(service: service, user: _admin, media: image));
      await tapAndSettle(tester, find.byKey(const Key('website-media-consent')));
      await tapAndSettle(tester, find.byKey(const Key('website-media-save')));
      expect(tester.widget<Text>(find.byKey(const Key('website-media-withdraw-text'))).data, allOf(contains('Homepage hero'), contains('Admissions'), contains('Open Day')));

      await tapAndSettle(tester, find.text('Cancel'));
      expect((await service.getMedia(requesterRole: 'admin', mediaId: image.id))!.isPublished, isTrue, reason: 'cancel changes nothing');

      await tapAndSettle(tester, find.byKey(const Key('website-media-save')));
      await tapAndSettle(tester, find.byKey(const Key('website-media-withdraw-confirm')));
      expect((await service.getMedia(requesterRole: 'admin', mediaId: image.id))!.status, WebsiteMediaStatus.hidden);

      await pumpAdmin(tester, WebsiteContentScreen(service: service));
      await tapAndSettle(tester, find.byKey(const Key('website-tab-pages')));
      expect(find.byKey(const Key('website-page-image-not-shown')), findsNWidgets(2), reason: 'Homepage hero and Admissions');
      expect(find.descendant(of: find.byKey(Key('website-custom-page-${(await service.listCustomPages(requesterRole: 'admin')).single.draft.id}')), matching: find.text('Image not shown')), findsOneWidget);
    });

    test('a record marked published without confirmed consent is never shown publicly', () async {
      await firestore.collection(WebsiteCollections.media).doc('inconsistent').set({
        'url': 'https://example.test/x.jpg',
        'status': 'published',
        'consentConfirmed': false,
        'alt': {'en': 'x'},
      });
      expect(await publicRepository().publishedMedia(), isEmpty);
    });
  });
}
