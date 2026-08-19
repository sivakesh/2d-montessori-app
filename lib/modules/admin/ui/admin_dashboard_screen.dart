// ignore_for_file: deprecated_member_use
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../services/user_session_log_service.dart';
import '../../fees/ui/admin_fees_screen.dart';
import '../../finance/ui/admin_finance_screen.dart';
import '../students/ui/admin_students_screen.dart';
import 'admin_attendance_management_screen.dart';
import 'admin_classes_screen.dart';
import 'admin_documents_screen.dart';
import 'admin_layout.dart';
import 'admin_notifications_screen.dart';
import 'admin_users_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  late final Future<_DashboardData> _future = _loadDashboardData();

  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    UserSessionLogService().logSessionOpened(source: 'admin_dashboard');
  }

  Future<int> _safeCount(Future<int> Function() loader) async {
    try {
      return await loader();
    } catch (_) {
      return 0;
    }
  }

  Future<int> _countCollection(String collection) async {
    final snap = await _firestore.collection(collection).get();
    return snap.size;
  }

  Future<int> _countStaff() async {
    final snap = await _firestore
        .collection('users')
        .where('role', isEqualTo: 'staff')
        .get();
    return snap.size;
  }

  Future<int> _countPublishedNotifications() async {
    final snap = await _firestore
        .collection('school_notifications')
        .where('status', isEqualTo: 'Published')
        .get();
    return snap.size;
  }

  Future<int> _countTodayAttendance() async {
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day);
    final end = start.add(const Duration(days: 1));
    final snap = await _firestore
        .collection('attendance')
        .where('attendanceDate', isGreaterThanOrEqualTo: start)
        .where('attendanceDate', isLessThan: end)
        .get();
    return snap.size;
  }

  Future<int> _countPendingFees() async {
    const candidates = ['fees', 'fee_collections', 'student_fees'];
    for (final collection in candidates) {
      try {
        final snap = await _firestore
            .collection(collection)
            .where('status', whereIn: ['pending', 'due', 'unpaid'])
            .get();
        return snap.size;
      } catch (_) {}
    }
    return 0;
  }

  Future<List<_ActivityItem>> _recentFromCollection({
    required String collection,
    required String titleField,
    required String subtitle,
    int limit = 5,
  }) async {
    try {
      final snap = await _firestore
          .collection(collection)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();
      return snap.docs.map((doc) {
        final data = doc.data();
        final createdAt = _timestampValue(data['createdAt']);
        return _ActivityItem(
          title: data[titleField]?.toString() ??
              data['name']?.toString() ??
              'Untitled',
          subtitle: subtitle,
          trailing: _formatTimestamp(createdAt),
          sortKey: createdAt,
        );
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<_ActivityItem>> _loadRecentActivity() async {
    try {
      final audit = await _firestore
          .collection('auditLogs')
          .orderBy('createdAt', descending: true)
          .limit(5)
          .get();
      if (audit.docs.isNotEmpty) {
        return audit.docs.map((doc) {
          final data = doc.data();
          final createdAt = _timestampValue(data['createdAt']);
          return _ActivityItem(
            title: data['title']?.toString() ??
                data['action']?.toString() ??
                'Audit entry',
            subtitle: data['module']?.toString() ?? 'Audit log',
            trailing: _formatTimestamp(createdAt),
            sortKey: createdAt,
          );
        }).toList();
      }
    } catch (_) {}

    final combined = <_ActivityItem>[];
    combined.addAll(
      await _recentFromCollection(
        collection: 'students',
        titleField: 'name',
        subtitle: 'Student created',
      ),
    );
    combined.addAll(
      await _recentFromCollection(
        collection: 'users',
        titleField: 'name',
        subtitle: 'User created',
      ),
    );
    combined.addAll(
      await _recentFromCollection(
        collection: 'school_notifications',
        titleField: 'title',
        subtitle: 'Notification updated',
      ),
    );
    combined.addAll(
      await _recentFromCollection(
        collection: 'school_documents',
        titleField: 'title',
        subtitle: 'Document uploaded',
      ),
    );

    combined.sort((a, b) => b.sortKey.compareTo(a.sortKey));
    return combined.take(5).toList();
  }

  Future<_DashboardData> _loadDashboardData() async {
    final results = await Future.wait([
      _safeCount(() => _countCollection('students')),
      _safeCount(_countStaff),
      _safeCount(() => _countCollection('classes')),
      _safeCount(_countTodayAttendance),
      _safeCount(_countPendingFees),
      _safeCount(_countPublishedNotifications),
      _loadRecentActivity(),
      _recentFromCollection(
        collection: 'school_notifications',
        titleField: 'title',
        subtitle: 'Published notice',
        limit: 3,
      ),
      _recentFromCollection(
        collection: 'school_documents',
        titleField: 'title',
        subtitle: 'Document uploaded',
        limit: 3,
      ),
    ]);

    return _DashboardData(
      totalStudents: results[0] as int,
      totalStaff: results[1] as int,
      activeClasses: results[2] as int,
      todayAttendance: results[3] as int,
      pendingFees: results[4] as int,
      publishedNotices: results[5] as int,
      recentActivity: results[6] as List<_ActivityItem>,
      recentNotifications: results[7] as List<_ActivityItem>,
      recentDocuments: results[8] as List<_ActivityItem>,
    );
  }

  String _formatTimestamp(dynamic value) {
    if (value is Timestamp) {
      final d = value.toDate();
      return '${d.month}/${d.day}/${d.year}';
    }
    return '';
  }

  DateTime _timestampValue(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  void _openScreen(Widget screen) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AdminLayout(
      selectedIndex: 0,
      title: 'Admin Dashboard',
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: FutureBuilder<_DashboardData>(
          future: _future,
          builder: (context, snapshot) {
            final data = snapshot.data;
            final loading = snapshot.connectionState == ConnectionState.waiting;
            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (loading)
                    const _DashboardSkeleton()
                  else if (data != null) ...[
                    Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        _KpiCard(
                          title: 'Total Students',
                          value: data.totalStudents.toString(),
                          helperText: 'Active learners in school',
                          icon: Icons.groups_outlined,
                          color: const Color(0xFF2E7D32),
                        ),
                        _KpiCard(
                          title: 'Total Staff',
                          value: data.totalStaff.toString(),
                          helperText: 'Teachers and support team',
                          icon: Icons.badge_outlined,
                          color: const Color(0xFF4E7C5B),
                        ),
                        _KpiCard(
                          title: 'Active Classes',
                          value: data.activeClasses.toString(),
                          helperText: 'Running classrooms',
                          icon: Icons.class_outlined,
                          color: const Color(0xFF558B2F),
                        ),
                        _KpiCard(
                          title: 'Today\'s Attendance',
                          value: data.todayAttendance.toString(),
                          helperText: 'Marked attendance records',
                          icon: Icons.fact_check_outlined,
                          color: const Color(0xFF388E3C),
                        ),
                        _KpiCard(
                          title: 'Pending Fees',
                          value: data.pendingFees.toString(),
                          helperText: 'Fees needing follow-up',
                          icon: Icons.payments_outlined,
                          color: const Color(0xFF6D4C41),
                        ),
                        _KpiCard(
                          title: 'Published Notices',
                          value: data.publishedNotices.toString(),
                          helperText: 'Visible school updates',
                          icon: Icons.notifications_active_outlined,
                          color: const Color(0xFF2E7D32),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final wide = constraints.maxWidth >= 1000;
                        return wide
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: _TodayOperations(
                                      recentNotifications: data.recentNotifications,
                                      recentDocuments: data.recentDocuments,
                                      onMarkAttendance: () => _openScreen(
                                        const AdminAttendanceManagementScreen(),
                                      ),
                                      onFeeCollection: () => _openScreen(
                                        const AdminFeesScreen(),
                                      ),
                                      onFinanceEntry: () => _openScreen(
                                        const AdminFinanceScreen(),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: _RecentActivityList(
                                      items: data.recentActivity,
                                    ),
                                  ),
                                ],
                              )
                            : Column(
                                children: [
                                  _TodayOperations(
                                    recentNotifications: data.recentNotifications,
                                    recentDocuments: data.recentDocuments,
                                    onMarkAttendance: () => _openScreen(
                                      const AdminAttendanceManagementScreen(),
                                    ),
                                    onFeeCollection: () => _openScreen(
                                      const AdminFeesScreen(),
                                    ),
                                    onFinanceEntry: () => _openScreen(
                                      const AdminFinanceScreen(),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  _RecentActivityList(
                                    items: data.recentActivity,
                                  ),
                                ],
                              );
                      },
                    ),
                    const SizedBox(height: 20),
                    _SectionCard(
                      title: 'Quick Actions',
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final columns = constraints.maxWidth >= 1000
                              ? 4
                              : constraints.maxWidth >= 700
                                  ? 3
                                  : 2;
                          return GridView.count(
                            crossAxisCount: columns,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: 2.2,
                            children: [
                              _QuickActionCard(
                                icon: Icons.person_add_alt_1_outlined,
                                label: 'Add Student',
                                onTap: () => _openScreen(
                                  const admin_students_screen(),
                                ),
                              ),
                              _QuickActionCard(
                                icon: Icons.people_outline,
                                label: 'Add User',
                                onTap: () => _openScreen(
                                  const AdminUsersScreen(),
                                ),
                              ),
                              _QuickActionCard(
                                icon: Icons.class_outlined,
                                label: 'Add Class',
                                onTap: () => _openScreen(
                                  const AdminClassesScreen(),
                                ),
                              ),
                              _QuickActionCard(
                                icon: Icons.description_outlined,
                                label: 'Add Document',
                                onTap: () => _openScreen(
                                  const AdminDocumentsScreen(),
                                ),
                              ),
                              _QuickActionCard(
                                icon: Icons.notifications_outlined,
                                label: 'Create Notification',
                                onTap: () => _openScreen(
                                  const AdminNotificationsScreen(),
                                ),
                              ),
                              _QuickActionCard(
                                icon: Icons.fact_check_outlined,
                                label: 'Mark Attendance',
                                onTap: () => _openScreen(
                                  const AdminAttendanceManagementScreen(),
                                ),
                              ),
                              _QuickActionCard(
                                icon: Icons.payments_outlined,
                                label: 'Fee Collection',
                                onTap: () => _openScreen(
                                  const AdminFeesScreen(),
                                ),
                              ),
                              _QuickActionCard(
                                icon: Icons.account_balance_wallet_outlined,
                                label: 'Finance Entry',
                                onTap: () => _openScreen(
                                  const AdminFinanceScreen(),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

}

class _DashboardData {
  const _DashboardData({
    required this.totalStudents,
    required this.totalStaff,
    required this.activeClasses,
    required this.todayAttendance,
    required this.pendingFees,
    required this.publishedNotices,
    required this.recentActivity,
    required this.recentNotifications,
    required this.recentDocuments,
  });

  final int totalStudents;
  final int totalStaff;
  final int activeClasses;
  final int todayAttendance;
  final int pendingFees;
  final int publishedNotices;
  final List<_ActivityItem> recentActivity;
  final List<_ActivityItem> recentNotifications;
  final List<_ActivityItem> recentDocuments;
}

class _ActivityItem {
  const _ActivityItem({
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.sortKey,
  });

  final String title;
  final String subtitle;
  final String trailing;
  final DateTime sortKey;
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.title,
    required this.value,
    required this.helperText,
    required this.icon,
    required this.color,
  });

  final String title;
  final String value;
  final String helperText;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 320),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.10),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey[700],
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              helperText,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[600],
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF2E7D32).withOpacity(0.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: const Color(0xFF2E7D32)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _TodayOperations extends StatelessWidget {
  const _TodayOperations({
    required this.recentNotifications,
    required this.recentDocuments,
    required this.onMarkAttendance,
    required this.onFeeCollection,
    required this.onFinanceEntry,
  });

  final List<_ActivityItem> recentNotifications;
  final List<_ActivityItem> recentDocuments;
  final VoidCallback onMarkAttendance;
  final VoidCallback onFeeCollection;
  final VoidCallback onFinanceEntry;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Today\'s Operations',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _MiniSummaryCard(
            title: 'Attendance',
            value: 'Mark today\'s attendance',
            icon: Icons.fact_check_outlined,
            onTap: onMarkAttendance,
          ),
          const SizedBox(height: 12),
          _MiniSummaryCard(
            title: 'Fee Collection',
            value: 'Review due and paid fees',
            icon: Icons.payments_outlined,
            onTap: onFeeCollection,
          ),
          const SizedBox(height: 12),
          _MiniSummaryCard(
            title: 'Finance',
            value: 'Add income or expense entries',
            icon: Icons.account_balance_wallet_outlined,
            onTap: onFinanceEntry,
          ),
          const SizedBox(height: 20),
          Text(
            'Recent Notifications',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 10),
          if (recentNotifications.isEmpty)
            const _EmptyState(message: 'No notifications yet')
          else
            ...recentNotifications.map(
              (item) => _OperationTile(item: item),
            ),
          const SizedBox(height: 20),
          Text(
            'Recent Documents',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 10),
          if (recentDocuments.isEmpty)
            const _EmptyState(message: 'No documents uploaded yet')
          else
            ...recentDocuments.map(
              (item) => _OperationTile(item: item),
            ),
        ],
      ),
    );
  }
}

class _MiniSummaryCard extends StatelessWidget {
  const _MiniSummaryCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String value;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF7F8F7),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF2E7D32).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: const Color(0xFF2E7D32)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      value,
                      style: TextStyle(
                        color: Colors.grey[700],
                        fontSize: 13,
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

class _RecentActivityList extends StatelessWidget {
  const _RecentActivityList({required this.items});

  final List<_ActivityItem> items;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Recent Activity',
      child: items.isEmpty
          ? const _EmptyState(message: 'No recent activity')
          : Column(
              children: items
                  .map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _ActivityTile(item: item),
                    ),
                  )
                  .toList(),
            ),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({required this.item});

  final _ActivityItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8F7),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF2E7D32).withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.history, color: Color(0xFF2E7D32)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  item.subtitle,
                  style: TextStyle(color: Colors.grey[700]),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            item.trailing.isEmpty ? '' : item.trailing,
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _OperationTile extends StatelessWidget {
  const _OperationTile({required this.item});

  final _ActivityItem item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          const Icon(Icons.circle, size: 8, color: Color(0xFF2E7D32)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${item.title} • ${item.subtitle}',
              style: TextStyle(color: Colors.grey[800]),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8F7),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        message,
        style: TextStyle(color: Colors.grey[600]),
      ),
    );
  }
}

class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: List.generate(
            6,
            (_) => Container(
              width: 260,
              height: 140,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          height: 220,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
