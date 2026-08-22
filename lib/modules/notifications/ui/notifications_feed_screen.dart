import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_sizes.dart';
import '../../admin/notifications/data/admin_notification_service.dart';
import '../../admin/notifications/models/admin_notification_model.dart';
import 'notification_relevance.dart';

/// Simple, read-only notification feed shared by the Parent and Staff
/// consumer experiences — deliberately NOT the Admin notification screen's
/// dense management UI (no create/edit/delete/publish/archive/filters).
/// Reuses the existing `school_notifications` collection and
/// [AdminNotificationModel] entirely; no new notification data model.
///
/// Which notifications are relevant is resolved in Dart against the small,
/// already-audience-narrowed list [AdminNotificationService.
/// getNotificationsForAudience] returns — see notification_relevance.dart.
///
/// Read/unread state is NOT persisted anywhere: the existing notification
/// model has no per-user read or acknowledgement field, and inventing one
/// is out of scope for this phase (see the Phase A report). Opening a
/// notification only dims it for the rest of this in-memory session, purely
/// as a visual aid — it resets on next launch and isn't synced anywhere.
class NotificationsFeedScreen extends StatefulWidget {
  const NotificationsFeedScreen.forParent({
    super.key,
    required this.title,
    required Set<String> childStudentIds,
    required Set<String> childClassIds,
    this.showOwnScaffold = true,
  }) : audience = 'Parents',
       _childStudentIds = childStudentIds,
       _childClassIds = childClassIds,
       _staffUserId = null;

  const NotificationsFeedScreen.forStaff({
    super.key,
    required this.title,
    required String staffUserId,
    this.showOwnScaffold = true,
  }) : audience = 'Staff',
       _staffUserId = staffUserId,
       _childStudentIds = const {},
       _childClassIds = const {};

  final String title;
  final String audience;
  final Set<String> _childStudentIds;
  final Set<String> _childClassIds;
  final String? _staffUserId;

  /// True (the default, unchanged for every existing caller) renders this
  /// screen's own `Scaffold`+`AppBar`, exactly as before. Pass false to get
  /// back just the loading/error/list body, so a caller can embed it inside
  /// its own shell instead — used by ParentNotificationsScreen so Parent's
  /// notification feed sits inside the same AppSidebar/AppBottomNav shell
  /// ParentDashboard uses, without duplicating the loading/error/list logic.
  final bool showOwnScaffold;

  @override
  State<NotificationsFeedScreen> createState() =>
      _NotificationsFeedScreenState();
}

class _NotificationsFeedScreenState extends State<NotificationsFeedScreen> {
  bool _loading = true;
  bool _hasError = false;
  List<AdminNotificationModel> _items = const [];
  final Set<String> _openedThisSession = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _hasError = false;
    });
    try {
      // Constructed inside the try block (not as a field) so a failure to
      // construct it — e.g. Firebase not yet ready — is caught by the same
      // error handling as a failed fetch, instead of throwing uncaught
      // before this widget's error state can ever show.
      final service = AdminNotificationService();
      final fetched = await service.getNotificationsForAudience(
        widget.audience,
      );
      final relevant = widget.audience == 'Parents'
          ? fetched
                .where(
                  (n) => isNotificationRelevantToParent(
                    n,
                    childStudentIds: widget._childStudentIds,
                    childClassIds: widget._childClassIds,
                  ),
                )
                .toList()
          : fetched
                .where(
                  (n) => isNotificationRelevantToStaff(
                    n,
                    staffUserId: widget._staffUserId ?? '',
                  ),
                )
                .toList();
      if (!mounted) return;
      setState(() {
        _items = relevant;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _hasError = true;
        _loading = false;
      });
    }
  }

  void _openDetail(AdminNotificationModel notification) {
    setState(() => _openedThisSession.add(notification.id));
    showNotificationDetail(context, notification);
  }

  @override
  Widget build(BuildContext context) {
    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : _hasError
        ? _NotificationsErrorState(onRetry: _load)
        : _items.isEmpty
        ? const _EmptyNotifications()
        : RefreshIndicator(
            onRefresh: _load,
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final notification = _items[index];
                final opened = _openedThisSession.contains(notification.id);
                return _NotificationCard(
                  notification: notification,
                  opened: opened,
                  onTap: () => _openDetail(notification),
                );
              },
            ),
          );

    if (!widget.showOwnScaffold) {
      return body;
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(widget.title)),
      body: body,
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.notification,
    required this.opened,
    required this.onTap,
  });

  final AdminNotificationModel notification;
  final bool opened;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isHighPriority = notification.priority.toLowerCase() == 'high';
    return Card(
      elevation: 0,
      color: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!opened)
                Padding(
                  padding: const EdgeInsets.only(top: 6, right: 10),
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: AppColors.secondary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (notification.isPinned)
                          const Padding(
                            padding: EdgeInsets.only(right: 6),
                            child: Icon(
                              Icons.push_pin,
                              size: 16,
                              color: AppColors.secondary,
                            ),
                          ),
                        Expanded(
                          child: Text(
                            notification.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: opened
                                  ? FontWeight.w500
                                  : FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        if (isHighPriority)
                          const Icon(
                            Icons.priority_high,
                            size: 16,
                            color: Colors.redAccent,
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${notification.category} · ${_relativeDay(notification.publishDate ?? notification.createdAt)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      notification.message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Opens the shared notification detail view for [notification]. Public so
/// both the full feed and the Dashboard preview row open the exact same
/// detail view, rather than each screen owning its own.
///
/// Presentation is responsive using the same [AppSizes.mobileBreakpoint]
/// every other screen in the app already keys its mobile/desktop shell off
/// of — below it, a bottom sheet (a professional, standard pattern for a
/// single-item "peek" on a phone-sized screen, and consistent with the
/// mobile bottom-nav shell already showing at that width); at or above it,
/// a centered, width-capped dialog, so tablet/desktop never see a
/// phone-style sheet stretched full width. Both branches share the exact
/// same content widget — nothing about the notification itself is
/// duplicated between them.
void showNotificationDetail(
  BuildContext context,
  AdminNotificationModel notification,
) {
  final isMobile =
      MediaQuery.of(context).size.width < AppSizes.mobileBreakpoint;

  if (isMobile) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      // A fixed pixel cap would either waste space on a small phone or fail
      // to bound a tall one — sizing off the viewport's own height (via the
      // sheet's own BuildContext, which already reflects it) keeps this
      // correct at 390/400/412 alike, and everything in between.
      builder: (sheetContext) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(sheetContext).size.height * 0.75,
        ),
        child: _NotificationDetailContent(notification: notification),
      ),
    );
    return;
  }

  showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog(
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 520,
          // Capped by whichever is smaller: a comfortable absolute reading
          // height (so a huge monitor doesn't get an oddly tall dialog for
          // a short notification) or 80% of the actual window (so a modest
          // laptop window never gets a dialog taller than it can show).
          maxHeight: math.min(
            640,
            MediaQuery.of(dialogContext).size.height * 0.8,
          ),
        ),
        child: _NotificationDetailContent(notification: notification),
      ),
    ),
  );
}

Future<void> _openAttachment(
  BuildContext context,
  AdminNotificationModel notification,
) async {
  final messenger = ScaffoldMessenger.of(context);
  var opened = false;
  try {
    opened = await launchUrl(
      Uri.parse(notification.attachmentUrl),
      mode: LaunchMode.externalApplication,
    );
  } catch (_) {
    opened = false;
  }
  if (!opened) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Could not open attachment.')),
    );
  }
}

/// Shared by both the mobile bottom sheet and the desktop/tablet dialog —
/// "a school communication card expanded into a focused reading view."
/// The actual notification content is identical either way; only the outer
/// chrome (sheet vs. dialog, and the max-height it hands down) in
/// [showNotificationDetail] differs.
///
/// Structured as a fixed header (indicator/close, title, metadata) above a
/// [Flexible] scrollable body — not one single scroll view — so the close
/// button stays reachable even once a long message has been scrolled, and
/// so metadata reads as visually separate from the message itself. The
/// `Flexible` (not `Expanded`) on the body is what keeps a short
/// notification compact: it only ever claims as much height as its content
/// actually needs, up to whatever max height the caller supplied.
class _NotificationDetailContent extends StatelessWidget {
  const _NotificationDetailContent({required this.notification});

  final AdminNotificationModel notification;

  @override
  Widget build(BuildContext context) {
    final isHighPriority = notification.priority.toLowerCase() == 'high';
    final hasIndicator = notification.isPinned || isHighPriority;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 12, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header toolbar: pinned/priority indicator (if any) on the
            // left, close on the right — kept out of the title's own line
            // so the title never has to share its row with anything else.
            Row(
              children: [
                if (hasIndicator) ...[
                  if (notification.isPinned)
                    const Icon(
                      Icons.push_pin,
                      size: 16,
                      color: AppColors.secondary,
                    ),
                  if (notification.isPinned && isHighPriority)
                    const SizedBox(width: 8),
                  if (isHighPriority)
                    const Icon(
                      Icons.priority_high,
                      size: 16,
                      color: Colors.redAccent,
                    ),
                  const Spacer(),
                ] else
                  const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).maybePop(),
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.background,
                    foregroundColor: AppColors.textSecondary,
                    shape: const CircleBorder(),
                    minimumSize: const Size(34, 34),
                    padding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8, top: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notification.title,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${notification.category} · ${_relativeDay(notification.publishDate ?? notification.createdAt)}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            // The message (and attachment, if any) is the only part that
            // scrolls — long content is safely contained by the caller's
            // max-height without ever hiding the header above.
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(right: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      notification.message,
                      style: const TextStyle(
                        fontSize: 15,
                        height: 1.55,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (notification.attachmentUrl.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      _AttachmentRow(notification: notification),
                    ],
                    // Bottom breathing room inside the scroll area itself,
                    // so the last line of a long message never sits flush
                    // against the sheet/dialog's own edge.
                    const SizedBox(height: 8),
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

class _AttachmentRow extends StatelessWidget {
  const _AttachmentRow({required this.notification});

  final AdminNotificationModel notification;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.background,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openAttachment(context, notification),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.attach_file,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  notification.attachmentName.isEmpty
                      ? 'Attachment'
                      : notification.attachmentName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.open_in_new,
                size: 18,
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificationsErrorState extends StatelessWidget {
  const _NotificationsErrorState({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_outlined,
              size: 40,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 12),
            const Text(
              "Couldn't load notifications.",
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _EmptyNotifications extends StatelessWidget {
  const _EmptyNotifications();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.notifications_none,
              size: 40,
              color: AppColors.textSecondary,
            ),
            SizedBox(height: 12),
            Text(
              'No notifications yet.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

String _relativeDay(DateTime? date) {
  if (date == null) return '-';
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final target = DateTime(date.year, date.month, date.day);
  final diff = today.difference(target).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  if (diff > 1 && diff < 7) return '$diff days ago';
  return DateFormat('d MMM yyyy').format(date);
}
