import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../models/calendar_event_model.dart';
import 'calendar_event_style.dart';

const _weekdayLabels = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Month grid — 7 columns, one row per week of the focused month. Each day
/// cell shows the day number and up to 3 small color dots (one per distinct
/// event type that day, matching `calendarEventTypeStyle`), with a "+N"
/// label if there are more. Tapping a day with events opens [onDayTap]
/// (the caller shows a bottom sheet listing that day's events).
class CalendarMonthView extends StatelessWidget {
  const CalendarMonthView({
    super.key,
    required this.focusedMonth,
    required this.eventsByDay,
    required this.onDayTap,
  });

  final DateTime focusedMonth;
  final Map<DateTime, List<CalendarEventModel>> eventsByDay;
  final void Function(DateTime day, List<CalendarEventModel> events) onDayTap;

  @override
  Widget build(BuildContext context) {
    final firstOfMonth = DateTime(focusedMonth.year, focusedMonth.month, 1);
    final daysInMonth = DateTime(focusedMonth.year, focusedMonth.month + 1, 0).day;
    // Dart's DateTime.weekday is Mon=1..Sun=7; this calendar is Sunday-first,
    // so Sunday (7) must map to column 0 — `% 7` does exactly that while
    // leaving Mon..Sat (1..6) mapped to columns 1..6 unchanged.
    final leadingBlanks = firstOfMonth.weekday % 7;
    final totalCells = leadingBlanks + daysInMonth;
    final rowCount = (totalCells / 7).ceil();
    final today = DateTime.now();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              for (final label in _weekdayLabels)
                Expanded(
                  child: Center(
                    child: Text(
                      label,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            // A fixed pixel row height (not an aspect ratio) — with 7
            // columns, an aspect ratio makes row height scale with column
            // width, which balloons into a mostly-empty, scroll-required
            // grid on wide/desktop viewports where each column is wide.
            // A flat 68px row keeps every row compact and the whole month
            // visible without scrolling on any of the supported widths.
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisExtent: 68,
              mainAxisSpacing: 2,
              crossAxisSpacing: 2,
            ),
            itemCount: rowCount * 7,
            itemBuilder: (context, index) {
              final dayNum = index - leadingBlanks + 1;
              if (dayNum < 1 || dayNum > daysInMonth) {
                return const SizedBox.shrink();
              }
              final day = DateTime(focusedMonth.year, focusedMonth.month, dayNum);
              final dayEvents = eventsByDay[day] ?? const [];
              return _DayCell(
                dayNumber: dayNum,
                events: dayEvents,
                isToday: _isSameDay(day, today),
                onTap: dayEvents.isEmpty ? null : () => onDayTap(day, dayEvents),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.dayNumber,
    required this.events,
    required this.isToday,
    this.onTap,
  });

  final int dayNumber;
  final List<CalendarEventModel> events;
  final bool isToday;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final dotColors = <Color>[];
    for (final event in events) {
      final (color, _) = calendarEventTypeStyle(event.eventType);
      if (!dotColors.contains(color)) dotColors.add(color);
      if (dotColors.length == 3) break;
    }
    final overflow = events.length > dotColors.length ? events.length - dotColors.length : 0;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          color: isToday ? AppColors.primary.withValues(alpha: 0.08) : null,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: isToday
                  ? const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle)
                  : null,
              child: Text(
                '$dayNumber',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
                  color: isToday ? Colors.white : AppColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 3),
            SizedBox(
              height: 6,
              child: dotColors.isEmpty
                  ? null
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final color in dotColors)
                          Container(
                            width: 5,
                            height: 5,
                            margin: const EdgeInsets.symmetric(horizontal: 1),
                            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                          ),
                        if (overflow > 0)
                          Text(
                            '+$overflow',
                            style: const TextStyle(fontSize: 8, color: AppColors.textSecondary),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
