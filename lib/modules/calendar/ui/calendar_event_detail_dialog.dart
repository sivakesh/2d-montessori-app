import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/responsive_dialog_shell.dart';
import '../../finance/widgets/finance_status_chip.dart';
import '../models/calendar_event_model.dart';
import 'calendar_event_style.dart';

/// Full detail view for one calendar item, opened by tapping an event in
/// any of the three views (List/Month/Week) so the level of detail a user
/// can see is identical regardless of which view they tapped from. Carries
/// the same Admin management actions the List view's card already offers,
/// so Month/Week aren't a management dead-end for Admin.
Future<void> showCalendarEventDetail(
  BuildContext context,
  CalendarEventModel event, {
  required bool isAdmin,
  VoidCallback? onEdit,
  VoidCallback? onPublish,
  VoidCallback? onArchive,
  VoidCallback? onDelete,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => _CalendarEventDetailDialog(
      event: event,
      isAdmin: isAdmin,
      onEdit: onEdit == null
          ? null
          : () {
              Navigator.of(dialogContext).pop();
              onEdit();
            },
      onPublish: onPublish == null
          ? null
          : () {
              Navigator.of(dialogContext).pop();
              onPublish();
            },
      onArchive: onArchive == null
          ? null
          : () {
              Navigator.of(dialogContext).pop();
              onArchive();
            },
      onDelete: onDelete == null
          ? null
          : () {
              Navigator.of(dialogContext).pop();
              onDelete();
            },
    ),
  );
}

class _CalendarEventDetailDialog extends StatelessWidget {
  const _CalendarEventDetailDialog({
    required this.event,
    required this.isAdmin,
    this.onEdit,
    this.onPublish,
    this.onArchive,
    this.onDelete,
  });

  final CalendarEventModel event;
  final bool isAdmin;
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

    return ResponsiveDialogShell.form(
      desktopWidth: 480,
      title: event.title,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Chip(
                avatar: Icon(typeIcon, size: 16, color: typeColor),
                label: Text(event.eventType),
                backgroundColor: typeColor.withValues(alpha: 0.1),
                visualDensity: VisualDensity.compact,
              ),
              if (isAdmin) FinanceStatusChip(label: statusLabel, color: statusColor),
            ],
          ),
          const SizedBox(height: 16),
          _DetailRow(icon: Icons.calendar_today_outlined, text: DateFormat('EEEE, MMM d, yyyy').format(event.date)),
          if (timeLabel != null) ...[
            const SizedBox(height: 8),
            _DetailRow(icon: Icons.access_time, text: timeLabel),
          ],
          if (event.location.isNotEmpty) ...[
            const SizedBox(height: 8),
            _DetailRow(icon: Icons.place_outlined, text: event.location),
          ],
          const SizedBox(height: 8),
          _DetailRow(
            icon: Icons.groups_outlined,
            text: event.audience == 'Public' ? 'Everyone' : event.audience,
          ),
          if (event.description.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(event.description, style: const TextStyle(fontSize: 14, color: AppColors.textPrimary)),
          ],
          // Admin management actions are rendered as a wrapping row inside
          // the scrollable content — NOT via ResponsiveDialogShell.form's
          // `actions` (a plain, non-wrapping Row) — since there can be up
          // to three of them here (Publish/Edit/Archive) and that row would
          // overflow at narrow widths.
          if (isAdmin &&
              (onEdit != null || onPublish != null || onArchive != null || onDelete != null)) ...[
            const Divider(height: 32),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                if (event.status == CalendarEventStatus.draft && onPublish != null)
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
                if (event.status != CalendarEventStatus.archived && onArchive != null)
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
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppColors.textSecondary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text, style: const TextStyle(fontSize: 14, color: AppColors.textPrimary)),
        ),
      ],
    );
  }
}
