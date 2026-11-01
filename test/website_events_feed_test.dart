// The Upcoming events block: calendar events an admin has shown on the
// website, read from their public copies only, upcoming first, at school
// time, in the visitor's language.
//
// Every record here is synthetic test data. The fake Firestore proves the
// app's behaviour, not deployed security rules (deferred).

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/admin/website/data/website_content_admin_service.dart';
import 'package:montessori_app/modules/admin/website/ui/page_builder/website_block_editor.dart';
import 'package:montessori_app/modules/auth/models/app_user.dart';
import 'package:montessori_app/modules/public_website/content/blocks/block_registry.dart';
import 'package:montessori_app/modules/public_website/content/blocks/section_presets.dart';
import 'package:montessori_app/modules/public_website/content/blocks/website_block.dart';
import 'package:montessori_app/modules/public_website/content/built_in_pages.dart';
import 'package:montessori_app/modules/public_website/content/website_content_models.dart';
import 'package:montessori_app/modules/public_website/content/website_content_repository.dart';
import 'package:montessori_app/modules/public_website/content/website_public_events.dart';
import 'package:montessori_app/modules/public_website/content/website_public_item.dart';
import 'package:montessori_app/modules/public_website/public_strings.dart';
import 'package:montessori_app/modules/public_website/widgets/blocks/public_events_feed.dart';
import 'package:montessori_app/modules/public_website/widgets/blocks/website_blocks_view.dart';

/// "Now" for every test: 1 February 2027, 10:00 at school (IST).
final _now = DateTime.utc(2027, 2, 1, 4, 30);

/// [hour]:[minute] at school (IST) on [day] February 2027, as an instant.
DateTime _ist(int day, [int hour = 0, int minute = 0]) => DateTime.utc(2027, 2, day, hour, minute).subtract(const Duration(hours: 5, minutes: 30));

WebsitePublicItem _event(
  String id, {
  required DateTime start,
  DateTime? end,
  bool allDay = false,
  LocalizedText? title,
  LocalizedText body = const LocalizedText(en: 'Something for everyone.'),
  LocalizedText location = const LocalizedText(en: 'School hall'),
  String? image,
  DateTime? expireAt,
  WebsitePublicItemKind kind = WebsitePublicItemKind.event,
  String schoolId = WebsitePublicItem.defaultSchoolId,
}) =>
    WebsitePublicItem(
      kind: kind,
      sourceId: id,
      title: title ?? LocalizedText(en: 'Event $id'),
      body: body,
      location: location,
      startAt: start,
      endAt: end,
      allDay: allDay,
      imageMediaId: image,
      expireAt: expireAt,
      schoolId: schoolId,
    );

StructuredBlock _feed({
  String maxItems = '6',
  String layout = 'list',
  String desktop = '3',
  String tablet = '2',
  String mobile = '1',
  bool showImages = true,
  LocalizedText heading = const LocalizedText(en: 'Upcoming events'),
}) {
  final b = BlockRegistry.create(BlockRegistry.eventsFeed);
  return b.copyWith(values: {
    ...b.values,
    'heading': heading,
    'maxItems': maxItems,
    'layout': layout,
    'desktopColumns': desktop,
    'tabletColumns': tablet,
    'mobileColumns': mobile,
    'showImages': showImages,
  });
}

const _media = WebsiteMedia(
  id: 'm1',
  url: 'https://example.test/m1.jpg',
  storagePath: 'website_media/m1/d.jpg',
  alt: LocalizedText(en: 'Children on stage'),
  status: WebsiteMediaStatus.published,
  consentConfirmed: true,
);

Future<void> _pumpFeed(
  WidgetTester tester, {
  required List<Override> overrides,
  StructuredBlock? block,
  PublicLanguage language = PublicLanguage.english,
  bool interactive = true,
  double width = 1000,
}) async {
  tester.view.physicalSize = Size(width, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  // A fresh scope each time, so these overrides apply.
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(ProviderScope(
    overrides: [publicClockProvider.overrideWithValue(() => _now), ...overrides],
    child: MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: WebsiteBlocksView(blocks: [block ?? _feed()], media: const {}, language: language, interactive: interactive),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

List<Override> _items(List<WebsitePublicItem> items, {List<WebsiteMedia> media = const []}) => [
      publicEventItemsProvider.overrideWith((ref) async => items),
      publishedWebsiteMediaProvider.overrideWith((ref) async => media),
    ];

String _text(WidgetTester tester, String key) => tester.widget<Text>(find.byKey(Key(key))).data!;

void main() {
  // ---------------------------------------------------------- the block

  group('block', () {
    test('registered: addable everywhere, valid as created, with practical defaults', () {
      expect(BlockRegistry.definition('events_feed'), same(BlockRegistry.eventsFeed));
      expect(BlockRegistry.all, contains(BlockRegistry.eventsFeed));
      expect(BlockRegistry.nestable, contains(BlockRegistry.eventsFeed), reason: 'it can go inside a section or columns');
      final block = BlockRegistry.create(BlockRegistry.eventsFeed);
      expect(BlockRegistry.validate([block]), isEmpty);
      expect(block.string('maxItems'), '6');
      expect(block.string('layout'), 'grid');
      expect([block.string('desktopColumns'), block.string('tabletColumns'), block.string('mobileColumns')], ['3', '2', '1']);
      expect(block.flag('showImages'), isTrue);
      expect(BlockRegistry.eventsFeed.styleKeys, containsAll(['background', 'spacing', 'width']));
    });

    test('stored and read back; translations and unknown fields kept; bad options reported; a newer version kept unchanged', () {
      final raw = {
        'id': 'b_events00001', 'type': 'events_feed', 'v': 1, 'maxItems': '3', 'layout': 'compact_cards', 'showImages': false,
        'heading': {'en': 'What’s on', 'ta': 'நிகழ்வுகள்', 'hi': 'कार्यक्रम'}, 'futureKey': 1,
      };
      final block = BlockRegistry.parse(raw) as StructuredBlock;
      expect(BlockRegistry.validate([block]), isEmpty);
      final stored = block.toMap();
      expect(stored['heading'], {'en': 'What’s on', 'ta': 'நிகழ்வுகள்', 'hi': 'कार्यक्रम'});
      expect(stored['futureKey'], 1);
      expect(stored['maxItems'], '3');

      final bad = BlockRegistry.parse({...raw, 'maxItems': '500', 'layout': 'carousel', 'desktopColumns': '5', 'mobileColumns': '3'}) as StructuredBlock;
      expect(BlockRegistry.blockProblems(bad), containsAll([
        '“500” is not a events shown at most option',
        '“carousel” is not a layout option',
        '“5” is not a columns on desktop option',
        '“3” is not a columns on phones option',
      ]));
      expect(BlockRegistry.parse({...raw, 'v': 2}), isA<UnsupportedBlock>());
    });

    test('Events section preset: valid, holding the block with a heading; every preset still valid', () {
      final preset = SectionPreset.byId('events')!;
      final section = preset.create();
      expect(BlockRegistry.validate([section]), isEmpty);
      final feed = BlockRegistry.flatten([section]).whereType<StructuredBlock>().singleWhere((b) => b.type == 'events_feed');
      expect(feed.text('heading').en, 'Upcoming events');
      for (final p in SectionPreset.all) {
        expect(BlockRegistry.validate([p.create()]), isEmpty, reason: p.id);
      }
    });

    testWidgets('editor: heading, number of events, layout, columns and images can be set', (tester) async {
      var block = _feed();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: StatefulBuilder(
              builder: (context, setState) => WebsiteBlockForm(
                block: block,
                library: const [],
                generation: 0,
                onChanged: (b) => setState(() => block = b as StructuredBlock),
              ),
            ),
          ),
        ),
      ));
      final prefix = 'website-block-${block.id}';
      expect(find.textContaining('Heading'), findsWidgets);
      await tester.tap(find.byKey(Key('$prefix-maxItems')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('$prefix-maxItems-3')).last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('$prefix-layout')));
      await tester.pumpAndSettle();
      expect(find.text('Compact cards'), findsWidgets, reason: 'options have readable names');
      await tester.tap(find.byKey(Key('$prefix-layout-compact_cards')).last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(Key('$prefix-desktopColumns')));
      await tester.tap(find.byKey(Key('$prefix-desktopColumns')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('$prefix-desktopColumns-4')).last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(Key('$prefix-mobileColumns')));
      await tester.tap(find.byKey(Key('$prefix-mobileColumns')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('$prefix-mobileColumns-2')).last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('$prefix-showImages')));
      await tester.pumpAndSettle();
      expect(block.string('maxItems'), '3');
      expect(block.string('layout'), 'compact_cards');
      expect(block.string('desktopColumns'), '4');
      expect(block.string('mobileColumns'), '2');
      expect(block.flag('showImages'), isFalse);
      expect(BlockRegistry.validate([block]), isEmpty);
    });
  });

  // ----------------------------------------------------- which are shown

  group('upcoming events', () {
    List<String> ids(Iterable<WebsitePublicItem> items, {int limit = 20}) => [for (final i in upcomingPublicEvents(items, now: _now, limit: limit)) i.sourceId];

    test('soonest first, ties by title, at most the limit', () {
      final items = [
        _event('c', start: _ist(20, 9)),
        _event('a', start: _ist(5, 9)),
        _event('b2', start: _ist(10, 9), title: const LocalizedText(en: 'Beta')),
        _event('b1', start: _ist(10, 9), title: const LocalizedText(en: 'Alpha')),
      ];
      expect(ids(items), ['a', 'b1', 'b2', 'c']);
      expect(ids(items, limit: 2), ['a', 'b1']);
      expect(ids(items, limit: 0), isEmpty);
    });

    test('past events leave: with an end, when it ends; otherwise at the end of their school day', () {
      final items = [
        _event('ended', start: _ist(1, 8), end: _ist(1, 9, 30)),
        _event('ongoing', start: _ist(1, 9), end: _ist(1, 11)),
        _event('earlierToday', start: _ist(1, 8)),
        _event('allDayToday', start: _ist(1), allDay: true),
        _event('allDayYesterday', start: _ist(0) /* 31 January */, allDay: true),
        _event('yesterdayEvening', start: _ist(0, 21)),
        _event('tomorrow', start: _ist(2), allDay: true),
      ];
      expect(ids(items), ['allDayToday', 'earlierToday', 'ongoing', 'tomorrow']);
    });

    test('an all-day event stays until midnight at school, not in UTC or the visitor’s zone', () {
      final today = _event('today', start: _ist(1), allDay: true);
      // 23:59 at school is 18:29 UTC: still today at school.
      expect(upcomingPublicEvents([today], now: _ist(1, 23, 59), limit: 5), hasLength(1));
      expect(upcomingPublicEvents([today], now: _ist(2), limit: 5), isEmpty);
    });

    test('expired items, announcements, other schools and malformed items are left out', () {
      final items = [
        _event('ok', start: _ist(3, 9)),
        _event('expired', start: _ist(3, 9), expireAt: _ist(1, 9)),
        _event('notice', start: _ist(3, 9), kind: WebsitePublicItemKind.announcement),
        _event('elsewhere', start: _ist(3, 9), schoolId: 'other_school'),
        _event('endsBeforeStart', start: _ist(3, 9), end: _ist(3, 8)),
        _event('noTitle', start: _ist(3, 9), title: const LocalizedText()),
      ];
      expect(ids(items), ['ok']);
    });
  });

  // ------------------------------------------------------- dates, times

  group('dates and times at school time', () {
    test('a timed event, in English (12-hour) and Tamil (24-hour)', () {
      final item = _event('e', start: _ist(14, 9, 30), end: _ist(14, 12));
      final en = PublicEventDateText(item, PublicLanguage.english);
      expect(en.date, 'Sun 14 February 2027');
      expect(en.time, '9:30 AM – 12:00 PM IST');
      expect(en.dayOfMonth, 14);
      expect(en.monthShort, 'Feb');
      final ta = PublicEventDateText(item, PublicLanguage.tamil);
      expect(ta.date, 'ஞாயிறு 14 பிப்ரவரி 2027');
      expect(ta.time, '09:30 – 12:00 IST');
    });

    test('an all-day event shows its date and "All day", never midnight', () {
      final item = _event('e', start: _ist(14), allDay: true);
      expect(PublicEventDateText(item, PublicLanguage.english).time, 'All day');
      expect(PublicEventDateText(item, PublicLanguage.tamil).time, 'நாள் முழுவதும்');
      expect(PublicEventDateText(item, PublicLanguage.english).date, 'Sun 14 February 2027');
    });

    test('a start without an end; an end on another day; late evening stays on its school date', () {
      expect(PublicEventDateText(_event('e', start: _ist(14, 18, 45)), PublicLanguage.english).time, '6:45 PM IST');
      expect(PublicEventDateText(_event('e', start: _ist(14, 0, 5)), PublicLanguage.english).time, '12:05 AM IST');
      expect(PublicEventDateText(_event('e', start: _ist(14, 18), end: _ist(15, 10)), PublicLanguage.english).time,
          '6:00 PM – Mon 15 February 2027, 10:00 AM IST');
      // 23:30 at school is 18:00 UTC the same day, but 14 Feb 23:30 IST is
      // still the 14th whatever the device's zone.
      expect(PublicEventDateText(_event('e', start: _ist(14, 23, 30)), PublicLanguage.english).date, 'Sun 14 February 2027');
    });

    test('another language: dates in its fallback strings (English)', () {
      const hindi = PublicLanguage('hi', nativeName: 'हिन्दी', englishName: 'Hindi');
      expect(PublicEventDateText(_event('e', start: _ist(14), allDay: true), hindi).date, 'Sun 14 February 2027');
    });
  });

  // -------------------------------------------------------- the feed UI

  group('feed', () {
    testWidgets('list: heading, upcoming events in order with title, text, date, time and location', (tester) async {
      await _pumpFeed(tester, overrides: _items([
        _event('later', start: _ist(20, 9, 30), end: _ist(20, 12)),
        _event('past', start: _ist(1, 7), end: _ist(1, 8)),
        _event('soon', start: _ist(5), allDay: true, location: const LocalizedText()),
      ]));
      expect(find.text('Upcoming events'), findsOneWidget);
      expect(find.byKey(const Key('public-events-list')), findsOneWidget);
      expect(find.byKey(const Key('public-event-event_past')), findsNothing);
      final soon = tester.getTopLeft(find.byKey(const Key('public-event-event_soon'))).dy;
      final later = tester.getTopLeft(find.byKey(const Key('public-event-event_later'))).dy;
      expect(soon, lessThan(later));
      expect(_text(tester, 'public-event-title-event_later'), 'Event later');
      expect(find.byKey(const Key('public-event-body-event_later')), findsNothing, reason: 'previews never show the description');
      expect(find.text('Something for everyone.'), findsNothing);
      expect(_text(tester, 'public-event-date-event_later'), 'Sat 20 February 2027');
      expect(_text(tester, 'public-event-time-event_later'), '9:30 AM – 12:00 PM IST');
      expect(_text(tester, 'public-event-location-event_later'), 'School hall');
      expect(_text(tester, 'public-event-time-event_soon'), 'All day');
      expect(find.byKey(const Key('public-event-location-event_soon')), findsNothing, reason: 'no location, no line');
    });

    testWidgets('the configured maximum, and cards', (tester) async {
      final items = [for (var d = 2; d <= 9; d++) _event('d$d', start: _ist(d, 9))];
      await _pumpFeed(tester, overrides: _items(items), block: _feed(maxItems: '3', layout: 'grid'));
      expect(find.byKey(const Key('public-events-grid')), findsOneWidget);
      expect(find.byKey(const Key('public-event-event_d2')), findsOneWidget);
      expect(find.byKey(const Key('public-event-event_d4')), findsOneWidget);
      expect(find.byKey(const Key('public-event-event_d5')), findsNothing);
    });

    testWidgets('empty: “No upcoming events.” (in Tamil too)', (tester) async {
      await _pumpFeed(tester, overrides: _items([_event('past', start: _ist(1, 7), end: _ist(1, 8))]));
      expect(find.byKey(const Key('public-events-empty')), findsOneWidget);
      expect(find.text('No upcoming events.'), findsOneWidget);
      await _pumpFeed(tester, overrides: _items(const []), language: PublicLanguage.tamil);
      expect(find.text(PublicStrings.of(PublicLanguage.tamil).eventsEmpty), findsOneWidget);
    });

    testWidgets('loading, then the events', (tester) async {
      final completer = Completer<List<WebsitePublicItem>>();
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          publicClockProvider.overrideWithValue(() => _now),
          publicEventItemsProvider.overrideWith((ref) => completer.future),
          publishedWebsiteMediaProvider.overrideWith((ref) async => const <WebsiteMedia>[]),
        ],
        child: MaterialApp(home: Scaffold(body: WebsiteBlocksView(blocks: [_feed()], media: const {}, language: PublicLanguage.english))),
      ));
      await tester.pump();
      expect(find.byKey(const Key('public-events-loading')), findsOneWidget);
      completer.complete([_event('soon', start: _ist(3, 9))]);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('public-events-loading')), findsNothing);
      expect(find.byKey(const Key('public-event-event_soon')), findsOneWidget);
    });

    testWidgets('error: a message and Try again, which reloads', (tester) async {
      var fail = true;
      await _pumpFeed(tester, overrides: [
        publicEventItemsProvider.overrideWith((ref) async {
          if (fail) throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
          return [_event('soon', start: _ist(3, 9))];
        }),
        publishedWebsiteMediaProvider.overrideWith((ref) async => const <WebsiteMedia>[]),
      ]);
      expect(find.byKey(const Key('public-events-error')), findsOneWidget);
      expect(find.text('Events could not be loaded'), findsOneWidget);
      fail = false;
      await tester.tap(find.byKey(const Key('public-events-retry')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('public-event-event_soon')), findsOneWidget);
    });

    testWidgets('languages: Tamil when entered, otherwise the established fallback (fallback language, then English)', (tester) async {
      final items = [
        _event('both', start: _ist(3, 9), title: const LocalizedText(en: 'Annual Day', ta: 'ஆண்டு விழா'), body: const LocalizedText(en: 'Performances.', ta: 'நிகழ்ச்சிகள்.')),
        _event('english', start: _ist(4, 9), title: const LocalizedText(en: 'Sports Day')),
      ];
      final block = _feed(heading: const LocalizedText(en: 'Upcoming events', ta: 'வரவிருக்கும் நிகழ்வுகள்'));
      await _pumpFeed(tester, overrides: _items(items), block: block, language: PublicLanguage.tamil);
      expect(find.text('வரவிருக்கும் நிகழ்வுகள்'), findsOneWidget);
      expect(_text(tester, 'public-event-title-event_both'), 'ஆண்டு விழா');
      expect(find.text('நிகழ்ச்சிகள்.'), findsNothing, reason: 'previews never show the description');
      expect(_text(tester, 'public-event-title-event_english'), 'Sports Day', reason: 'no Tamil: English');
      expect(_text(tester, 'public-event-date-event_both'), 'புதன் 3 பிப்ரவரி 2027');

      const hindiViaTamil = PublicLanguage('hi', nativeName: 'हिन्दी', englishName: 'Hindi', fallbackCode: 'ta');
      await _pumpFeed(tester, overrides: _items(items), block: block, language: hindiViaTamil);
      expect(_text(tester, 'public-event-title-event_both'), 'ஆண்டு விழா', reason: 'its fallback language');
      expect(_text(tester, 'public-event-title-event_english'), 'Sports Day');

      await _pumpFeed(tester, overrides: _items(items), block: block);
      expect(_text(tester, 'public-event-title-event_both'), 'Annual Day');
    });

    testWidgets('images: only a published website image; a missing one is left out; can be turned off', (tester) async {
      final items = [
        _event('pictured', start: _ist(3, 9), image: 'm1'),
        _event('missing', start: _ist(4, 9), image: 'gone'),
        _event('none', start: _ist(5, 9)),
      ];
      Finder imageIn(String id) => find.descendant(of: find.byKey(Key('public-event-event_$id')), matching: find.byType(Image));
      await _pumpFeed(tester, overrides: _items(items, media: [_media]));
      expect(imageIn('pictured'), findsWidgets);
      expect(imageIn('missing'), findsNothing);
      expect(imageIn('none'), findsNothing);
      expect(find.byKey(const Key('public-event-event_missing')), findsOneWidget, reason: 'the event itself is still shown');

      await _pumpFeed(tester, overrides: _items(items, media: [_media]), block: _feed(showImages: false));
      expect(imageIn('pictured'), findsNothing);
    });

    testWidgets('narrow screens: list and cards fit', (tester) async {
      final items = [
        _event('long', start: _ist(3, 9), end: _ist(4, 17), image: 'm1', title: LocalizedText(en: 'A very long event title ' * 4), location: LocalizedText(en: 'Somewhere ' * 10)),
      ];
      for (final layout in ['list', 'grid', 'compact_cards']) {
        await _pumpFeed(tester, overrides: _items(items, media: [_media]), block: _feed(layout: layout, mobile: '2'), width: 360);
        expect(tester.takeException(), isNull, reason: layout);
        expect(find.byKey(const Key('public-event-event_long')), findsOneWidget, reason: layout);
      }
    });

    testWidgets('the editor canvas (not interactive) shows the same feed', (tester) async {
      await _pumpFeed(tester, overrides: _items([_event('soon', start: _ist(3, 9))]), interactive: false);
      expect(find.byKey(const Key('public-event-event_soon')), findsOneWidget);
    });
  });

  // ------------------------------------------------- data from Firestore

  group('reading', () {
    late FakeFirebaseFirestore firestore;
    setUp(() => firestore = FakeFirebaseFirestore());

    Future<void> addItem(WebsitePublicItem item, {Map<String, dynamic> extra = const {}}) =>
        firestore.collection(WebsitePublicItem.collection).doc(item.id).set({...item.toMap(), ...extra});

    testWidgets('only the public copies are read: never the calendar or announcements', (tester) async {
      await addItem(_event('shown', start: _ist(3, 9)));
      // An internal event and announcement that look eligible but were never
      // shown on the website.
      await firestore.collection('school_calendar_events').doc('internal').set({
        'title': 'Internal event', 'date': Timestamp.fromDate(_ist(3)), 'audience': 'Public', 'status': 'Published',
      });
      await firestore.collection('school_notifications').doc('notice').set({'title': 'Internal notice', 'audience': 'Public', 'status': 'Published'});
      // Reading anything but the website's own collections fails.
      firestore.securityRules = FakeFirebaseFirestore(securityRules: '''
service cloud.firestore {
  match /databases/{database}/documents {
    match /${WebsitePublicItem.collection}/{id} { allow read: if true; }
    match /${WebsiteCollections.media}/{id} { allow read: if true; }
  }
}''').securityRules;
      await expectLater(firestore.collection('school_calendar_events').get(), throwsA(anything), reason: 'the rules really refuse it');

      await _pumpFeed(tester, overrides: [websiteContentRepositoryProvider.overrideWithValue(WebsiteContentRepository(firestore: firestore))]);
      expect(find.byKey(const Key('public-events-error')), findsNothing);
      expect(find.byKey(const Key('public-event-event_shown')), findsOneWidget);
      expect(find.text('Internal event'), findsNothing);
      expect(find.text('Internal notice'), findsNothing);
    });

    test('malformed and incomplete documents are skipped; private fields never read; announcements not listed', () async {
      await addItem(_event('good', start: _ist(3, 9)), extra: {'createdByName': 'Synthetic Creator'});
      await addItem(_event('notice', start: _ist(3, 9), kind: WebsitePublicItemKind.announcement));
      final col = firestore.collection(WebsitePublicItem.collection);
      await col.doc('event_noTitle').set({'kind': 'event', 'sourceCollection': 'school_calendar_events', 'sourceId': 'noTitle', 'startAt': Timestamp.fromDate(_ist(3))});
      await col.doc('event_badStart').set({'kind': 'event', 'sourceCollection': 'school_calendar_events', 'sourceId': 'badStart', 'title': {'en': 'X'}, 'startAt': 'tomorrow'});
      await col.doc('event_wrongSource').set({'kind': 'event', 'sourceCollection': 'school_notifications', 'sourceId': 'x', 'title': {'en': 'X'}, 'startAt': Timestamp.fromDate(_ist(3))});
      await col.doc('event_badTitle').set({'kind': 'event', 'sourceCollection': 'school_calendar_events', 'sourceId': 'badTitle', 'title': 'plain', 'startAt': Timestamp.fromDate(_ist(3))});

      final events = await WebsiteContentRepository(firestore: firestore).publicEvents();
      expect(events.map((e) => e.sourceId), ['good']);
    });
  });

  // ------------------------------------------------ publishing safeguards

  group('publishing a page with the block', () {
    late FakeFirebaseFirestore firestore;
    late WebsiteContentAdminService service;
    final admin = AppUser(id: '9000000002', phone: '9000000002', role: 'admin', isActive: true, name: 'Test admin');

    setUp(() {
      firestore = FakeFirebaseFirestore();
      service = WebsiteContentAdminService(firestore: firestore, storage: MockFirebaseStorage());
    });

    test('a page of only an Events section publishes; the block itself is stored, never any event', () async {
      final section = SectionPreset.byId('events')!.create();
      await service.publishBuiltInPage(requesterRole: 'admin', actor: admin, page: BuiltInPage.admissions, blocks: [section]);
      final live = (await firestore.collection(WebsiteCollections.livePages).doc(BuiltInPage.admissions.id).get()).data()!;
      final stored = BlockRegistry.parseList(live['blocks']);
      final feed = BlockRegistry.flatten(stored).whereType<StructuredBlock>().singleWhere((b) => b.type == 'events_feed');
      expect(feed.string('maxItems'), '6');
      expect(live.toString(), isNot(contains('school_calendar_events')));
    });

    test('a hidden Events block is not visible content, and is left out of the live page', () async {
      final hidden = _feed().copyWith(hidden: true);
      await expectLater(
        service.publishBuiltInPage(requesterRole: 'admin', actor: admin, page: BuiltInPage.admissions, blocks: [hidden]),
        throwsA(isA<WebsiteContentException>().having((e) => e.message, 'message', WebsiteContentAdminService.nothingVisibleMessage)),
      );
      final text = BlockRegistry.create(BlockRegistry.text);
      final visible = text.copyWith(values: {...text.values, 'heading': const LocalizedText(en: 'Hello')});
      await service.publishBuiltInPage(requesterRole: 'admin', actor: admin, page: BuiltInPage.admissions, blocks: [visible, hidden]);
      final live = (await firestore.collection(WebsiteCollections.livePages).doc(BuiltInPage.admissions.id).get()).data()!;
      expect(BlockRegistry.parseList(live['blocks']).map((b) => b.type), ['text']);
      final draft = (await firestore.collection(WebsiteCollections.pageDrafts).doc(BuiltInPage.admissions.id).get()).data()!;
      expect(BlockRegistry.parseList(draft['blocks']).map((b) => b.type), ['text', 'events_feed'], reason: 'the draft keeps it');
    });
  });
}
