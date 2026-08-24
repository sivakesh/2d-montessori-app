// ignore_for_file: use_build_context_synchronously, curly_braces_in_flow_control_structures, unnecessary_underscores, deprecated_member_use
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/layout/bottom_nav.dart';
import '../../../core/layout/responsive_layout.dart';
import '../../../core/layout/sidebar.dart';
import '../../../core/theme/app_sizes.dart';
import '../../../core/widgets/responsive_dialog_shell.dart';
import '../../auth/models/app_user.dart';
import '../../auth/data/user_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../services/user_session_log_service.dart';
import '../../admin/students/data/admin_student_service.dart';
import '../../admin/ui/admin_attendance_management_screen.dart'
    show resolveAttendanceDisplayStatus;
import '../../attendance/providers/attendance_provider.dart';
import '../../attendance/ui/attendance_screen.dart';
import '../../calendar/ui/calendar_view.dart';
import '../../classes/data/class_service.dart';
import '../../classes/providers/class_provider.dart';
import '../../classes/ui/class_list_screen.dart';
import '../../leave/services/leave_service.dart';
import '../../leave/ui/my_leave_view.dart';
import '../../mood_checkin/models/mood_checkin_model.dart';
import '../../mood_checkin/models/mood_option_model.dart';
import '../../mood_checkin/providers/mood_checkin_provider.dart';
import '../../mood_checkin/ui/mood_checkin_dialog.dart';
import '../../mood_checkin/widgets/mood_option_chip.dart';
import '../../notifications/ui/notifications_feed_screen.dart';
import '../../students/providers/student_provider.dart';
import '../../students/ui/student_list_screen.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({
    super.key,
    this.userService,
    this.userSessionLogService,
    this.adminStudentService,
    this.classService,
    this.leaveService,
  });

  /// Overridable only so tests can inject fake-Firestore-backed services —
  /// the same DI seam every service here already exposes on its own
  /// constructor. Production callers never pass these. Without this seam
  /// DashboardScreen could not be constructed in a widget test at all:
  /// UserSessionLogService/UserService default to real Firebase singletons,
  /// and UserSessionLogService.logSessionOpened is called unconditionally
  /// from initState, so an un-injected instance throws before the widget
  /// ever finishes mounting. adminStudentService/classService are passed
  /// through to the Students/Classes tabs for the same reason — those
  /// screens construct their own services eagerly too. leaveService is the
  /// same seam AttendanceScreen already exposes, needed here so the "Not
  /// Marked Today" count can fold in approved Student Leave (ATT-06).
  final UserService? userService;
  final UserSessionLogService? userSessionLogService;
  final AdminStudentService? adminStudentService;
  final ClassService? classService;
  final LeaveService? leaveService;

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  int selectedIndex = 0;
  bool _loadingMetrics = true;
  bool _savingCheckin = false;
  List<_DashboardMetric> _metrics = const [];
  List<MoodCheckinModel> _recentMoodCheckins = const [];
  final Map<String, String> _classNames = {};
  final _classListKey = GlobalKey<ClassListScreenState>();
  final _studentListKey = GlobalKey<StudentListScreenState>();

  late final _userService = widget.userService ?? UserService();
  late final _userSessionLogService =
      widget.userSessionLogService ?? UserSessionLogService();
  late final _leaveService = widget.leaveService ?? LeaveService();

  @override
  void initState() {
    super.initState();
    _userSessionLogService.logSessionOpened(source: 'dashboard');
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    setState(() => _loadingMetrics = true);
    try {
      final attendanceService = ref.read(attendanceServiceProvider);
      final moodService = ref.read(moodCheckinServiceProvider);
      final studentService = ref.read(studentServiceProvider);
      final classService = ref.read(classServiceProvider);

      final classes = await classService.getClasses();
      // Already active-only: StudentService.getAllStudents and
      // UserService.getStaffUsers both filter `isActive == true`
      // server-side (staff additionally to the staff/teacher/admin_staff
      // roles) — so these lists ARE the Total Students / Total Staff
      // populations, with no further filtering needed here.
      final students = await studentService.getAllStudents();
      final staff = await _userService.getStaffUsers();
      final attendanceMap = await attendanceService.getTodayAttendanceMap();
      final moodCount = await moodService.getTodayMoodCheckinCount();
      final alertCount = await moodService.getTodayAlertCount();
      final recentMoodCheckins = await moodService.getLatestTodayMoodCheckins(
        limit: 5,
      );
      // Best-effort, same fallback AttendanceScreen uses for the identical
      // lookup: a failure to resolve on-leave students/staff must not block
      // the dashboard from loading — it just means Not Marked Today
      // temporarily can't exclude leave for this refresh.
      Set<String> studentIdsOnLeave = {};
      try {
        studentIdsOnLeave = await _leaveService.getStudentIdsOnApprovedLeave(
          DateTime.now().toLocal(),
        );
      } catch (_) {
        studentIdsOnLeave = {};
      }
      Set<String> staffIdsOnLeave = {};
      try {
        staffIdsOnLeave = await _leaveService.getStaffIdsOnApprovedLeave(
          DateTime.now().toLocal(),
        );
      } catch (_) {
        staffIdsOnLeave = {};
      }

      final classNames = <String, String>{
        for (final doc in classes)
          doc.id: doc.data()['name']?.toString() ?? '-',
      };
      _classNames
        ..clear()
        ..addAll(classNames);

      final totalStudents = students.length;
      final totalStaff = staff.length;
      final totalPeople = totalStudents + totalStaff;

      // One pass per population resolves Present/Absent/On Leave/Not Marked
      // together, via the same resolveAttendanceDisplayStatus helper the
      // Attendance screen itself uses (ATT-01..05) — so this can never
      // disagree with what Attendance shows, and Total = Present + Absent +
      // On Leave + Not Marked holds by construction rather than by a
      // separate "Total - Present" assumption. Present/Absent keep the
      // exact status == 'present'/'absent' check this dashboard has always
      // used, so those two counts are unchanged from before; only Not
      // Marked's calculation changes, to stop miscounting an approved leave.
      var studentsPresent = 0;
      var studentsAbsent = 0;
      var studentsOnLeave = 0;
      var studentsNotMarked = 0;
      for (final doc in students) {
        final record = attendanceMap['student_${doc.id}'];
        final display = resolveAttendanceDisplayStatus(
          rawStatus: _dashboardRawStatus(record),
          isOnApprovedLeave: studentIdsOnLeave.contains(doc.id),
        );
        switch (display) {
          case 'present':
            studentsPresent++;
          case 'absent':
            studentsAbsent++;
          case 'on_leave':
            studentsOnLeave++;
          default:
            studentsNotMarked++;
        }
      }

      // Staff Leave -> Attendance is now wired (ATT-06 completion), the same
      // resolveAttendanceDisplayStatus pipeline as Students, via
      // LeaveService.getStaffIdsOnApprovedLeave.
      var staffPresent = 0;
      var staffAbsent = 0;
      var staffOnLeave = 0;
      var staffNotMarked = 0;
      for (final user in staff) {
        final record = attendanceMap['staff_${user.id}'];
        final display = resolveAttendanceDisplayStatus(
          rawStatus: _dashboardRawStatus(record),
          isOnApprovedLeave: staffIdsOnLeave.contains(user.id),
        );
        switch (display) {
          case 'present':
            staffPresent++;
          case 'absent':
            staffAbsent++;
          case 'on_leave':
            staffOnLeave++;
          default:
            staffNotMarked++;
        }
      }

      // Documents (and, in debug builds, enforces) the reconciliation rule
      // ATT-06 requires — Total = Present + Absent + On Leave + Not Marked
      // for each population — rather than assuming Not Marked = Total -
      // Present, which would silently double-count an approved leave.
      assert(
        studentsPresent + studentsAbsent + studentsOnLeave + studentsNotMarked ==
            totalStudents,
      );
      assert(
        staffPresent + staffAbsent + staffOnLeave + staffNotMarked == totalStaff,
      );

      final notMarked = studentsNotMarked + staffNotMarked;

      final metrics = <_DashboardMetric>[
        _DashboardMetric(
          'Total Students',
          totalStudents.toString(),
          Icons.groups_outlined,
        ),
        _DashboardMetric(
          'Total Staff',
          totalStaff.toString(),
          Icons.people_outline,
        ),
        _DashboardMetric(
          'Total People',
          totalPeople.toString(),
          Icons.diversity_3,
        ),
        _DashboardMetric(
          'Students Present Today',
          studentsPresent.toString(),
          Icons.verified_outlined,
        ),
        _DashboardMetric(
          'Staff Present Today',
          staffPresent.toString(),
          Icons.badge_outlined,
        ),
        _DashboardMetric(
          'Not Marked Today',
          notMarked.toString(),
          Icons.pending_actions_outlined,
        ),
        _DashboardMetric(
          'Mood Check-ins Today',
          moodCount.toString(),
          Icons.favorite_outline,
        ),
        _DashboardMetric(
          'Alerts / Distress',
          alertCount.toString(),
          Icons.warning_amber_outlined,
        ),
      ];

      if (!mounted) return;
      setState(() {
        _metrics = metrics;
        _recentMoodCheckins = recentMoodCheckins;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _metrics = const [];
        _recentMoodCheckins = const [];
      });
    } finally {
      if (mounted) setState(() => _loadingMetrics = false);
    }
  }

  /// The dashboard's own, pre-existing present/absent convention — a plain
  /// `status == 'present'`/`'absent'` check on the attendance record, with
  /// no photo-based fallback (unlike AttendanceScreen's own richer
  /// `_rawStatus`). Kept exactly as this dashboard already computed
  /// Present Today before ATT-06, so those counts are unchanged; only fed
  /// into [resolveAttendanceDisplayStatus] so Not Marked Today can also
  /// fold in approved leave via that one shared helper.
  String _dashboardRawStatus(Map<String, dynamic>? record) {
    if (record == null) return 'not_marked';
    final status = record['status']?.toString() ?? '';
    if (status == 'present') return 'present';
    if (status == 'absent') return 'absent';
    return 'not_marked';
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  Future<void> _showManualStudentCheckIn() async {
    final student = await _selectStudent();
    if (student == null) return;
    final currentUser = ref.read(currentUserProvider);
    if (currentUser == null) return;
    await _saveManualMoodCheckIn(
      entityType: 'student',
      entityId: student.id,
      entityName: student.data()['name']?.toString() ?? '',
      classId: student.data()['classId']?.toString(),
      className: _classNames[student.data()['classId']?.toString() ?? ''],
      createdBy: currentUser.id,
    );
  }

  Future<void> _showManualStaffCheckIn() async {
    final staff = await _selectStaff();
    if (staff == null) return;
    final currentUser = ref.read(currentUserProvider);
    if (currentUser == null) return;
    await _saveManualMoodCheckIn(
      entityType: 'staff',
      entityId: staff.id,
      entityName: staff.name?.isNotEmpty == true ? staff.name! : staff.phone,
      createdBy: currentUser.id,
    );
  }

  Future<void> _saveManualMoodCheckIn({
    required String entityType,
    required String entityId,
    required String entityName,
    required String createdBy,
    String? classId,
    String? className,
  }) async {
    final mood = await MoodCheckinDialog.show(context, entityType: entityType);
    if (mood == null) return;
    final service = ref.read(moodCheckinServiceProvider);
    String? photoUrl;
    setState(() => _savingCheckin = true);
    try {
      final wantPhoto = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Add photo?'),
          content: const Text('Would you like to attach an optional photo?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Skip'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Add Photo'),
            ),
          ],
        ),
      );

      if (wantPhoto == true) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Uploading photo...')));
        photoUrl = await service.uploadOptionalMoodPhoto(
          entityType: entityType,
          entityId: entityId,
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Saving check-in...')));
      await service.createMoodCheckin(
        entityType: entityType,
        entityId: entityId,
        entityName: entityName,
        classId: classId,
        className: className,
        moodCode: mood.moodCode,
        moodLabel: mood.moodLabel,
        moodCategory: mood.moodCategory,
        intensity: mood.intensity,
        notes: mood.notes,
        source: 'manual',
        photoUrl: photoUrl,
        createdBy: createdBy,
      );
      await _loadDashboardData();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Mood check-in saved')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save mood check-in: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _savingCheckin = false);
    }
  }

  Future<QueryDocumentSnapshot<Map<String, dynamic>>?> _selectStudent() async {
    final studentService = ref.read(studentServiceProvider);
    final classes = await ref.read(classServiceProvider).getClasses();
    final classNames = {
      for (final doc in classes) doc.id: doc.data()['name']?.toString() ?? '-',
    };
    final students = await studentService.getAllStudents();
    if (!mounted) return null;

    String query = '';
    String? selectedClassId;
    return showDialog<QueryDocumentSnapshot<Map<String, dynamic>>>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final filtered = students.where((doc) {
              final data = doc.data();
              if (data['isActive'] != true) return false;
              final classId = data['classId']?.toString();
              if (selectedClassId != null && classId != selectedClassId)
                return false;
              final name = data['name']?.toString().toLowerCase() ?? '';
              final admissionNo =
                  data['admissionNo']?.toString().toLowerCase() ?? '';
              final className = classNames[classId ?? '']?.toLowerCase() ?? '';
              return query.isEmpty ||
                  name.contains(query) ||
                  admissionNo.contains(query) ||
                  className.contains(query);
            }).toList();

            return ResponsiveDialogShell(
              desktopWidth: 600,
              child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Select Student',
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.of(dialogContext).maybePop(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        decoration: const InputDecoration(
                          labelText: 'Search student',
                          prefixIcon: Icon(Icons.search),
                        ),
                        onChanged: (value) =>
                            setDialogState(() => query = value.toLowerCase()),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilterChip(
                            label: const Text('All Classes'),
                            selected: selectedClassId == null,
                            onSelected: (_) =>
                                setDialogState(() => selectedClassId = null),
                          ),
                          for (final doc in classes)
                            FilterChip(
                              label: Text(doc.data()['name']?.toString() ?? ''),
                              selected: selectedClassId == doc.id,
                              onSelected: (_) => setDialogState(
                                () => selectedClassId = doc.id,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Flexible(
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final student = filtered[index];
                            final data = student.data();
                            return ListTile(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              tileColor: Colors.grey.shade50,
                              title: Text(data['name']?.toString() ?? ''),
                              subtitle: Text(
                                'Admission: ${data['admissionNo']?.toString() ?? '-'} • Class: ${classNames[data['classId']?.toString() ?? ''] ?? '-'}',
                              ),
                              onTap: () =>
                                  Navigator.of(dialogContext).pop(student),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
            );
          },
        );
      },
    );
  }

  Future<AppUser?> _selectStaff() async {
    final users = await _userService.getStaffUsers();
    if (!mounted) return null;
    String query = '';
    return showDialog<AppUser>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final filtered = users.where((user) {
              final name = (user.name ?? '').toLowerCase();
              final phone = user.phone.toLowerCase();
              final role = user.role.toLowerCase();
              return query.isEmpty ||
                  name.contains(query) ||
                  phone.contains(query) ||
                  role.contains(query);
            }).toList();

            return ResponsiveDialogShell(
              desktopWidth: 560,
              child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Select Staff Member',
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.of(dialogContext).maybePop(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        decoration: const InputDecoration(
                          labelText: 'Search staff',
                          prefixIcon: Icon(Icons.search),
                        ),
                        onChanged: (value) =>
                            setDialogState(() => query = value.toLowerCase()),
                      ),
                      const SizedBox(height: 12),
                      Flexible(
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final staff = filtered[index];
                            final name = staff.name?.isNotEmpty == true
                                ? staff.name!
                                : staff.phone;
                            return ListTile(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              tileColor: Colors.grey.shade50,
                              title: Text(name),
                              subtitle: Text('${staff.phone} • ${staff.role}'),
                              onTap: () =>
                                  Navigator.of(dialogContext).pop(staff),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final isMobile = MediaQuery.of(context).size.width < AppSizes.mobileBreakpoint;

    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final isAdmin = user.role.toLowerCase() == 'admin';

    final dashboardContent = SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          isMobile ? 20 : 32,
          24,
          isMobile ? 20 : 32,
          40,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DashboardHeader(dateLabel: _formatDate(DateTime.now().toLocal())),
            const SizedBox(height: 14),
            _PersonalWellbeingCard(
              onSaved: () async {
                await _loadDashboardData();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Wellbeing check-in saved')),
                  );
                }
              },
            ),
            const SizedBox(height: 20),
            if (_loadingMetrics)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              )
            else ...[
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 1200
                      ? 3
                      : constraints.maxWidth >= 700
                      ? 2
                      : 1;
                  return Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: [
                      for (final metric in _metrics)
                        SizedBox(
                          width:
                              (constraints.maxWidth - (16 * (columns - 1))) /
                              columns,
                          child: _MetricCard(metric: metric),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 24),
              Text(
                'Quick Actions',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 1000
                      ? 4
                      : constraints.maxWidth >= 600
                      ? 2
                      : 1;
                  // index 1 = Attendance — must match the `tabs` list built
                  // later in build() (Dashboard=0, Attendance=1, ...), which
                  // is itself defined in the same order as AppSidebar/
                  // AppBottomNav's destinations. Can't reference `tabs`
                  // directly here since it's declared after
                  // dashboardContent (whose construction this is part of).
                  final actions = [
                    _QuickActionCard(
                      icon: Icons.fact_check_outlined,
                      title: 'Mark Student Attendance',
                      subtitle: 'Go to attendance screen',
                      onTap: () => setState(() => selectedIndex = 1),
                    ),
                    _QuickActionCard(
                      icon: Icons.badge_outlined,
                      title: 'Mark Staff Attendance',
                      subtitle: 'Go to attendance screen',
                      onTap: () => setState(() => selectedIndex = 1),
                    ),
                    _QuickActionCard(
                      icon: Icons.favorite_border,
                      title: 'Student Mood Check-In',
                      subtitle: 'Manual mood observation',
                      onTap: _savingCheckin ? null : _showManualStudentCheckIn,
                    ),
                    _QuickActionCard(
                      icon: Icons.health_and_safety_outlined,
                      title: 'Staff Wellbeing Check-In',
                      subtitle: 'Manual wellbeing check-in',
                      onTap: _savingCheckin ? null : _showManualStaffCheckIn,
                    ),
                  ];
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final action in actions)
                        SizedBox(
                          width:
                              (constraints.maxWidth - (12 * (columns - 1))) /
                              columns,
                          child: action,
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 24),
              Text(
                'Recent Mood Check-ins',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              if (_recentMoodCheckins.isEmpty)
                const Text('No mood check-ins today.')
              else
                _ExpandableRecentMoodList(
                  items: _recentMoodCheckins,
                  showCount: 3,
                ),
            ],
          ],
        ),
      ),
    );

    // Single source of truth for "what does tab N mean" — title and body
    // are defined together, per entry, in the exact order AppSidebar/
    // AppBottomNav render their destinations (Dashboard, Attendance,
    // Calendar, Leave, Students, Classes). Title and body used to be two
    // independently-hardcoded switch statements (one per mobile/web
    // layout) that could drift out of sync with each other and with this
    // order — which is exactly what happened after the destinations were
    // reordered: the web layout's switch was never updated, so e.g.
    // "Attendance" kept showing the old index-1 screen (Classes) under
    // the new label. Deriving both from one list makes that class of bug
    // structurally impossible: there is nowhere left for title and body
    // to disagree.
    final tabs = [
      (
        title: 'Dashboard',
        body: () => RefreshIndicator(onRefresh: _loadDashboardData, child: dashboardContent),
      ),
      (title: 'Attendance', body: () => const AttendanceScreen()),
      (title: 'Calendar', body: () => const CalendarView()),
      (title: 'Leave', body: () => const MyLeaveView()),
      (
        title: 'Students',
        body: () => StudentListScreen(
          key: _studentListKey,
          adminService: widget.adminStudentService,
        ),
      ),
      (
        title: 'Classes',
        body: () => ClassListScreen(
          key: _classListKey,
          readOnly: !isAdmin,
          service: widget.classService,
        ),
      ),
    ];
    final safeIndex = selectedIndex >= 0 && selectedIndex < tabs.length ? selectedIndex : 0;
    final currentTitle = tabs[safeIndex].title;
    final currentBody = tabs[safeIndex].body();
    final Widget? fab = !isAdmin
        ? null
        : currentTitle == 'Students'
        ? FloatingActionButton(
            backgroundColor: const Color(0xFF2E7D32),
            elevation: 4,
            onPressed: () => _studentListKey.currentState?.openAddStudent(),
            child: const Icon(Icons.add, color: Colors.white),
          )
        : currentTitle == 'Classes'
        ? FloatingActionButton(
            backgroundColor: const Color(0xFF2E7D32),
            elevation: 4,
            onPressed: () => _classListKey.currentState?.openAddClass(),
            child: const Icon(Icons.add, color: Colors.white),
          )
        : null;

    return ResponsiveLayout(
      mobile: Scaffold(
        backgroundColor: Colors.grey[50],
        floatingActionButton: fab,
        appBar: AppBar(
          centerTitle: false,
          title: Text(currentTitle),
          actions: [
            if (isAdmin)
              IconButton(
                icon: const Icon(Icons.admin_panel_settings),
                onPressed: () =>
                    Navigator.of(context).pushNamed('/admin_dashboard'),
              )
            else
              IconButton(
                icon: const Icon(Icons.notifications_outlined),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => NotificationsFeedScreen.forStaff(
                      title: 'Notifications',
                      staffUserId: user.id,
                    ),
                  ),
                ),
              ),
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () async {
                await ref.read(authServiceProvider).logout(ref, context);
                if (context.mounted) {
                  Navigator.of(
                    context,
                  ).pushNamedAndRemoveUntil('/login', (route) => false);
                }
              },
            ),
          ],
        ),
        body: SafeArea(child: currentBody),
        bottomNavigationBar: AppBottomNav(
          selectedIndex: selectedIndex,
          onItemTapped: (index) => setState(() => selectedIndex = index),
        ),
      ),
      web: Scaffold(
        backgroundColor: Colors.grey[50],
        floatingActionButton: fab,
        body: Row(
          children: [
            AppSidebar(
              selectedIndex: selectedIndex,
              onItemTapped: (index) => setState(() => selectedIndex = index),
            ),
            Expanded(
              child: Column(
                children: [
                  AppBar(
                    title: Text(currentTitle),
                    actions: [
                      if (isAdmin)
                        IconButton(
                          icon: const Icon(Icons.admin_panel_settings),
                          onPressed: () => Navigator.of(
                            context,
                          ).pushNamed('/admin_dashboard'),
                        )
                      else
                        IconButton(
                          icon: const Icon(Icons.notifications_outlined),
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => NotificationsFeedScreen.forStaff(
                                title: 'Notifications',
                                staffUserId: user.id,
                              ),
                            ),
                          ),
                        ),
                      IconButton(
                        icon: const Icon(Icons.logout),
                        onPressed: () async {
                          await ref
                              .read(authServiceProvider)
                              .logout(ref, context);
                          if (context.mounted) {
                            Navigator.of(context).pushNamedAndRemoveUntil(
                              '/login',
                              (route) => false,
                            );
                          }
                        },
                      ),
                    ],
                  ),
                  Expanded(child: currentBody),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardHeader extends ConsumerWidget {
  const _DashboardHeader({
    required this.dateLabel,
  });

  final String dateLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final providerUser = ref.watch(currentUserProvider);
    final authUser = FirebaseAuth.instance.currentUser;
    final phone = providerUser?.phone.trim().isNotEmpty == true
        ? providerUser!.phone.trim()
        : authUser?.phoneNumber?.trim() ?? '';
    final displayName = providerUser?.name?.trim() ?? '';
    final displayRole = providerUser?.role.trim() ?? '';
    final providerData = <String, dynamic>{
      'name': displayName,
      'fullName': displayName,
      'displayName': displayName,
      'role': displayRole,
      'phoneNumber': phone,
      'mobile': phone,
      'phone': phone,
      'contactNumber': phone,
    };

    final fallbackRef = authUser?.uid.isNotEmpty == true
        ? FirebaseFirestore.instance
            .collection('users')
            .where('firebaseAuthUid', isEqualTo: authUser!.uid)
            .limit(1)
        : phone.isNotEmpty
        ? FirebaseFirestore.instance
            .collection('users')
            .where('phoneNumber', isEqualTo: phone)
            .limit(1)
        : null;

    if (fallbackRef == null) {
      return _UserSummaryCard(userData: providerData, dateLabel: dateLabel);
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: fallbackRef.snapshots(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? const [];
        final firestoreData = docs.isNotEmpty ? docs.first.data() : const {};
        return _UserSummaryCard(
          userData: {
            ...firestoreData,
            ...providerData,
            'profileUrl':
                firestoreData['profileUrl'] ??
                firestoreData['photoUrl'] ??
                firestoreData['avatarUrl'] ??
                firestoreData['profileImageUrl'],
            'photoUrl':
                firestoreData['photoUrl'] ??
                firestoreData['profileUrl'] ??
                firestoreData['avatarUrl'] ??
                firestoreData['profileImageUrl'],
            'avatarUrl':
                firestoreData['avatarUrl'] ??
                firestoreData['profileUrl'] ??
                firestoreData['photoUrl'] ??
                firestoreData['profileImageUrl'],
            'profileImageUrl':
                firestoreData['profileImageUrl'] ??
                firestoreData['photoUrl'] ??
                firestoreData['profileUrl'] ??
                firestoreData['avatarUrl'],
          },
          dateLabel: dateLabel,
        );
      },
    );
  }
}

class _UserSummaryCard extends StatelessWidget {
  const _UserSummaryCard({
    required this.userData,
    required this.dateLabel,
  });

  final Map<String, dynamic> userData;
  final String dateLabel;

  String _firstNonEmpty(List<String> keys, {String fallback = ''}) {
    for (final key in keys) {
      final value = userData[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return fallback;
  }

  String _formatRole(String role) {
    final normalized = role.trim().toLowerCase();
    switch (normalized) {
      case 'admin':
        return 'Admin';
      case 'school_admin':
      case 'school-admin':
      case 'school admin':
        return 'School Admin';
      case 'staff':
        return 'Staff';
      default:
        return 'Staff';
    }
  }

  String _name() {
    final phone = _phone();
    return _firstNonEmpty(
      const ['name', 'fullName', 'displayName'],
      fallback: phone.isNotEmpty ? phone : 'User',
    );
  }

  String _phone() {
    return _firstNonEmpty(const ['phoneNumber', 'mobile', 'phone', 'contactNumber']);
  }

  String _role() {
    return _formatRole(_firstNonEmpty(const ['role'], fallback: 'staff'));
  }

  String _photoUrl() {
    return _firstNonEmpty(const ['profileUrl', 'photoUrl', 'avatarUrl', 'profileImageUrl']);
  }

  String _initials(String name) {
    final parts = name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return 'U';
    String firstLetter(String value) => value.isNotEmpty ? value[0].toUpperCase() : '';
    if (parts.length == 1) return firstLetter(parts.first);
    return '${firstLetter(parts.first)}${firstLetter(parts.last)}';
  }

  @override
  Widget build(BuildContext context) {
    final name = _name();
    final phone = _phone();
    final role = _role();
    final photoUrl = _photoUrl();
    final initials = _initials(name);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 420;
            final info = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Welcome back', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 6),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  '$role${phone.isNotEmpty ? ' • $phone' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey.shade600,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  dateLabel,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade500,
                      ),
                ),
              ],
            );

            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  info,
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: _Avatar(imageUrl: photoUrl, initials: initials),
                  ),
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: info),
                const SizedBox(width: 16),
                _Avatar(imageUrl: photoUrl, initials: initials),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.imageUrl,
    required this.initials,
  });

  final String imageUrl;
  final String initials;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 28,
      backgroundColor: const Color(0xFF2E7D32).withOpacity(0.12),
      backgroundImage: imageUrl.isNotEmpty ? NetworkImage(imageUrl) : null,
      onBackgroundImageError: imageUrl.isNotEmpty ? (Object error, StackTrace? stackTrace) {} : null,
      child: imageUrl.isEmpty
          ? Text(
              initials,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: Color(0xFF2E7D32),
              ),
            )
          : null,
    );
  }
}

class _DashboardMetric {
  const _DashboardMetric(this.label, this.value, this.icon);

  final String label;
  final String value;
  final IconData icon;
}

class _PersonalWellbeingCard extends ConsumerStatefulWidget {
  const _PersonalWellbeingCard({required this.onSaved});

  final Future<void> Function() onSaved;

  @override
  ConsumerState<_PersonalWellbeingCard> createState() =>
      _PersonalWellbeingCardState();
}

class _PersonalWellbeingCardState
    extends ConsumerState<_PersonalWellbeingCard> {
  bool _saving = false;
  String? _savingMoodCode;
  String? _latestMoodCode;
  List<MoodCheckinModel> _todayHistory = const [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final currentUser = ref.read(currentUserProvider);
    if (currentUser == null) return;
    final service = ref.read(moodCheckinServiceProvider);
    final entityId = _getCurrentStaffEntityId(currentUser);
    debugPrint('FETCH PERSONAL TODAY CHECKINS');
    debugPrint('entityId used: $entityId');
    final today = DateTime.now().toLocal();
    final startOfToday = DateTime(today.year, today.month, today.day);
    final endOfToday = startOfToday.add(const Duration(days: 1));
    debugPrint('startOfToday: $startOfToday');
    debugPrint('endOfToday: $endOfToday');
    final history = await service.getTodayMoodCheckinsForEntity(
      entityType: 'staff',
      entityId: entityId,
    );
    debugPrint('count fetched: ${history.length}');
    debugPrint('count after filtering: ${history.length}');
    if (!mounted) return;
    setState(() {
      _todayHistory = history;
    });
  }

  Future<void> _saveMood(MoodOptionModel option) async {
    if (_saving) return;
    final currentUser = ref.read(currentUserProvider);
    if (currentUser == null) return;
    final service = ref.read(moodCheckinServiceProvider);
    final entityId = _getCurrentStaffEntityId(currentUser);
    final entityName = currentUser.name?.isNotEmpty == true
        ? currentUser.name!
        : currentUser.phone.isNotEmpty
        ? currentUser.phone
        : 'Staff';
    final createdBy = FirebaseAuth.instance.currentUser?.uid.isNotEmpty == true
        ? FirebaseAuth.instance.currentUser!.uid
        : currentUser.id.isNotEmpty
        ? currentUser.id
        : currentUser.phone.isNotEmpty
        ? currentUser.phone
        : 'staff';
    final checkInAt = DateTime.now().toUtc();
    debugPrint('Inline staff wellbeing check-in payload:');
    debugPrint('current user id: ${currentUser.id}');
    debugPrint(
      'current user name/phone: ${currentUser.name ?? currentUser.phone}',
    );
    debugPrint('selected moodCode: ${option.moodCode}');
    debugPrint('selected moodLabel: ${option.moodLabel}');
    debugPrint('moodCategory: ${option.moodCategory}');
    debugPrint('entityType: staff');
    debugPrint('source: manual');
    debugPrint('checkInAt: $checkInAt');
    setState(() {
      _saving = true;
      _savingMoodCode = option.moodCode;
      _latestMoodCode = option.moodCode;
    });
    try {
      debugPrint(
        'Saving inline staff wellbeing check-in with entityId: $entityId',
      );
      await service.createMoodCheckin(
        entityType: 'staff',
        entityId: entityId,
        entityName: entityName,
        moodCode: option.moodCode,
        moodLabel: option.moodLabel,
        moodCategory: option.moodCategory,
        intensity: 3,
        notes: '',
        source: 'manual',
        photoUrl: null,
        checkInAt: checkInAt,
        createdBy: createdBy,
      );
      await _loadHistory();
      await widget.onSaved();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Wellbeing check-in saved')),
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 350));
      if (mounted) {
        setState(() {
          _latestMoodCode = null;
        });
      }
    } catch (e, stackTrace) {
      debugPrint('Could not save inline staff wellbeing check-in: $e');
      debugPrint('Stack trace: $stackTrace');
      if (e is FirebaseException &&
          e.code.toLowerCase() == 'permission-denied') {
        debugPrint(
          'Mood check-in save failed due to Firestore permission/rules',
        );
      }
      if (mounted) {
        setState(() {
          _latestMoodCode = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not save check-in. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
          _savingMoodCode = null;
        });
      }
    }
  }

  String _getCurrentStaffEntityId(dynamic currentUser) {
    final appUserId = currentUser.id.toString().trim();
    if (appUserId.isNotEmpty) return appUserId;
    final authUid = FirebaseAuth.instance.currentUser?.uid.trim();
    if (authUid != null && authUid.isNotEmpty) return authUid;
    final phone = currentUser.phone.toString().trim();
    if (phone.isNotEmpty) return phone;
    return 'staff';
  }

  String? _latestLabelAndTime(BuildContext context) {
    if (_todayHistory.isEmpty) return null;
    final latest = _todayHistory.first;
    final time = latest.checkInAt;
    if (time == null) return latest.moodLabel;
    return '${latest.moodLabel} · ${TimeOfDay.fromDateTime(time).format(context)}';
  }

  @override
  Widget build(BuildContext context) {
    final latestLine = _latestLabelAndTime(context);
    final inlineOptions = staffMoodOptions
        .where((option) => option.moodCode != 'not_observed')
        .toList();
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.self_improvement_outlined,
                      color: Colors.green.shade700,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'How are you feeling now?',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Take a quick wellbeing check-in for yourself.',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (latestLine != null) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'Latest: $latestLine',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final option in inlineOptions)
                    _InlineMoodChip(
                      option: option,
                      selected: _latestMoodCode == option.moodCode,
                      saving: _savingMoodCode == option.moodCode,
                      disabled: _saving,
                      onTap: () => _saveMood(option),
                    ),
                ],
              ),
              if (_saving) ...[
                const SizedBox(height: 10),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Saving check-in...',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              Text(
                'Today\'s check-ins',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 10),
              if (_todayHistory.isEmpty)
                Text(
                  'No check-ins yet today.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
                )
              else
                _ExpandableHistoryList(items: _todayHistory, showCount: 3),
            ],
          ),
        ),
      ),
    );
  }
}

class _TodayHistoryItem extends StatelessWidget {
  const _TodayHistoryItem({required this.item});

  final MoodCheckinModel item;

  @override
  Widget build(BuildContext context) {
    final time = item.checkInAt;
    final timeLabel = time == null
        ? '-'
        : TimeOfDay.fromDateTime(time).format(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$timeLabel · ${item.moodLabel}',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _ExpandableHistoryList extends StatefulWidget {
  const _ExpandableHistoryList({required this.items, required this.showCount});

  final List<MoodCheckinModel> items;
  final int showCount;

  @override
  State<_ExpandableHistoryList> createState() => _ExpandableHistoryListState();
}

class _ExpandableHistoryListState extends State<_ExpandableHistoryList> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final visibleItems = _expanded || widget.items.length <= widget.showCount
        ? widget.items
        : widget.items.take(widget.showCount).toList();
    final hasMore = widget.items.length > widget.showCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          child: Column(
            children: [
              for (final item in visibleItems)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _TodayHistoryItem(item: item),
                ),
            ],
          ),
        ),
        if (hasMore)
          TextButton.icon(
            onPressed: () => setState(() => _expanded = !_expanded),
            icon: Icon(
              _expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
            ),
            label: Text(_expanded ? 'Show less' : 'Show more'),
          ),
      ],
    );
  }
}

class _InlineMoodChip extends StatelessWidget {
  const _InlineMoodChip({
    required this.option,
    required this.selected,
    required this.saving,
    required this.disabled,
    required this.onTap,
  });

  final MoodOptionModel option;
  final bool selected;
  final bool saving;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: disabled && !saving ? 0.75 : 1,
      child: Stack(
        alignment: Alignment.center,
        children: [
          MoodOptionChip(
            option: option,
            selected: selected || saving,
            onTap: disabled ? () {} : onTap,
          ),
          if (saving)
            Positioned(
              right: 8,
              top: 8,
              child: SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.8,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.metric});

  final _DashboardMetric metric;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                metric.icon,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    metric.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    metric.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
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
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade600,
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

class _RecentMoodCard extends StatelessWidget {
  const _RecentMoodCard({required this.item});

  final MoodCheckinModel item;

  @override
  Widget build(BuildContext context) {
    final time = item.checkInAt;
    final timeLabel = time == null
        ? '-'
        : TimeOfDay.fromDateTime(time).format(context);
    final isStaff = item.entityType == 'staff';
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.entityName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${isStaff ? 'Staff' : 'Student'} • ${item.moodLabel} • Intensity ${item.intensity}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(timeLabel, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            if ((item.notes ?? '').trim().isNotEmpty)
              Icon(Icons.sticky_note_2_outlined, color: Colors.grey.shade600),
          ],
        ),
      ),
    );
  }
}

class _ExpandableRecentMoodList extends StatefulWidget {
  const _ExpandableRecentMoodList({
    required this.items,
    required this.showCount,
  });

  final List<MoodCheckinModel> items;
  final int showCount;

  @override
  State<_ExpandableRecentMoodList> createState() =>
      _ExpandableRecentMoodListState();
}

class _ExpandableRecentMoodListState extends State<_ExpandableRecentMoodList> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final visibleItems = _expanded || widget.items.length <= widget.showCount
        ? widget.items
        : widget.items.take(widget.showCount).toList();
    final hasMore = widget.items.length > widget.showCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          child: Column(
            children: [
              for (final item in visibleItems)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _RecentMoodCard(item: item),
                ),
            ],
          ),
        ),
        if (hasMore)
          TextButton.icon(
            onPressed: () => setState(() => _expanded = !_expanded),
            icon: Icon(
              _expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
            ),
            label: Text(_expanded ? 'Show less' : 'Show more'),
          ),
      ],
    );
  }
}
