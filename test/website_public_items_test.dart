// Website public items: the sanitized copies of school events and
// announcements an administrator chooses to show on the public website.
//
// Every source record here is synthetic test data (no real students,
// parents or staff). The fake Firestore proves the app's behaviour, not
// security rules (deferred to the rules hardening phase).

import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/admin/settings/models/school_settings_model.dart';
import 'package:montessori_app/modules/admin/website/data/website_content_admin_service.dart';
import 'package:montessori_app/modules/admin/website/data/website_public_items_service.dart';
import 'package:montessori_app/modules/public_website/content/website_content_models.dart';
import 'package:montessori_app/modules/public_website/content/website_public_item.dart';

const _event = WebsitePublicItemKind.event;
const _announcement = WebsitePublicItemKind.announcement;

/// Fields a source carries that must never reach the website.
const _privateValues = ['Synthetic Creator', 'creator-0001', 'Child One', 'student-0001', 'Staff Member', 'staff-0001', 'class-0001', 'secret_report.pdf', 'https://storage.example.test/private'];

Map<String, dynamic> _calendarEvent({String status = 'Published', String audience = 'Public', String startTime = '09:30', String endTime = '12:00'}) => {
      'title': 'Annual Day',
      'date': Timestamp.fromDate(DateTime(2027, 2, 14)),
      'startTime': startTime,
      'endTime': endTime,
      'eventType': 'Event',
      'description': 'Performances by every class.',
      'location': 'School hall',
      'audience': audience,
      'status': status,
      'createdBy': 'creator-0001',
      'createdByName': 'Synthetic Creator',
      'internalNote': 'class-0001',
    };

/// A school notice. Untargeted unless [targeted]: a "Public" notice sent to
/// particular classes, students or staff is personal and never shown.
Map<String, dynamic> _notification({String status = 'Published', String audience = 'Public', bool targeted = false}) => {
      'title': 'Admissions open',
      'message': 'Admissions for 2027–28 are open.',
      'notificationType': 'General',
      'category': 'Admissions',
      'priority': 'High',
      'audience': audience,
      'visibility': audience,
      'status': status,
      'publishDate': Timestamp.fromDate(DateTime(2027, 1, 5, 8)),
      'expiryDate': Timestamp.fromDate(DateTime(2027, 3, 31)),
      'sentAt': Timestamp.fromDate(DateTime(2027, 1, 5, 8, 1)),
      'isPinned': true,
      'requiresAcknowledgement': true,
      'createdBy': 'creator-0001',
      'createdByName': 'Synthetic Creator',
      'attachmentName': 'secret_report.pdf',
      'attachmentUrl': 'https://storage.example.test/private',
      'applicableClassIds': [if (targeted) 'class-0001'],
      'applicableStudentIds': [if (targeted) 'student-0001'],
      'applicableStudentNames': [if (targeted) 'Child One'],
      'applicableStaffIds': [if (targeted) 'staff-0001'],
      'applicableStaffNames': [if (targeted) 'Staff Member'],
      // Kept from earlier forms even when nobody is targeted.
      'appliesToAllStudents': false,
      'isPublic': true,
    };

void main() {
  // ---------------------------------------------------------------- model

  group('model', () {
    final event = WebsitePublicItem(
      kind: _event,
      sourceId: 'ev1',
      title: const LocalizedText(en: 'Annual Day', ta: 'ஆண்டு விழா', others: {'hi': 'वार्षिक दिवस'}),
      body: const LocalizedText(en: 'Performances.', ta: 'நிகழ்ச்சிகள்.'),
      startAt: DateTime(2027, 2, 14, 9, 30),
      endAt: DateTime(2027, 2, 14, 12),
      location: const LocalizedText(en: 'School hall'),
      category: 'Event',
      imageMediaId: 'm1',
    );

    test('an event: stored and read back, every language kept', () {
      final map = event.toMap();
      expect(map['kind'], 'event');
      expect(map['sourceCollection'], 'school_calendar_events');
      expect(map['startAt'], isA<Timestamp>());
      expect(map['schoolId'], 'default_school');
      expect(map.keys.every(WebsitePublicItem.fields.contains), isTrue);
      final back = WebsitePublicItem.tryParse(map)!;
      expect(back.id, 'event_ev1');
      expect(back.title, event.title);
      expect(back.body, event.body);
      expect(back.startAt, event.startAt);
      expect(back.endAt, event.endAt);
      expect(back.location.en, 'School hall');
      expect(back.imageMediaId, 'm1');
      expect(back.toMap(), map);
    });

    test('an announcement: no end, an expiry and pinned', () {
      final notice = WebsitePublicItem(
        kind: _announcement,
        sourceId: 'n1',
        title: const LocalizedText(en: 'Admissions open'),
        startAt: DateTime(2027, 1, 5),
        pinned: true,
        expireAt: DateTime(2027, 3, 31),
      );
      final map = notice.toMap();
      expect(map['sourceCollection'], 'school_notifications');
      expect(map.containsKey('endAt'), isFalse);
      expect(map.containsKey('imageMediaId'), isFalse);
      final back = WebsitePublicItem.tryParse(map)!;
      expect(back.id, 'announcement_n1');
      expect(back.pinned, isTrue);
      expect(back.expireAt, DateTime(2027, 3, 31));
      expect(back.endAt, isNull);
    });

    test('unsupported kinds and malformed documents are not shown', () {
      final good = event.toMap();
      for (final (name, bad) in <(String, Object?)>[
        ('not a map', 'event'),
        ('unknown kind', {...good, 'kind': 'news'}),
        ('missing kind', {...good}..remove('kind')),
        ('kind and source disagree', {...good, 'sourceCollection': 'school_notifications'}),
        ('source id with a path', {...good, 'sourceId': '../users/x'}),
        ('empty source id', {...good, 'sourceId': ''}),
        ('no start', {...good}..remove('startAt')),
        ('start is text', {...good, 'startAt': '2027-02-14'}),
        ('no English title', {...good, 'title': {'en': '', 'ta': 'ஆண்டு விழா'}}),
        ('title is a list', {...good, 'title': ['Annual Day']}),
        ('body is text', {...good, 'body': 7}),
      ]) {
        expect(WebsitePublicItem.tryParse(bad), isNull, reason: name);
      }
    });

    test('fields outside the public model are ignored when read and never written', () {
      final withExtra = {...event.toMap(), 'createdByName': 'Synthetic Creator', 'applicableStudentNames': ['Child One']};
      final back = WebsitePublicItem.tryParse(withExtra)!;
      expect(jsonEncode(back.toMap(), toEncodable: (o) => o.toString()), isNot(contains('Synthetic Creator')));
      expect(back.toMap().keys.toSet().difference(WebsitePublicItem.fields), isEmpty);
    });

    test('validation: limits and English first in every language, end and expiry after the start', () {
      expect(event.validationErrors(), isEmpty);
      WebsitePublicItem bad({LocalizedText? title, DateTime? endAt, DateTime? expireAt, String schoolId = 'default_school'}) => WebsitePublicItem(
            kind: _event,
            sourceId: 'ev1',
            title: title ?? const LocalizedText(en: 'Annual Day'),
            startAt: DateTime(2027, 2, 14, 9),
            endAt: endAt,
            expireAt: expireAt,
            schoolId: schoolId,
          );
      expect(bad(title: LocalizedText(en: 'x' * 121)).validationErrors(), contains('The title must be 120 characters or fewer.'));
      expect(bad(title: LocalizedText(en: 'Day', ta: 'த' * 121)).validationErrors(), isNotEmpty, reason: 'Tamil is limited too');
      expect(bad(title: const LocalizedText(ta: 'ஆண்டு விழா')).validationErrors(), contains('Enter an English title.'));
      expect(bad(endAt: DateTime(2027, 2, 14, 8)).validationErrors(), contains('An event can’t end before it starts.'));
      expect(bad(expireAt: DateTime(2027, 2, 14, 9)).validationErrors(), contains('The item must be shown before it expires.'));
      expect(bad(schoolId: ' ').validationErrors(), contains('The school is missing.'));
    });

    test('school id: the app’s default school unless stored otherwise', () {
      expect(WebsitePublicItem.defaultSchoolId, kDefaultSchoolId);
      final map = event.toMap()..remove('schoolId');
      expect(WebsitePublicItem.tryParse(map)!.schoolId, kDefaultSchoolId);
      expect(WebsitePublicItem.tryParse({...map, 'schoolId': 'other_school'})!.schoolId, 'other_school');
      expect(WebsitePublicItem.tryParse({...map, 'schoolId': ''})!.schoolId, kDefaultSchoolId);
    });
  });

  // -------------------------------------------------------------- service

  group('service', () {
    late FakeFirebaseFirestore firestore;
    late WebsitePublicItemsService service;

    setUp(() async {
      firestore = FakeFirebaseFirestore();
      service = WebsitePublicItemsService(firestore: firestore);
      await firestore.collection('school_calendar_events').doc('ev1').set(_calendarEvent());
      await firestore.collection('school_notifications').doc('n1').set(_notification());
      for (final (id, published) in [('m1', true), ('m2', false)]) {
        await firestore.collection(WebsiteCollections.media).doc(id).set({
          'url': 'https://example.test/$id.jpg',
          'storagePath': 'website_media/$id/d.jpg',
          'status': published ? 'published' : 'draft',
          'consentConfirmed': published,
          'alt': {'en': 'Alt $id', 'ta': ''},
          'caption': {'en': '', 'ta': ''},
        });
      }
    });

    Future<Map<String, dynamic>?> stored(String id) async => (await firestore.collection(WebsitePublicItem.collection).doc(id).get()).data();
    Future<int> count() async => (await firestore.collection(WebsitePublicItem.collection).get()).docs.length;

    Future<WebsitePublicItem> publish(WebsitePublicItemKind kind, String id, {WebsitePublicItemExtras? extras}) =>
        service.publish(requesterRole: 'admin', kind: kind, sourceId: id, approvedForWebsite: true, extras: extras);

    final refused = throwsA(isA<WebsiteContentException>());

    test('only admins can list, read, publish, update or withdraw', () async {
      for (final role in ['staff', 'parent', 'user', '']) {
        final denied = throwsA(isA<UnauthorizedWebsiteContentException>());
        await expectLater(service.listItems(requesterRole: role), denied, reason: role);
        await expectLater(service.getItem(requesterRole: role, kind: _event, sourceId: 'ev1'), denied);
        await expectLater(service.publish(requesterRole: role, kind: _event, sourceId: 'ev1', approvedForWebsite: true), denied);
        await expectLater(service.update(requesterRole: role, kind: _event, sourceId: 'ev1'), denied);
        await expectLater(service.withdraw(requesterRole: role, kind: _event, sourceId: 'ev1'), denied);
      }
      expect(await count(), 0);
    });

    test('publishing needs explicit approval; nothing is written without it', () async {
      await expectLater(service.publish(requesterRole: 'admin', kind: _event, sourceId: 'ev1', approvedForWebsite: false), refused);
      expect(await count(), 0);
    });

    test('only a Published source for everyone can be shown; an app-wide "Public" source isn’t shown by itself', () async {
      final events = firestore.collection('school_calendar_events');
      final notices = firestore.collection('school_notifications');
      await events.doc('draft').set(_calendarEvent(status: 'Draft'));
      await events.doc('archived').set(_calendarEvent(status: 'Archived'));
      await events.doc('parents').set(_calendarEvent(audience: 'Parents'));
      await events.doc('staff').set(_calendarEvent(audience: 'Staff'));
      await notices.doc('scheduled').set(_notification(status: 'Scheduled'));
      await notices.doc('parents').set(_notification(audience: 'Parents'));
      await notices.doc('targeted').set(_notification(targeted: true));
      for (final id in ['draft', 'archived', 'parents', 'staff', 'missing']) {
        await expectLater(publish(_event, id), refused, reason: 'event $id');
      }
      for (final id in ['scheduled', 'parents', 'targeted', 'missing']) {
        await expectLater(publish(_announcement, id), refused, reason: 'announcement $id');
      }
      await expectLater(publish(_event, 'n1'), refused, reason: 'an event is read from the calendar only');
      await expectLater(publish(_event, 'bad/id'), refused);
      expect(await count(), 0, reason: 'a Public, Published source is still not on the website until an admin publishes it');
    });

    test('an event: sanitized copy of its visitor-facing fields only', () async {
      final item = await publish(_event, 'ev1');
      expect(item.id, 'event_ev1');
      final doc = (await stored('event_ev1'))!;
      expect(doc.keys.toSet().difference(WebsitePublicItem.fields), isEmpty);
      final json = jsonEncode(doc, toEncodable: (o) => o.toString());
      for (final value in _privateValues) {
        expect(json, isNot(contains(value)), reason: value);
      }
      expect(item.title.en, 'Annual Day');
      expect(item.body.en, 'Performances by every class.');
      expect(item.location.en, 'School hall');
      expect(item.category, 'Event');
      expect(item.startAt, DateTime(2027, 2, 14, 9, 30));
      expect(item.endAt, DateTime(2027, 2, 14, 12));
      expect(item.schoolId, kDefaultSchoolId);
      expect(item.publishedAt, isNotNull);

      await firestore.collection('school_calendar_events').doc('ev2').set(_calendarEvent(startTime: '', endTime: 'late'));
      final allDay = await publish(_event, 'ev2');
      expect(allDay.startAt, DateTime(2027, 2, 14), reason: 'no start time: the day itself');
      expect(allDay.endAt, isNull, reason: 'an invalid end time is left out');
    });

    test('an announcement: no creator, targeting or attachment; its dates and pin are kept', () async {
      final item = await publish(_announcement, 'n1');
      final doc = (await stored('announcement_n1'))!;
      expect(doc.keys.toSet().difference(WebsitePublicItem.fields), isEmpty);
      final json = jsonEncode(doc, toEncodable: (o) => o.toString());
      for (final value in _privateValues) {
        expect(json, isNot(contains(value)), reason: value);
      }
      expect(doc.containsKey('imageMediaId'), isFalse, reason: 'an attachment is never used as the image');
      expect(item.startAt, DateTime(2027, 1, 5, 8));
      expect(item.expireAt, DateTime(2027, 3, 31));
      expect(item.pinned, isTrue);
      expect(item.category, 'Admissions');
    });

    test('publishing again stores the same item; its first publication time is kept', () async {
      await publish(_event, 'ev1');
      final first = (await stored('event_ev1'))!;
      await publish(_event, 'ev1');
      final second = (await stored('event_ev1'))!;
      expect(second['publishedAt'], first['publishedAt']);
      Map<String, dynamic> content(Map<String, dynamic> d) => {...d}..remove('updatedAt');
      expect(content(second), content(first));
      expect(await count(), 1);
    });

    test('languages: English comes from the source, other languages from the admin, and are kept until replaced', () async {
      const tamil = WebsitePublicItemExtras(
        title: LocalizedText(en: 'ignored', ta: 'ஆண்டு விழா', others: {'hi': 'वार्षिक दिवस'}),
        body: LocalizedText(ta: 'எல்லா வகுப்புகளின் நிகழ்ச்சிகள்.'),
        location: LocalizedText(ta: 'பள்ளி அரங்கம்'),
      );
      final item = await publish(_event, 'ev1', extras: tamil);
      expect(item.title, const LocalizedText(en: 'Annual Day', ta: 'ஆண்டு விழா', others: {'hi': 'वार्षिक दिवस'}));
      expect(item.body.ta, 'எல்லா வகுப்புகளின் நிகழ்ச்சிகள்.');
      expect(item.location.ta, 'பள்ளி அரங்கம்');

      expect((await publish(_event, 'ev1')).title.ta, 'ஆண்டு விழா', reason: 'publishing again without extras keeps them');

      // The source changes: an explicit update refreshes English and keeps
      // the translations.
      await firestore.collection('school_calendar_events').doc('ev1').update({'title': 'Annual Day 2027'});
      expect((await stored('event_ev1'))!['title']['en'], 'Annual Day', reason: 'nothing changes until updated');
      final updated = await service.update(requesterRole: 'admin', kind: _event, sourceId: 'ev1');
      expect(updated.title.en, 'Annual Day 2027');
      expect(updated.title.ta, 'ஆண்டு விழா');
      expect(updated.title.others['hi'], 'वार्षिक दिवस');

      final replaced = await service.update(requesterRole: 'admin', kind: _event, sourceId: 'ev1', extras: const WebsitePublicItemExtras(title: LocalizedText(ta: 'ஆண்டு விழா 2027')));
      expect(replaced.title.ta, 'ஆண்டு விழா 2027');
      expect(replaced.title.others, isEmpty, reason: 'extras given replace what was there');
      expect(replaced.body.ta, isEmpty);
    });

    test('update: only an item already on the website, and only while its source can still be shown', () async {
      await expectLater(service.update(requesterRole: 'admin', kind: _event, sourceId: 'ev1'), refused);
      expect(await count(), 0);
      await publish(_event, 'ev1');
      final before = await stored('event_ev1');
      await firestore.collection('school_calendar_events').doc('ev1').update({'status': 'Archived'});
      await expectLater(service.update(requesterRole: 'admin', kind: _event, sourceId: 'ev1'), refused);
      expect(await stored('event_ev1'), before, reason: 'unchanged; withdrawing is a separate, explicit action');
    });

    test('images: published website media only', () async {
      final withImage = await publish(_event, 'ev1', extras: const WebsitePublicItemExtras(imageMediaId: 'm1'));
      expect(withImage.imageMediaId, 'm1');
      await expectLater(publish(_announcement, 'n1', extras: const WebsitePublicItemExtras(imageMediaId: 'm2')), refused, reason: 'not published');
      await expectLater(publish(_announcement, 'n1', extras: const WebsitePublicItemExtras(imageMediaId: 'nope')), refused, reason: 'missing');
      expect(await stored('announcement_n1'), isNull);
    });

    test('withdraw: the item leaves the website, the source stays; withdrawing again changes nothing', () async {
      await publish(_event, 'ev1');
      final source = (await firestore.collection('school_calendar_events').doc('ev1').get()).data();
      await service.withdraw(requesterRole: 'admin', kind: _event, sourceId: 'ev1');
      expect(await stored('event_ev1'), isNull);
      expect(await service.getItem(requesterRole: 'admin', kind: _event, sourceId: 'ev1'), isNull);
      await service.withdraw(requesterRole: 'admin', kind: _event, sourceId: 'ev1');
      expect((await firestore.collection('school_calendar_events').doc('ev1').get()).data(), source);
    });

    test('a field added to a stored item by anything else is dropped on the next publish', () async {
      await publish(_event, 'ev1');
      await firestore.collection(WebsitePublicItem.collection).doc('event_ev1').update({'createdByName': 'Synthetic Creator'});
      await publish(_event, 'ev1');
      expect((await stored('event_ev1'))!.containsKey('createdByName'), isFalse);
    });

    test('list: every item, newest first; unreadable documents left out', () async {
      await publish(_event, 'ev1');
      await publish(_announcement, 'n1');
      await firestore.collection(WebsitePublicItem.collection).doc('junk').set({'kind': 'news'});
      final items = await service.listItems(requesterRole: 'admin');
      expect([for (final i in items) i.id], ['event_ev1', 'announcement_n1']);
      expect(items.every((i) => i.schoolId == kDefaultSchoolId), isTrue);
    });
  });
}
