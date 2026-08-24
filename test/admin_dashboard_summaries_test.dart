// Coverage for the Admin Dashboard's Calendar summary — a pure
// text-formatting function over already-loaded events, no Firestore access
// (AdminDashboardScreen itself uses FirebaseFirestore.instance/
// CalendarService() directly with no injection seam, so — like
// AdminAttendanceManagementScreen's computeAttendanceSummary — the testable
// unit is this pure logic, not the full screen).
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/admin/ui/admin_dashboard_screen.dart';
import 'package:montessori_app/modules/calendar/models/calendar_event_model.dart';

CalendarEventModel _event({required String title, required DateTime date}) {
  return CalendarEventModel(
    id: 'id-$title',
    title: title,
    date: date,
    startTime: null,
    endTime: null,
    eventType: CalendarEventType.event,
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

void main() {
  group('formatUpcomingEventsSummary', () {
    test('no upcoming events', () {
      expect(formatUpcomingEventsSummary(const []), 'No upcoming events');
    });

    test('a single upcoming event includes its title and date', () {
      final summary = formatUpcomingEventsSummary([
        _event(title: 'Sports Day', date: DateTime(2026, 11, 5)),
      ]);
      expect(summary, 'Sports Day (Nov 5)');
    });

    test('multiple upcoming events are joined in the given order', () {
      final summary = formatUpcomingEventsSummary([
        _event(title: 'Diwali Holiday', date: DateTime(2026, 10, 20)),
        _event(title: 'Sports Day', date: DateTime(2026, 11, 5)),
      ]);
      expect(summary, 'Diwali Holiday (Oct 20), Sports Day (Nov 5)');
    });
  });
}
