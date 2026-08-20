import 'package:flutter/material.dart';

import '../../../core/config/app_env.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_sizes.dart';
import '../../finance/widgets/finance_status_chip.dart';
import '../notifications/data/admin_notification_service.dart';
import '../notifications/models/admin_notification_model.dart';
import '../notifications/ui/admin_notification_form_dialog.dart';
import '../notifications/ui/admin_notification_view_dialog.dart';
import 'admin_fab.dart';
import 'admin_layout.dart';

class AdminNotificationsScreen extends StatefulWidget {
  const AdminNotificationsScreen({super.key});

  @override
  State<AdminNotificationsScreen> createState() => _AdminNotificationsScreenState();
}

class _AdminNotificationsScreenState extends State<AdminNotificationsScreen> {
  final _service = AdminNotificationService();
  final _searchController = TextEditingController();
  String _type = 'All';
  String _category = 'All';
  String _audience = 'All';
  String _priority = 'All';
  String _status = 'All';
  String _academicYear = 'All';
  bool? _pinned;
  bool? _requiresAck;
  bool _loading = true;
  List<AdminNotificationModel> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final items = await _service.getNotifications();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  Future<void> _openForm({AdminNotificationModel? model}) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AdminNotificationFormDialog(document: model),
    );
    await _load();
  }

  List<String> _notificationTypeOptions() => const [
        'All',
        'General Announcement',
        'Circular',
        'Reminder',
        'Emergency Alert',
        'Event Notice',
        'Fee Reminder',
        'Holiday Notice',
        'Academic Notice',
        'Attendance Notice',
        'Exam Notice',
        'Health & Safety',
        'Transport Notice',
        'Parent Meeting',
        'Staff Notice',
        'Public Notice',
        'Other',
      ];

  List<String> _categoryOptions() => const [
        'All',
        'Academic',
        'Administration',
        'Admission',
        'Finance',
        'HR/Staff',
        'Parent Communication',
        'Compliance',
        'Safety',
        'Events',
        'General',
      ];

  String _filterSummary() {
    final parts = <String>[];
    if (_pinned == true) parts.add('Pinned');
    if (_pinned == false) parts.add('Unpinned');
    if (_requiresAck == true) parts.add('Ack Required');
    if (_requiresAck == false) parts.add('No Ack');
    if (_type != 'All') parts.add(_type);
    if (_category != 'All') parts.add(_category);
    if (parts.isEmpty) return 'All notifications';
    return parts.join(' • ');
  }

  Future<void> _openMoreFilters() async {
    final type = _type;
    final category = _category;
    final audience = _audience;
    final priority = _priority;
    final status = _status;
    final academicYear = _academicYear;
    final pinned = _pinned;
    final requiresAck = _requiresAck;

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        String localType = type;
        String localCategory = category;
        String localAudience = audience;
        String localPriority = priority;
        String localStatus = status;
        String localAcademicYear = academicYear;
        bool? localPinned = pinned;
        bool? localRequiresAck = requiresAck;

        Widget sectionTitle(String title) => Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 8),
              child: Text(title, style: Theme.of(sheetContext).textTheme.titleMedium),
            );

        return StatefulBuilder(
          builder: (context, setSheetState) {
            Widget chipRow<T>(List<T> values, T current, ValueChanged<T> onChanged) {
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: values
                    .map(
                      (e) => ChoiceChip(
                        label: Text(e.toString()),
                        selected: current == e,
                        onSelected: (_) => setSheetState(() => onChanged(e)),
                      ),
                    )
                    .toList(),
              );
            }

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  top: 8,
                  bottom: MediaQuery.of(sheetContext).padding.bottom + 20,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      sectionTitle('Notification Type'),
                      chipRow(_notificationTypeOptions(), localType, (v) => localType = v),
                      sectionTitle('Category'),
                      chipRow(_categoryOptions(), localCategory, (v) => localCategory = v),
                      sectionTitle('Audience'),
                      chipRow(const ['All', 'Parents', 'Staff', 'Public', 'Admin Only'], localAudience, (v) => localAudience = v),
                      sectionTitle('Priority'),
                      chipRow(const ['All', 'Low', 'Normal', 'High', 'Urgent'], localPriority, (v) => localPriority = v),
                      sectionTitle('Status'),
                      chipRow(const ['All', 'Draft', 'Scheduled', 'Published', 'Archived', 'Expired'], localStatus, (v) => localStatus = v),
                      sectionTitle('Academic Year'),
                      chipRow(const ['All', '2026-2027'], localAcademicYear, (v) => localAcademicYear = v),
                      sectionTitle('Flags'),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilterChip(
                            label: const Text('Pinned'),
                            selected: localPinned == true,
                            onSelected: (_) => setSheetState(() => localPinned = localPinned == true ? null : true),
                          ),
                          FilterChip(
                            label: const Text('Unpinned'),
                            selected: localPinned == false,
                            onSelected: (_) => setSheetState(() => localPinned = localPinned == false ? null : false),
                          ),
                          FilterChip(
                            label: const Text('Ack Required'),
                            selected: localRequiresAck == true,
                            onSelected: (_) => setSheetState(() => localRequiresAck = localRequiresAck == true ? null : true),
                          ),
                          FilterChip(
                            label: const Text('No Ack'),
                            selected: localRequiresAck == false,
                            onSelected: (_) => setSheetState(() => localRequiresAck = localRequiresAck == false ? null : false),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          TextButton(
                            onPressed: () {
                              Navigator.pop(sheetContext, {
                                'type': 'All',
                                'category': 'All',
                                'audience': 'All',
                                'priority': 'All',
                                'status': 'All',
                                'academicYear': 'All',
                                'pinned': null,
                                'requiresAck': null,
                              });
                            },
                            child: const Text('Clear Filters'),
                          ),
                          const Spacer(),
                          FilledButton(
                            onPressed: () {
                              Navigator.pop(sheetContext, {
                                'type': localType,
                                'category': localCategory,
                                'audience': localAudience,
                                'priority': localPriority,
                                'status': localStatus,
                                'academicYear': localAcademicYear,
                                'pinned': localPinned,
                                'requiresAck': localRequiresAck,
                              });
                            },
                            child: const Text('Apply'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (result == null || !mounted) return;
    setState(() {
      _type = result['type'] as String? ?? _type;
      _category = result['category'] as String? ?? _category;
      _audience = result['audience'] as String? ?? _audience;
      _priority = result['priority'] as String? ?? _priority;
      _status = result['status'] as String? ?? _status;
      _academicYear = result['academicYear'] as String? ?? _academicYear;
      _pinned = result['pinned'] as bool?;
      _requiresAck = result['requiresAck'] as bool?;
    });
  }

  @override
  Widget build(BuildContext context) {
    final q = _searchController.text.trim().toLowerCase();
    final isMobile = MediaQuery.of(context).size.width < AppSizes.mobileBreakpoint;
    final filtered = _items.where((n) {
      final search = q.isEmpty || n.title.toLowerCase().contains(q) || n.message.toLowerCase().contains(q);
      final type = _type == 'All' || n.notificationType == _type;
      final cat = _category == 'All' || n.category == _category;
      final aud = _audience == 'All' || n.audience == _audience;
      final pri = _priority == 'All' || n.priority == _priority;
      final stat = _status == 'All' || n.status == _status;
      final year = _academicYear == 'All' || n.academicYear == _academicYear;
      final pin = _pinned == null || n.isPinned == _pinned;
      final ack = _requiresAck == null || n.requiresAcknowledgement == _requiresAck;
      return search && type && cat && aud && pri && stat && year && pin && ack;
    }).toList();

    return AdminLayout(
      selectedIndex: 5,
      title: 'Notifications',
      floatingActionButton: AdminFab(
        icon: Icons.add,
        onPressed: () => _openForm(),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
        child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Notifications',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Manage school announcements, circulars, and reminders.',
                            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    if (currentEnvironment == AppEnvironment.dev)
                      TextButton.icon(
                        onPressed: () async {
                          await _service.seedSampleNotifications();
                          await _load();
                        },
                        icon: const Icon(Icons.auto_awesome),
                        label: const Text('Seed Sample'),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Search by title or message',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Filters',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _filterSummary(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                            ),
                          ),
                        ],
                      ),
                      if (isMobile)
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FilterChip(
                              label: const Text('All'),
                              selected: _pinned == null && _requiresAck == null,
                              onSelected: (_) => setState(() {
                                _pinned = null;
                                _requiresAck = null;
                              }),
                            ),
                            FilterChip(
                              label: const Text('Pinned'),
                              selected: _pinned == true,
                              onSelected: (_) => setState(() => _pinned = _pinned == true ? null : true),
                            ),
                            FilterChip(
                              label: const Text('Ack'),
                              selected: _requiresAck == true,
                              onSelected: (_) => setState(() => _requiresAck = _requiresAck == true ? null : true),
                            ),
                            OutlinedButton.icon(
                              onPressed: _openMoreFilters,
                              icon: const Icon(Icons.tune),
                              label: const Text('More Filters'),
                            ),
                          ],
                        )
                      else
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _FilterGroupLabel('Acknowledgement'),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                ('All', null),
                                ('Pinned', true),
                                ('Unpinned', false),
                                ('Ack Required', true),
                                ('No Ack', false),
                              ].map((e) {
                                final label = e.$1;
                                final value = e.$2;
                                final selected = (label == 'Pinned' || label == 'Unpinned')
                                    ? _pinned == value
                                    : (label == 'Ack Required' || label == 'No Ack')
                                        ? _requiresAck == value
                                        : false;
                                return FilterChip(
                                  label: Text(label),
                                  selected: selected,
                                  onSelected: (_) {
                                    setState(() {
                                      if (label == 'Pinned' || label == 'Unpinned') _pinned = value as bool;
                                      if (label == 'Ack Required' || label == 'No Ack') _requiresAck = value as bool;
                                    });
                                  },
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 14),
                            _FilterGroupLabel('Type'),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: _notificationTypeOptions()
                                  .map((e) => ChoiceChip(label: Text(e), selected: _type == e, onSelected: (_) => setState(() => _type = e)))
                                  .toList(),
                            ),
                            const SizedBox(height: 14),
                            _FilterGroupLabel('Category'),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: _categoryOptions()
                                  .map((e) => ChoiceChip(label: Text(e), selected: _category == e, onSelected: (_) => setState(() => _category = e)))
                                  .toList(),
                            ),
                            const SizedBox(height: 14),
                            _FilterGroupLabel('Audience'),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: ['All', 'Parents', 'Staff', 'Public', 'Admin Only']
                                  .map((e) => ChoiceChip(label: Text(e), selected: _audience == e, onSelected: (_) => setState(() => _audience = e)))
                                  .toList(),
                            ),
                            const SizedBox(height: 14),
                            _FilterGroupLabel('Priority'),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: ['All', 'Low', 'Normal', 'High', 'Urgent']
                                  .map((e) => ChoiceChip(label: Text(e), selected: _priority == e, onSelected: (_) => setState(() => _priority = e)))
                                  .toList(),
                            ),
                            const SizedBox(height: 14),
                            _FilterGroupLabel('Status'),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: ['All', 'Draft', 'Scheduled', 'Published', 'Archived', 'Expired']
                                  .map((e) => ChoiceChip(label: Text(e), selected: _status == e, onSelected: (_) => setState(() => _status = e)))
                                  .toList(),
                            ),
                            const SizedBox(height: 14),
                            _FilterGroupLabel('Academic Year'),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: ['All', '2026-2027']
                                  .map((e) => ChoiceChip(label: Text(e), selected: _academicYear == e, onSelected: (_) => setState(() => _academicYear = e)))
                                  .toList(),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (filtered.isEmpty)
                  const _NotificationsEmptyState()
                else
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final n = filtered[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _NotificationRow(
                          notification: n,
                          onView: () => showDialog(
                            context: context,
                            builder: (_) => AdminNotificationViewDialog(notificationId: n.id),
                          ),
                          onEdit: () => _openForm(model: n),
                        ),
                      );
                    },
                  ),
                const SizedBox(height: 24),
              ],
            ),
      ),
    );
  }
}

/// Small uppercase label above each filter group's chip row — makes the
/// filter area read as grouped filters rather than independent chip rows.
class _FilterGroupLabel extends StatelessWidget {
  const _FilterGroupLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
      ),
    );
  }
}

/// Compact notification row matching the shared card style established
/// for Finance/Attendance/Users/Students/Classes/Documents. Only View and
/// Edit are exposed — delete/publish/archive were deliberately left out of
/// the prior stabilization pass and are not added here.
class _NotificationRow extends StatelessWidget {
  const _NotificationRow({
    required this.notification,
    required this.onView,
    required this.onEdit,
  });

  final AdminNotificationModel notification;
  final VoidCallback onView;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final metaLine = [notification.notificationType, notification.category].where((v) => v.isNotEmpty).join(' • ');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: const Icon(Icons.notifications_outlined, color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        notification.title.isEmpty ? 'Notification' : notification.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textPrimary),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FinanceStatusChip(label: notification.status.toUpperCase(), color: _statusColor(notification.status)),
                  ],
                ),
                if (metaLine.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(metaLine, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                ],
                if (notification.message.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    notification.message,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Wrap(
            spacing: 2,
            children: [
              IconButton(
                tooltip: 'View',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.visibility_outlined, size: 20),
                onPressed: onView,
              ),
              IconButton(
                tooltip: 'Edit',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.edit_outlined, size: 20),
                onPressed: onEdit,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _statusColor(String status) => switch (status) {
        'Published' => AppColors.primary,
        'Draft' => const Color(0xFFB26A00),
        'Archived' => Colors.grey,
        _ => AppColors.secondary,
      };
}

class _NotificationsEmptyState extends StatelessWidget {
  const _NotificationsEmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Column(
        children: [
          Icon(Icons.notifications_none_outlined, size: 36, color: AppColors.textSecondary.withValues(alpha: 0.6)),
          const SizedBox(height: 12),
          const Text(
            'No notifications found',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 4),
          const Text(
            'No notifications match your current search or filters.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
