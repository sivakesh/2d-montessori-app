// Regression coverage for the Attendance screen's summary calculation —
// a pure function over already-loaded status strings, no Firestore access.
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/admin/ui/admin_attendance_management_screen.dart';

void main() {
  group('computeAttendanceSummary', () {
    test('counts present/absent/not_marked and total from the displayed population', () {
      final summary = computeAttendanceSummary([
        'present',
        'present',
        'absent',
        'not_marked',
        'not_marked',
        'not_marked',
      ]);

      expect(summary.present, 2);
      expect(summary.absent, 1);
      expect(summary.notMarked, 3);
      expect(summary.total, 6);
    });

    test('updates as a single status changes, matching the worked example', () {
      // 6 students, none marked.
      var summary = computeAttendanceSummary(List.filled(6, 'not_marked'));
      expect((summary.present, summary.absent, summary.notMarked, summary.total), (0, 0, 6, 6));

      // One marked present.
      summary = computeAttendanceSummary(['present', 'not_marked', 'not_marked', 'not_marked', 'not_marked', 'not_marked']);
      expect((summary.present, summary.absent, summary.notMarked, summary.total), (1, 0, 5, 6));

      // Another marked absent.
      summary = computeAttendanceSummary(['present', 'absent', 'not_marked', 'not_marked', 'not_marked', 'not_marked']);
      expect((summary.present, summary.absent, summary.notMarked, summary.total), (1, 1, 4, 6));
    });

    test('empty population yields all zeros, not an error', () {
      final summary = computeAttendanceSummary(const []);
      expect((summary.present, summary.absent, summary.notMarked, summary.total), (0, 0, 0, 0));
    });
  });

  // Coverage for the Student Leave -> Attendance integration's display
  // decision — a pure function over an already-resolved raw status and an
  // already-resolved "is this student on approved leave for the selected
  // date" flag, no Firestore access. `getStudentIdsOnApprovedLeave`'s own
  // date-range logic is covered separately in
  // student_leave_attendance_integration_test.dart.
  group('resolveAttendanceDisplayStatus', () {
    test('not_marked + on approved leave displays as on_leave', () {
      expect(
        resolveAttendanceDisplayStatus(rawStatus: 'not_marked', isOnApprovedLeave: true),
        'on_leave',
      );
    });

    test('not_marked + not on leave stays not_marked', () {
      expect(
        resolveAttendanceDisplayStatus(rawStatus: 'not_marked', isOnApprovedLeave: false),
        'not_marked',
      );
    });

    test('an already-Present record is never overridden by an approved leave', () {
      expect(
        resolveAttendanceDisplayStatus(rawStatus: 'present', isOnApprovedLeave: true),
        'present',
      );
    });

    test('an already-Absent record is never overridden by an approved leave', () {
      expect(
        resolveAttendanceDisplayStatus(rawStatus: 'absent', isOnApprovedLeave: true),
        'absent',
      );
    });
  });
}
