// Calendar events on the public website: an admin explicitly shows an
// eligible event there, updates or removes its copy, and archiving or
// deleting the event removes the copy first.
//
// Every record here is synthetic test data (no real students, parents or
// staff). The fake Firestore proves the app's behaviour, not security
// rules (deferred to the rules hardening phase).

import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/admin/notifications/data/admin_notification_service.dart';
import 'package:montessori_app/modules/admin/website/data/website_content_admin_service.dart';
import 'package:montessori_app/modules/admin/website/data/website_public_items_service.dart';
import 'package:montessori_app/modules/auth/models/app_user.dart';
import 'package:montessori_app/modules/auth/providers/auth_provider.dart';
import 'package:montessori_app/modules/calendar/models/calendar_event_model.dart';
import 'package:montessori_app/modules/calendar/services/calendar_service.dart';
import 'package:montessori_app/modules/calendar/services/calendar_website_publisher.dart';
import 'package:montessori_app/modules/calendar/ui/calendar_view.dart';
import 'package:montessori_app/modules/public_website/content/website_public_item.dart';

const _events = 'school_calendar_events';
const _items = WebsitePublicItem.collection;

/// Source fields that must never reach the website.
const _privateValues = ['creator-0001', 'Synthetic Creator', 'internal-0001'];

class _UnusedFilePicker extends FilePicker {}

/// Fails its writes (and, optionally, its listing) while told to.
class _FlakyWebsite extends WebsitePublicItemsService {
  _FlakyWebsite({required super.firestore});

  bool failWrites = false;
  bool failList = false;
  int withdrawCalls = 0;
  int listCalls = 0;

  static final _unavailable = FirebaseException(plugin: 'cloud_firestore', code: 'unavailable', message: 'offline');

  @override
  Future<List<WebsitePublicItem>> listItems({required String requesterRole}) {
    listCalls++;
    if (failList) throw _unavailable;
    return super.listItems(requesterRole: requesterRole);
  }

  @override
  Future<WebsitePublicItem> publish({
    required String requesterRole,
    required WebsitePublicItemKind kind,
    required String sourceId,
    required bool approvedForWebsite,
    WebsitePublicItemExtras? extras,
    String? Function()? image,
  }) {
    if (failWrites) throw _unavailable;
    return super.publish(requesterRole: requesterRole, kind: kind, sourceId: sourceId, approvedForWebsite: approvedForWebsite, extras: extras, image: image);
  }

  @override
  Future<void> withdraw({required String requesterRole, required WebsitePublicItemKind kind, required String sourceId}) {
    withdrawCalls++;
    if (failWrites) throw _unavailable;
    return super.withdraw(requesterRole: requesterRole, kind: kind, sourceId: sourceId);
  }
}

Map<String, dynamic> _eventData({
  String title = 'Annual Day',
  String status = CalendarEventStatus.published,
  String audience = 'Public',
  String startTime = '09:30',
  String endTime = '12:00',
}) =>
    {
      'title': title,
      'date': Timestamp.fromDate(DateTime(2027, 2, 14)),
      'startTime': startTime,
      'endTime': endTime,
      'eventType': CalendarEventType.event,
      'description': 'Performances by every class.',
      'location': 'School hall',
      'audience': audience,
      'status': status,
      'createdBy': 'creator-0001',
      'createdByName': 'Synthetic Creator',
      'internalNote': 'internal-0001',
    };

class _Harness {
  _Harness() {
    calendar = CalendarService(
      firestore: firestore,
      notificationService: AdminNotificationService(firestore: firestore, storage: MockFirebaseStorage(), filePicker: _UnusedFilePicker()),
    );
    website = _FlakyWebsite(firestore: firestore);
    publisher = CalendarWebsitePublisher(calendar: calendar, website: website);
  }

  final firestore = FakeFirebaseFirestore();
  late final CalendarService calendar;
  late final _FlakyWebsite website;
  late final CalendarWebsitePublisher publisher;

  Future<CalendarEventModel> seed(String id, {Map<String, dynamic>? data}) async {
    await firestore.collection(_events).doc(id).set(data ?? _eventData());
    return event(id);
  }

  Future<CalendarEventModel> event(String id) async {
    final doc = await firestore.collection(_events).doc(id).get();
    return CalendarEventModel.fromMap(id, doc.data()!);
  }

  Future<Map<String, dynamic>?> item(String eventId) async => (await firestore.collection(_items).doc('event_$eventId').get()).data();

  Future<int> itemCount() async => (await firestore.collection(_items).get()).docs.length;

  Future<WebsitePublicItem> show(CalendarEventModel event) => publisher.show(requesterRole: 'admin', event: event, approvedForWebsite: true);
}

void main() {
  // -------------------------------------------------------------- service

  group('publisher', () {
    late _Harness h;
    setUp(() => h = _Harness());

    test('an eligible event: shown when approved, as a sanitized copy; the event itself is unchanged', () async {
      final event = await h.seed('ev1');
      final sourceBefore = (await h.firestore.collection(_events).doc('ev1').get()).data();

      final item = await h.show(event);

      expect(item.id, 'event_ev1');
      expect(item.title.en, 'Annual Day');
      expect(item.startAt, DateTime(2027, 2, 14, 9, 30));
      expect(item.endAt, DateTime(2027, 2, 14, 12));
      expect(item.allDay, isFalse);
      final stored = (await h.item('ev1'))!;
      expect(stored.keys.toSet().difference(WebsitePublicItem.fields), isEmpty);
      final json = jsonEncode(stored, toEncodable: (o) => o.toString());
      for (final value in _privateValues) {
        expect(json, isNot(contains(value)), reason: value);
      }
      expect((await h.firestore.collection(_events).doc('ev1').get()).data(), sourceBefore,
          reason: 'no website flag is written to the calendar event');
      expect(CalendarWebsitePublisher.stateOf(event, item), CalendarWebsiteState.current);
    });

    test('an event without a start time is all day: its date only, no end', () async {
      final event = await h.seed('ev1', data: _eventData(startTime: '', endTime: '15:00'));
      final item = await h.show(event);
      expect(item.allDay, isTrue);
      expect(item.startAt, DateTime(2027, 2, 14));
      expect(item.endAt, isNull, reason: 'an end time alone is left out');
      expect((await h.item('ev1'))!['allDay'], isTrue);
      expect(CalendarWebsitePublisher.stateOf(event, item), CalendarWebsiteState.current);
    });

    test('refused without approval, for a Draft or Archived event, and for an event not for everyone; nothing written', () async {
      final ok = await h.seed('ok');
      await expectLater(
        h.publisher.show(requesterRole: 'admin', event: ok, approvedForWebsite: false),
        throwsA(isA<WebsiteContentException>()),
      );
      for (final (id, data, reason) in [
        ('draft', _eventData(status: CalendarEventStatus.draft), 'Only a published event can be shown on the website.'),
        ('archived', _eventData(status: CalendarEventStatus.archived), 'Only a published event can be shown on the website.'),
        ('parents', _eventData(audience: 'Parents'), 'Only an event for everyone (audience Public) can be shown on the website; this one is for Parents.'),
        ('staff', _eventData(audience: 'Staff'), 'Only an event for everyone (audience Public) can be shown on the website; this one is for Staff.'),
      ]) {
        final event = await h.seed(id, data: data);
        expect(CalendarWebsitePublisher.ineligibility(event), reason, reason: id);
        await expectLater(h.show(event), throwsA(isA<WebsiteContentException>().having((e) => e.message, 'message', reason)), reason: id);
      }
      expect(await h.itemCount(), 0);
      expect(CalendarWebsitePublisher.ineligibility(ok), isNull);
    });

    test('only admins', () async {
      final event = await h.seed('ev1');
      for (final role in ['staff', 'parent', '']) {
        await expectLater(
          h.publisher.show(requesterRole: role, event: event, approvedForWebsite: true),
          throwsA(isA<UnauthorizedWebsiteContentException>()),
        );
        await expectLater(h.publisher.withdraw(requesterRole: role, eventId: 'ev1'), throwsA(isA<UnauthorizedWebsiteContentException>()));
        await expectLater(h.publisher.loadItems(requesterRole: role), throwsA(isA<UnauthorizedWebsiteContentException>()));
      }
      expect(await h.itemCount(), 0);
    });

    test('publishing the event in the calendar never shows it on the website', () async {
      final event = await h.seed('ev1', data: _eventData(status: CalendarEventStatus.draft));
      await h.calendar.publishEvent(event);
      expect((await h.event('ev1')).status, CalendarEventStatus.published);
      expect(await h.itemCount(), 0);
    });

    test('edited after being shown: out of date until updated; one copy, first publication time kept, translations kept', () async {
      final event = await h.seed('ev1');
      final first = await h.show(event);
      await h.firestore.collection(_items).doc('event_ev1').update({'title.ta': 'ஆண்டு விழா'});

      await h.calendar.updateEvent('ev1', {'title': 'Annual Day 2027', 'startTime': '10:00'});
      final edited = await h.event('ev1');
      var items = await h.publisher.loadItems(requesterRole: 'admin');
      expect(CalendarWebsitePublisher.stateOf(edited, items['ev1']), CalendarWebsiteState.outOfDate);
      expect(items['ev1']!.title.en, 'Annual Day', reason: 'an edit alone never changes the website');

      final updated = await h.show(edited);
      expect(updated.title.en, 'Annual Day 2027');
      expect(updated.title.ta, 'ஆண்டு விழா');
      expect(updated.startAt, DateTime(2027, 2, 14, 10));
      expect(updated.publishedAt, first.publishedAt);
      expect(await h.itemCount(), 1, reason: 'one copy per event, never a duplicate');
      items = await h.publisher.loadItems(requesterRole: 'admin');
      expect(CalendarWebsitePublisher.stateOf(edited, items['ev1']), CalendarWebsiteState.current);

      await h.show(edited);
      expect(await h.itemCount(), 1, reason: 'showing again changes nothing');
    });

    test('no longer eligible after an edit: still on the website until removed, and shown as such', () async {
      final event = await h.seed('ev1');
      final item = await h.show(event);
      await h.calendar.updateEvent('ev1', {'audience': 'Parents'});
      expect(CalendarWebsitePublisher.stateOf(await h.event('ev1'), item), CalendarWebsiteState.noLongerEligible);
      await expectLater(h.show(await h.event('ev1')), throwsA(isA<WebsiteContentException>()));
      expect((await h.item('ev1'))!['title']['en'], 'Annual Day', reason: 'a refused update leaves the copy as it was');
    });

    test('withdraw: off the website, the event untouched; withdrawing again changes nothing', () async {
      final event = await h.seed('ev1');
      await h.show(event);
      await h.publisher.withdraw(requesterRole: 'admin', eventId: 'ev1');
      expect(await h.item('ev1'), isNull);
      expect((await h.event('ev1')).status, CalendarEventStatus.published);
      await h.publisher.withdraw(requesterRole: 'admin', eventId: 'ev1');
      expect(await h.itemCount(), 0);
      expect(CalendarWebsitePublisher.stateOf(event, null), CalendarWebsiteState.notShown);
    });

    group('the dialog’s choice after an edit', () {
      Future<CalendarWebsiteChange> apply(CalendarEventModel event, {required bool show, required bool was}) =>
          h.publisher.applyChoice(requesterRole: 'admin', event: event, showOnWebsite: show, wasOnWebsite: was);

      test('shown, updated, removed, or nothing', () async {
        var event = await h.seed('ev1');
        expect(await apply(event, show: false, was: false), CalendarWebsiteChange.none);
        expect(await h.itemCount(), 0);

        expect(await apply(event, show: true, was: false), CalendarWebsiteChange.shown);
        expect(await h.item('ev1'), isNotNull);

        await h.calendar.updateEvent('ev1', {'location': 'Garden'});
        event = await h.event('ev1');
        expect(await apply(event, show: true, was: true), CalendarWebsiteChange.updated);
        expect((await h.item('ev1'))!['location']['en'], 'Garden');

        expect(await apply(event, show: false, was: true), CalendarWebsiteChange.withdrawn);
        expect(await h.item('ev1'), isNull);
      });

      test('an event that can no longer be shown is removed even if still chosen', () async {
        await h.show(await h.seed('ev1'));
        await h.calendar.updateEvent('ev1', {'audience': 'Staff'});
        expect(await apply(await h.event('ev1'), show: true, was: true), CalendarWebsiteChange.withdrawn);
        expect(await h.item('ev1'), isNull);
      });

      test('an ineligible event is never shown, even if chosen', () async {
        final draft = await h.seed('ev1', data: _eventData(status: CalendarEventStatus.draft));
        expect(await apply(draft, show: true, was: false), CalendarWebsiteChange.none);
        expect(await h.itemCount(), 0);
      });
    });

    group('archive and delete', () {
      test('archiving an event on the website removes its copy first', () async {
        final event = await h.seed('ev1');
        await h.show(event);
        expect(await h.publisher.archive(requesterRole: 'admin', event: event, onWebsite: true), isTrue);
        expect(await h.item('ev1'), isNull);
        expect((await h.event('ev1')).status, CalendarEventStatus.archived);
      });

      test('deleting an event on the website removes its copy first', () async {
        final event = await h.seed('ev1');
        await h.show(event);
        await h.publisher.delete(requesterRole: 'admin', event: event, onWebsite: true);
        expect(await h.item('ev1'), isNull);
        expect((await h.firestore.collection(_events).doc('ev1').get()).exists, isFalse);
      });

      test('an event known not to be on the website: no website write at all', () async {
        final a = await h.seed('a');
        final b = await h.seed('b');
        h.website.failWrites = true;
        expect(await h.publisher.archive(requesterRole: 'admin', event: a, onWebsite: false), isTrue);
        await h.publisher.delete(requesterRole: 'admin', event: b, onWebsite: false);
        expect(h.website.withdrawCalls, 0);
        expect((await h.event('a')).status, CalendarEventStatus.archived);
        expect((await h.firestore.collection(_events).doc('b').get()).exists, isFalse);
      });

      test('the copy can’t be removed: nothing archived or deleted; trying again once it can works', () async {
        final event = await h.seed('ev1');
        await h.show(event);
        h.website.failWrites = true;

        await expectLater(
          h.publisher.archive(requesterRole: 'admin', event: event, onWebsite: true),
          throwsA(isA<CalendarWebsiteRemovalException>().having((e) => e.toString(), 'message', startsWith('Its copy on the public website couldn’t be removed, so it wasn’t archived.'))),
        );
        await expectLater(h.publisher.delete(requesterRole: 'admin', event: event, onWebsite: true), throwsA(isA<CalendarWebsiteRemovalException>()));
        expect((await h.event('ev1')).status, CalendarEventStatus.published);
        expect(await h.item('ev1'), isNotNull);

        h.website.failWrites = false;
        await h.publisher.delete(requesterRole: 'admin', event: event, onWebsite: true);
        expect(await h.itemCount(), 0);
        expect((await h.firestore.collection(_events).doc('ev1').get()).exists, isFalse);
      });

      test('website status unknown: removal is still tried; on failure, archive goes ahead (reported) but delete doesn’t', () async {
        final event = await h.seed('ev1');
        await h.show(event);
        expect(await h.publisher.archive(requesterRole: 'admin', event: event, onWebsite: null), isTrue);
        expect(await h.item('ev1'), isNull, reason: 'removed even though it wasn’t known to be there');

        final other = await h.seed('ev2');
        await h.show(other);
        h.website.failWrites = true;
        expect(await h.publisher.archive(requesterRole: 'admin', event: other, onWebsite: null), isFalse);
        expect((await h.event('ev2')).status, CalendarEventStatus.archived);
        expect(CalendarWebsitePublisher.stateOf(await h.event('ev2'), (await h.publisher.loadItems(requesterRole: 'admin'))['ev2']),
            CalendarWebsiteState.noLongerEligible, reason: 'the calendar then offers to remove it');

        final third = await h.seed('ev3');
        await expectLater(h.publisher.delete(requesterRole: 'admin', event: third, onWebsite: null), throwsA(isA<CalendarWebsiteRemovalException>()));
        expect((await h.firestore.collection(_events).doc('ev3').get()).exists, isTrue);
      });
    });
  });

  // --------------------------------------------------------------- the UI

  group('calendar UI', () {
    late _Harness h;
    setUp(() => h = _Harness());

    Future<void> pump(WidgetTester tester, {String role = 'admin'}) async {
      tester.view.physicalSize = const Size(1200, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          currentUserProvider.overrideWith((ref) => AppUser(id: 'admin-1', phone: '9999999999', role: role, isActive: true)),
        ],
        child: MaterialApp(home: Scaffold(body: CalendarView(service: h.calendar, websitePublisher: h.publisher))),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('List'));
      await tester.pumpAndSettle();
    }

    Future<void> tapKey(WidgetTester tester, String key) async {
      await tester.ensureVisible(find.byKey(Key(key)));
      await tester.tap(find.byKey(Key(key)));
      await tester.pumpAndSettle();
    }

    testWidgets('Show on website: offered for an eligible event only, confirmed first; Cancel writes nothing', (tester) async {
      await h.seed('ev1');
      await h.seed('draft', data: _eventData(title: 'Draft day', status: CalendarEventStatus.draft));
      await h.seed('parents', data: _eventData(title: 'Parents day', audience: 'Parents'));
      await pump(tester);

      expect(find.byKey(const Key('calendar-website-show')), findsOneWidget, reason: 'only the Published event for everyone');
      expect(find.byKey(const Key('calendar-website-chip')), findsNothing);

      await tapKey(tester, 'calendar-website-show');
      expect(find.text('Show on the public website?'), findsOneWidget);
      await tapKey(tester, 'calendar-website-cancel');
      expect(await h.itemCount(), 0);

      await tapKey(tester, 'calendar-website-show');
      await tapKey(tester, 'calendar-website-show-confirm');
      expect(await h.item('ev1'), isNotNull);
      expect(find.text('Shown on the public website'), findsOneWidget);
      expect(find.text('On website'), findsOneWidget);
      expect(find.byKey(const Key('calendar-website-show')), findsNothing);
      expect(find.byKey(const Key('calendar-website-remove')), findsOneWidget);
    });

    testWidgets('detail: why an event can’t be shown', (tester) async {
      await h.seed('parents', data: _eventData(title: 'Parents day', audience: 'Parents'));
      await pump(tester);
      await tester.tap(find.text('Parents day'));
      await tester.pumpAndSettle();
      expect(
        find.text('Public website: Only an event for everyone (audience Public) can be shown on the website; this one is for Parents.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('calendar-website-show')), findsNothing);
    });

    testWidgets('edited after being shown: "Website out of date" and Update website', (tester) async {
      await h.show(await h.seed('ev1'));
      await h.calendar.updateEvent('ev1', {'title': 'Annual Day 2027'});
      await pump(tester);

      expect(find.text('Website out of date'), findsOneWidget);
      await tapKey(tester, 'calendar-website-update');
      expect((await h.item('ev1'))!['title']['en'], 'Annual Day 2027');
      expect(find.text('Public website updated'), findsOneWidget);
      expect(find.text('On website'), findsOneWidget);
      expect(find.byKey(const Key('calendar-website-update')), findsNothing);
    });

    testWidgets('out of date: the detail and the edit dialog say what the website shows differently', (tester) async {
      await h.show(await h.seed('ev1', data: _eventData(startTime: '', endTime: '')));
      await h.calendar.updateEvent('ev1', {'startTime': '15:00', 'endTime': '16:00', 'location': 'Online', 'description': 'Join from home.'});
      await pump(tester);

      await tester.tap(find.text('Annual Day'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.descendant(of: find.byKey(const Key('calendar-website-note')), matching: find.byType(Text))).data,
        'Public website: shows an older version (its date or time, location, description differ). '
        'Visitors see it until you update it, or remove it from the website.',
      );
      expect(find.byKey(const Key('calendar-website-update')), findsWidgets, reason: 'on the card and in the detail');
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const Key('calendar-website-explanation'))).data,
        'The website shows an older date or time, location, description. Saving updates it with these details.',
      );
    });

    testWidgets('website status unknown: saving an edit says the website wasn’t changed', (tester) async {
      await h.show(await h.seed('ev1'));
      h.website.failList = true;
      await pump(tester);
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, 'Location (optional)'), 'Online');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(find.textContaining('The public website couldn’t be checked, so it wasn’t changed.'), findsOneWidget);
      expect((await h.item('ev1'))!['location']['en'], 'School hall');
      expect((await h.event('ev1')).location, 'Online');
    });

    testWidgets('Remove from website: confirmed; the event stays', (tester) async {
      await h.show(await h.seed('ev1'));
      await pump(tester);
      await tapKey(tester, 'calendar-website-remove');
      await tapKey(tester, 'calendar-website-cancel');
      expect(await h.item('ev1'), isNotNull);
      await tapKey(tester, 'calendar-website-remove');
      await tapKey(tester, 'calendar-website-remove-confirm');
      expect(await h.item('ev1'), isNull);
      expect((await h.event('ev1')).status, CalendarEventStatus.published);
      expect(find.byKey(const Key('calendar-website-show')), findsOneWidget);
    });

    testWidgets('Archive and Delete say the copy goes too, and remove it', (tester) async {
      await h.show(await h.seed('ev1'));
      await h.show(await h.seed('ev2', data: _eventData(title: 'Sports Day')));
      await pump(tester);

      await tester.tap(find.text('Archive').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('It will also be removed from the public website.'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Archive'));
      await tester.pumpAndSettle();
      expect(await h.itemCount(), 1);

      final remaining = (await h.firestore.collection(_items).get()).docs.single.data()['title']['en'] as String;
      final card = find.ancestor(of: find.text(remaining), matching: find.byType(Card));
      await tester.tap(find.descendant(of: card, matching: find.text('Delete')));
      await tester.pumpAndSettle();
      expect(find.textContaining('It will also be removed from the public website.'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(await h.itemCount(), 0);
    });

    testWidgets('a failed removal stops Delete and says why', (tester) async {
      await h.show(await h.seed('ev1'));
      await pump(tester);
      h.website.failWrites = true;
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(find.textContaining('so it wasn’t deleted'), findsOneWidget);
      expect((await h.firestore.collection(_events).doc('ev1').get()).exists, isTrue);
      expect(await h.item('ev1'), isNotNull);
    });

    testWidgets('website unreadable: the calendar still works, without website actions', (tester) async {
      await h.seed('ev1');
      h.website.failList = true;
      await pump(tester);
      expect(find.text('Annual Day'), findsOneWidget);
      expect(find.byKey(const Key('calendar-website-show')), findsNothing);
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('calendar-website-unknown-note')), findsOneWidget);
      expect(find.byKey(const Key('calendar-website-switch')), findsNothing);
    });

    testWidgets('Staff and Parents: the website is never read and nothing about it is shown', (tester) async {
      await h.show(await h.seed('ev1'));
      for (final role in ['parent', 'staff']) {
        h.website.listCalls = 0;
        await pump(tester, role: role);
        expect(find.text('Annual Day'), findsOneWidget, reason: role);
        expect(h.website.listCalls, 0, reason: role);
        expect(find.byKey(const Key('calendar-website-chip')), findsNothing, reason: role);
        expect(find.byKey(const Key('calendar-website-show')), findsNothing, reason: role);
        expect(find.byKey(const Key('calendar-website-remove')), findsNothing, reason: role);
      }
    });

    group('event dialog', () {
      Future<void> openEdit(WidgetTester tester) async {
        await tester.tap(find.text('Edit'));
        await tester.pumpAndSettle();
      }

      Future<void> save(WidgetTester tester) async {
        await tester.tap(find.widgetWithText(FilledButton, 'Save'));
        await tester.pumpAndSettle();
      }

      String explanation(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('calendar-website-explanation'))).data!;

      testWidgets('new item: explains it can be shown only once saved and published; saving shows nothing', (tester) async {
        await pump(tester);
        await tester.tap(find.byIcon(Icons.add));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('calendar-website-new-note')), findsOneWidget);
        expect(find.byKey(const Key('calendar-website-switch')), findsNothing);
        await tester.enterText(find.widgetWithText(TextFormField, 'Title'), 'New event');
        await save(tester);
        final created = (await h.firestore.collection(_events).get()).docs.single.data();
        expect(created['status'], CalendarEventStatus.draft);
        expect(await h.itemCount(), 0);
      });

      testWidgets('a Draft event: the switch is unavailable, with the reason', (tester) async {
        await h.seed('ev1', data: _eventData(status: CalendarEventStatus.draft));
        await pump(tester);
        await openEdit(tester);
        final tile = tester.widget<SwitchListTile>(find.byKey(const Key('calendar-website-switch')));
        expect(tile.onChanged, isNull);
        expect(tile.value, isFalse);
        expect(explanation(tester), 'Only a published event can be shown on the website.');
      });

      testWidgets('a Published event for everyone: switching on and saving shows it; leaving it off saves only the event', (tester) async {
        await h.seed('ev1');
        await pump(tester);

        await openEdit(tester);
        expect(explanation(tester), 'Not shown on the public website.');
        await tester.enterText(find.widgetWithText(TextFormField, 'Location (optional)'), 'Garden');
        await save(tester);
        expect((await h.event('ev1')).location, 'Garden');
        expect(await h.itemCount(), 0, reason: 'normal editing is unchanged');

        await openEdit(tester);
        await tapKey(tester, 'calendar-website-switch');
        expect(explanation(tester), 'Saving shows this event on the public website, to anyone on the internet.');
        await save(tester);
        expect((await h.item('ev1'))!['location']['en'], 'Garden');
        expect(find.text('Calendar item saved and shown on the public website.'), findsOneWidget);
      });

      testWidgets('on the website: saving with the switch on updates the copy; off removes it', (tester) async {
        await h.show(await h.seed('ev1'));
        await pump(tester);

        await openEdit(tester);
        expect(tester.widget<SwitchListTile>(find.byKey(const Key('calendar-website-switch'))).value, isTrue);
        expect(explanation(tester), 'Saving updates the website with these details.');
        await tester.enterText(find.widgetWithText(TextFormField, 'Title'), 'Annual Day 2027');
        await save(tester);
        expect((await h.item('ev1'))!['title']['en'], 'Annual Day 2027');
        expect(find.text('Calendar item saved and updated on the public website.'), findsOneWidget);

        await openEdit(tester);
        await tapKey(tester, 'calendar-website-switch');
        expect(explanation(tester), 'Saving removes this event from the public website.');
        await save(tester);
        expect(await h.item('ev1'), isNull);
        expect((await h.event('ev1')).title, 'Annual Day 2027');
      });

      testWidgets('changing the audience of an event on the website: saving removes its copy, and says so first', (tester) async {
        await h.show(await h.seed('ev1'));
        await pump(tester);
        await openEdit(tester);
        await tester.tap(find.text('Everyone').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Parents').last);
        await tester.pumpAndSettle();
        expect(explanation(tester), startsWith('Saving removes it from the website.'));
        await save(tester);
        expect(await h.item('ev1'), isNull);
        expect((await h.event('ev1')).audience, 'Parents');
      });

      testWidgets('the website step fails: the event is saved, the copy is unchanged, and the message says so', (tester) async {
        await h.show(await h.seed('ev1'));
        await pump(tester);
        h.website.failWrites = true;
        await openEdit(tester);
        await tester.enterText(find.widgetWithText(TextFormField, 'Title'), 'Annual Day 2027');
        await save(tester);
        expect((await h.event('ev1')).title, 'Annual Day 2027');
        expect((await h.item('ev1'))!['title']['en'], 'Annual Day');
        expect(find.textContaining('Calendar item saved, but the public website wasn’t changed'), findsOneWidget);
        expect(find.text('Website out of date'), findsOneWidget, reason: 'the calendar shows where the copy stands');

        h.website.failWrites = false;
        await tapKey(tester, 'calendar-website-update');
        expect((await h.item('ev1'))!['title']['en'], 'Annual Day 2027');
      });
    });
  });

  test('the item for an event keeps its local date and times', () {
    final event = CalendarEventModel.fromMap('ev1', {..._eventData(startTime: '18:45', endTime: '20:00'), 'date': DateTime(2027, 12, 31)});
    final item = WebsitePublicItemsService.itemForEvent(event);
    expect(item.startAt, DateTime(2027, 12, 31, 18, 45));
    expect(item.endAt, DateTime(2027, 12, 31, 20));
    expect(item.title.en, 'Annual Day');
  });
}
