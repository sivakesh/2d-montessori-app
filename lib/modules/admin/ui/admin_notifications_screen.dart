import 'package:flutter/material.dart';

import '../notifications/data/admin_notification_service.dart';
import '../notifications/models/admin_notification_model.dart';
import '../notifications/ui/admin_notification_form_dialog.dart';
import '../notifications/ui/admin_notification_view_dialog.dart';
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
    final isMobile = MediaQuery.of(context).size.width < 700;
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
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF2E7D32),
        elevation: 4,
        onPressed: () => _openForm(),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: Padding(
        padding: EdgeInsets.zero,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('Notifications', style: Theme.of(context).textTheme.headlineSmall),
                    const Spacer(),
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
                const SizedBox(height: 16),
                TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Search by title or message',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _filterSummary(),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
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
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _notificationTypeOptions()
                            .map((e) => ChoiceChip(label: Text(e), selected: _type == e, onSelected: (_) => setState(() => _type = e)))
                            .toList(),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _categoryOptions()
                            .map((e) => ChoiceChip(label: Text(e), selected: _category == e, onSelected: (_) => setState(() => _category = e)))
                            .toList(),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: ['All', 'Parents', 'Staff', 'Public', 'Admin Only']
                            .map((e) => ChoiceChip(label: Text(e), selected: _audience == e, onSelected: (_) => setState(() => _audience = e)))
                            .toList(),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: ['All', 'Low', 'Normal', 'High', 'Urgent']
                            .map((e) => ChoiceChip(label: Text(e), selected: _priority == e, onSelected: (_) => setState(() => _priority = e)))
                            .toList(),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: ['All', 'Draft', 'Scheduled', 'Published', 'Archived', 'Expired']
                            .map((e) => ChoiceChip(label: Text(e), selected: _status == e, onSelected: (_) => setState(() => _status = e)))
                            .toList(),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: ['All', '2026-2027']
                            .map((e) => ChoiceChip(label: Text(e), selected: _academicYear == e, onSelected: (_) => setState(() => _academicYear = e)))
                            .toList(),
                      ),
                    ],
                  ),
                const SizedBox(height: 16),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 96),
                    child: _loading
                        ? const Center(child: CircularProgressIndicator())
                        : filtered.isEmpty
                            ? const Center(child: Text('No notifications found'))
                            : ListView.builder(
                                itemCount: filtered.length,
                                itemBuilder: (context, index) {
                                  final n = filtered[index];
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: Card(
                                      child: ListTile(
                                        leading: const CircleAvatar(child: Icon(Icons.notifications)),
                                        title: Text(n.title),
                                        subtitle: Text('${n.notificationType} • ${n.category}\n${n.message.length > 100 ? '${n.message.substring(0, 100)}...' : n.message}'),
                                        isThreeLine: true,
                                        trailing: Wrap(
                                          spacing: 8,
                                          children: [
                                            IconButton(icon: const Icon(Icons.visibility), onPressed: () => showDialog(context: context, builder: (_) => AdminNotificationViewDialog(notificationId: n.id))),
                                            IconButton(icon: const Icon(Icons.edit), onPressed: () => _openForm(model: n)),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
