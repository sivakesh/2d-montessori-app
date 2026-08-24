// ignore_for_file: deprecated_member_use
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_sizes.dart';
import '../../../services/user_session_log_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../../calendar/models/calendar_event_model.dart';
import '../../calendar/services/calendar_service.dart';
import '../../calendar/ui/admin_calendar_screen.dart';
import '../../fees/services/fee_service.dart';
import '../../fees/ui/admin_fees_screen.dart';
import '../../finance/ui/admin_finance_screen.dart';
import '../students/ui/admin_students_screen.dart';
import 'admin_attendance_management_screen.dart';
import 'admin_classes_screen.dart';
import 'admin_documents_screen.dart';
import 'admin_layout.dart';
import 'admin_notifications_screen.dart';
import 'admin_users_screen.dart';

/// Pure text formatting for the Admin Dashboard's compact Calendar summary —
/// no Firestore access, so (like `computeAttendanceSummary` in
/// admin_attendance_management_screen.dart) it's public and unit tested
/// directly rather than only through the full screen.
String formatUpcomingEventsSummary(List<CalendarEventModel> events) {
  if (events.isEmpty) return 'No upcoming events';
  return events
      .map((e) => '${e.title} (${DateFormat('MMM d').format(e.date)})')
      .join(', ');
}

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

/// Guards direct navigation (e.g. the '/admin_dashboard' route) so Staff
/// cannot reach the Admin console even without going through the sidebar.
class _AdminAccessRestrictedScreen extends StatelessWidget {
  const _AdminAccessRestrictedScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, size: 48, color: Colors.grey),
              const SizedBox(height: 12),
              const Text(
                'You do not have access to this section.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text('Go Back'),
              ),
            ],
          ),
        ),
      ),
    );
  }
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

  // 'attendance' documents store the day as a 'yyyy-MM-dd' string in the
  // `date` field on every write path (Dashboard Attendance's markPresent/
  // markAbsent and the Admin Attendance Management batch save both write
  // it). `attendanceDate` is only written by the admin batch path in that
  // same string format, so a DateTime range filter against it can never
  // match — querying `date` with an equality match is what actually
  // reflects the stored data.
  Future<int> _countTodayAttendance() async {
    final todayKey = DateFormat('yyyy-MM-dd').format(DateTime.now().toLocal());
    final snap = await _firestore
        .collection('attendance')
        .where('date', isEqualTo: todayKey)
        .get();
    return snap.size;
  }

  // "Pending Fees" = student fee assignments with an outstanding balance,
  // matching the Fees module's own Dues/Collections tabs
  // (student_fee_assignments.balanceAmount > 0). Reuses FeeService rather
  // than a second fee-calculation path.
  Future<int> _countPendingFees() async {
    final assignments = await FeeService().getAssignments();
    return assignments.where((a) => a.balanceAmount > 0).length;
  }

  // Published items only — a Draft calendar item isn't really "upcoming"
  // from the school's perspective yet, so it's excluded the same way the
  // Parent/Staff calendar feeds already exclude it.
  Future<List<CalendarEventModel>> _loadUpcomingEvents() async {
    try {
      final events = await CalendarService().getAllEvents();
      final today = DateTime.now();
      final todayOnly = DateTime(today.year, today.month, today.day);
      final upcoming = events
          .where((e) =>
              e.status == CalendarEventStatus.published &&
              !e.date.isBefore(todayOnly))
          .toList();
      upcoming.sort((a, b) => a.date.compareTo(b.date));
      return upcoming.take(3).toList();
    } catch (_) {
      return const [];
    }
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

  // Recent activity is built from actual creation timestamps across the
  // core collections — there is no audit-log subsystem in this app (no
  // code anywhere writes an "auditLogs" document), so that was previously
  // queried but always fell through to this same union unnoticed.
  Future<List<_ActivityItem>> _loadRecentActivity() async {
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
      _loadUpcomingEvents(),
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
      upcomingEvents: results[9] as List<CalendarEventModel>,
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
    return Consumer(
      builder: (context, ref, _) {
        final role = ref.watch(currentUserProvider)?.role.toLowerCase();
        if (role != 'admin') {
          return const _AdminAccessRestrictedScreen();
        }
        return _buildAdminDashboard(context);
      },
    );
  }

  Widget _buildAdminDashboard(BuildContext context) {
    final isMobile =
        MediaQuery.of(context).size.width < AppSizes.mobileBreakpoint;
    return AdminLayout(
      selectedIndex: 0,
      title: 'Admin Dashboard',
      body: FutureBuilder<_DashboardData>(
          future: _future,
          builder: (context, snapshot) {
            final data = snapshot.data;
            final loading = snapshot.connectionState == ConnectionState.waiting;
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                isMobile ? 16 : 24,
                isMobile ? 16 : 24,
                isMobile ? 16 : 24,
                isMobile ? 40 : 24,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (loading)
                    const _DashboardSkeleton()
                  else if (data != null) ...[
                    _KpiSection(data: data, isMobile: isMobile),
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
                                      upcomingEvents: data.upcomingEvents,
                                      onMarkAttendance: () => _openScreen(
                                        const AdminAttendanceManagementScreen(),
                                      ),
                                      onFeeCollection: () => _openScreen(
                                        const AdminFeesScreen(),
                                      ),
                                      onFinanceEntry: () => _openScreen(
                                        const AdminFinanceScreen(),
                                      ),
                                      onOpenCalendar: () => _openScreen(
                                        const AdminCalendarScreen(),
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
                                    upcomingEvents: data.upcomingEvents,
                                    onMarkAttendance: () => _openScreen(
                                      const AdminAttendanceManagementScreen(),
                                    ),
                                    onFeeCollection: () => _openScreen(
                                      const AdminFeesScreen(),
                                    ),
                                    onFinanceEntry: () => _openScreen(
                                      const AdminFinanceScreen(),
                                    ),
                                    onOpenCalendar: () => _openScreen(
                                      const AdminCalendarScreen(),
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
                          // A fixed tile height (mainAxisExtent) rather than
                          // childAspectRatio, so a 2-line label can never
                          // overflow the cell regardless of column count.
                          final tileHeight = columns >= 4
                              ? 72.0
                              : columns == 3
                                  ? 80.0
                                  : 92.0;
                          return GridView.builder(
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: columns,
                              mainAxisSpacing: 12,
                              crossAxisSpacing: 12,
                              mainAxisExtent: tileHeight,
                            ),
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _quickActions.length,
                            itemBuilder: (context, index) =>
                                _quickActions[index],
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
    );
  }

  List<Widget> get _quickActions => [
        _QuickActionCard(
          icon: Icons.person_add_alt_1_outlined,
          label: 'Add Student',
          onTap: () => _openScreen(const admin_students_screen()),
        ),
        _QuickActionCard(
          icon: Icons.people_outline,
          label: 'Add User',
          onTap: () => _openScreen(const AdminUsersScreen()),
        ),
        _QuickActionCard(
          icon: Icons.class_outlined,
          label: 'Add Class',
          onTap: () => _openScreen(const AdminClassesScreen()),
        ),
        _QuickActionCard(
          icon: Icons.description_outlined,
          label: 'Add Document',
          onTap: () => _openScreen(const AdminDocumentsScreen()),
        ),
        _QuickActionCard(
          icon: Icons.notifications_outlined,
          label: 'Create Notification',
          onTap: () => _openScreen(const AdminNotificationsScreen()),
        ),
        _QuickActionCard(
          icon: Icons.fact_check_outlined,
          label: 'Mark Attendance',
          onTap: () => _openScreen(const AdminAttendanceManagementScreen()),
        ),
        _QuickActionCard(
          icon: Icons.payments_outlined,
          label: 'Fee Collection',
          onTap: () => _openScreen(const AdminFeesScreen()),
        ),
        _QuickActionCard(
          icon: Icons.account_balance_wallet_outlined,
          label: 'Finance Entry',
          onTap: () => _openScreen(const AdminFinanceScreen()),
        ),
      ];
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
    required this.upcomingEvents,
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
  final List<CalendarEventModel> upcomingEvents;
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

/// Lays out the 6 KPI cards: a desktop `Wrap` of roomy cards, or — on
/// mobile — a fixed 2-column grid of compact cards, so a KPI section never
/// collapses into one oversized card per row.
class _KpiSection extends StatelessWidget {
  const _KpiSection({required this.data, required this.isMobile});

  final _DashboardData data;
  final bool isMobile;

  List<_KpiCard> _cards() => [
        _KpiCard(
          title: 'Total Students',
          value: data.totalStudents.toString(),
          helperText: 'Active learners in school',
          icon: Icons.groups_outlined,
          color: const Color(0xFF2E7D32),
          compact: isMobile,
        ),
        _KpiCard(
          title: 'Total Staff',
          value: data.totalStaff.toString(),
          helperText: 'Teachers and support team',
          icon: Icons.badge_outlined,
          color: const Color(0xFF4E7C5B),
          compact: isMobile,
        ),
        _KpiCard(
          title: 'Active Classes',
          value: data.activeClasses.toString(),
          helperText: 'Running classrooms',
          icon: Icons.class_outlined,
          color: const Color(0xFF558B2F),
          compact: isMobile,
        ),
        _KpiCard(
          title: 'Today\'s Attendance',
          value: data.todayAttendance.toString(),
          helperText: 'Marked attendance records',
          icon: Icons.fact_check_outlined,
          color: const Color(0xFF388E3C),
          compact: isMobile,
        ),
        _KpiCard(
          title: 'Pending Fees',
          value: data.pendingFees.toString(),
          helperText: 'Fees needing follow-up',
          icon: Icons.payments_outlined,
          color: const Color(0xFF6D4C41),
          compact: isMobile,
        ),
        _KpiCard(
          title: 'Published Notices',
          value: data.publishedNotices.toString(),
          helperText: 'Visible school updates',
          icon: Icons.notifications_active_outlined,
          color: const Color(0xFF2E7D32),
          compact: isMobile,
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final cards = _cards();
    if (!isMobile) {
      return Wrap(spacing: 16, runSpacing: 16, children: cards);
    }
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        mainAxisExtent: 118,
      ),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: cards.length,
      itemBuilder: (context, index) => cards[index],
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.title,
    required this.value,
    required this.helperText,
    required this.icon,
    required this.color,
    this.compact = false,
  });

  final String title;
  final String value;
  final String helperText;
  final IconData icon;
  final Color color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: EdgeInsets.all(compact ? 12 : 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(compact ? 16 : 20),
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
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: EdgeInsets.all(compact ? 7 : 10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.10),
              borderRadius: BorderRadius.circular(compact ? 10 : 14),
            ),
            child: Icon(icon, color: color, size: compact ? 18 : 24),
          ),
          SizedBox(height: compact ? 6 : 16),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: (compact
                    ? Theme.of(context).textTheme.bodySmall
                    : Theme.of(context).textTheme.bodyMedium)
                ?.copyWith(
                  color: Colors.grey[700],
                  fontWeight: FontWeight.w600,
                ),
          ),
          SizedBox(height: compact ? 2 : 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: (compact
                    ? Theme.of(context).textTheme.titleLarge
                    : Theme.of(context).textTheme.headlineMedium)
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          if (!compact) ...[
            const SizedBox(height: 6),
            Text(
              helperText,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[600],
                  ),
            ),
          ],
        ],
      ),
    );

    if (compact) return card;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 320),
      child: card,
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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF2E7D32).withOpacity(0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: const Color(0xFF2E7D32), size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    height: 1.2,
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
    required this.upcomingEvents,
    required this.onMarkAttendance,
    required this.onFeeCollection,
    required this.onFinanceEntry,
    required this.onOpenCalendar,
  });

  final List<_ActivityItem> recentNotifications;
  final List<_ActivityItem> recentDocuments;
  final List<CalendarEventModel> upcomingEvents;
  final VoidCallback onMarkAttendance;
  final VoidCallback onFeeCollection;
  final VoidCallback onFinanceEntry;
  final VoidCallback onOpenCalendar;

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
            title: 'Calendar',
            value: formatUpcomingEventsSummary(upcomingEvents),
            icon: Icons.calendar_month_outlined,
            onTap: onOpenCalendar,
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  item.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
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
