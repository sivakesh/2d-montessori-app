import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../models/calendar_event_model.dart';

/// (Color, Icon) used to visually distinguish an event type — shared by the
/// List, Month, and Week views so a "School Holiday" always reads the same
/// color/icon everywhere it appears on the calendar.
(Color, IconData) calendarEventTypeStyle(String eventType) {
  return switch (eventType) {
    CalendarEventType.schoolHoliday => (Colors.redAccent, Icons.beach_access_outlined),
    CalendarEventType.workingDay => (AppColors.secondary, Icons.work_outline),
    CalendarEventType.exam => (Colors.deepPurple, Icons.edit_note_outlined),
    CalendarEventType.parentMeeting => (Colors.orange, Icons.people_alt_outlined),
    CalendarEventType.staffMeeting => (Colors.blueGrey, Icons.groups_outlined),
    CalendarEventType.event => (AppColors.primary, Icons.event_outlined),
    _ => (Colors.teal, Icons.star_outline),
  };
}

/// (Label, Color) for a calendar item's Draft/Published/Archived lifecycle
/// status — Admin-only display (Staff/Parent never see anything but
/// Published items in the first place).
(String, Color) calendarEventStatusStyle(String status) {
  return switch (status) {
    CalendarEventStatus.published => ('Published', AppColors.secondary),
    CalendarEventStatus.archived => ('Archived', Colors.grey),
    _ => ('Draft', Colors.orange),
  };
}
