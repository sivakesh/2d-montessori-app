import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/layout/bottom_nav.dart';
import '../../../core/layout/responsive_layout.dart';
import '../../../core/layout/sidebar.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_sizes.dart';
import '../../admin/settings/models/academic_year_matching.dart';
import '../../admin/settings/models/school_settings_model.dart' show kDefaultSchoolId;
import '../../admin/settings/providers/academic_year_provider.dart';
import '../../admin/students/models/admin_student_model.dart';
import '../../calendar/ui/calendar_view.dart';
import '../../admin/notifications/data/admin_notification_service.dart';
import '../../admin/notifications/models/admin_notification_model.dart';
import '../../attendance/data/attendance_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../../classes/data/class_service.dart';
import '../../fees/models/student_fee_assignment_model.dart';
import '../../fees/services/fee_service.dart';
import '../../fees/ui/parent_fee_history_view.dart';
import '../../finance/widgets/finance_status_chip.dart';
import '../../leave/models/leave_request_model.dart';
import '../../leave/services/leave_service.dart';
import '../../leave/ui/dialogs/student_leave_request_dialog.dart';
import '../../leave/ui/parent_leave_view.dart';
import '../../leave/ui/widgets/student_leave_card.dart';
import '../../mood_checkin/models/mood_checkin_model.dart';
import '../../mood_checkin/models/mood_option_model.dart';
import '../../mood_checkin/services/mood_checkin_service.dart';
import '../../mood_checkin/widgets/mood_option_chip.dart';
import '../../notifications/ui/notification_relevance.dart';
import '../../notifications/ui/notifications_feed_screen.dart';
import '../data/parent_service.dart';
import 'parent_attendance_history_view.dart';
import 'parent_child_profile_view.dart';
import 'parent_notifications_screen.dart';

/// Parent MVP home screen — read-only. Answers "what's happening with my
/// child, and what does the school need me to know?" using only existing
/// collections/services (ParentService, AttendanceService, FeeService,
/// AdminNotificationService); no parent-specific Firestore data is written
/// or duplicated here beyond what those services already own.
class ParentDashboard extends ConsumerStatefulWidget {
  const ParentDashboard({
    super.key,
    this.parentService,
    this.attendanceService,
    this.feeService,
    this.notificationService,
    this.classService,
    this.moodCheckinService,
    this.leaveService,
  });

  /// Overridable only so tests can inject fake-Firestore-backed services —
  /// the same DI seam every service here already exposes on its own
  /// constructor. Production callers never pass these.
  final ParentService? parentService;
  final AttendanceService? attendanceService;
  final FeeService? feeService;
  final AdminNotificationService? notificationService;
  final ClassService? classService;
  final MoodCheckinService? moodCheckinService;
  final LeaveService? leaveService;

  @override
  ConsumerState<ParentDashboard> createState() => _ParentDashboardState();
}

class _ParentDashboardState extends ConsumerState<ParentDashboard> {
  // Index into the `tabs` list built in `build` — AppSidebar/AppBottomNav
  // are role-aware and offer exactly [Dashboard, Calendar, Leave, Fees] for
  // role == 'parent', in that order.
  int selectedIndex = 0;

  late final _parentService = widget.parentService ?? ParentService();
  late final _attendanceService =
      widget.attendanceService ?? AttendanceService();
  late final _feeService = widget.feeService ?? FeeService();
  late final _notificationService =
      widget.notificationService ?? AdminNotificationService();
  late final _classService = widget.classService ?? ClassService();
  late final _moodCheckinService =
      widget.moodCheckinService ?? MoodCheckinService();
  late final _leaveService = widget.leaveService ?? LeaveService();

  bool _loading = true;
  List<AdminStudentModel> _children = const [];
  Map<String, String> _classNames = const {};
  Map<String, String> _classAcademicYears = const {};
  String _selectedChildId = '';
  Map<String, dynamic>? _todayAttendance;
  List<StudentFeeAssignmentModel> _feeAssignments = const [];
  bool _loadingChildDetail = false;

  /// The Published, `audience == 'Parents'` notifications for this parent's
  /// account, straight from [AdminNotificationService.
  /// getNotificationsForAudience] — deliberately NOT pre-filtered by any
  /// child here. Which of these are relevant is re-derived per the
  /// *currently selected* child at build time (see `build`'s
  /// `notificationsForSelectedChild`), not fixed once at load time — a
  /// notification targeted to one linked child must disappear from the
  /// Dashboard preview the moment a different child is selected, even
  /// though both children belong to the same parent account.
  List<AdminNotificationModel> _parentNotifications = const [];
  bool _notificationsError = false;

  /// Every linked child's leave history, resolved server-side by
  /// LeaveService.getStudentRequestsForParent (never trusts a client-
  /// supplied student id) — filtered down to the *currently selected*
  /// child at build time, the same "fetch once for the account, filter per
  /// selected child at build" shape `_parentNotifications` already uses.
  List<LeaveRequestModel> _studentLeaveRequests = const [];
  bool _leaveRequestsError = false;

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  Future<void> _loadDashboard() async {
    setState(() => _loading = true);
    final user = ref.read(currentUserProvider);
    final userId = user?.id ?? '';

    final children = await _parentService.getLinkedStudents(userId);
    final classes = await _classService.getClasses();
    final classNames = <String, String>{
      for (final doc in classes) doc.id: doc.data()['name']?.toString() ?? '-',
    };
    // AY-IMPLEMENT-02-B: resolved through the canonical `academicYearId`
    // when a Class has one — via the same shared AcademicYearService every
    // other Academic-Year-aware screen already reads — falling back to the
    // legacy `academicYear` string for a Class that hasn't been migrated
    // yet. Fetched once for the whole dashboard load, not per child/class.
    // Defensive the same way notifications/leave requests below already
    // are: a transient failure here only degrades the displayed academic
    // year back to each Class's own legacy string — it never blocks the
    // rest of the dashboard from loading.
    var academicYearNamesById = const <String, String>{};
    try {
      final academicYearService = ref.read(academicYearServiceProvider);
      final academicYears = await academicYearService.getAllAcademicYears(schoolId: kDefaultSchoolId);
      academicYearNamesById = {for (final year in academicYears) year.id: year.name};
    } catch (_) {
      // academicYearNamesById stays empty — resolveClassAcademicYearLabel
      // falls back to each Class's own academicYear string.
    }
    final classAcademicYears = <String, String>{
      for (final doc in classes)
        doc.id: resolveClassAcademicYearLabel(
          academicYearId: doc.data()['academicYearId']?.toString() ?? '',
          academicYear: doc.data()['academicYear']?.toString() ?? '',
          academicYearNamesById: academicYearNamesById,
        ),
    };

    // Notifications are fetched separately from children/attendance/fees so
    // a transient failure here (e.g. a network blip) only degrades the
    // Notifications card — it never blocks the rest of the dashboard from
    // loading, and never leaves the user stuck on an infinite spinner.
    // Not filtered by any child here — see `_parentNotifications`'s doc
    // comment for why that has to happen per selected child at build time
    // instead.
    List<AdminNotificationModel> parentNotifications = const [];
    var notificationsError = false;
    try {
      parentNotifications = await _notificationService
          .getNotificationsForAudience('Parents');
    } catch (_) {
      notificationsError = true;
    }

    // Fetched the same defensive way as notifications above — a transient
    // failure here only degrades the Student Leave section, never blocks
    // the rest of the dashboard.
    List<LeaveRequestModel> studentLeaveRequests = const [];
    var leaveRequestsError = false;
    try {
      studentLeaveRequests =
          await _leaveService.getStudentRequestsForParent(userId);
    } catch (_) {
      leaveRequestsError = true;
    }

    if (!mounted) return;
    setState(() {
      _children = children;
      _classNames = classNames;
      _classAcademicYears = classAcademicYears;
      _parentNotifications = parentNotifications;
      _notificationsError = notificationsError;
      _studentLeaveRequests = studentLeaveRequests;
      _leaveRequestsError = leaveRequestsError;
      _selectedChildId = children.isNotEmpty ? children.first.id : '';
      _loading = false;
    });

    if (_selectedChildId.isNotEmpty) {
      await _loadChildDetail(_selectedChildId);
    }
  }

  Future<void> _loadChildDetail(String studentId) async {
    setState(() => _loadingChildDetail = true);
    final attendance = await _attendanceService.getAttendanceForEntity(
      entityType: 'student',
      entityId: studentId,
    );
    final assignments = await _feeService.getAssignmentsForStudent(studentId);
    if (!mounted) return;
    setState(() {
      _todayAttendance = attendance;
      _feeAssignments = assignments;
      _loadingChildDetail = false;
    });
  }

  void _selectChild(String studentId) {
    if (studentId == _selectedChildId) return;
    setState(() => _selectedChildId = studentId);
    _loadChildDetail(studentId);
  }

  Future<void> _openRequestLeave() async {
    final user = ref.read(currentUserProvider);
    if (user == null || _children.isEmpty) return;
    final submitted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => StudentLeaveRequestDialog(
        requesterId: user.id,
        requesterName: user.name?.isNotEmpty == true ? user.name! : user.phone,
        requesterRole: LeaveRequesterRole.parent,
        linkedStudents: _children,
        service: _leaveService,
      ),
    );
    if (submitted == true) {
      await _loadDashboard();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Leave request submitted')),
        );
      }
    }
  }

  void _openAllNotifications() {
    final childStudentIds = _children.map((c) => c.id).toSet();
    final childClassIds = _children
        .map((c) => c.classId)
        .where((id) => id.isNotEmpty)
        .toSet();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ParentNotificationsScreen(
          childStudentIds: childStudentIds,
          childClassIds: childClassIds,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final isMobile =
        MediaQuery.of(context).size.width < AppSizes.mobileBreakpoint;

    final selectedChild = _children.isEmpty
        ? null
        : _children.firstWhere(
            (c) => c.id == _selectedChildId,
            orElse: () => _children.first,
          );

    // Scoped to a singleton set of exactly the *selected* child's own
    // studentId/classId — not the union across every linked child — so a
    // notification targeted to one child (selected-student or class
    // targeting) never bleeds into another child's dashboard context, even
    // though isNotificationRelevantToParent itself is unchanged: it already
    // correctly answers "is this notification relevant to this set of
    // ids", the bug was in which ids the Dashboard preview used to ask it.
    final notificationsForSelectedChild = selectedChild == null
        ? const <AdminNotificationModel>[]
        : _parentNotifications
              .where(
                (n) => isNotificationRelevantToParent(
                  n,
                  childStudentIds: {selectedChild.id},
                  childClassIds: selectedChild.classId.isEmpty
                      ? const {}
                      : {selectedChild.classId},
                ),
              )
              .take(3)
              .toList();

    final dashboardContent = _loading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _loadDashboard,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                isMobile ? 20 : 32,
                24,
                isMobile ? 20 : 32,
                40,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _WelcomeCard(parentName: user?.name ?? ''),
                  const SizedBox(height: 20),
                  // Belongs to the authenticated parent account, not to
                  // whichever child happens to be selected — deliberately
                  // placed outside the `if (_children.isEmpty) ... else`
                  // block below (so it renders even with zero linked
                  // children) and built as a fully self-contained widget
                  // that never reads `_selectedChildId`, so switching the
                  // selected child structurally cannot affect it.
                  _ParentMoodSection(
                    parentUserId: user?.id ?? '',
                    parentName: user?.name ?? '',
                    moodCheckinService: _moodCheckinService,
                  ),
                  const SizedBox(height: 20),
                  if (_children.isEmpty)
                    const _NoChildrenLinkedCard()
                  else ...[
                    if (_children.length > 1) ...[
                      _ChildSelector(
                        children: _children,
                        selectedId: _selectedChildId,
                        onSelected: _selectChild,
                      ),
                      const SizedBox(height: 12),
                    ],
                    Builder(
                      builder: (context) {
                        final className =
                            _classNames[selectedChild!.classId] ?? '-';
                        final academicYear =
                            _classAcademicYears[selectedChild.classId] ?? '';
                        return _ChildCard(
                          child: selectedChild,
                          className: className,
                          loading: _loadingChildDetail,
                          attendance: _todayAttendance,
                          onViewProfile: () => showChildProfile(
                            context,
                            child: selectedChild,
                            className: className,
                            academicYear: academicYear,
                          ),
                          onViewHistory: () => showChildAttendanceHistory(
                            context,
                            studentId: selectedChild.id,
                            studentName: selectedChild.name,
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 20),
                    _FeeSummarySection(
                      loading: _loadingChildDetail,
                      assignments: _feeAssignments,
                    ),
                    const SizedBox(height: 20),
                    _StudentLeaveSection(
                      loading: _loading,
                      hasError: _leaveRequestsError,
                      requests: _studentLeaveRequests
                          .where((r) => r.studentId == selectedChild!.id)
                          .toList(),
                      onRequestLeave: _openRequestLeave,
                      onRetry: _loadDashboard,
                    ),
                  ],
                  const SizedBox(height: 20),
                  _NotificationsSection(
                    notifications: notificationsForSelectedChild,
                    hasError: _notificationsError,
                    onViewAll: _openAllNotifications,
                    onRetry: _loadDashboard,
                  ),
                ],
              ),
            ),
          );

    // AppSidebar/AppBottomNav's destination order for role 'parent' is
    // [Dashboard, Calendar, Leave, Fees] on both desktop and mobile — this
    // single tabs list (same pattern as DashboardScreen's) is the one source
    // of truth for title/body per index, so sidebar/bottom-nav selection,
    // page title, and body content can never drift out of sync the way the
    // old duplicated-switch Staff nav once did.
    final tabs = [
      (title: 'Dashboard', body: () => dashboardContent),
      (title: 'Calendar', body: () => const CalendarView()),
      (
        title: 'Leave',
        body: () => ParentLeaveView(
          leaveService: _leaveService,
          parentService: _parentService,
        ),
      ),
      (
        title: 'Fees',
        body: () => ParentFeeHistoryView(
          feeService: _feeService,
          parentService: _parentService,
        ),
      ),
    ];
    final safeIndex = selectedIndex >= 0 && selectedIndex < tabs.length ? selectedIndex : 0;
    final currentTitle = tabs[safeIndex].title;
    final currentBody = tabs[safeIndex].body();

    Widget logoutAction() => IconButton(
      icon: const Icon(Icons.logout),
      onPressed: () async {
        await ref.read(authServiceProvider).logout(ref, context);
        if (context.mounted) {
          Navigator.of(
            context,
          ).pushNamedAndRemoveUntil('/login', (route) => false);
        }
      },
    );

    // Mirrors DashboardScreen's shell exactly: same ResponsiveLayout,
    // AppSidebar/AppBottomNav (already role-aware and Dashboard-only for
    // 'parent'), background, and AppBar structure — only the body content
    // differs, so switching from Staff to Parent feels like the same
    // application with different navigation/content, not a separate app.
    return ResponsiveLayout(
      mobile: Scaffold(
        backgroundColor: Colors.grey[50],
        appBar: AppBar(
          centerTitle: false,
          title: Text(currentTitle),
          actions: [logoutAction()],
        ),
        body: SafeArea(child: currentBody),
        bottomNavigationBar: AppBottomNav(
          selectedIndex: selectedIndex,
          onItemTapped: (index) => setState(() => selectedIndex = index),
        ),
      ),
      web: Scaffold(
        backgroundColor: Colors.grey[50],
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
                    actions: [logoutAction()],
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

class _WelcomeCard extends StatelessWidget {
  const _WelcomeCard({required this.parentName});

  final String parentName;

  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 17
        ? 'Good afternoon'
        : 'Good evening';
    final name = parentName.trim().isNotEmpty ? parentName.trim() : 'there';
    return Card(
      elevation: 0,
      color: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$greeting, $name',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              "Here's what's happening with your child today.",
              style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoChildrenLinkedCard extends StatelessWidget {
  const _NoChildrenLinkedCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: const Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(
              Icons.family_restroom_outlined,
              size: 36,
              color: AppColors.textSecondary,
            ),
            SizedBox(height: 12),
            Text(
              'No children linked to your account yet.',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 6),
            Text(
              "Ask the school office to link your child's profile to this account.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChildSelector extends StatelessWidget {
  const _ChildSelector({
    required this.children,
    required this.selectedId,
    required this.onSelected,
  });

  final List<AdminStudentModel> children;
  final String selectedId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final child in children)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(child.name),
                selected: child.id == selectedId,
                onSelected: (_) => onSelected(child.id),
              ),
            ),
        ],
      ),
    );
  }
}

class _ChildCard extends StatelessWidget {
  const _ChildCard({
    required this.child,
    required this.className,
    required this.loading,
    required this.attendance,
    required this.onViewProfile,
    required this.onViewHistory,
  });

  final AdminStudentModel child;
  final String className;
  final bool loading;
  final Map<String, dynamic>? attendance;
  final VoidCallback onViewProfile;
  final VoidCallback onViewHistory;

  @override
  Widget build(BuildContext context) {
    final status = attendance?['status']?.toString();
    final checkInTime = _formatCheckInTime(attendance?['updatedAt']);

    return Card(
      elevation: 0,
      color: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                  backgroundImage: child.profileImageUrl.isNotEmpty
                      ? NetworkImage(child.profileImageUrl)
                      : null,
                  child: child.profileImageUrl.isEmpty
                      ? Text(
                          child.name.isNotEmpty
                              ? child.name[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        child.name,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        className,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      FinanceStatusChip(
                        label: child.isActive ? 'Active' : 'Inactive',
                        color: child.isActive
                            ? AppColors.secondary
                            : Colors.grey,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 28),
            const Text(
              "Today's Attendance",
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            if (loading)
              const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Row(
                children: [
                  _AttendanceStatusChip(status: status),
                  if (checkInTime != null) ...[
                    const SizedBox(width: 10),
                    Text(
                      'at $checkInTime',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            const Divider(height: 28),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onViewProfile,
                    icon: const Icon(Icons.person_outline, size: 18),
                    label: const Text(
                      'Profile',
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onViewHistory,
                    icon: const Icon(Icons.event_note_outlined, size: 18),
                    label: const Text(
                      'History',
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String? _formatCheckInTime(dynamic value) {
    final time = value is Timestamp
        ? value.toDate()
        : value is DateTime
        ? value
        : null;
    if (time == null) return null;
    final local = time.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final period = local.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }
}

class _AttendanceStatusChip extends StatelessWidget {
  const _AttendanceStatusChip({required this.status});

  final String? status;

  @override
  Widget build(BuildContext context) {
    final normalized = (status ?? '').toLowerCase();
    final (label, color) = switch (normalized) {
      'present' => ('Present', AppColors.secondary),
      'absent' => ('Absent', Colors.redAccent),
      _ => ('Not marked yet', Colors.grey),
    };
    return FinanceStatusChip(label: label, color: color);
  }
}

/// Parent self-check-in — reuses the existing generic mood architecture
/// (`MoodCheckinModel`/`MoodCheckinService`/`MoodOptionModel`/
/// `MoodOptionChip`) exactly the way Child and Staff mood check-in already
/// do, via `entityType: 'parent'` and `entityId: <the authenticated
/// parent's own AppUser.id>` — the same identity ParentDashboard already
/// uses everywhere else (`ParentService.getLinkedStudents(userId)`), not a
/// new identifier. No new model, service, or Firestore collection.
///
/// Reuses `staffMoodOptions` (minus 'not_observed', which is an observer-
/// only option) rather than `studentMoodOptions`, since a parent
/// self-reporting their own feelings is the same "how am I doing" register
/// Staff wellbeing check-in already uses — not a third, invented mood
/// vocabulary.
///
/// Deliberately self-contained (loads/saves its own state, independent of
/// ParentDashboard's `_selectedChildId`) so the parent's mood can never be
/// tied to — or change with — whichever child is currently selected; it
/// mirrors dashboard_screen.dart's `_PersonalWellbeingCard` (the existing
/// Staff self-check-in), adapted to ParentDashboard's own card styling
/// (AppColors, not the admin shell's raw Material colors) and without that
/// screen's optional-photo-upload step, which the compact Parent surface
/// this task asks for doesn't need.
class _ParentMoodSection extends StatefulWidget {
  const _ParentMoodSection({
    required this.parentUserId,
    required this.parentName,
    required this.moodCheckinService,
  });

  final String parentUserId;
  final String parentName;
  final MoodCheckinService moodCheckinService;

  @override
  State<_ParentMoodSection> createState() => _ParentMoodSectionState();
}

class _ParentMoodSectionState extends State<_ParentMoodSection> {
  bool _loading = true;
  bool _loadError = false;
  bool _saving = false;
  String? _savingMoodCode;
  MoodCheckinModel? _todayMood;

  static final _options =
      staffMoodOptions.where((o) => o.moodCode != 'not_observed').toList();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.parentUserId.isEmpty) {
      setState(() {
        _loading = false;
        _loadError = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _loadError = false;
    });
    try {
      final latest = await widget.moodCheckinService.getLatestMoodForEntity(
        'parent',
        widget.parentUserId,
      );
      if (!mounted) return;
      setState(() {
        _todayMood = latest;
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

  Future<void> _saveMood(MoodOptionModel option) async {
    if (_saving || widget.parentUserId.isEmpty) return;
    // Preserved so a failed save can restore exactly what was showing
    // before this attempt, instead of leaving a stale/incorrect selection.
    final previousMood = _todayMood;
    setState(() {
      _saving = true;
      _savingMoodCode = option.moodCode;
    });
    try {
      await widget.moodCheckinService.createMoodCheckin(
        entityType: 'parent',
        entityId: widget.parentUserId,
        entityName: widget.parentName.isNotEmpty ? widget.parentName : 'Parent',
        moodCode: option.moodCode,
        moodLabel: option.moodLabel,
        moodCategory: option.moodCategory,
        intensity: 3,
        source: 'manual',
        createdBy: widget.parentUserId,
      );
      final refreshed = await widget.moodCheckinService.getLatestMoodForEntity(
        'parent',
        widget.parentUserId,
      );
      if (!mounted) return;
      setState(() => _todayMood = refreshed);
    } catch (_) {
      if (!mounted) return;
      setState(() => _todayMood = previousMood);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not save your mood. Please try again.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
          _savingMoodCode = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    'How are you feeling today?',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                if (_todayMood != null)
                  FinanceStatusChip(
                    label: _todayMood!.moodLabel,
                    color: AppColors.secondary,
                  ),
              ],
            ),
            const SizedBox(height: 14),
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (_loadError)
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      "Couldn't load your mood.",
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                  TextButton(onPressed: _load, child: const Text('Retry')),
                ],
              )
            else ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final option in _options)
                    Opacity(
                      opacity: _saving && _savingMoodCode != option.moodCode
                          ? 0.5
                          : 1,
                      child: MoodOptionChip(
                        option: option,
                        selected: _todayMood?.moodCode == option.moodCode,
                        onTap: () => _saveMood(option),
                      ),
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
                      'Saving...',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// New, self-contained card — additive only, doesn't touch _ChildCard or
/// any other existing widget. Shows the *currently selected* child's leave
/// history (via LeaveService.getStudentRequestsForParent, already scoped
/// server-side to this parent's linked children) and a "Request Leave"
/// button that opens StudentLeaveRequestDialog pre-populated with every
/// linked child to choose from.
class _StudentLeaveSection extends StatelessWidget {
  const _StudentLeaveSection({
    required this.loading,
    required this.hasError,
    required this.requests,
    required this.onRequestLeave,
    required this.onRetry,
  });

  final bool loading;
  final bool hasError;
  final List<LeaveRequestModel> requests;
  final VoidCallback onRequestLeave;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Leave Requests',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: onRequestLeave,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Request Leave'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (hasError)
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      "Couldn't load leave requests.",
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                  TextButton(onPressed: onRetry, child: const Text('Retry')),
                ],
              )
            else if (requests.isEmpty)
              const Text(
                'No leave requests for this child yet.',
                style: TextStyle(color: AppColors.textSecondary),
              )
            else
              for (final request in requests) ...[
                StudentLeaveCard(request: request),
                const SizedBox(height: 10),
              ],
          ],
        ),
      ),
    );
  }
}

class _FeeSummarySection extends StatelessWidget {
  const _FeeSummarySection({required this.loading, required this.assignments});

  final bool loading;
  final List<StudentFeeAssignmentModel> assignments;

  @override
  Widget build(BuildContext context) {
    final outstanding = assignments.fold<double>(
      0,
      (total, a) => total + a.balanceAmount,
    );

    return Card(
      elevation: 0,
      color: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Fees',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            if (loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (assignments.isEmpty)
              const Text(
                'No fee assignments yet.',
                style: TextStyle(color: AppColors.textSecondary),
              )
            else ...[
              for (final assignment in assignments) ...[
                _FeeAssignmentRow(assignment: assignment),
                const SizedBox(height: 10),
              ],
              const Divider(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Total Outstanding',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    '₹${outstanding.toStringAsFixed(0)}',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: outstanding > 0
                          ? Colors.redAccent
                          : AppColors.secondary,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FeeAssignmentRow extends StatelessWidget {
  const _FeeAssignmentRow({required this.assignment});

  final StudentFeeAssignmentModel assignment;

  @override
  Widget build(BuildContext context) {
    final isPaid = assignment.balanceAmount <= 0;
    final isPartial = !isPaid && assignment.paidAmount > 0;
    final (label, color) = isPaid
        ? ('Paid', AppColors.secondary)
        : isPartial
        ? ('Partially Paid', Colors.orange)
        : ('Pending', Colors.redAccent);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  assignment.feeStructureName.isNotEmpty
                      ? assignment.feeStructureName
                      : 'Fee',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
              ),
              const SizedBox(width: 8),
              FinanceStatusChip(label: label, color: color),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _FeeAmountColumn(
                label: 'Total',
                amount: assignment.payableAmount,
              ),
              _FeeAmountColumn(label: 'Paid', amount: assignment.paidAmount),
              _FeeAmountColumn(
                label: 'Due',
                amount: assignment.balanceAmount,
                emphasize: assignment.balanceAmount > 0,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One Total/Paid/Due column within a fee card. A plain [Row] of three
/// [Expanded] columns rather than a fixed-width table — reads as a compact
/// row on desktop and stays comfortably within a 390px card on mobile,
/// without a separate breakpoint-specific layout.
class _FeeAmountColumn extends StatelessWidget {
  const _FeeAmountColumn({
    required this.label,
    required this.amount,
    this.emphasize = false,
  });

  final String label;
  final double amount;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '₹${amount.toStringAsFixed(0)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: emphasize ? Colors.redAccent : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationsSection extends StatelessWidget {
  const _NotificationsSection({
    required this.notifications,
    required this.hasError,
    required this.onViewAll,
    required this.onRetry,
  });

  final List<AdminNotificationModel> notifications;
  final bool hasError;
  final VoidCallback onViewAll;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Notifications',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                TextButton(
                  onPressed: onViewAll,
                  child: const Text('View All'),
                ),
              ],
            ),
            if (hasError)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        "Couldn't load notifications.",
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    ),
                    TextButton(onPressed: onRetry, child: const Text('Retry')),
                  ],
                ),
              )
            else if (notifications.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'No notifications yet.',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              )
            else
              for (final notification in notifications) ...[
                _NotificationPreviewRow(notification: notification),
                const SizedBox(height: 10),
              ],
          ],
        ),
      ),
    );
  }
}

class _NotificationPreviewRow extends StatelessWidget {
  const _NotificationPreviewRow({required this.notification});

  final AdminNotificationModel notification;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.background,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => showNotificationDetail(context, notification),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                notification.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                notification.category,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                notification.message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
