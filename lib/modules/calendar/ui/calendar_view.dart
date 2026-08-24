import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../admin/ui/admin_fab.dart';
import '../../auth/providers/auth_provider.dart';
import '../../finance/widgets/finance_status_chip.dart';
import '../models/calendar_event_model.dart';
import '../services/calendar_service.dart';
import 'calendar_event_detail_dialog.dart';
import 'calendar_event_style.dart';
import 'calendar_month_view.dart';
import 'calendar_week_view.dart';
import 'dialogs/calendar_event_dialog.dart';

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// School Calendar body content — role-adaptive so it can be embedded
/// directly wherever a role already has a shell (DashboardScreen's tab
/// switch, ParentDashboard's tab switch, or the Admin back-office's
/// AdminLayout body) without a separate screen per role:
///  - Admin sees every item (Draft/Published/Archived) with manage actions
///    and an "Add" FAB.
///  - Staff/Parent see only Published items whose audience matches them
///    (or 'Public'), read-only — never a Draft or Admin-only item.
///
/// Offers three views over the exact same [CalendarEventModel] list fetched
/// once per load — Month (default), Week, and List (the original
/// chronological list) — so switching views is purely a presentation
/// choice, never a second data fetch or a second model.
class CalendarView extends ConsumerStatefulWidget {
  const CalendarView({super.key, this.service});

  final CalendarService? service;

  @override
  ConsumerState<CalendarView> createState() => _CalendarViewState();
}

enum _CalendarViewMode { month, week, list }

class _CalendarViewState extends ConsumerState<CalendarView> {
  late final _service = widget.service ?? CalendarService();
  bool _loading = true;
  bool _loadError = false;
  List<CalendarEventModel> _events = const [];
  _CalendarViewMode _viewMode = _CalendarViewMode.month;
  DateTime _focusedDate = _dateOnly(DateTime.now());

  @override
  void initState() {
    super.initState();
    _load();
  }

  bool get _isAdmin =>
      (ref.read(currentUserProvider)?.role.toLowerCase() ?? '') == 'admin';

  Map<DateTime, List<CalendarEventModel>> get _eventsByDay {
    final map = <DateTime, List<CalendarEventModel>>{};
    for (final event in _events) {
      final key = _dateOnly(event.date);
      (map[key] ??= []).add(event);
    }
    return map;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = false;
    });
    final user = ref.read(currentUserProvider);
    final role = user?.role.toLowerCase() ?? 'parent';
    try {
      final events = _isAdmin
          ? await _service.getAllEvents()
          : await _service.getEventsForAudience(
              role == 'parent' ? 'Parents' : 'Staff',
            );
      if (!mounted) return;
      setState(() {
        _events = events;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadError = true;
        _loading = false;
      });
    }
  }

  Future<void> _openAddOrEdit({CalendarEventModel? event}) async {
    final user = ref.read(currentUserProvider);
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CalendarEventDialog(
        event: event,
        createdBy: user?.id ?? '',
        createdByName: user?.name ?? user?.phone ?? 'Admin',
        service: _service,
      ),
    );
    if (saved == true) await _load();
  }

  Future<void> _publish(CalendarEventModel event) async {
    try {
      await _service.publishEvent(event);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Calendar item published')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not publish: $e')),
        );
      }
    }
  }

  Future<void> _archive(CalendarEventModel event) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove calendar item?'),
        content: Text('"${event.title}" will be archived and hidden from Parents/Staff.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _service.archiveEvent(event.id);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Calendar item archived')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not archive: $e')),
        );
      }
    }
  }

  Future<void> _delete(CalendarEventModel event) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete calendar item?'),
        content: Text(
          '"${event.title}" will be permanently deleted. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _service.deleteEvent(event.id);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Calendar item deleted')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete: $e')),
        );
      }
    }
  }

  void _openEventDetail(CalendarEventModel event) {
    final isAdmin = _isAdmin;
    showCalendarEventDetail(
      context,
      event,
      isAdmin: isAdmin,
      onEdit: isAdmin ? () => _openAddOrEdit(event: event) : null,
      onPublish: isAdmin && event.status == CalendarEventStatus.draft
          ? () => _publish(event)
          : null,
      onArchive: isAdmin && event.status != CalendarEventStatus.archived
          ? () => _archive(event)
          : null,
      onDelete: isAdmin ? () => _delete(event) : null,
    );
  }

  void _openDayEvents(DateTime day, List<CalendarEventModel> events) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  DateFormat('EEEE, MMM d, yyyy').format(day),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              for (final event in events)
                ListTile(
                  leading: Builder(
                    builder: (context) {
                      final (color, icon) = calendarEventTypeStyle(event.eventType);
                      return CircleAvatar(
                        backgroundColor: color.withValues(alpha: 0.12),
                        child: Icon(icon, color: color, size: 18),
                      );
                    },
                  ),
                  title: Text(event.title),
                  subtitle: Text(event.eventType),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _openEventDetail(event);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  void _goToday() => setState(() => _focusedDate = _dateOnly(DateTime.now()));

  void _goPrevious() {
    setState(() {
      _focusedDate = _viewMode == _CalendarViewMode.week
          ? _focusedDate.subtract(const Duration(days: 7))
          : DateTime(_focusedDate.year, _focusedDate.month - 1, 1);
    });
  }

  void _goNext() {
    setState(() {
      _focusedDate = _viewMode == _CalendarViewMode.week
          ? _focusedDate.add(const Duration(days: 7))
          : DateTime(_focusedDate.year, _focusedDate.month + 1, 1);
    });
  }

  DateTime get _weekStart {
    // Sunday-first week — Dart's weekday is Mon=1..Sun=7, so `% 7` maps
    // Sunday to 0 days back and every other day to its distance from the
    // preceding Sunday.
    final back = _focusedDate.weekday % 7;
    return _focusedDate.subtract(Duration(days: back));
  }

  String get _headerLabel {
    return switch (_viewMode) {
      _CalendarViewMode.month => DateFormat('MMMM yyyy').format(_focusedDate),
      _CalendarViewMode.week => () {
          final start = _weekStart;
          final end = start.add(const Duration(days: 6));
          final sameMonth = start.month == end.month;
          final startLabel = DateFormat(sameMonth ? 'MMM d' : 'MMM d').format(start);
          final endLabel = DateFormat('MMM d, yyyy').format(end);
          return '$startLabel - $endLabel';
        }(),
      _CalendarViewMode.list => 'All Events',
    };
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = _isAdmin;
    final showDateNav = _viewMode != _CalendarViewMode.list;

    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : _loadError
            ? _ErrorState(onRetry: _load)
            : _events.isEmpty
                ? const _EmptyState()
                : switch (_viewMode) {
                    _CalendarViewMode.month => CalendarMonthView(
                        focusedMonth: _focusedDate,
                        eventsByDay: _eventsByDay,
                        onDayTap: _openDayEvents,
                      ),
                    _CalendarViewMode.week => CalendarWeekView(
                        weekStart: _weekStart,
                        eventsByDay: _eventsByDay,
                        onEventTap: _openEventDetail,
                      ),
                    _CalendarViewMode.list => RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.md,
                            AppSpacing.md,
                            AppSpacing.md,
                            96,
                          ),
                          itemCount: _events.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: AppSpacing.sm),
                          itemBuilder: (context, index) {
                            final event = _events[index];
                            return _CalendarEventCard(
                              event: event,
                              isAdmin: isAdmin,
                              onTap: () => _openEventDetail(event),
                              onEdit: isAdmin ? () => _openAddOrEdit(event: event) : null,
                              onPublish: isAdmin && event.status == CalendarEventStatus.draft
                                  ? () => _publish(event)
                                  : null,
                              onArchive: isAdmin && event.status != CalendarEventStatus.archived
                                  ? () => _archive(event)
                                  : null,
                              onDelete: isAdmin ? () => _delete(event) : null,
                            );
                          },
                        ),
                      ),
                  };

    final content = Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0),
          child: Column(
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final narrow = constraints.maxWidth < 460;
                  final switcher = SegmentedButton<_CalendarViewMode>(
                    segments: const [
                      ButtonSegment(value: _CalendarViewMode.month, label: Text('Month')),
                      ButtonSegment(value: _CalendarViewMode.week, label: Text('Week')),
                      ButtonSegment(value: _CalendarViewMode.list, label: Text('List')),
                    ],
                    selected: {_viewMode},
                    onSelectionChanged: (selection) =>
                        setState(() => _viewMode = selection.first),
                    showSelectedIcon: false,
                  );
                  if (!showDateNav) {
                    return Align(alignment: Alignment.centerLeft, child: switcher);
                  }
                  if (narrow) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        switcher,
                        const SizedBox(height: 8),
                        _DateNavRow(
                          label: _headerLabel,
                          onPrevious: _goPrevious,
                          onNext: _goNext,
                          onToday: _goToday,
                        ),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      switcher,
                      const SizedBox(width: 16),
                      Expanded(
                        child: _DateNavRow(
                          label: _headerLabel,
                          onPrevious: _goPrevious,
                          onNext: _goNext,
                          onToday: _goToday,
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
        Expanded(child: body),
      ],
    );

    if (!isAdmin) return content;

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: AdminFab(
        icon: Icons.add,
        onPressed: () => _openAddOrEdit(),
      ),
      body: content,
    );
  }
}

class _DateNavRow extends StatelessWidget {
  const _DateNavRow({
    required this.label,
    required this.onPrevious,
    required this.onNext,
    required this.onToday,
  });

  final String label;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: onPrevious,
          visualDensity: VisualDensity.compact,
        ),
        Expanded(
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          onPressed: onNext,
          visualDensity: VisualDensity.compact,
        ),
        TextButton(onPressed: onToday, child: const Text('Today')),
      ],
    );
  }
}

class _CalendarEventCard extends StatelessWidget {
  const _CalendarEventCard({
    required this.event,
    required this.isAdmin,
    required this.onTap,
    this.onEdit,
    this.onPublish,
    this.onArchive,
    this.onDelete,
  });

  final CalendarEventModel event;
  final bool isAdmin;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onPublish;
  final VoidCallback? onArchive;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final (typeColor, typeIcon) = calendarEventTypeStyle(event.eventType);
    final (statusLabel, statusColor) = calendarEventStatusStyle(event.status);
    final timeLabel = event.startTime != null
        ? event.endTime != null
            ? '${event.startTime} - ${event.endTime}'
            : event.startTime
        : null;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: typeColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(typeIcon, color: typeColor, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          event.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          event.eventType,
                          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  if (isAdmin) FinanceStatusChip(label: statusLabel, color: statusColor),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 14,
                runSpacing: 6,
                children: [
                  _InfoChunk(
                    icon: Icons.calendar_today_outlined,
                    text: DateFormat('EEE, MMM d, yyyy').format(event.date),
                  ),
                  if (timeLabel != null)
                    _InfoChunk(icon: Icons.access_time, text: timeLabel),
                  if (event.location.isNotEmpty)
                    _InfoChunk(icon: Icons.place_outlined, text: event.location),
                ],
              ),
              if (event.description.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  event.description,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
                ),
              ],
              if (isAdmin &&
                  (onEdit != null || onPublish != null || onArchive != null || onDelete != null)) ...[
                const Divider(height: 24),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    if (onPublish != null)
                      TextButton.icon(
                        onPressed: onPublish,
                        icon: const Icon(Icons.publish_outlined, size: 18),
                        label: const Text('Publish'),
                      ),
                    if (onEdit != null)
                      TextButton.icon(
                        onPressed: onEdit,
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: const Text('Edit'),
                      ),
                    if (onArchive != null)
                      TextButton.icon(
                        onPressed: onArchive,
                        icon: const Icon(Icons.archive_outlined, size: 18),
                        label: const Text('Archive'),
                      ),
                    if (onDelete != null)
                      TextButton.icon(
                        onPressed: onDelete,
                        icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                        label: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoChunk extends StatelessWidget {
  const _InfoChunk({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.textSecondary),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_note_outlined, size: 40, color: AppColors.textSecondary),
            SizedBox(height: 12),
            Text(
              'No calendar items yet.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Couldn't load the calendar.",
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
