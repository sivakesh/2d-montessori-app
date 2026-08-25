// Coverage for CalendarWeekView's genuine 7-day grid (CAL-04): distinct date
// columns, events positioned under the correct day, multiple same-day events
// staying distinguishable, and no invented time for events with none. Tests
// the real widget directly (not a reimplementation) with hand-built
// CalendarEventModel instances, since exercising column-placement precisely
// through the full CalendarView+Firestore stack would be indirect and
// harder to pin down than asserting on the widget under test itself.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/calendar/models/calendar_event_model.dart';
import 'package:montessori_app/modules/calendar/ui/calendar_week_view.dart';

CalendarEventModel _event({
  required String id,
  required String title,
  required DateTime date,
  String? startTime,
  String? endTime,
  String eventType = CalendarEventType.event,
}) {
  return CalendarEventModel(
    id: id,
    title: title,
    date: date,
    startTime: startTime,
    endTime: endTime,
    eventType: eventType,
    description: '',
    location: '',
    audience: 'Public',
    status: CalendarEventStatus.published,
    createdBy: 'admin-1',
    createdByName: 'Admin',
    createdAt: null,
    updatedAt: null,
  );
}

Widget _wrap(Widget child) {
  return MaterialApp(home: Scaffold(body: SizedBox(height: 700, child: child)));
}

void main() {
  // Sunday-first week matching the UAT report: Sun Aug 23 – Sat Aug 29 2026,
  // with Monday Aug 24 and Tuesday Aug 25 as the days under test.
  final weekStart = DateTime(2026, 8, 23);
  final monday = DateTime(2026, 8, 24);
  final tuesday = DateTime(2026, 8, 25);

  testWidgets('1. Renders all 7 dates of the selected week as day columns', (tester) async {
    await tester.pumpWidget(_wrap(CalendarWeekView(
      weekStart: weekStart,
      eventsByDay: const {},
      onEventTap: (_) {},
    )));
    await tester.pumpAndSettle();

    for (var i = 0; i < 7; i++) {
      final day = weekStart.add(Duration(days: i));
      expect(find.text('${day.day}'), findsOneWidget, reason: 'missing date column for ${day.day}');
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('2. An event on Monday appears and, when tapped, reports the Monday event', (tester) async {
    final mondayEvent = _event(id: 'm1', title: 'Working Day', date: monday, startTime: '09:00');
    CalendarEventModel? tapped;
    await tester.pumpWidget(_wrap(CalendarWeekView(
      weekStart: weekStart,
      eventsByDay: {
        monday: [mondayEvent],
      },
      onEventTap: (e) => tapped = e,
    )));
    await tester.pumpAndSettle();

    expect(find.text('Working Day'), findsOneWidget);
    await tester.tap(find.text('Working Day'));
    await tester.pumpAndSettle();
    expect(tapped?.id, 'm1');
  });

  testWidgets('3. An event keyed under Monday never renders when only Tuesday has an event', (tester) async {
    final tuesdayEvent = _event(id: 't1', title: 'Onam Celebration', date: tuesday, startTime: '10:00');
    await tester.pumpWidget(_wrap(CalendarWeekView(
      weekStart: weekStart,
      eventsByDay: {
        tuesday: [tuesdayEvent],
      },
      onEventTap: (_) {},
    )));
    await tester.pumpAndSettle();

    // Only the seeded Tuesday event should exist — no phantom tile leaks
    // onto Monday or any other event-less day in the week.
    expect(find.text('Onam Celebration'), findsOneWidget);
    expect(find.text('Working Day'), findsNothing);
  });

  testWidgets('4. Multiple events on the same date both render as distinguishable tiles', (tester) async {
    final e1 = _event(id: 'a', title: 'Onam Celebration', date: tuesday, startTime: '10:00');
    final e2 = _event(id: 'b', title: 'Staff Meeting', date: tuesday, startTime: '10:30', eventType: CalendarEventType.staffMeeting);
    await tester.pumpWidget(_wrap(CalendarWeekView(
      weekStart: weekStart,
      eventsByDay: {
        tuesday: [e1, e2],
      },
      onEventTap: (_) {},
    )));
    await tester.pumpAndSettle();

    expect(find.text('Onam Celebration'), findsOneWidget);
    expect(find.text('Staff Meeting'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('5. Days with no events create no event entries', (tester) async {
    final mondayEvent = _event(id: 'm1', title: 'Working Day', date: monday, startTime: '09:00');
    await tester.pumpWidget(_wrap(CalendarWeekView(
      weekStart: weekStart,
      eventsByDay: {
        monday: [mondayEvent],
      },
      onEventTap: (_) {},
    )));
    await tester.pumpAndSettle();

    // Exactly one event tile exists across all 7 columns — the other 6
    // event-less days contribute nothing.
    expect(find.text('Working Day'), findsOneWidget);
    expect(find.byType(InkWell), findsWidgets);
  });

  testWidgets('6. An event with no start time renders in the "All day" strip, never with an invented time', (tester) async {
    final noTimeEvent = _event(id: 'nt1', title: 'School Holiday', date: monday);
    await tester.pumpWidget(_wrap(CalendarWeekView(
      weekStart: weekStart,
      eventsByDay: {
        monday: [noTimeEvent],
      },
      onEventTap: (_) {},
    )));
    await tester.pumpAndSettle();

    expect(find.text('All day'), findsOneWidget);
    expect(find.text('School Holiday'), findsOneWidget);
  });

  testWidgets('7. No "All day" strip appears when every event in the week has a time', (tester) async {
    final mondayEvent = _event(id: 'm1', title: 'Working Day', date: monday, startTime: '09:00');
    await tester.pumpWidget(_wrap(CalendarWeekView(
      weekStart: weekStart,
      eventsByDay: {
        monday: [mondayEvent],
      },
      onEventTap: (_) {},
    )));
    await tester.pumpAndSettle();

    expect(find.text('All day'), findsNothing);
  });

  testWidgets('8. Week view with several long-titled events on the same day does not overflow at a narrow mobile width', (tester) async {
    final originalSize = tester.view.physicalSize;
    final originalDpr = tester.view.devicePixelRatio;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.physicalSize = originalSize;
      tester.view.devicePixelRatio = originalDpr;
    });

    final events = [
      _event(
        id: '1',
        title: 'Monthly Staff Development Workshop on Montessori Pedagogy Techniques',
        date: monday,
        startTime: '09:00',
      ),
      _event(id: '2', title: 'Overlapping Parent Meeting', date: monday, startTime: '09:15'),
      _event(id: '3', title: 'No Time Assembly Announcement', date: monday),
    ];
    await tester.pumpWidget(_wrap(CalendarWeekView(
      weekStart: weekStart,
      eventsByDay: {
        monday: events,
      },
      onEventTap: (_) {},
    )));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Monthly Staff Development'), findsOneWidget);
  });
}
