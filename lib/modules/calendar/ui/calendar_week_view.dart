import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../models/calendar_event_model.dart';
import 'calendar_event_style.dart';

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Parses a "HH:mm" 24-hour time-of-day string (the format
/// [CalendarEventModel.startTime]/[CalendarEventModel.endTime] are always
/// stored in) into minutes since midnight, or null if [time] is
/// null/blank/unparsable. Callers must treat a null result as "no
/// meaningful time" and never substitute a default — an event with no time
/// belongs in the unscheduled strip, not at an invented position on the
/// hourly grid.
int? _parseMinutes(String? time) {
  if (time == null || time.isEmpty) return null;
  final parts = time.split(':');
  if (parts.length != 2) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null) return null;
  return h * 60 + m;
}

const double _hourHeight = 60;
const double _timeAxisWidth = 44;
const double _minDayColumnWidth = 108;

/// A genuine 7-day week grid: a day-of-week/date header row, an optional
/// all-day/unscheduled strip for events with no time-of-day, and an hourly
/// time grid below where every timed event is a tile positioned in its own
/// date column at its own vertical time offset — never grouped into a
/// single vertical agenda list. Tapping an event opens [onEventTap].
///
/// Below the minimum readable column width, the grid scrolls horizontally
/// instead of squeezing 7 columns into an unreadable width; the hourly
/// grid itself scrolls vertically. The default visible hour range is
/// 7 AM–7 PM, widened automatically to fit any event that falls outside it
/// so no event is ever clipped off the grid.
class CalendarWeekView extends StatelessWidget {
  const CalendarWeekView({
    super.key,
    required this.weekStart,
    required this.eventsByDay,
    required this.onEventTap,
  });

  /// The first day (Sunday) of the focused week, normalized to midnight.
  final DateTime weekStart;
  final Map<DateTime, List<CalendarEventModel>> eventsByDay;
  final void Function(CalendarEventModel event) onEventTap;

  @override
  Widget build(BuildContext context) {
    final days = List.generate(7, (i) => weekStart.add(Duration(days: i)));
    final today = DateTime.now();

    final timedByDay = <DateTime, List<_TimedEvent>>{};
    final unscheduledByDay = <DateTime, List<CalendarEventModel>>{};
    var minStartMinute = 7 * 60;
    var maxEndMinute = 19 * 60;

    for (final day in days) {
      final events = eventsByDay[day] ?? const [];
      final timed = <_TimedEvent>[];
      final unscheduled = <CalendarEventModel>[];
      for (final event in events) {
        final start = _parseMinutes(event.startTime);
        if (start == null) {
          unscheduled.add(event);
          continue;
        }
        var end = _parseMinutes(event.endTime) ?? (start + 45);
        if (end <= start) end = start + 45;
        timed.add(_TimedEvent(event: event, startMinute: start, endMinute: end));
        if (start < minStartMinute) minStartMinute = start;
        if (end > maxEndMinute) maxEndMinute = end;
      }
      timed.sort((a, b) => a.startMinute.compareTo(b.startMinute));
      timedByDay[day] = _assignColumns(timed);
      if (unscheduled.isNotEmpty) unscheduledByDay[day] = unscheduled;
    }

    final gridStartHour = minStartMinute ~/ 60;
    final gridEndHour = (maxEndMinute / 60).ceil();
    final hours = List.generate(math.max(1, gridEndHour - gridStartHour), (i) => gridStartHour + i);
    final gridHeight = hours.length * _hourHeight;
    final hasUnscheduled = unscheduledByDay.isNotEmpty;

    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth - _timeAxisWidth;
        final columnWidth = math.max(_minDayColumnWidth, available / 7);
        final contentWidth = _timeAxisWidth + columnWidth * 7;
        final needsHScroll = contentWidth > constraints.maxWidth + 0.5;
        final maxHeight = constraints.hasBoundedHeight ? constraints.maxHeight : null;

        final content = SizedBox(
          width: needsHScroll ? contentWidth : constraints.maxWidth,
          height: maxHeight,
          child: Column(
            children: [
              _WeekHeaderRow(days: days, today: today, columnWidth: columnWidth),
              const Divider(height: 1),
              if (hasUnscheduled) ...[
                _UnscheduledRow(
                  days: days,
                  columnWidth: columnWidth,
                  unscheduledByDay: unscheduledByDay,
                  onEventTap: onEventTap,
                ),
                const Divider(height: 1),
              ],
              Expanded(
                child: SingleChildScrollView(
                  child: SizedBox(
                    height: gridHeight,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _HourAxis(hours: hours),
                        for (final day in days)
                          _DayColumn(
                            width: columnWidth,
                            hours: hours,
                            gridStartHour: gridStartHour,
                            isToday: _isSameDay(day, today),
                            events: timedByDay[day] ?? const [],
                            onEventTap: onEventTap,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );

        if (!needsHScroll) return content;
        return SingleChildScrollView(scrollDirection: Axis.horizontal, child: content);
      },
    );
  }
}

/// Greedy interval-graph coloring: sweeps [sortedEvents] (already sorted by
/// start time) left-to-right, reusing the first column whose last event has
/// already ended, else opening a new one. Every event that overlaps another
/// in time ends up in a distinct column so overlapping events on the same
/// date are always laid out side by side rather than stacked unreadably on
/// top of each other.
List<_TimedEvent> _assignColumns(List<_TimedEvent> sortedEvents) {
  final columnEndMinutes = <int>[];
  for (final item in sortedEvents) {
    var placedIndex = -1;
    for (var c = 0; c < columnEndMinutes.length; c++) {
      if (columnEndMinutes[c] <= item.startMinute) {
        placedIndex = c;
        break;
      }
    }
    if (placedIndex == -1) {
      placedIndex = columnEndMinutes.length;
      columnEndMinutes.add(item.endMinute);
    } else {
      columnEndMinutes[placedIndex] = item.endMinute;
    }
    item.column = placedIndex;
  }
  final totalColumns = columnEndMinutes.length;
  for (final item in sortedEvents) {
    item.totalColumns = totalColumns;
  }
  return sortedEvents;
}

class _TimedEvent {
  _TimedEvent({required this.event, required this.startMinute, required this.endMinute});

  final CalendarEventModel event;
  final int startMinute;
  final int endMinute;
  int column = 0;
  int totalColumns = 1;
}

class _WeekHeaderRow extends StatelessWidget {
  const _WeekHeaderRow({required this.days, required this.today, required this.columnWidth});

  final List<DateTime> days;
  final DateTime today;
  final double columnWidth;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(width: _timeAxisWidth),
          for (final day in days)
            SizedBox(
              width: columnWidth,
              child: _WeekDayHeader(day: day, isToday: _isSameDay(day, today)),
            ),
        ],
      ),
    );
  }
}

class _WeekDayHeader extends StatelessWidget {
  const _WeekDayHeader({required this.day, required this.isToday});

  final DateTime day;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          DateFormat('EEE').format(day),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: isToday
              ? const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle)
              : null,
          child: Text(
            '${day.day}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
              color: isToday ? Colors.white : AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

class _UnscheduledRow extends StatelessWidget {
  const _UnscheduledRow({
    required this.days,
    required this.columnWidth,
    required this.unscheduledByDay,
    required this.onEventTap,
  });

  final List<DateTime> days;
  final double columnWidth;
  final Map<DateTime, List<CalendarEventModel>> unscheduledByDay;
  final void Function(CalendarEventModel event) onEventTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(
              width: _timeAxisWidth,
              child: Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'All day',
                  style: TextStyle(fontSize: 9, color: AppColors.textSecondary),
                ),
              ),
            ),
            for (final day in days)
              SizedBox(
                width: columnWidth,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final event in unscheduledByDay[day] ?? const [])
                        Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: _UnscheduledChip(event: event, onTap: () => onEventTap(event)),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _UnscheduledChip extends StatelessWidget {
  const _UnscheduledChip({required this.event, required this.onTap});

  final CalendarEventModel event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = calendarEventTypeStyle(event.eventType);
    return Material(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 11, color: color),
              const SizedBox(width: 3),
              Flexible(
                child: Text(
                  event.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HourAxis extends StatelessWidget {
  const _HourAxis({required this.hours});

  final List<int> hours;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _timeAxisWidth,
      child: Column(
        children: [
          for (final hour in hours)
            SizedBox(
              height: _hourHeight,
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    _formatHour(hour),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 9, color: AppColors.textSecondary),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  static String _formatHour(int hour) {
    final h = hour % 24;
    final period = h < 12 ? 'AM' : 'PM';
    final displayHour = h % 12 == 0 ? 12 : h % 12;
    return '$displayHour $period';
  }
}

class _DayColumn extends StatelessWidget {
  const _DayColumn({
    required this.width,
    required this.hours,
    required this.gridStartHour,
    required this.isToday,
    required this.events,
    required this.onEventTap,
  });

  final double width;
  final List<int> hours;
  final int gridStartHour;
  final bool isToday;
  final List<_TimedEvent> events;
  final void Function(CalendarEventModel event) onEventTap;

  @override
  Widget build(BuildContext context) {
    final height = hours.length * _hourHeight;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: isToday ? AppColors.primary.withValues(alpha: 0.04) : null,
        border: const Border(left: BorderSide(color: Color(0x14000000))),
      ),
      child: Stack(
        children: [
          Column(
            children: [
              for (var i = 0; i < hours.length; i++)
                Container(
                  height: _hourHeight,
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: Color(0x14000000))),
                  ),
                ),
            ],
          ),
          for (final item in events) _positionedTile(item, width),
        ],
      ),
    );
  }

  Widget _positionedTile(_TimedEvent item, double columnWidth) {
    final top = (item.startMinute - gridStartHour * 60).toDouble();
    final tileHeight = math.max(22.0, (item.endMinute - item.startMinute).toDouble());
    const gap = 2.0;
    final slotWidth = (columnWidth - 4) / item.totalColumns;
    final left = 2 + item.column * slotWidth;
    return Positioned(
      top: top,
      left: left,
      width: math.max(0, slotWidth - gap),
      height: tileHeight,
      child: _WeekEventTile(event: item.event, onTap: () => onEventTap(item.event)),
    );
  }
}

class _WeekEventTile extends StatelessWidget {
  const _WeekEventTile({required this.event, required this.onTap});

  final CalendarEventModel event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (color, _) = calendarEventTypeStyle(event.eventType);
    return Material(
      color: color.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: color, width: 3)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          alignment: Alignment.topLeft,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                event.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color),
              ),
              if (event.startTime != null)
                Text(
                  event.startTime!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 9, color: color.withValues(alpha: 0.85)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
