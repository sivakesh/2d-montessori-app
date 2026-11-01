// Event details: an event in the Upcoming events block opens its details
// at /events/<id>, read only from its public copy.
//
// Every record here is synthetic test data. The fake Firestore proves the
// app's behaviour, not deployed security rules (deferred).

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/main.dart';
import 'package:montessori_app/modules/admin/website/data/website_content_admin_service.dart';
import 'package:montessori_app/modules/admin/website/data/website_public_items_service.dart';
import 'package:montessori_app/modules/auth/models/app_user.dart';
import 'package:montessori_app/modules/auth/providers/auth_state_provider.dart';
import 'package:montessori_app/modules/calendar/models/calendar_event_model.dart';
import 'package:montessori_app/modules/calendar/services/calendar_service.dart';
import 'package:montessori_app/modules/calendar/services/calendar_website_publisher.dart';
import 'package:montessori_app/modules/public_website/content/blocks/block_registry.dart';
import 'package:montessori_app/modules/public_website/content/blocks/website_block.dart';
import 'package:montessori_app/modules/public_website/content/built_in_pages.dart';
import 'package:montessori_app/modules/public_website/content/website_content_models.dart';
import 'package:montessori_app/modules/public_website/content/website_content_repository.dart';
import 'package:montessori_app/modules/public_website/content/website_public_item.dart';
import 'package:montessori_app/modules/public_website/public_routes.dart';
import 'package:montessori_app/modules/public_website/public_strings.dart';
import 'package:montessori_app/modules/public_website/widgets/blocks/website_blocks_view.dart';

/// "Now" for every test: 1 February 2027, 10:00 at school (IST).
final _now = DateTime.utc(2027, 2, 1, 4, 30);

/// [hour]:[minute] at school (IST) on [day] February 2027, as an instant.
DateTime _ist(int day, [int hour = 0, int minute = 0]) => DateTime.utc(2027, 2, day, hour, minute).subtract(const Duration(hours: 5, minutes: 30));

final _admin = AppUser(id: '9000000002', phone: '9000000002', role: 'admin', isActive: true, name: 'Test admin');

WebsitePublicItem _event(
  String id, {
  DateTime? start,
  DateTime? end,
  bool allDay = false,
  LocalizedText title = const LocalizedText(en: 'Annual Day', ta: 'ஆண்டு விழா'),
  LocalizedText body = const LocalizedText(en: 'Performances by every class.\n\nFamilies are welcome.', ta: 'ஒவ்வொரு வகுப்பின் நிகழ்ச்சிகள்.'),
  LocalizedText location = const LocalizedText(en: 'School hall'),
  String? image,
  String? registration,
  DateTime? expireAt,
}) =>
    WebsitePublicItem(
      kind: WebsitePublicItemKind.event,
      sourceId: id,
      title: title,
      body: body,
      location: location,
      startAt: start ?? _ist(14, 9, 30),
      endAt: end,
      allDay: allDay,
      imageMediaId: image,
      registrationUrl: registration,
      expireAt: expireAt,
    );

class _FailingRepository extends WebsiteContentRepository {
  _FailingRepository(FakeFirebaseFirestore firestore) : super(firestore: firestore);

  bool fail = true;

  @override
  Future<WebsitePublicItem?> publicEvent(String sourceId) async {
    if (fail) throw StateError('offline');
    return super.publicEvent(sourceId);
  }
}

void main() {
  late FakeFirebaseFirestore firestore;

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    await firestore.collection(WebsiteCollections.media).doc('m1').set({
      'url': 'https://example.test/m1.jpg',
      'storagePath': 'website_media/m1/d.jpg',
      'status': 'published',
      'consentConfirmed': true,
      'inGallery': false,
      'alt': {'en': 'Children on stage', 'ta': ''},
      'caption': {'en': '', 'ta': ''},
    });
  });

  Future<void> addItem(WebsitePublicItem item, {Map<String, dynamic> raw = const {}}) =>
      firestore.collection(WebsitePublicItem.collection).doc(item.id).set({...item.toMap(), ...raw});

  /// Publishes Programs as a page holding only an Upcoming events block.
  Future<void> publishFeedPage({String layout = 'list'}) async {
    final b = BlockRegistry.create(BlockRegistry.eventsFeed);
    final feed = b.copyWith(values: {...b.values, 'heading': const LocalizedText(en: 'Upcoming events'), 'layout': layout});
    await WebsiteContentAdminService(firestore: firestore, storage: MockFirebaseStorage())
        .publishBuiltInPage(requesterRole: 'admin', actor: _admin, page: BuiltInPage.programs, blocks: [feed]);
  }

  Future<void> pumpApp(
    WidgetTester tester, {
    String route = PublicRoutes.programs,
    PublicLanguage language = PublicLanguage.english,
    WebsiteContentRepository? repository,
    Size size = const Size(1200, 1600),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authStateProvider.overrideWith((ref) => Stream.value(null)),
        websiteContentRepositoryProvider.overrideWithValue(repository ?? WebsiteContentRepository(firestore: firestore)),
        publicClockProvider.overrideWithValue(() => _now),
        publicLanguageProvider.overrideWith((ref) => language),
      ],
      child: const MontessoriApp(),
    ));
    await tester.pumpAndSettle();
    if (route != PublicRoutes.home) {
      tester.state<NavigatorState>(find.byType(Navigator).first).pushNamed(route);
      await tester.pumpAndSettle();
    }
  }

  String text(WidgetTester tester, String key) => tester.widget<Text>(find.byKey(Key(key))).data!;
  String? currentRoute(WidgetTester tester) => ModalRoute.of(tester.element(find.byType(Scaffold).last))?.settings.name;

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  // -------------------------------------------------------------- opening

  group('opening an event', () {
    testWidgets('a list item opens its details at a stable address; Back returns to the list', (tester) async {
      await addItem(_event('Ev1abc', end: _ist(14, 12)));
      await publishFeedPage();
      await pumpApp(tester);

      await tap(tester, find.byKey(const Key('public-event-open-event_Ev1abc')));
      expect(find.byKey(const Key('public-event-details')), findsOneWidget);
      expect(currentRoute(tester), '/events/Ev1abc', reason: 'the id keeps its case');

      await tap(tester, find.byKey(const Key('public-event-back')));
      expect(find.byKey(const Key('public-event-details')), findsNothing);
      expect(find.byKey(const Key('public-event-open-event_Ev1abc')), findsOneWidget);
      expect(currentRoute(tester), PublicRoutes.programs);
    });

    testWidgets('a card opens its details too', (tester) async {
      await addItem(_event('ev1'));
      await publishFeedPage(layout: 'grid');
      await pumpApp(tester);
      await tap(tester, find.byKey(const Key('public-event-open-event_ev1')));
      expect(text(tester, 'public-event-title'), 'Annual Day');
    });

    testWidgets('keyboard: Tab reaches the event, Enter opens it; one labelled button per event', (tester) async {
      final semantics = tester.ensureSemantics();
      await addItem(_event('ev1', allDay: true, start: _ist(14)));
      await publishFeedPage();
      await pumpApp(tester);

      expect(find.bySemanticsLabel('Annual Day, Sun 14 February 2027, All day. Opens the event’s details.'), findsOneWidget);
      final target = find.byKey(const Key('public-event-open-event_ev1'));
      var reached = false;
      for (var i = 0; i < 60 && !reached; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        final focused = FocusManager.instance.primaryFocus?.context;
        reached = focused != null && find.descendant(of: target, matching: find.byWidget(focused.widget)).evaluate().isNotEmpty;
      }
      expect(reached, isTrue, reason: 'the event can be focused with the keyboard');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('public-event-details')), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('in the editor’s canvas (not interactive) events don’t open anything', (tester) async {
      final b = BlockRegistry.create(BlockRegistry.eventsFeed);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          publicClockProvider.overrideWithValue(() => _now),
          publicEventItemsProvider.overrideWith((ref) async => [_event('ev1')]),
          publishedWebsiteMediaProvider.overrideWith((ref) async => const <WebsiteMedia>[]),
        ],
        child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: WebsiteBlocksView(blocks: <WebsiteBlock>[b], media: const {}, language: PublicLanguage.english, interactive: false)))),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('public-event-event_ev1')), findsOneWidget);
      expect(find.byKey(const Key('public-event-open-event_ev1')), findsNothing);
    });
  });

  // ------------------------------------------------- previews vs details

  group('previews show no description; the details page shows all of it', () {
    const long = 'Performances by every class.\n\nFamilies are welcome.';

    for (final layout in ['list', 'grid', 'compact_cards']) {
      testWidgets('$layout: title, date, time, location and image only; opening it shows the whole description', (tester) async {
        await addItem(_event('ev1', end: _ist(14, 12), image: 'm1'));
        await publishFeedPage(layout: layout);
        await pumpApp(tester);

        expect(text(tester, 'public-event-title-event_ev1'), 'Annual Day');
        expect(text(tester, 'public-event-date-event_ev1'), 'Sun 14 February 2027');
        expect(text(tester, 'public-event-time-event_ev1'), '9:30 AM – 12:00 PM IST');
        expect(text(tester, 'public-event-location-event_ev1'), 'School hall');
        expect(find.descendant(of: find.byKey(const Key('public-event-event_ev1')), matching: find.byType(Image)), findsWidgets, reason: 'its image');
        expect(find.byKey(const Key('public-event-body-event_ev1')), findsNothing);
        expect(find.textContaining('Performances by every class.'), findsNothing);
        expect(find.textContaining('Families are welcome.'), findsNothing);

        await tap(tester, find.byKey(const Key('public-event-open-event_ev1')));
        expect(currentRoute(tester), '/events/ev1');
        expect(text(tester, 'public-event-description'), 'Performances by every class.');
        expect(find.text('Families are welcome.'), findsOneWidget);
      });
    }

    testWidgets('in Tamil too: no description in the list, the Tamil description on its page', (tester) async {
      await addItem(_event('ev1'));
      await publishFeedPage();
      await pumpApp(tester, language: PublicLanguage.tamil);
      expect(text(tester, 'public-event-title-event_ev1'), 'ஆண்டு விழா');
      expect(find.text('ஒவ்வொரு வகுப்பின் நிகழ்ச்சிகள்.'), findsNothing);
      await tap(tester, find.byKey(const Key('public-event-open-event_ev1')));
      expect(text(tester, 'public-event-description'), 'ஒவ்வொரு வகுப்பின் நிகழ்ச்சிகள்.');
    });

    testWidgets('an event without a description: the preview and its page are unchanged otherwise', (tester) async {
      await addItem(_event('ev1', body: const LocalizedText(), location: const LocalizedText()));
      await publishFeedPage();
      await pumpApp(tester);
      expect(text(tester, 'public-event-title-event_ev1'), 'Annual Day');
      expect(find.byKey(const Key('public-event-location-event_ev1')), findsNothing);
      await tap(tester, find.byKey(const Key('public-event-open-event_ev1')));
      expect(text(tester, 'public-event-title'), 'Annual Day');
      expect(find.byKey(const Key('public-event-description')), findsNothing);
    });

    test('the stored copy keeps the whole description', () async {
      await addItem(_event('ev1'));
      final stored = (await firestore.collection(WebsitePublicItem.collection).doc('event_ev1').get()).data()!;
      expect(stored['body'], {'en': long, 'ta': 'ஒவ்வொரு வகுப்பின் நிகழ்ச்சிகள்.'});
      expect((await WebsiteContentRepository(firestore: firestore).publicEvent('ev1'))!.body.en, long);
    });
  });

  // -------------------------------------------------------------- details

  group('details', () {
    testWidgets('a timed event: title, full description, date, time with IST, location and its image', (tester) async {
      await addItem(_event('ev1', end: _ist(14, 12), image: 'm1'));
      await pumpApp(tester, route: '/events/ev1');
      expect(text(tester, 'public-event-title'), 'Annual Day');
      expect(text(tester, 'public-event-date'), 'Sun 14 February 2027');
      expect(text(tester, 'public-event-time'), '9:30 AM – 12:00 PM IST');
      expect(text(tester, 'public-event-location'), 'School hall');
      expect(text(tester, 'public-event-description'), 'Performances by every class.');
      expect(find.text('Families are welcome.'), findsOneWidget, reason: 'the whole description, every paragraph');
      expect(find.byKey(const Key('public-event-image')), findsOneWidget);
      expect(find.byKey(const Key('public-event-register')), findsNothing, reason: 'no registration link');
    });

    testWidgets('an all-day event: its date and “All day”; no location or image when there are none', (tester) async {
      await addItem(_event('ev1', start: _ist(14), allDay: true, location: const LocalizedText(), image: 'not-published'));
      await pumpApp(tester, route: '/events/ev1');
      expect(text(tester, 'public-event-time'), 'All day');
      expect(text(tester, 'public-event-date'), 'Sun 14 February 2027');
      expect(find.byKey(const Key('public-event-location')), findsNothing);
      expect(find.byKey(const Key('public-event-image')), findsNothing, reason: 'only a published website image is shown');
    });

    testWidgets('Tamil: its own text, English where there is none, Tamil labels', (tester) async {
      await addItem(_event('ev1', end: _ist(14, 12), location: const LocalizedText(en: 'School hall')));
      await pumpApp(tester, route: '/events/ev1', language: PublicLanguage.tamil);
      expect(text(tester, 'public-event-title'), 'ஆண்டு விழா');
      expect(text(tester, 'public-event-description'), 'ஒவ்வொரு வகுப்பின் நிகழ்ச்சிகள்.');
      expect(text(tester, 'public-event-location'), 'School hall', reason: 'no Tamil: English');
      expect(text(tester, 'public-event-time'), '09:30 – 12:00 IST');
      expect(find.text(PublicStrings.of(PublicLanguage.tamil).eventBack), findsOneWidget);
    });

    testWidgets('a registration link that is allowed is offered and followed; one that isn’t is never offered', (tester) async {
      await addItem(_event('ev1', registration: '/admissions'));
      await addItem(_event('ev2'), raw: {'registrationUrl': 'javascript:alert(1)'});
      await pumpApp(tester, route: '/events/ev1');
      expect(find.text('Register'), findsOneWidget);
      await tap(tester, find.byKey(const Key('public-event-register')));
      expect(find.byKey(const Key('public-section-title')), findsOneWidget, reason: 'the Admissions page');
      expect(currentRoute(tester), PublicRoutes.admissions);

      await pumpApp(tester, route: '/events/ev2');
      expect(find.byKey(const Key('public-event-details')), findsOneWidget, reason: 'the event itself is fine');
      expect(find.byKey(const Key('public-event-register')), findsNothing);
    });

    testWidgets('opened directly from a shared link: Back goes Home', (tester) async {
      await addItem(_event('ev1'));
      await pumpApp(tester, route: '/events/ev1');
      await tap(tester, find.byKey(const Key('public-event-back')));
      expect(currentRoute(tester), anyOf(PublicRoutes.home, '/'));
      expect(find.byKey(const Key('public-event-details')), findsNothing);
    });
  });

  // ----------------------------------------------------------- unavailable

  group('not available', () {
    final cases = <(String, Future<void> Function(Future<void> Function(WebsitePublicItem, {Map<String, dynamic> raw}) add), String)>[
      ('withdrawn (no copy)', (add) async {}, '/events/ev1'),
      ('over', (add) => add(_event('ev1', start: _ist(1, 7), end: _ist(1, 8))), '/events/ev1'),
      ('yesterday, all day', (add) => add(_event('ev1', start: _ist(0), allDay: true)), '/events/ev1'),
      ('expired', (add) => add(_event('ev1', expireAt: _ist(1, 9))), '/events/ev1'),
      ('malformed', (add) => add(_event('ev1'), raw: {'title': 'not a map'}), '/events/ev1'),
      // An announcement stored where the event's copy would be.
      ('an announcement', (add) => add(_event('ev1'), raw: {'kind': 'announcement', 'sourceCollection': 'school_notifications'}), '/events/ev1'),
      ('an invalid id', (add) async {}, '/events/a%20b'),
      ('a deeper address', (add) => add(_event('ev1')), '/events/ev1/extra'),
      ('no id', (add) async {}, '/events/'),
    ];
    for (final (name, seed, route) in cases) {
      testWidgets('$name: a friendly message and ways back', (tester) async {
        await seed(addItem);
        await pumpApp(tester, route: route);
        expect(find.byKey(const Key('public-event-unavailable')), findsOneWidget, reason: name);
        expect(find.text('This event is not available'), findsOneWidget);
        expect(find.byKey(const Key('public-event-details')), findsNothing);
        await tap(tester, find.byKey(const Key('public-back-home')));
        expect(find.byKey(const Key('public-event-unavailable')), findsNothing);
      });
    }

    testWidgets('loading fails: an error with Try again, which loads it', (tester) async {
      await addItem(_event('ev1'));
      final repository = _FailingRepository(firestore);
      await pumpApp(tester, route: '/events/ev1', repository: repository);
      expect(find.byKey(const Key('public-event-error')), findsOneWidget);
      repository.fail = false;
      await tap(tester, find.byKey(const Key('public-event-retry')));
      expect(find.byKey(const Key('public-event-details')), findsOneWidget);
    });
  });

  // ------------------------------------- from the calendar to the details page

  group('from a calendar event to its details page', () {
    // Synthetic calendar records, saved as the calendar's dialog saves them
    // (the date at local midnight, times as "HH:mm").
    late CalendarService calendar;
    late CalendarWebsitePublisher publisher;
    setUp(() {
      calendar = CalendarService(firestore: firestore);
      publisher = CalendarWebsitePublisher(calendar: calendar);
    });

    Future<void> saveEvent(String id, {String start = '15:00', String end = '16:00', String location = 'Online', String description = 'Join from home.\n\nA link is sent on the day.'}) =>
        firestore.collection('school_calendar_events').doc(id).set({
          'title': 'Test', 'date': DateTime(2027, 2, 14), 'startTime': start, 'endTime': end, 'eventType': CalendarEventType.event,
          'description': description, 'location': location, 'audience': 'Public', 'status': CalendarEventStatus.published,
          'createdBy': 'creator-0001', 'createdByName': 'Synthetic Creator',
        });

    Future<CalendarEventModel> event(String id) async =>
        CalendarEventModel.fromMap(id, (await firestore.collection('school_calendar_events').doc(id).get()).data()!);

    Future<void> show(String id) async => publisher.show(requesterRole: 'admin', event: await event(id), approvedForWebsite: true);

    /// The calendar's times are local to the admin's device; in IST (the
    /// school's zone, as on the school's devices) they are exact.
    final inIst = DateTime(2027, 2, 14).timeZoneOffset == const Duration(hours: 5, minutes: 30);

    void expectTime(WidgetTester tester, String exact) {
      final time = text(tester, 'public-event-time');
      if (inIst) {
        expect(time, exact);
      } else {
        expect(time, allOf(isNot('All day'), contains('–'), endsWith(' IST')));
      }
    }

    testWidgets('a timed event with a location and description: every field shown, no private ones stored', (tester) async {
      await saveEvent('B73RxHOvOjL3BsiX6Yj0');
      await show('B73RxHOvOjL3BsiX6Yj0');
      final stored = (await firestore.collection(WebsitePublicItem.collection).doc('event_B73RxHOvOjL3BsiX6Yj0').get()).data()!;
      expect(stored.toString(), isNot(contains('creator-0001')));
      expect(stored.toString(), isNot(contains('Synthetic Creator')));
      expect(stored.containsKey('allDay'), isFalse);

      await pumpApp(tester, route: '/events/B73RxHOvOjL3BsiX6Yj0');
      expect(text(tester, 'public-event-title'), 'Test');
      if (inIst) expect(text(tester, 'public-event-date'), 'Sun 14 February 2027');
      expectTime(tester, '3:00 PM – 4:00 PM IST');
      expect(text(tester, 'public-event-location'), 'Online');
      expect(text(tester, 'public-event-description'), 'Join from home.');
      expect(find.text('A link is sent on the day.'), findsOneWidget);
    });

    testWidgets('an all-day event: “All day”; empty location and description stay hidden', (tester) async {
      await saveEvent('ev1', start: '', end: '', location: '', description: '');
      await show('ev1');
      await pumpApp(tester, route: '/events/ev1');
      expect(text(tester, 'public-event-time'), 'All day');
      expect(find.byKey(const Key('public-event-location')), findsNothing);
      expect(find.byKey(const Key('public-event-description')), findsNothing);
    });

    testWidgets('the reported case: shown while date-only, then edited without republishing; republishing brings the details', (tester) async {
      await saveEvent('ev1', start: '', end: '', location: '', description: '');
      await show('ev1');
      // Edited afterwards without updating the website (e.g. from a version
      // of the app without website publishing, or while the website status
      // couldn't be loaded).
      await calendar.updateEvent('ev1', {'startTime': '15:00', 'endTime': '16:00', 'location': 'Online', 'description': 'Join from home.'});

      final edited = await event('ev1');
      final copy = (await publisher.loadItems(requesterRole: 'admin'))['ev1']!;
      expect(CalendarWebsitePublisher.stateOf(edited, copy), CalendarWebsiteState.outOfDate, reason: 'the calendar says so');
      expect(CalendarWebsitePublisher.differences(edited, copy), ['date or time', 'location', 'description']);

      // Visitors see the published copy, not the unpublished edit.
      await pumpApp(tester, route: '/events/ev1');
      expect(text(tester, 'public-event-time'), 'All day');
      expect(find.byKey(const Key('public-event-location')), findsNothing);
      expect(find.byKey(const Key('public-event-description')), findsNothing);

      // The admin republishes (Update website) while the visitor's page is
      // open in the same session; opening the event again shows it.
      await tap(tester, find.byKey(const Key('public-event-back')));
      await publisher.show(requesterRole: 'admin', event: edited, approvedForWebsite: true);
      tester.state<NavigatorState>(find.byType(Navigator).first).pushNamed('/events/ev1');
      await tester.pumpAndSettle();
      expectTime(tester, '3:00 PM – 4:00 PM IST');
      expect(text(tester, 'public-event-location'), 'Online');
      expect(text(tester, 'public-event-description'), 'Join from home.');
      expect(CalendarWebsitePublisher.stateOf(edited, (await publisher.loadItems(requesterRole: 'admin'))['ev1']), CalendarWebsiteState.current);
    });

    testWidgets('the Upcoming events list also shows the republished details when its page is opened again', (tester) async {
      await saveEvent('ev1', start: '', end: '', location: '', description: '');
      await show('ev1');
      await publishFeedPage();
      await pumpApp(tester);
      expect(find.byKey(const Key('public-event-location-event_ev1')), findsNothing);

      await calendar.updateEvent('ev1', {'location': 'Online'});
      await show('ev1');
      // Leave the page and open it again.
      final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
      navigator.pop();
      await tester.pumpAndSettle();
      navigator.pushNamed(PublicRoutes.programs);
      await tester.pumpAndSettle();
      expect(text(tester, 'public-event-location-event_ev1'), 'Online');
    });

    Future<void> publishWithExtras() async {
      await saveEvent('ev1');
      await WebsitePublicItemsService(firestore: firestore).publish(
        requesterRole: 'admin', kind: WebsitePublicItemKind.event, sourceId: 'ev1', approvedForWebsite: true,
        extras: const WebsitePublicItemExtras(imageMediaId: 'm1', registrationUrl: 'https://forms.example.test/register', title: LocalizedText(ta: 'சோதனை')),
      );
    }

    testWidgets('every available public field: image and registration too', (tester) async {
      await publishWithExtras();
      await pumpApp(tester, route: '/events/ev1');
      for (final key in ['title', 'date', 'time', 'location', 'description', 'image', 'register']) {
        expect(find.byKey(Key('public-event-$key')), findsOneWidget, reason: key);
      }
    });

    testWidgets('in Tamil: the admin’s Tamil title, English where there is no Tamil', (tester) async {
      await publishWithExtras();
      await pumpApp(tester, route: '/events/ev1', language: PublicLanguage.tamil);
      expect(text(tester, 'public-event-title'), 'சோதனை');
      expect(text(tester, 'public-event-location'), 'Online', reason: 'no Tamil: English');
    });
  });

  // ------------------------------------------------------------- data safety

  testWidgets('only the website’s own collections are read: never the calendar or announcements', (tester) async {
    await addItem(_event('ev1'));
    await firestore.collection('school_calendar_events').doc('ev1').set({'title': 'Internal title', 'status': 'Published', 'audience': 'Public'});
    await firestore.collection('school_notifications').doc('ev1').set({'title': 'Internal notice'});
    firestore.securityRules = FakeFirebaseFirestore(securityRules: '''
service cloud.firestore {
  match /databases/{database}/documents {
    match /${WebsitePublicItem.collection}/{id} { allow read: if true; }
    match /${WebsiteCollections.media}/{id} { allow read: if true; }
    match /${WebsiteCollections.livePages}/{id} { allow read: if true; }
  }
}''').securityRules;
    await expectLater(firestore.collection('school_calendar_events').doc('ev1').get(), throwsA(anything), reason: 'the rules really refuse it');

    await pumpApp(tester, route: '/events/ev1');
    expect(find.byKey(const Key('public-event-error')), findsNothing);
    expect(text(tester, 'public-event-title'), 'Annual Day');
    expect(find.text('Internal title'), findsNothing);
  });

  // ------------------------------------------------------- routes and model

  group('routes and registration links', () {
    test('event addresses', () {
      expect(PublicRoutes.event('Ev1abc'), '/events/Ev1abc');
      expect(PublicRoutes.eventIdFromRoute('/events/Ev1abc'), 'Ev1abc');
      expect(PublicRoutes.eventIdFromRoute('/events/Ev1abc/'), 'Ev1abc');
      expect(PublicRoutes.eventIdFromRoute('/events/Ev1abc?x=1#y'), 'Ev1abc');
      expect(PublicRoutes.eventIdFromRoute('/events/'), isNull);
      expect(PublicRoutes.eventIdFromRoute('/events/a/b'), isNull);
      expect(PublicRoutes.eventIdFromRoute('/pages/a'), isNull);
    });

    test('registration links: allowed ones stored and read; others refused when written and ignored when read', () {
      for (final good in ['https://forms.example.test/register', '/admissions', 'mailto:office@example.test', 'tel:+911234567890']) {
        final item = _event('ev1', registration: good);
        expect(item.validationErrors(), isEmpty, reason: good);
        expect(WebsitePublicItem.tryParse(item.toMap())!.registrationUrl, good);
      }
      for (final bad in ['javascript:alert(1)', 'http://insecure.example.test', '/app', 'ftp://x']) {
        expect(_event('ev1', registration: bad).validationErrors(), isNotEmpty, reason: bad);
        expect(WebsitePublicItem.tryParse({..._event('ev1').toMap(), 'registrationUrl': bad})!.registrationUrl, isNull, reason: bad);
      }
      expect(_event('ev1').toMap().containsKey('registrationUrl'), isFalse);
    });

    test('the service stores an admin’s registration link, keeps it on republish, and refuses a bad one', () async {
      await firestore.collection('school_calendar_events').doc('ev1').set({
        'title': 'Annual Day', 'date': DateTime(2027, 2, 14), 'startTime': '09:30', 'endTime': '', 'eventType': 'Event',
        'description': '', 'location': '', 'audience': 'Public', 'status': 'Published', 'createdBy': 'c', 'createdByName': 'C',
      });
      final service = WebsitePublicItemsService(firestore: firestore);
      final item = await service.publish(
        requesterRole: 'admin', kind: WebsitePublicItemKind.event, sourceId: 'ev1', approvedForWebsite: true,
        extras: const WebsitePublicItemExtras(registrationUrl: 'https://forms.example.test/register'),
      );
      expect(item.registrationUrl, 'https://forms.example.test/register');
      final again = await service.publish(requesterRole: 'admin', kind: WebsitePublicItemKind.event, sourceId: 'ev1', approvedForWebsite: true);
      expect(again.registrationUrl, 'https://forms.example.test/register', reason: 'kept when no extras are given');
      await expectLater(
        service.update(requesterRole: 'admin', kind: WebsitePublicItemKind.event, sourceId: 'ev1', extras: const WebsitePublicItemExtras(registrationUrl: 'javascript:alert(1)')),
        throwsA(isA<WebsiteContentException>()),
      );
      expect((await service.getItem(requesterRole: 'admin', kind: WebsitePublicItemKind.event, sourceId: 'ev1'))!.registrationUrl, 'https://forms.example.test/register');
    });
  });
}

