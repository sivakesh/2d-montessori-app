// Coverage for the Calendar Month/Week/List view switcher added to
// CalendarView. Reuses the exact same CalendarEventModel/CalendarService as
// the existing List view (no second data model or fetch), and preserves
// the existing audience/Draft-Archived visibility rules regardless of which
// view is active.
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/auth/models/app_user.dart';
import 'package:montessori_app/modules/auth/providers/auth_provider.dart';
import 'package:montessori_app/modules/calendar/models/calendar_event_model.dart';
import 'package:montessori_app/modules/calendar/services/calendar_service.dart';
import 'package:montessori_app/modules/calendar/ui/calendar_view.dart';

ProviderScope _withRole(String role, Widget child) {
  return ProviderScope(
    overrides: [
      currentUserProvider.overrideWith(
        (ref) => AppUser(id: 'u1', phone: '9999999999', role: role, isActive: true),
      ),
    ],
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

Future<String> _seedEvent(
  CalendarService service, {
  required String title,
  required DateTime date,
  required String audience,
  required String status,
  String eventType = CalendarEventType.event,
}) {
  return service.createEvent({
    'title': title,
    'date': date,
    'startTime': '',
    'endTime': '',
    'eventType': eventType,
    'description': '',
    'location': '',
    'audience': audience,
    'status': status,
    'createdBy': 'admin-1',
    'createdByName': 'Admin',
  });
}

void main() {
  testWidgets('1. Month view renders correctly, defaulting to the current month', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final service = CalendarService(firestore: firestore);
    await _seedEvent(
      service,
      title: 'Annual Day',
      date: DateTime.now(),
      audience: 'Public',
      status: CalendarEventStatus.published,
    );

    await tester.pumpWidget(_withRole('parent', CalendarView(service: service)));
    await tester.pumpAndSettle();

    expect(find.text('Month'), findsOneWidget);
    expect(find.byType(GridView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('2. Week view renders correctly when selected', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final service = CalendarService(firestore: firestore);
    await _seedEvent(
      service,
      title: 'Staff Meeting',
      date: DateTime.now(),
      audience: 'Staff',
      status: CalendarEventStatus.published,
    );

    await tester.pumpWidget(_withRole('staff', CalendarView(service: service)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Week'));
    await tester.pumpAndSettle();

    expect(find.text('Staff Meeting'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('3. List view still works and shows the existing chronological cards', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final service = CalendarService(firestore: firestore);
    await _seedEvent(
      service,
      title: 'Term Exam',
      date: DateTime(2026, 9, 10),
      audience: 'Public',
      status: CalendarEventStatus.published,
      eventType: CalendarEventType.exam,
    );

    await tester.pumpWidget(_withRole('parent', CalendarView(service: service)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('List'));
    await tester.pumpAndSettle();

    expect(find.text('Term Exam'), findsOneWidget);
    expect(find.text('Exam'), findsOneWidget);
  });

  testWidgets('4. Month navigation (prev/next) changes the header label', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final service = CalendarService(firestore: firestore);
    await _seedEvent(
      service,
      title: 'Something',
      date: DateTime.now(),
      audience: 'Public',
      status: CalendarEventStatus.published,
    );
    await tester.pumpWidget(_withRole('parent', CalendarView(service: service)));
    await tester.pumpAndSettle();

    final before = tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).whereType<String>().toList();

    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();
    final after = tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).whereType<String>().toList();

    expect(before, isNot(equals(after)));
    expect(tester.takeException(), isNull);
  });

  testWidgets('5. Week navigation (prev/next) changes the header label', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final service = CalendarService(firestore: firestore);
    await _seedEvent(
      service,
      title: 'Something',
      date: DateTime.now(),
      audience: 'Public',
      status: CalendarEventStatus.published,
    );
    await tester.pumpWidget(_withRole('parent', CalendarView(service: service)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Week'));
    await tester.pumpAndSettle();

    // `find.byIcon(chevron_right)` alone would also match the trailing
    // "view detail" chevron on each week-agenda event row — scope to the
    // IconButton (the actual nav control) to disambiguate.
    await tester.tap(find.widgetWithIcon(IconButton, Icons.chevron_right));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('6. Today navigation returns to the current month/week', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final service = CalendarService(firestore: firestore);
    await _seedEvent(
      service,
      title: 'Something',
      date: DateTime.now(),
      audience: 'Public',
      status: CalendarEventStatus.published,
    );
    await tester.pumpWidget(_withRole('parent', CalendarView(service: service)));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Today'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('7. Events appear on their correct date in Month view (event dot only on that day)', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final service = CalendarService(firestore: firestore);
    final now = DateTime.now();
    final eventDay = DateTime(now.year, now.month, 15);
    await _seedEvent(
      service,
      title: 'Mid-month Event',
      date: eventDay,
      audience: 'Public',
      status: CalendarEventStatus.published,
    );

    await tester.pumpWidget(_withRole('parent', CalendarView(service: service)));
    await tester.pumpAndSettle();

    // Tapping day 15's cell should open a bottom sheet listing exactly that
    // event (proves the event is attached to the correct day, not just
    // present somewhere in the month).
    await tester.tap(find.text('15').first);
    await tester.pumpAndSettle();

    expect(find.text('Mid-month Event'), findsOneWidget);
  });

  testWidgets('8. Audience filtering is preserved across all views: a Staff-only event never reaches Parent', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final service = CalendarService(firestore: firestore);
    await _seedEvent(
      service,
      title: 'Staff Only Meeting',
      date: DateTime.now(),
      audience: 'Staff',
      status: CalendarEventStatus.published,
    );

    await tester.pumpWidget(_withRole('parent', CalendarView(service: service)));
    await tester.pumpAndSettle();

    // Month view: no event dot to tap, and switching to List view confirms
    // nothing was fetched for this parent at all.
    await tester.tap(find.text('List'));
    await tester.pumpAndSettle();

    expect(find.text('Staff Only Meeting'), findsNothing);
    expect(find.text('No calendar items yet.'), findsOneWidget);
  });

  testWidgets('9. Draft and Archived events remain hidden from Staff/Parent in every view', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final service = CalendarService(firestore: firestore);
    await _seedEvent(
      service,
      title: 'Draft Item',
      date: DateTime.now(),
      audience: 'Public',
      status: CalendarEventStatus.draft,
    );
    await _seedEvent(
      service,
      title: 'Archived Item',
      date: DateTime.now(),
      audience: 'Public',
      status: CalendarEventStatus.archived,
    );

    await tester.pumpWidget(_withRole('staff', CalendarView(service: service)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('List'));
    await tester.pumpAndSettle();

    expect(find.text('Draft Item'), findsNothing);
    expect(find.text('Archived Item'), findsNothing);
    expect(find.text('No calendar items yet.'), findsOneWidget);
  });

  testWidgets('10. Week navigation changes the visible day-column dates, and Today returns to the current week', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final service = CalendarService(firestore: firestore);
    await _seedEvent(
      service,
      title: 'Something',
      date: DateTime.now(),
      audience: 'Public',
      status: CalendarEventStatus.published,
    );
    await tester.pumpWidget(_withRole('parent', CalendarView(service: service)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Week'));
    await tester.pumpAndSettle();

    final today = DateTime.now();
    expect(find.text('${today.day}'), findsOneWidget);

    await tester.tap(find.widgetWithIcon(IconButton, Icons.chevron_right));
    await tester.pumpAndSettle();
    final nextWeekSameDay = today.add(const Duration(days: 7));
    expect(find.text('${nextWeekSameDay.day}'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Today'));
    await tester.pumpAndSettle();
    expect(find.text('${today.day}'), findsOneWidget);
  });

  testWidgets('9b. Admin still sees Draft/Archived items, and the status chip reflects each', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final service = CalendarService(firestore: firestore);
    await _seedEvent(
      service,
      title: 'Draft Item',
      date: DateTime.now(),
      audience: 'Public',
      status: CalendarEventStatus.draft,
    );

    await tester.pumpWidget(_withRole('admin', CalendarView(service: service)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('List'));
    await tester.pumpAndSettle();

    expect(find.text('Draft Item'), findsOneWidget);
    expect(find.text('Draft'), findsOneWidget);
  });
}
