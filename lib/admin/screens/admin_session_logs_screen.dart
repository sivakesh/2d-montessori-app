// ignore_for_file: deprecated_member_use
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../modules/auth/providers/auth_provider.dart';
import '../../modules/auth/models/app_user.dart';
import '../../admin/models/user_session_log_model.dart';
import '../../modules/admin/ui/admin_layout.dart';

class AdminSessionLogsScreen extends ConsumerStatefulWidget {
  const AdminSessionLogsScreen({super.key});

  @override
  ConsumerState<AdminSessionLogsScreen> createState() =>
      _AdminSessionLogsScreenState();
}

class _AdminSessionLogsScreenState extends ConsumerState<AdminSessionLogsScreen> {
  late final Future<List<UserSessionLogModel>> _future = _loadLogs();
  final TextEditingController _searchController = TextEditingController();
  String _action = 'All';
  String _role = 'All';
  String _dateFilter = 'All';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<List<UserSessionLogModel>> _loadLogs() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('user_session_logs')
          .orderBy('createdAt', descending: true)
          .limit(100)
          .get();
      return snap.docs
          .map((doc) => UserSessionLogModel.fromMap(doc.id, doc.data()))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  bool _matchesDate(UserSessionLogModel log) {
    final now = DateTime.now();
    final created = log.createdAt;
    final startToday = DateTime(now.year, now.month, now.day);
    final start7 = startToday.subtract(const Duration(days: 6));
    final start30 = startToday.subtract(const Duration(days: 29));

    switch (_dateFilter) {
      case 'Today':
        return !created.isBefore(startToday);
      case 'Last 7 days':
        return !created.isBefore(start7);
      case 'Last 30 days':
        return !created.isBefore(start30);
      default:
        return true;
    }
  }

  List<UserSessionLogModel> _applyFilters(List<UserSessionLogModel> items) {
    final query = _searchController.text.trim().toLowerCase();
    return items.where((log) {
      final matchesSearch = query.isEmpty ||
          log.name.toLowerCase().contains(query) ||
          log.phone.toLowerCase().contains(query) ||
          log.email.toLowerCase().contains(query);
      final matchesAction = _action == 'All' || log.action == _action;
      final matchesRole = _role == 'All' || log.role == _role;
      final matchesDate = _matchesDate(log);
      return matchesSearch && matchesAction && matchesRole && matchesDate;
    }).toList();
  }

  bool _isAdmin(AppUser? user) => user?.role.toLowerCase() == 'admin';

  String _formatDateTime(DateTime dateTime) {
    return DateFormat('dd MMM yyyy, hh:mm a').format(dateTime);
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider);
    if (!_isAdmin(currentUser)) {
      return const AdminLayout(
        selectedIndex: 9,
        title: 'Login & Logout Logs',
        body: Padding(
          padding: EdgeInsets.all(24),
          child: Center(
            child: Text('Access denied'),
          ),
        ),
      );
    }

    return AdminLayout(
      selectedIndex: 9,
      title: 'Login & Logout Logs',
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: FutureBuilder<List<UserSessionLogModel>>(
          future: _future,
          builder: (context, snapshot) {
            final logs = snapshot.data ?? const <UserSessionLogModel>[];
            final filtered = _applyFilters(logs);
            final loading = snapshot.connectionState == ConnectionState.waiting;

            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Login & Logout Logs',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Track user access, session opens, and logout activity.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey[700],
                        ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: 320,
                        child: TextField(
                          controller: _searchController,
                          decoration: const InputDecoration(
                            labelText: 'Search by name, phone, or email',
                            prefixIcon: Icon(Icons.search),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      DropdownButton<String>(
                        value: _action,
                        items: const ['All', 'login', 'logout', 'session_opened']
                            .map(
                              (value) => DropdownMenuItem(
                                value: value,
                                child: Text(value),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() => _action = value);
                        },
                      ),
                      DropdownButton<String>(
                        value: _role,
                        items: const ['All', 'admin', 'staff', 'parent', 'unknown']
                            .map(
                              (value) => DropdownMenuItem(
                                value: value,
                                child: Text(value),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() => _role = value);
                        },
                      ),
                      DropdownButton<String>(
                        value: _dateFilter,
                        items: const ['All', 'Today', 'Last 7 days', 'Last 30 days']
                            .map(
                              (value) => DropdownMenuItem(
                                value: value,
                                child: Text(value),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() => _dateFilter = value);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (loading)
                    const Center(child: CircularProgressIndicator())
                  else if (filtered.isEmpty)
                    const _EmptyLogs()
                  else
                    _LogsTable(
                      items: filtered,
                      formatDateTime: _formatDateTime,
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _LogsTable extends StatelessWidget {
  const _LogsTable({
    required this.items,
    required this.formatDateTime,
  });

  final List<UserSessionLogModel> items;
  final String Function(DateTime) formatDateTime;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Date & Time')),
            DataColumn(label: Text('User')),
            DataColumn(label: Text('Role')),
            DataColumn(label: Text('Action')),
            DataColumn(label: Text('Module')),
            DataColumn(label: Text('Platform')),
            DataColumn(label: Text('Source')),
          ],
          rows: items.map((item) {
            return DataRow(
              cells: [
                DataCell(Text(formatDateTime(item.createdAt))),
                DataCell(
                  Text(
                    item.name.isNotEmpty
                        ? '${item.name}\n${item.phone}'
                        : item.phone,
                  ),
                ),
                DataCell(Text(item.role)),
                DataCell(Text(item.action)),
                DataCell(Text(item.module)),
                DataCell(Text(item.platform)),
                DataCell(Text(item.source)),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _EmptyLogs extends StatelessWidget {
  const _EmptyLogs();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Center(child: Text('No login logs found')),
    );
  }
}
