// Coverage for the School Calendar MVP (CalendarService + CalendarEventModel):
//  - Admin CRUD: create, edit, archive (safe "remove").
//  - Visibility: a Draft item never reaches the Parent/Staff feed; a
//    Published item reaches only the audience(s) it was published for
//    (plus 'Public'); an Archived item is excluded from the feed exactly
//    like a Draft one, so "removing" an item is a safe, reversible action
//    that also revokes it from every consumer immediately.
//  - Dates: the stored `date` round-trips exactly, and getEventsForAudience/
//    getAllEvents both return items sorted by event date ascending.
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/admin/notifications/data/admin_notification_service.dart';
import 'package:montessori_app/modules/calendar/models/calendar_event_model.dart';
import 'package:montessori_app/modules/calendar/services/calendar_service.dart';

// AdminNotificationService default-initializes FirebaseStorage/FilePicker to
// real platform singletons unless supplied — this stand-in avoids ever
// touching a real platform channel in a test, mirroring the same pattern
// used in admin_notification_archive_test.dart.
class _UnusedFilePicker extends FilePicker {}

CalendarService _service(FakeFirebaseFirestore firestore) => CalendarService(
      firestore: firestore,
      notificationService: AdminNotificationService(
        firestore: firestore,
        storage: MockFirebaseStorage(),
        filePicker: _UnusedFilePicker(),
      ),
    );

void main() {
  group('CalendarService — Admin CRUD', () {
    test('1. Admin can create a calendar item, saved as Draft', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);

      final id = await service.createEvent({
        'title': 'Term Exam Week',
        'date': DateTime(2026, 9, 10),
        'startTime': '',
        'endTime': '',
        'eventType': CalendarEventType.exam,
        'description': 'Term 1 exams begin.',
        'location': '',
        'audience': 'Public',
        'status': CalendarEventStatus.draft,
        'createdBy': 'admin-1',
        'createdByName': 'Admin',
      });

      final all = await service.getAllEvents();
      final created = all.singleWhere((e) => e.id == id);
      expect(created.title, 'Term Exam Week');
      expect(created.status, CalendarEventStatus.draft);
      expect(created.eventType, CalendarEventType.exam);
    });

    test('2. Calendar item can be edited', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      final id = await service.createEvent({
        'title': 'Staff Meeting',
        'date': DateTime(2026, 9, 1),
        'startTime': '',
        'endTime': '',
        'eventType': CalendarEventType.staffMeeting,
        'description': '',
        'location': '',
        'audience': 'Staff',
        'status': CalendarEventStatus.draft,
        'createdBy': 'admin-1',
        'createdByName': 'Admin',
      });

      await service.updateEvent(id, {
        'title': 'Staff Meeting (Rescheduled)',
        'date': DateTime(2026, 9, 3),
        'startTime': '10:00',
        'endTime': '11:00',
        'eventType': CalendarEventType.staffMeeting,
        'description': 'Moved by two days.',
        'location': 'Staff Room',
        'audience': 'Staff',
      });

      final all = await service.getAllEvents();
      final edited = all.singleWhere((e) => e.id == id);
      expect(edited.title, 'Staff Meeting (Rescheduled)');
      expect(edited.date, DateTime(2026, 9, 3));
      expect(edited.startTime, '10:00');
      expect(edited.location, 'Staff Room');
    });

    test('3. Calendar item can be archived safely (document preserved, hidden from feeds)', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      final id = await service.createEvent({
        'title': 'Old Notice',
        'date': DateTime(2026, 8, 1),
        'startTime': '',
        'endTime': '',
        'eventType': CalendarEventType.event,
        'description': '',
        'location': '',
        'audience': 'Public',
        'status': CalendarEventStatus.published,
        'createdBy': 'admin-1',
        'createdByName': 'Admin',
      });

      await service.archiveEvent(id);

      final all = await service.getAllEvents();
      final archived = all.singleWhere((e) => e.id == id);
      expect(archived.status, CalendarEventStatus.archived);
      expect(archived.title, 'Old Notice');

      final parentFeed = await service.getEventsForAudience('Parents');
      final staffFeed = await service.getEventsForAudience('Staff');
      expect(parentFeed.where((e) => e.id == id), isEmpty);
      expect(staffFeed.where((e) => e.id == id), isEmpty);
    });
  });

  group('CalendarService — visibility', () {
    test('4. A Draft item never appears in the Parent feed even with Public audience', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      await service.createEvent({
        'title': 'Unpublished holiday notice',
        'date': DateTime(2026, 10, 2),
        'startTime': '',
        'endTime': '',
        'eventType': CalendarEventType.schoolHoliday,
        'description': '',
        'location': '',
        'audience': 'Public',
        'status': CalendarEventStatus.draft,
        'createdBy': 'admin-1',
        'createdByName': 'Admin',
      });

      final feed = await service.getEventsForAudience('Parents');
      expect(feed, isEmpty);
    });

    test('5. A Published, Parents-audience item appears in the Parent feed', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      final id = await service.createEvent({
        'title': 'Annual Day',
        'date': DateTime(2026, 12, 5),
        'startTime': '17:00',
        'endTime': '19:00',
        'eventType': CalendarEventType.event,
        'description': 'Annual day celebrations.',
        'location': 'Main Hall',
        'audience': 'Parents',
        'status': CalendarEventStatus.draft,
        'createdBy': 'admin-1',
        'createdByName': 'Admin',
      });
      final created = (await service.getAllEvents()).singleWhere((e) => e.id == id);
      await service.publishEvent(created);

      final parentFeed = await service.getEventsForAudience('Parents');
      expect(parentFeed.map((e) => e.id), contains(id));
    });

    test('6. A Published, Staff-audience item appears in the Staff feed', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      final id = await service.createEvent({
        'title': 'Monthly Staff Meeting',
        'date': DateTime(2026, 9, 15),
        'startTime': '',
        'endTime': '',
        'eventType': CalendarEventType.staffMeeting,
        'description': '',
        'location': '',
        'audience': 'Staff',
        'status': CalendarEventStatus.draft,
        'createdBy': 'admin-1',
        'createdByName': 'Admin',
      });
      final created = (await service.getAllEvents()).singleWhere((e) => e.id == id);
      await service.publishEvent(created);

      final staffFeed = await service.getEventsForAudience('Staff');
      expect(staffFeed.map((e) => e.id), contains(id));
    });

    test('7. A Staff-only published item is not visible to Parents, and vice versa', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      final staffOnlyId = await service.createEvent({
        'title': 'Staff Training',
        'date': DateTime(2026, 9, 20),
        'startTime': '',
        'endTime': '',
        'eventType': CalendarEventType.staffMeeting,
        'description': '',
        'location': '',
        'audience': 'Staff',
        'status': CalendarEventStatus.published,
        'createdBy': 'admin-1',
        'createdByName': 'Admin',
      });
      final parentOnlyId = await service.createEvent({
        'title': 'PTA Meeting',
        'date': DateTime(2026, 9, 22),
        'startTime': '',
        'endTime': '',
        'eventType': CalendarEventType.parentMeeting,
        'description': '',
        'location': '',
        'audience': 'Parents',
        'status': CalendarEventStatus.published,
        'createdBy': 'admin-1',
        'createdByName': 'Admin',
      });

      final parentFeed = await service.getEventsForAudience('Parents');
      final staffFeed = await service.getEventsForAudience('Staff');

      expect(parentFeed.map((e) => e.id), isNot(contains(staffOnlyId)));
      expect(staffFeed.map((e) => e.id), isNot(contains(parentOnlyId)));
      expect(parentFeed.map((e) => e.id), contains(parentOnlyId));
      expect(staffFeed.map((e) => e.id), contains(staffOnlyId));
    });
  });

  group('CalendarService — dates', () {
    test('8. Event dates round-trip exactly and lists sort by date ascending', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      await service.createEvent({
        'title': 'Later Event',
        'date': DateTime(2026, 11, 20),
        'startTime': '',
        'endTime': '',
        'eventType': CalendarEventType.event,
        'description': '',
        'location': '',
        'audience': 'Public',
        'status': CalendarEventStatus.published,
        'createdBy': 'admin-1',
        'createdByName': 'Admin',
      });
      await service.createEvent({
        'title': 'Earlier Event',
        'date': DateTime(2026, 9, 5),
        'startTime': '',
        'endTime': '',
        'eventType': CalendarEventType.event,
        'description': '',
        'location': '',
        'audience': 'Public',
        'status': CalendarEventStatus.published,
        'createdBy': 'admin-1',
        'createdByName': 'Admin',
      });

      final all = await service.getAllEvents();
      expect(all.map((e) => e.title), ['Earlier Event', 'Later Event']);
      expect(all.first.date, DateTime(2026, 9, 5));

      final feed = await service.getEventsForAudience('Public');
      expect(feed.map((e) => e.title), ['Earlier Event', 'Later Event']);
    });
  });
}
