// Upcoming events: configurable layouts (list, grid, compact cards) with
// columns per screen size, and event images from the website media library
// (upload, consent, publish, replace, remove).
//
// Every record here is synthetic test data. The fake Firestore and Storage
// prove the app's behaviour, not deployed security rules (deferred).

import 'dart:typed_data';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/main.dart';
import 'package:montessori_app/modules/admin/website/data/website_content_admin_service.dart';
import 'package:montessori_app/modules/admin/website/data/website_image_processor.dart';
import 'package:montessori_app/modules/admin/website/data/website_public_items_service.dart';
import 'package:montessori_app/modules/admin/website/ui/website_content_editors.dart';
import 'package:montessori_app/modules/auth/models/app_user.dart';
import 'package:montessori_app/modules/auth/providers/auth_provider.dart';
import 'package:montessori_app/modules/auth/providers/auth_state_provider.dart';
import 'package:montessori_app/modules/calendar/models/calendar_event_model.dart';
import 'package:montessori_app/modules/calendar/services/calendar_service.dart';
import 'package:montessori_app/modules/calendar/services/calendar_website_publisher.dart';
import 'package:montessori_app/modules/calendar/ui/calendar_view.dart';
import 'package:montessori_app/modules/public_website/content/blocks/block_registry.dart';
import 'package:montessori_app/modules/public_website/content/blocks/website_block.dart';
import 'package:montessori_app/modules/public_website/content/website_content_models.dart';
import 'package:montessori_app/modules/public_website/content/website_content_repository.dart';
import 'package:montessori_app/modules/public_website/content/website_public_item.dart';
import 'package:montessori_app/modules/public_website/public_strings.dart';
import 'package:montessori_app/modules/public_website/widgets/blocks/public_events_feed.dart';
import 'package:montessori_app/modules/public_website/widgets/blocks/website_blocks_view.dart';

final _admin = AppUser(id: '9000000002', phone: '9000000002', role: 'admin', isActive: true, name: 'Test admin');

class _FakeProcessor implements WebsiteImageProcessor {
  @override
  Future<ProcessedWebsiteImage> process(Uint8List bytes, {required String contentType}) async => ProcessedWebsiteImage(
        width: 1600,
        height: 900,
        display: Uint8List.fromList([1, 2, 3]),
        displayContentType: 'image/jpeg',
        thumb: Uint8List.fromList([4]),
        thumbContentType: 'image/jpeg',
      );
}

/// Always picks the same synthetic photograph.
class _Picker extends FilePicker {
  int picks = 0;

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
    picks++;
    return FilePickerResult([PlatformFile(name: 'synthetic_open_day.jpg', size: 3, bytes: Uint8List.fromList([9, 9, 9]))]);
  }
}

/// [hour]:[minute] at school (IST) on [day] February 2027, as an instant.
DateTime _ist(int day, [int hour = 0, int minute = 0]) => DateTime.utc(2027, 2, day, hour, minute).subtract(const Duration(hours: 5, minutes: 30));

final _now = DateTime.utc(2027, 2, 1, 4, 30);

WebsitePublicItem _item(String id, {int day = 3, String? image, String title = 'Open Day'}) => WebsitePublicItem(
      kind: WebsitePublicItemKind.event,
      sourceId: id,
      title: LocalizedText(en: title),
      body: const LocalizedText(en: 'The whole description.'),
      location: const LocalizedText(en: 'School hall'),
      startAt: _ist(day, 9),
      endAt: _ist(day, 12),
      imageMediaId: image,
    );

const _published = WebsiteMedia(
  id: 'pub1',
  url: 'https://example.test/pub1.jpg',
  storagePath: 'website_media/pub1/123_display.jpg',
  thumbUrl: 'https://example.test/pub1_thumb.jpg',
  thumbStoragePath: 'website_media/pub1/123_thumb.jpg',
  alt: LocalizedText(en: 'Children at the open day'),
  status: WebsiteMediaStatus.published,
  consentConfirmed: true,
  inGallery: false,
);

StructuredBlock _feed({String layout = 'grid', String desktop = '3', String tablet = '2', String mobile = '1', String max = '6', bool images = true}) {
  final b = BlockRegistry.create(BlockRegistry.eventsFeed);
  return b.copyWith(values: {...b.values, 'layout': layout, 'desktopColumns': desktop, 'tabletColumns': tablet, 'mobileColumns': mobile, 'maxItems': max, 'showImages': images});
}

Future<void> _pumpFeed(WidgetTester tester, StructuredBlock block, List<WebsitePublicItem> items, {double width = 1400, List<WebsiteMedia> media = const [_published]}) async {
  tester.view.physicalSize = Size(width, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  // A fresh scope each time, so these overrides apply.
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(ProviderScope(
    overrides: [
      publicClockProvider.overrideWithValue(() => _now),
      publicEventItemsProvider.overrideWith((ref) async => items),
      publishedWebsiteMediaProvider.overrideWith((ref) async => media),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: WebsiteBlocksView(blocks: [block], media: const {}, language: PublicLanguage.english),
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

Finder _imageIn(String id) => find.descendant(of: find.byKey(Key('public-event-event_$id')), matching: find.byType(Image));

void main() {
  // ---------------------------------------------------------------- layout

  group('layout', () {
    test('an older block (no layout settings) shows the defaults: a 3/2/1-column grid; its old setting is kept as stored', () {
      final older = BlockRegistry.parse({
        'id': 'b_events00001', 'type': 'events_feed', 'v': 1, 'heading': {'en': 'Upcoming events'}, 'maxItems': '6', 'display': 'list', 'showImages': true,
      }) as StructuredBlock;
      expect(BlockRegistry.validate([older]), isEmpty);
      expect(PublicEventsLayout.parse(older.string('layout')), PublicEventsLayout.grid);
      expect([older.string('desktopColumns'), older.string('tabletColumns'), older.string('mobileColumns')], ['3', '2', '1']);
      expect(older.toMap()['display'], 'list', reason: 'kept as stored');
      expect(PublicEventsLayout.parse('anything else'), PublicEventsLayout.grid);
    });

    test('columns: the number chosen for the screen size, never more than fit', () {
      int cols(double screen, double available, {int d = 3, int t = 2, int m = 1}) =>
          PublicEventsFeed.columnsFor(screenWidth: screen, available: available, desktop: d, tablet: t, mobile: m, gap: 20);
      expect(cols(1400, 1160), 3);
      expect(cols(1400, 1160, d: 4), 4);
      expect(cols(1400, 1160, d: 1), 1);
      expect(cols(900, 860), 2);
      expect(cols(900, 860, t: 3), 3);
      expect(cols(400, 368), 1);
      expect(cols(360, 328, m: 2), 2);
      expect(cols(1400, 500, d: 4), 3, reason: 'a narrow section column fits fewer');
      expect(cols(1400, 100, d: 4), 1, reason: 'always at least one');
    });

    for (final (name, width, expected) in [('desktop', 1400.0, 3), ('tablet', 900.0, 2), ('mobile', 400.0, 1)]) {
      testWidgets('grid on $name: $expected columns of equal width, inside the screen', (tester) async {
        final items = [for (var d = 2; d <= 7; d++) _item('e$d', day: d)];
        await _pumpFeed(tester, _feed(), items, width: width);
        expect(find.byKey(Key('public-events-columns-$expected')), findsOneWidget);
        final widths = {for (var d = 2; d <= 7; d++) tester.getSize(find.byKey(Key('public-event-event_e$d'))).width};
        expect(widths, hasLength(1), reason: 'equal widths');
        for (var d = 2; d <= 7; d++) {
          expect(tester.getRect(find.byKey(Key('public-event-event_e$d'))).right, lessThanOrEqualTo(width));
        }
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('chosen columns per screen size: 4 on desktop, 3 on tablets, 2 on phones', (tester) async {
      final items = [for (var d = 2; d <= 7; d++) _item('e$d', day: d)];
      for (final (width, expected) in [(1400.0, 4), (900.0, 3), (400.0, 2)]) {
        await _pumpFeed(tester, _feed(layout: 'compact_cards', desktop: '4', tablet: '3', mobile: '2'), items, width: width);
        expect(find.byKey(const Key('public-events-compact')), findsOneWidget);
        expect(find.byKey(Key('public-events-columns-$expected')), findsOneWidget, reason: '$width');
      }
    });

    testWidgets('list: one event per row, whatever the columns', (tester) async {
      await _pumpFeed(tester, _feed(layout: 'list', desktop: '4'), [_item('a', day: 2), _item('b', day: 3)]);
      expect(find.byKey(const Key('public-events-list')), findsOneWidget);
      final a = tester.getRect(find.byKey(const Key('public-event-event_a')));
      final b = tester.getRect(find.byKey(const Key('public-event-event_b')));
      expect(b.top, greaterThan(a.bottom));
    });

    testWidgets('the maximum applies to every layout', (tester) async {
      final items = [for (var d = 2; d <= 9; d++) _item('e$d', day: d)];
      for (final layout in ['list', 'grid', 'compact_cards']) {
        await _pumpFeed(tester, _feed(layout: layout, max: '4'), items);
        expect(find.byKey(const Key('public-event-event_e5')), findsOneWidget, reason: layout);
        expect(find.byKey(const Key('public-event-event_e6')), findsNothing, reason: layout);
      }
    });

    testWidgets('images on and off; previews never show the description; nothing overflows at 360 px', (tester) async {
      final items = [_item('pic', image: 'pub1', title: 'A long event title that wraps over several lines on a phone'), _item('none', day: 4)];
      for (final layout in ['list', 'grid', 'compact_cards']) {
        await _pumpFeed(tester, _feed(layout: layout, mobile: '2'), items, width: 360);
        expect(tester.takeException(), isNull, reason: layout);
        expect(_imageIn('pic'), findsWidgets, reason: layout);
        expect(_imageIn('none'), findsNothing, reason: layout);
        expect(find.text('The whole description.'), findsNothing, reason: layout);
        await _pumpFeed(tester, _feed(layout: layout, images: false), items, width: 360);
        expect(_imageIn('pic'), findsNothing, reason: '$layout, images off');
      }
    });

    testWidgets('whole-card click and its screen-reader label in the grid', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pumpFeed(tester, _feed(), [_item('a')]);
      expect(find.byKey(const Key('public-event-open-event_a')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^Open Day, Wed 3 February 2027, ')), findsOneWidget);
      semantics.dispose();
    });
  });

  // ------------------------------------------------------- images: service

  group('event images (service)', () {
    late FakeFirebaseFirestore firestore;
    late WebsiteContentAdminService media;
    late CalendarWebsitePublisher publisher;
    late _Picker picker;

    setUp(() async {
      firestore = FakeFirebaseFirestore();
      picker = _Picker();
      media = WebsiteContentAdminService(firestore: firestore, storage: MockFirebaseStorage(), imageProcessor: _FakeProcessor(), filePicker: picker);
      publisher = CalendarWebsitePublisher(calendar: CalendarService(firestore: firestore), media: media);
      await firestore.collection('school_calendar_events').doc('ev1').set({
        'title': 'Open Day', 'date': DateTime(2027, 2, 14), 'startTime': '09:00', 'endTime': '12:00', 'eventType': CalendarEventType.event,
        'description': 'Tour the classrooms.', 'location': 'School hall', 'audience': 'Public', 'status': CalendarEventStatus.published,
        'createdBy': 'creator-0001', 'createdByName': 'Synthetic Creator',
      });
    });

    Future<CalendarEventModel> event() async => CalendarEventModel.fromMap('ev1', (await firestore.collection('school_calendar_events').doc('ev1').get()).data()!);
    Future<WebsitePublicItem> show({String? Function()? image}) async => publisher.show(requesterRole: 'admin', event: await event(), approvedForWebsite: true, image: image);
    Future<Map<String, dynamic>> copy() async => (await firestore.collection(WebsitePublicItem.collection).doc('event_ev1').get()).data()!;
    Future<int> mediaCount() async => (await firestore.collection(WebsiteCollections.media).get()).docs.length;

    /// Uploads, then the library's steps: alt text and consent, then publish.
    Future<WebsiteMedia> uploadAndPublish() async {
      final uploaded = await media.uploadMedia(requesterRole: 'admin', actor: _admin, image: (await media.pickImage())!, inGallery: false);
      await media.updateMediaDetails(
        requesterRole: 'admin', actor: _admin, mediaId: uploaded.id, alt: const LocalizedText(en: 'Visitors in the hall'), caption: const LocalizedText(),
        category: GalleryCategory.general, inGallery: false, focalX: 0.5, focalY: 0.5, consentConfirmed: true,
      );
      await media.publishMedia(requesterRole: 'admin', actor: _admin, mediaId: uploaded.id);
      return (await media.getMedia(requesterRole: 'admin', mediaId: uploaded.id))!;
    }

    test('upload → consent → publish, then associate by id; only a published, consented image can be chosen', () async {
      final uploaded = await media.uploadMedia(requesterRole: 'admin', actor: _admin, image: (await media.pickImage())!, inGallery: false);
      expect(uploaded.status, WebsiteMediaStatus.draft);
      expect(uploaded.inGallery, isFalse, reason: 'an event image stays out of the gallery');
      const refused = 'Publish the chosen image first (Media library), or choose a published one.';
      await expectLater(show(image: () => uploaded.id), throwsA(isA<WebsiteContentException>().having((e) => e.message, 'message', refused)), reason: 'uploaded');

      await media.updateMediaDetails(
        requesterRole: 'admin', actor: _admin, mediaId: uploaded.id, alt: const LocalizedText(en: 'Visitors in the hall'), caption: const LocalizedText(),
        category: GalleryCategory.general, inGallery: false, focalX: 0.5, focalY: 0.5, consentConfirmed: true,
      );
      await expectLater(show(image: () => uploaded.id), throwsA(isA<WebsiteContentException>()), reason: 'approved, not published');

      await media.publishMedia(requesterRole: 'admin', actor: _admin, mediaId: uploaded.id);
      final item = await show(image: () => uploaded.id);
      expect(item.imageMediaId, uploaded.id);
      final stored = await copy();
      expect(stored['imageMediaId'], uploaded.id);
      expect(stored.toString(), isNot(contains('website_media/')), reason: 'no storage path in the copy');
      expect(stored.toString(), isNot(contains('http')), reason: 'no URL in the copy');
    });

    test('republishing without an image change keeps the image and uploads nothing', () async {
      final image = await uploadAndPublish();
      await show(image: () => image.id);
      final uploads = picker.picks;
      final count = await mediaCount();

      await firestore.collection('school_calendar_events').doc('ev1').update({'title': 'Open Day 2027'});
      final again = await show();
      expect(again.imageMediaId, image.id);
      expect(again.title.en, 'Open Day 2027');
      await show();
      expect(await mediaCount(), count, reason: 'no new media');
      expect(picker.picks, uploads);
    });

    test('replace and remove change only the image: translations and registration link are kept', () async {
      final first = await uploadAndPublish();
      final second = await uploadAndPublish();
      await publisher.show(requesterRole: 'admin', event: await event(), approvedForWebsite: true);
      await WebsitePublicItemsService(firestore: firestore).update(
        requesterRole: 'admin', kind: WebsitePublicItemKind.event, sourceId: 'ev1',
        extras: WebsitePublicItemExtras(title: const LocalizedText(ta: 'திறந்த நாள்'), imageMediaId: first.id, registrationUrl: 'https://forms.example.test/r'),
      );

      final replaced = await show(image: () => second.id);
      expect(replaced.imageMediaId, second.id);
      expect(replaced.title.ta, 'திறந்த நாள்');
      expect(replaced.registrationUrl, 'https://forms.example.test/r');
      expect(await media.getMedia(requesterRole: 'admin', mediaId: first.id), isNotNull, reason: 'the old image stays in the library');

      final removed = await show(image: () => null);
      expect(removed.imageMediaId, isNull);
      expect((await copy()).containsKey('imageMediaId'), isFalse);
      expect(removed.title.ta, 'திறந்த நாள்');
      expect(removed.registrationUrl, 'https://forms.example.test/r');
    });

    test('in use by an event: delete and hide are refused (with the event named); consent withdrawal still works at once', () async {
      final image = await uploadAndPublish();
      await show(image: () => image.id);
      expect(await media.pagesUsing(requesterRole: 'admin', mediaId: image.id), {'the “Open Day” event'});
      await expectLater(
        media.deleteMedia(requesterRole: 'admin', actor: _admin, mediaId: image.id),
        throwsA(isA<WebsiteContentException>().having((e) => e.message, 'message', contains('the “Open Day” event'))),
      );
      await expectLater(
        media.hideMedia(requesterRole: 'admin', actor: _admin, mediaId: image.id),
        throwsA(isA<WebsiteContentException>().having((e) => e.message, 'message', contains('in the Calendar first'))),
      );

      // Withdrawing consent hides it everywhere at once.
      await media.updateMediaDetails(
        requesterRole: 'admin', actor: _admin, mediaId: image.id, alt: image.alt, caption: image.caption,
        category: image.category, inGallery: false, focalX: 0.5, focalY: 0.5, consentConfirmed: false,
      );
      final public = await WebsiteContentRepository(firestore: firestore).publishedMedia();
      expect(public.where((m) => m.id == image.id), isEmpty, reason: 'visitors no longer get it');
      // The event's text can still be updated; its image just isn't shown.
      await firestore.collection('school_calendar_events').doc('ev1').update({'location': 'Garden'});
      final updated = await show();
      expect(updated.location.en, 'Garden');
      // Choosing it again explicitly is refused until it is published again.
      await expectLater(show(image: () => image.id), throwsA(isA<WebsiteContentException>()));

      // Once removed from the event, it can be deleted.
      await show(image: () => null);
      await media.deleteMedia(requesterRole: 'admin', actor: _admin, mediaId: image.id);
      expect(await media.getMedia(requesterRole: 'admin', mediaId: image.id), isNull);
    });

    test('a published record without consent (inconsistent) is never chosen nor shown', () async {
      await firestore.collection(WebsiteCollections.media).doc('odd').set({
        'url': 'https://example.test/odd.jpg', 'storagePath': 'website_media/odd/x.jpg', 'status': 'published', 'consentConfirmed': false,
        'alt': {'en': 'x'}, 'caption': {'en': ''},
      });
      await expectLater(show(image: () => 'odd'), throwsA(isA<WebsiteContentException>()));
      expect((await WebsiteContentRepository(firestore: firestore).publishedMedia()).where((m) => m.id == 'odd'), isEmpty);
    });
  });

  // -------------------------------------------------- images: calendar dialog

  group('event images (calendar dialog)', () {
    late FakeFirebaseFirestore firestore;
    late WebsiteContentAdminService media;
    late CalendarWebsitePublisher publisher;
    late CalendarService calendar;

    setUp(() async {
      firestore = FakeFirebaseFirestore();
      media = WebsiteContentAdminService(firestore: firestore, storage: MockFirebaseStorage(), imageProcessor: _FakeProcessor(), filePicker: _Picker());
      calendar = CalendarService(firestore: firestore);
      publisher = CalendarWebsitePublisher(calendar: calendar, media: media);
      await firestore.collection(WebsiteCollections.media).doc('pub1').set({
        'url': _published.url, 'thumbUrl': _published.thumbUrl, 'storagePath': _published.storagePath, 'thumbStoragePath': _published.thumbStoragePath,
        'status': 'published', 'consentConfirmed': true, 'inGallery': false, 'alt': {'en': 'Children at the open day'}, 'caption': {'en': ''},
      });
      await firestore.collection('school_calendar_events').doc('ev1').set({
        'title': 'Open Day', 'date': DateTime(2027, 2, 14), 'startTime': '09:00', 'endTime': '12:00', 'eventType': CalendarEventType.event,
        'description': 'Tour the classrooms.', 'location': 'School hall', 'audience': 'Public', 'status': CalendarEventStatus.published,
        'createdBy': 'creator-0001', 'createdByName': 'Synthetic Creator',
      });
      await publisher.show(requesterRole: 'admin', event: CalendarEventModel.fromMap('ev1', (await firestore.collection('school_calendar_events').doc('ev1').get()).data()!), approvedForWebsite: true);
    });

    Future<Map<String, dynamic>> copy() async => (await firestore.collection(WebsitePublicItem.collection).doc('event_ev1').get()).data()!;

    Future<void> openEdit(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [currentUserProvider.overrideWith((ref) => _admin)],
        child: MaterialApp(home: Scaffold(body: CalendarView(service: calendar, websitePublisher: publisher))),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('List'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
    }

    String status(WidgetTester tester) => tester.widget<Text>(find.descendant(of: find.byKey(const Key('calendar-website-image-status')), matching: find.byType(Text))).data!;

    Future<void> tapKey(WidgetTester tester, String key) async {
      await tester.ensureVisible(find.byKey(Key(key)));
      await tester.tap(find.byKey(Key(key)));
      await tester.pumpAndSettle();
    }

    testWidgets('choose a published image: preview and “Published”; saving associates it; remove takes it off', (tester) async {
      await openEdit(tester);
      expect(status(tester), 'No image');
      await tapKey(tester, 'calendar-website-image-choose');
      await tester.tap(find.byKey(const Key('website-choose-pub1')));
      await tester.pumpAndSettle();
      expect(status(tester), 'Published');
      expect(find.byKey(const Key('calendar-website-image-preview')), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect((await copy())['imageMediaId'], 'pub1');
      expect(find.text('Calendar item saved and updated on the public website.'), findsOneWidget);

      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      expect(status(tester), 'Published');
      await tapKey(tester, 'calendar-website-image-remove');
      expect(status(tester), 'No image');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect((await copy()).containsKey('imageMediaId'), isFalse);
    });

    testWidgets('upload: one draft in the library, opened in its editor; not yet published, so saving says so and changes nothing', (tester) async {
      await openEdit(tester);
      final before = (await firestore.collection(WebsiteCollections.media).get()).docs.length;
      await tapKey(tester, 'calendar-website-image-upload');
      expect(find.byType(WebsiteMediaEditorScreen), findsOneWidget, reason: 'the library’s own alt text, consent and publish steps');
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await tester.pumpAndSettle();

      expect((await firestore.collection(WebsiteCollections.media).get()).docs.length, before + 1, reason: 'one upload');
      expect(status(tester), 'Uploaded');
      expect(find.byKey(const Key('calendar-website-image-edit')), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(find.textContaining('the public website wasn’t changed: Publish the chosen image first'), findsOneWidget);
      expect(find.textContaining('updated on the public website'), findsNothing);
      expect((await copy()).containsKey('imageMediaId'), isFalse);
    });

    testWidgets('an image that has since been hidden or withdrawn: “Unavailable”, with what to do', (tester) async {
      await firestore.collection(WebsitePublicItem.collection).doc('event_ev1').update({'imageMediaId': 'pub1'});
      await firestore.collection(WebsiteCollections.media).doc('pub1').update({'status': 'hidden', 'consentConfirmed': false});
      await openEdit(tester);
      expect(status(tester), 'Unavailable');
      expect(tester.widget<Text>(find.byKey(const Key('calendar-website-image-detail'))).data, contains('consent was withdrawn'));
      expect(find.byKey(const Key('calendar-website-image-remove')), findsOneWidget);
    });

    testWidgets('an image deleted from the library: “Unavailable — no longer exists”', (tester) async {
      await firestore.collection(WebsitePublicItem.collection).doc('event_ev1').update({'imageMediaId': 'gone'});
      await openEdit(tester);
      expect(status(tester), 'Unavailable');
      expect(tester.widget<Text>(find.byKey(const Key('calendar-website-image-detail'))).data, 'This image no longer exists. Choose another, or remove it.');
    });

    testWidgets('Approved (consent confirmed, not published) is told apart from Uploaded', (tester) async {
      await firestore.collection(WebsiteCollections.media).doc('pub1').update({'status': 'draft'});
      await firestore.collection(WebsitePublicItem.collection).doc('event_ev1').update({'imageMediaId': 'pub1'});
      await openEdit(tester);
      expect(status(tester), 'Approved');
    });
  });

  // ------------------------------------------------------ images: public

  group('event images (public)', () {
    late FakeFirebaseFirestore firestore;

    setUp(() async {
      firestore = FakeFirebaseFirestore();
      for (final (id, status, consent) in [('pub1', 'published', true), ('draft1', 'draft', true), ('withdrawn1', 'hidden', false)]) {
        await firestore.collection(WebsiteCollections.media).doc(id).set({
          'url': 'https://example.test/$id.jpg', 'storagePath': 'website_media/$id/123_display.jpg', 'thumbStoragePath': 'website_media/$id/123_thumb.jpg',
          'status': status, 'consentConfirmed': consent, 'inGallery': false, 'alt': {'en': 'Alt $id'}, 'caption': {'en': ''},
        });
      }
      for (final (id, image) in [('a', 'pub1'), ('b', 'draft1'), ('c', 'withdrawn1'), ('d', 'gone')]) {
        await firestore.collection(WebsitePublicItem.collection).doc('event_$id').set(_item(id, image: image).toMap());
      }
    });

    Future<void> pumpApp(WidgetTester tester, String route) async {
      tester.view.physicalSize = const Size(1200, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          authStateProvider.overrideWith((ref) => Stream.value(null)),
          websiteContentRepositoryProvider.overrideWithValue(WebsiteContentRepository(firestore: firestore)),
          publicClockProvider.overrideWithValue(() => _now),
        ],
        child: const MontessoriApp(),
      ));
      await tester.pumpAndSettle();
      tester.state<NavigatorState>(find.byType(Navigator).first).pushNamed(route);
      await tester.pumpAndSettle();
    }

    /// Every string the page shows or reads out.
    String everything(WidgetTester tester) => [
          for (final t in tester.widgetList<Text>(find.byType(Text))) t.data ?? t.textSpan?.toPlainText() ?? '',
          for (final s in tester.widgetList<Semantics>(find.byType(Semantics))) s.properties.label ?? '',
        ].join('\n');

    for (final (id, shows) in [('a', true), ('b', false), ('c', false), ('d', false)]) {
      testWidgets('details page ${shows ? 'shows the approved image' : 'hides an unapproved, withdrawn or missing image'} ($id)', (tester) async {
        await pumpApp(tester, '/events/$id');
        expect(find.byKey(const Key('public-event-details')), findsOneWidget, reason: 'the event itself is fine');
        expect(find.byKey(const Key('public-event-image')), shows ? findsOneWidget : findsNothing);
        expect(everything(tester), isNot(contains('website_media/')), reason: 'no storage path anywhere');
        expect(find.text('The whole description.'), findsOneWidget, reason: 'the full description stays on the details page');
      });
    }

    testWidgets('cards show only the approved image; nothing breaks for the others', (tester) async {
      await _pumpFeed(tester, _feed(), [for (final id in ['a', 'b', 'c', 'd']) _item(id, image: (await firestore.collection(WebsitePublicItem.collection).doc('event_$id').get()).data()!['imageMediaId'] as String)],
          media: await WebsiteContentRepository(firestore: firestore).publishedMedia());
      expect(_imageIn('a'), findsWidgets);
      for (final id in ['b', 'c', 'd']) {
        expect(find.byKey(Key('public-event-event_$id')), findsOneWidget);
        expect(_imageIn(id), findsNothing, reason: id);
      }
      expect(tester.takeException(), isNull);
    });
  });
}
