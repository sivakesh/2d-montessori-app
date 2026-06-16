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

  @override
  Widget build(BuildContext context) {
    final q = _searchController.text.trim().toLowerCase();
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
        padding: const EdgeInsets.all(24),
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
            const SizedBox(height: 12),
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
                final selected = (label == 'Pinned' || label == 'Unpinned') ? _pinned == value : (label == 'Ack Required' || label == 'No Ack') ? _requiresAck == value : false;
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
              children: ['All', 'General Announcement', 'Circular', 'Reminder', 'Emergency Alert', 'Event Notice', 'Fee Reminder', 'Holiday Notice', 'Academic Notice', 'Attendance Notice', 'Exam Notice', 'Health & Safety', 'Transport Notice', 'Parent Meeting', 'Staff Notice', 'Public Notice', 'Other']
                  .map((e) => ChoiceChip(label: Text(e), selected: _type == e, onSelected: (_) => setState(() => _type = e)))
                  .toList(),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ['All', 'Academic', 'Administration', 'Admission', 'Finance', 'HR/Staff', 'Parent Communication', 'Compliance', 'Safety', 'Events', 'General']
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
            const SizedBox(height: 16),
            Expanded(
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
          ],
        ),
      ),
    );
  }
}
