// Coverage for the Calendar Entry Delete feature:
//  - CalendarService.deleteEvent performs a genuine Firestore removal, not
//    a status change — the document disappears from both Admin's full list
//    and every consumer audience feed, and other events/notifications are
//    left untouched.
//  - CalendarView's UI requires confirmation before deleting, and Cancel
//    leaves the document unchanged.
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/admin/notifications/data/admin_notification_service.dart';
import 'package:montessori_app/modules/auth/models/app_user.dart';
import 'package:montessori_app/modules/auth/providers/auth_provider.dart';
import 'package:montessori_app/modules/calendar/models/calendar_event_model.dart';
import 'package:montessori_app/modules/calendar/services/calendar_service.dart';
import 'package:montessori_app/modules/calendar/ui/calendar_view.dart';

class _UnusedFilePicker extends FilePicker {}

CalendarService _service(FakeFirebaseFirestore firestore) => CalendarService(
      firestore: firestore,
      notificationService: AdminNotificationService(
        firestore: firestore,
        storage: MockFirebaseStorage(),
        filePicker: _UnusedFilePicker(),
      ),
    );

Future<String> _seedEvent(
  CalendarService service, {
  required String title,
  required String status,
  required String audience,
  DateTime? date,
}) {
  return service.createEvent({
    'title': title,
    'date': date ?? DateTime(2026, 9, 1),
    'startTime': '',
    'endTime': '',
    'eventType': CalendarEventType.event,
    'description': '',
    'location': '',
    'audience': audience,
    'status': status,
    'createdBy': 'admin-1',
    'createdByName': 'Admin',
  });
}

ProviderScope _withAdminUser(Widget child) {
  return ProviderScope(
    overrides: [
      currentUserProvider.overrideWith(
        (ref) => AppUser(id: 'admin-1', phone: '9999999999', role: 'admin', isActive: true),
      ),
    ],
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

void main() {
  group('CalendarService.deleteEvent', () {
    test('permanently removes the document from the collection', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      final id = await _seedEvent(service, title: 'Old Notice', status: CalendarEventStatus.published, audience: 'Public');

      await service.deleteEvent(id);

      final doc = await firestore.collection('school_calendar_events').doc(id).get();
      expect(doc.exists, isFalse);
    });

    test('removed from Admin\'s getAllEvents (unlike archive, which keeps the document)', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      final id = await _seedEvent(service, title: 'Old Notice', status: CalendarEventStatus.draft, audience: 'Public');

      await service.deleteEvent(id);

      final all = await service.getAllEvents();
      expect(all.where((e) => e.id == id), isEmpty);
    });

    test('removed from every consumer audience feed', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      final id = await _seedEvent(service, title: 'Assembly', status: CalendarEventStatus.published, audience: 'Public');

      await service.deleteEvent(id);

      final parentFeed = await service.getEventsForAudience('Parents');
      final staffFeed = await service.getEventsForAudience('Staff');
      expect(parentFeed.where((e) => e.id == id), isEmpty);
      expect(staffFeed.where((e) => e.id == id), isEmpty);
    });

    test('deleting one event does not affect another, unrelated event', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      final deletedId = await _seedEvent(service, title: 'To Delete', status: CalendarEventStatus.published, audience: 'Public');
      final keptId = await _seedEvent(service, title: 'To Keep', status: CalendarEventStatus.published, audience: 'Public');

      await service.deleteEvent(deletedId);

      final all = await service.getAllEvents();
      expect(all.map((e) => e.id), [keptId]);
      final kept = all.singleWhere((e) => e.id == keptId);
      expect(kept.title, 'To Keep');
    });

    test('deleting a calendar event does not touch school_notifications', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      // Publishing creates a best-effort notification — deleting afterward
      // must leave that notification exactly as it was.
      final id = await _seedEvent(service, title: 'Assembly', status: CalendarEventStatus.draft, audience: 'Public');
      final event = (await service.getAllEvents()).single;
      await service.publishEvent(event);
      final notificationsBefore = await firestore.collection('school_notifications').get();

      await service.deleteEvent(id);

      final notificationsAfter = await firestore.collection('school_notifications').get();
      expect(notificationsAfter.docs.length, notificationsBefore.docs.length);
    });
  });

  group('CalendarView — Delete UI', () {
    testWidgets('Admin sees a Delete action in the List view', (tester) async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      await _seedEvent(service, title: 'Old Notice', status: CalendarEventStatus.published, audience: 'Public');

      await tester.pumpWidget(_withAdminUser(CalendarView(service: service)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('List'));
      await tester.pumpAndSettle();

      expect(find.text('Delete'), findsOneWidget);
    });

    testWidgets('tapping Delete requires confirmation before anything is removed', (tester) async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      final id = await _seedEvent(service, title: 'Old Notice', status: CalendarEventStatus.published, audience: 'Public');

      await tester.pumpWidget(_withAdminUser(CalendarView(service: service)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('List'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Delete calendar item?'), findsOneWidget);
      final doc = await firestore.collection('school_calendar_events').doc(id).get();
      expect(doc.exists, isTrue);
    });

    testWidgets('Cancel leaves the calendar item completely unchanged', (tester) async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      final id = await _seedEvent(service, title: 'Old Notice', status: CalendarEventStatus.published, audience: 'Public');

      await tester.pumpWidget(_withAdminUser(CalendarView(service: service)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('List'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Old Notice'), findsOneWidget);
      final doc = await firestore.collection('school_calendar_events').doc(id).get();
      expect(doc.exists, isTrue);
    });

    testWidgets('confirming Delete removes the item from the list and shows a success message', (tester) async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      await _seedEvent(service, title: 'Old Notice', status: CalendarEventStatus.published, audience: 'Public');

      await tester.pumpWidget(_withAdminUser(CalendarView(service: service)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('List'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Calendar item deleted'), findsOneWidget);
      expect(find.text('Old Notice'), findsNothing);
    });

    testWidgets('Staff/Parent never see a Delete action', (tester) async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      await _seedEvent(service, title: 'Assembly', status: CalendarEventStatus.published, audience: 'Public');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWith(
              (ref) => AppUser(id: 'parent-1', phone: '9999999999', role: 'parent', isActive: true),
            ),
          ],
          child: MaterialApp(home: Scaffold(body: CalendarView(service: service))),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('List'));
      await tester.pumpAndSettle();

      expect(find.text('Delete'), findsNothing);
    });
  });
}
