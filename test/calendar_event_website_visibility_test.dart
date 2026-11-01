// An event's description limit (2,000 characters, the same in the calendar
// and on the website), and an honest website status: "On website" only
// while visitors actually see the event.
//
// Every record here is synthetic test data. The fake Firestore proves the
// app's behaviour, not deployed security rules (deferred).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/admin/website/data/website_content_admin_service.dart';
import 'package:montessori_app/modules/admin/website/data/website_public_items_service.dart';
import 'package:montessori_app/modules/auth/models/app_user.dart';
import 'package:montessori_app/modules/auth/providers/auth_provider.dart';
import 'package:montessori_app/modules/calendar/models/calendar_event_model.dart';
import 'package:montessori_app/modules/calendar/services/calendar_service.dart';
import 'package:montessori_app/modules/calendar/services/calendar_website_publisher.dart';
import 'package:montessori_app/modules/calendar/ui/calendar_view.dart';
import 'package:montessori_app/modules/public_website/content/blocks/block_registry.dart';
import 'package:montessori_app/modules/public_website/content/website_content_repository.dart';
import 'package:montessori_app/modules/public_website/content/website_public_events.dart';
import 'package:montessori_app/modules/public_website/content/website_public_item.dart';
import 'package:montessori_app/modules/public_website/public_strings.dart';
import 'package:montessori_app/modules/public_website/widgets/blocks/website_blocks_view.dart';

const _events = 'school_calendar_events';

/// Fails its writes while told to.
class _FlakyWebsite extends WebsitePublicItemsService {
  _FlakyWebsite({required super.firestore});

  bool failWrites = false;

  @override
  Future<WebsitePublicItem> publish({
    required String requesterRole,
    required WebsitePublicItemKind kind,
    required String sourceId,
    required bool approvedForWebsite,
    WebsitePublicItemExtras? extras,
    String? Function()? image,
  }) {
    if (failWrites) throw FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied', message: 'Missing or insufficient permissions.');
    return super.publish(requesterRole: requesterRole, kind: kind, sourceId: sourceId, approvedForWebsite: approvedForWebsite, extras: extras, image: image);
  }
}

Map<String, dynamic> _data({
  String title = 'Test',
  DateTime? date,
  String start = '15:00',
  String end = '16:00',
  String description = 'Join from home.',
}) =>
    {
      'title': title, 'date': date ?? DateTime(2027, 2, 14), 'startTime': start, 'endTime': end, 'eventType': CalendarEventType.event,
      'description': description, 'location': 'Online', 'audience': 'Public', 'status': CalendarEventStatus.published,
      'createdBy': 'creator-0001', 'createdByName': 'Synthetic Creator',
    };

void main() {
  late FakeFirebaseFirestore firestore;
  late CalendarService calendar;
  late _FlakyWebsite website;
  late CalendarWebsitePublisher publisher;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    calendar = CalendarService(firestore: firestore);
    website = _FlakyWebsite(firestore: firestore);
    publisher = CalendarWebsitePublisher(calendar: calendar, website: website);
  });

  Future<CalendarEventModel> event(String id) async => CalendarEventModel.fromMap(id, (await firestore.collection(_events).doc(id).get()).data()!);

  Future<CalendarEventModel> seed(String id, Map<String, dynamic> data) async {
    await firestore.collection(_events).doc(id).set(data);
    return event(id);
  }

  Future<Map<String, dynamic>?> copy(String id) async => (await firestore.collection(WebsitePublicItem.collection).doc('event_$id').get()).data();

  Future<WebsitePublicItem> show(String id) async => publisher.show(requesterRole: 'admin', event: await event(id), approvedForWebsite: true);

  // ---------------------------------------------------------- description

  group('description limit', () {
    test('the calendar and the website have the same limit: 2,000 characters', () {
      expect(CalendarEventModel.maxDescriptionLength, 2000);
      expect(CalendarEventModel.maxDescriptionLength, WebsitePublicItem.maxBodyLength);
      expect(CalendarEventModel.descriptionProblem('a' * 2000), isNull);
      expect(CalendarEventModel.descriptionProblem('  ${'a' * 2000}  '), isNull, reason: 'surrounding spaces don’t count (as on the website)');
      expect(CalendarEventModel.descriptionProblem('a' * 2001), 'The description is 2001 characters; it can be at most 2000. Shorten it by 1.');
    });

    test('2,000 characters: saved in full and shown on the website in full', () async {
      final id = await calendar.createEvent(_data(description: 'a' * 2000));
      expect((await event(id)).description, hasLength(2000));
      final item = await show(id);
      expect(item.body.en, hasLength(2000));
      expect(CalendarWebsitePublisher.stateOf(await event(id), item, now: DateTime(2027)), CalendarWebsiteState.current);
    });

    test('2,001 characters: refused with a clear message, never shortened; nothing written', () async {
      await expectLater(
        calendar.createEvent(_data(description: 'a' * 2001)),
        throwsA(isA<CalendarEventValidationException>().having((e) => e.message, 'message', contains('at most 2000'))),
      );
      expect((await firestore.collection(_events).get()).docs, isEmpty);

      final id = await calendar.createEvent(_data(description: 'short'));
      await expectLater(calendar.updateEvent(id, {'description': 'b' * 2001}), throwsA(isA<CalendarEventValidationException>()));
      expect((await event(id)).description, 'short');
    });

    test('an event saved with a longer description before the limit (or elsewhere) can’t be shown: a clear error, no copy, never "On website"', () async {
      final long = await seed('long', _data(description: 'a' * 2001));
      await expectLater(show('long'), throwsA(isA<WebsiteContentException>().having((e) => e.message, 'message', 'The text must be 2000 characters or fewer.')));
      expect(await copy('long'), isNull);
      expect(CalendarWebsitePublisher.stateOf(long, (await publisher.loadItems(requesterRole: 'admin'))['long']), CalendarWebsiteState.notShown);
    });

    testWidgets('editor: a live count; over the limit it says by how much and can’t be saved; at the limit it saves', (tester) async {
      await seed('ev1', _data());
      await show('ev1');
      await pumpCalendar(tester, calendar, publisher);
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      expect(find.text('15 / 2000'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('calendar-event-description')), 'a' * 2001);
      await tester.pumpAndSettle();
      expect(find.text('2001 / 2000'), findsOneWidget);
      expect(find.text('The description is 2001 characters; it can be at most 2000. Shorten it by 1.'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect((await event('ev1')).description, 'Join from home.', reason: 'not saved, and not cut short');
      expect(find.widgetWithText(FilledButton, 'Save'), findsOneWidget, reason: 'the form stays open');

      await tester.enterText(find.byKey(const Key('calendar-event-description')), 'a' * 2000);
      await tester.pumpAndSettle();
      expect(find.text('2000 / 2000'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect((await event('ev1')).description, hasLength(2000));
      expect((await copy('ev1'))!['body']['en'], hasLength(2000), reason: 'it was on the website, so the copy is updated too');
    });
  });

  // -------------------------------------------- the reported missing event

  group('visible to visitors', () {
    // 27 October 2026 at school (IST).
    DateTime at(int hour, [int minute = 0]) => DateTime.utc(2026, 10, 27, hour, minute).subtract(const Duration(hours: 5, minutes: 30));

    test('the reported case: shown 15:00–16:00 today; after it ends the list leaves it out, and the calendar no longer says "On website"', () async {
      final test = await seed('t1', _data(title: 'Test', date: DateTime(2026, 10, 27)));
      final hello = await seed('h1', _data(title: 'Hello', date: DateTime(2026, 10, 30), start: '', end: ''));
      await show('t1');
      await show('h1');

      // The copy exists under the expected id, parses, and is valid.
      final items = await WebsiteContentRepository(firestore: firestore).publicEvents();
      final copyOfTest = items.singleWhere((i) => i.sourceId == 't1');
      expect(copyOfTest.id, 'event_t1');
      expect(copyOfTest.validationErrors(), isEmpty);
      expect(copyOfTest.expireAt, isNull);

      if (DateTime(2026, 10, 27).timeZoneOffset == const Duration(hours: 5, minutes: 30)) {
        // Before it ends: listed, and "On website".
        expect(upcomingPublicEvents(items, now: at(14), limit: 6).map((i) => i.title.en), ['Test', 'Hello']);
        expect(CalendarWebsitePublisher.stateOf(test, copyOfTest, now: at(14)), CalendarWebsiteState.current);
        // 19:30: over. Left out, and the calendar says why.
        expect(upcomingPublicEvents(items, now: at(19, 30), limit: 6).map((i) => i.title.en), ['Hello']);
        expect(CalendarWebsitePublisher.stateOf(test, copyOfTest, now: at(19, 30)), CalendarWebsiteState.notVisible);
        expect(CalendarWebsitePublisher.visibilityProblem(copyOfTest, now: at(19, 30)), contains('the event has ended'));
        expect(CalendarWebsitePublisher.stateOf(hello, items.singleWhere((i) => i.sourceId == 'h1'), now: at(19, 30)), CalendarWebsiteState.current);
      }
    });

    test('expired or invalid copies: not visible, with the reason; an invalid copy is replaced by updating', () async {
      final ev = await seed('ev1', _data());
      await show('ev1');
      // During the event (15:00–16:00), after the copy's expiry (15:30).
      var now = DateTime(2027, 2, 14, 15, 45);

      await firestore.collection(WebsitePublicItem.collection).doc('event_ev1').update({'expireAt': Timestamp.fromDate(DateTime(2027, 2, 14, 15, 30))});
      var item = (await publisher.loadItems(requesterRole: 'admin'))['ev1']!;
      expect(item.validationErrors(), isEmpty);
      expect(CalendarWebsitePublisher.stateOf(ev, item, now: now), CalendarWebsiteState.notVisible);
      expect(CalendarWebsitePublisher.visibilityProblem(item, now: now), 'Visitors don’t see it: it has expired on the website.');
      expect(upcomingPublicEvents([item], now: now, limit: 6), isEmpty);
      now = DateTime(2027);

      // A copy written elsewhere with a description over the limit.
      await firestore.collection(WebsitePublicItem.collection).doc('event_ev1').update({'expireAt': FieldValue.delete(), 'body': {'en': 'a' * 2001}});
      item = (await publisher.loadItems(requesterRole: 'admin'))['ev1']!;
      expect(CalendarWebsitePublisher.stateOf(ev, item, now: now), CalendarWebsiteState.notVisible);
      expect(CalendarWebsitePublisher.visibilityProblem(item, now: now), contains('isn’t valid (The text must be 2000 characters or fewer.)'));
      expect(upcomingPublicEvents([item], now: now, limit: 6), isEmpty, reason: 'never shown to visitors');

      item = await show('ev1');
      expect(CalendarWebsitePublisher.stateOf(ev, item, now: now), CalendarWebsiteState.current);
      expect(upcomingPublicEvents([item], now: now, limit: 6), hasLength(1));
    });

    testWidgets('a valid future event appears in Upcoming events once published; republishing refreshes it', (tester) async {
      await seed('ev1', _data(title: 'Open Day'));
      Future<void> pumpFeed() async {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(ProviderScope(
          overrides: [
            websiteContentRepositoryProvider.overrideWithValue(WebsiteContentRepository(firestore: firestore)),
            publicClockProvider.overrideWithValue(() => DateTime(2027)),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: WebsiteBlocksView(blocks: [BlockRegistry.create(BlockRegistry.eventsFeed)], media: const {}, language: PublicLanguage.english, interactive: false),
              ),
            ),
          ),
        ));
        await tester.pumpAndSettle();
      }

      await pumpFeed();
      expect(find.text('No upcoming events.'), findsOneWidget, reason: 'nothing until it is published');
      await tester.runAsync(() => show('ev1'));
      await pumpFeed();
      expect(find.text('Open Day'), findsOneWidget);

      await tester.runAsync(() async {
        await calendar.updateEvent('ev1', {'title': 'Open Day 2027'});
        await show('ev1');
      });
      await pumpFeed();
      expect(find.text('Open Day 2027'), findsOneWidget);
    });
  });

  // -------------------------------------------------------- calendar status

  group('calendar status', () {
    testWidgets('a failed publish is never reported as shown', (tester) async {
      await seed('ev1', _data());
      website.failWrites = true;
      await pumpCalendar(tester, calendar, publisher);
      await tester.tap(find.byKey(const Key('calendar-website-show')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('calendar-website-show-confirm')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Could not show it on the website'), findsOneWidget);
      expect(find.text('Shown on the public website'), findsNothing);
      expect(find.text('On website'), findsNothing);
      expect(await copy('ev1'), isNull);
    });

    testWidgets('a failed update from the edit dialog is never reported as updated', (tester) async {
      await seed('ev1', _data());
      await show('ev1');
      website.failWrites = true;
      await pumpCalendar(tester, calendar, publisher);
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, 'Title'), 'Renamed');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Calendar item saved, but the public website wasn’t changed'), findsOneWidget);
      expect(find.textContaining('updated on the public website'), findsNothing);
      expect(find.text('Website out of date'), findsOneWidget);
    });

    testWidgets('an event that has ended: "Not visible on website" with the reason; not newly shown', (tester) async {
      await seed('over', _data(title: 'Old fair', date: DateTime(2020, 3, 1)));
      await show('over');
      await seed('never', _data(title: 'Old talk', date: DateTime(2020, 3, 2)));
      await pumpCalendar(tester, calendar, publisher);

      expect(find.text('Not visible on website'), findsOneWidget);
      expect(find.text('On website'), findsNothing);
      expect(find.byKey(const Key('calendar-website-show')), findsNothing, reason: 'an ended event isn’t offered');
      expect(find.byKey(const Key('calendar-website-remove')), findsOneWidget, reason: 'its copy can still be removed');

      await tester.tap(find.text('Old fair'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.descendant(of: find.byKey(const Key('calendar-website-note')), matching: find.byType(Text))).data,
        'Public website: Visitors don’t see it: the event has ended. Upcoming events and event pages show only events that aren’t over.',
      );
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Old talk'));
      await tester.pumpAndSettle();
      expect(find.text('Public website: This event has ended, so visitors wouldn’t see it on the website.'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      // In the edit dialog the switch is unavailable for it, with the reason.
      final card = find.ancestor(of: find.text('Old talk'), matching: find.byType(Card));
      await tester.tap(find.descendant(of: card, matching: find.text('Edit')));
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(find.byKey(const Key('calendar-website-switch'))).onChanged, isNull);
      expect(tester.widget<Text>(find.byKey(const Key('calendar-website-explanation'))).data, 'This event has ended, so visitors wouldn’t see it on the website.');
    });

    testWidgets('updating the copy of an ended event says visitors won’t see it', (tester) async {
      await seed('over', _data(title: 'Old fair', date: DateTime(2020, 3, 1)));
      await show('over');
      await pumpCalendar(tester, calendar, publisher);
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, 'Title'), 'Old fair (photos)');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(find.textContaining('copied to the public website, but not shown to visitors'), findsOneWidget);
      expect(find.text('Calendar item saved and updated on the public website.'), findsNothing);
    });

    testWidgets('a future valid event: "On website" exactly as before', (tester) async {
      await seed('ev1', _data());
      await show('ev1');
      await pumpCalendar(tester, calendar, publisher);
      expect(find.text('On website'), findsOneWidget);
    });
  });
}

Future<void> pumpCalendar(WidgetTester tester, CalendarService calendar, CalendarWebsitePublisher publisher) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [currentUserProvider.overrideWith((ref) => AppUser(id: 'admin-1', phone: '9999999999', role: 'admin', isActive: true))],
    child: MaterialApp(home: Scaffold(body: CalendarView(service: calendar, websitePublisher: publisher))),
  ));
  await tester.pumpAndSettle();
  await tester.tap(find.text('List'));
  await tester.pumpAndSettle();
}
