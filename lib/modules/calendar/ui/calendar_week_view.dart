import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../models/calendar_event_model.dart';
import 'calendar_event_style.dart';

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Week agenda — a 7-day header strip (date + a dot if that day has events)
/// followed by a per-day section for every day that actually has events
/// (empty days are skipped rather than shown as blank agenda entries, to
/// keep the view useful rather than mostly-empty). Tapping an event opens
/// [onEventTap].
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
    final daysWithEvents = days.where((d) => (eventsByDay[d] ?? const []).isNotEmpty).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              for (final day in days)
                Expanded(
                  child: _WeekDayHeader(
                    day: day,
                    isToday: _isSameDay(day, today),
                    hasEvents: (eventsByDay[day] ?? const []).isNotEmpty,
                  ),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: daysWithEvents.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'No events this week.',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.md,
                    AppSpacing.md,
                    96,
                  ),
                  children: [
                    for (final day in daysWithEvents) ...[
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          DateFormat('EEEE, MMM d').format(day),
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                        ),
                      ),
                      for (final event in eventsByDay[day]!) ...[
                        _WeekEventRow(event: event, onTap: () => onEventTap(event)),
                        const SizedBox(height: 8),
                      ],
                      const SizedBox(height: 8),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _WeekDayHeader extends StatelessWidget {
  const _WeekDayHeader({required this.day, required this.isToday, required this.hasEvents});

  final DateTime day;
  final bool isToday;
  final bool hasEvents;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          DateFormat('E').format(day).substring(0, 1),
          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 2),
        Container(
          width: 26,
          height: 26,
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
        const SizedBox(height: 3),
        SizedBox(
          height: 5,
          width: 5,
          child: hasEvents
              ? const DecoratedBox(
                  decoration: BoxDecoration(color: AppColors.secondary, shape: BoxShape.circle),
                )
              : null,
        ),
      ],
    );
  }
}

class _WeekEventRow extends StatelessWidget {
  const _WeekEventRow({required this.event, required this.onTap});

  final CalendarEventModel event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = calendarEventTypeStyle(event.eventType);
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 16),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    if (event.startTime != null)
                      Text(
                        event.startTime!,
                        style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                      ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, size: 18, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
