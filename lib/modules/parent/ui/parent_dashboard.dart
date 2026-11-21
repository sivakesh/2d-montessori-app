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
import '../../calendar/models/calendar_event_model.dart';
import '../../calendar/services/calendar_service.dart';
import '../../calendar/ui/calendar_event_detail_dialog.dart';
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
import '../data/parent_access.dart' show parentFeesRestrictedMessage;
import '../data/parent_family_overview.dart';
import '../data/parent_file_service.dart';
import '../data/parent_service.dart';
import 'parent_attendance_history_view.dart';
import 'parent_app_bar.dart';
import 'parent_child_avatar.dart';
import 'parent_child_profile_view.dart';
import 'parent_family_overview.dart';
import 'parent_notifications_screen.dart';

/// Parent home screen — read-only. With several linked children it opens on
/// the family overview (every child's card, family summary, notices and
/// upcoming events) and each card opens that child's own dashboard; with
/// one child it is a single page for that child. Everything shown comes from
/// existing services and the parent-safe copies (ParentService,
/// ParentFamilyOverviewLoader, AdminNotificationService, LeaveService,
/// CalendarService); nothing is written here. Access checks are in the app;
/// server-side enforcement depends on the security rules
/// (docs/parent_access_security.md).
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
    this.calendarService,
    this.fileSaver,
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
  final CalendarService? calendarService;

  /// Where downloaded files go; tests only (production: the browser
  /// download / share sheet, ParentFileService's default).
  final ParentFileSaver? fileSaver;

  @override
  ConsumerState<ParentDashboard> createState() => _ParentDashboardState();
}

class _ParentDashboardState extends ConsumerState<ParentDashboard> {
  // Index into the `tabs` list built in `build` — AppSidebar/AppBottomNav
  // are role-aware and offer exactly [Dashboard, Calendar, Leave, Fees] for
  // role == 'parent', in that order.
  int selectedIndex = 0;
  static const _calendarTab = 1, _feesTab = 3;

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

  /// Protected downloads (photos, documents, bills) for the signed-in
  /// parent, created only once their access record is in use (the
  /// parent-safe copies); before that, nothing is downloaded through it.
  ParentFileService? _fileService;

  bool _loading = true;
  List<LinkedChild> _linked = const [];
  List<AdminStudentModel> _children = const [];
  Map<String, String> _classNames = const {};
  Map<String, String> _classAcademicYears = const {};

  /// Linked children whose profile couldn't be shown (ParentFamily).
  int _unavailableChildren = 0;

  /// The children (or the classes) couldn't be read: the dashboard can't tell
  /// whether any are linked, so it says so with Retry — never "no children".
  bool _familyError = false;

  /// The child whose own dashboard is shown (or, on the family overview,
  /// the one last opened). Kept across tabs and refreshes while linked.
  String _selectedChildId = '';

  /// A family (several children) is looking at one child's dashboard
  /// rather than the family overview.
  bool _showingChild = false;

  /// studentId → that child's overview (attendance, fees, payments, bills),
  /// loaded once per dashboard load, one child at a time; a child missing
  /// here is still loading.
  Map<String, ParentChildOverview> _overviews = const {};
  int _loadGeneration = 0;
  DateTime? _updatedAt;

  /// studentId → the linked child (photo path, documents, guardians from the
  /// parent-safe profile).
  Map<String, LinkedChild> _linkedById = const {};

  /// The Published, `audience == 'Parents'` notifications for this parent's
  /// account, straight from [AdminNotificationService.
  /// getNotificationsForParent] — deliberately NOT pre-filtered by any
  /// child here. Which of these are relevant is re-derived at build time:
  /// for the family overview against all the children, for one child's
  /// dashboard against exactly that child — a notification targeted to one
  /// linked child must disappear from another child's dashboard, even
  /// though both children belong to the same parent account.
  List<AdminNotificationModel> _parentNotifications = const [];
  bool _notificationsError = false;

  /// A parent account whose lookup succeeded and found no linked child:
  /// it has no notification access — none are fetched, shown or opened.
  /// Never set while loading or after a failed lookup.
  bool _unlinkedParent = false;

  /// Every linked child's leave history, resolved server-side by
  /// LeaveService.getStudentRequestsForParent (never trusts a client-
  /// supplied student id) — filtered down to one child at build time.
  List<LeaveRequestModel> _studentLeaveRequests = const [];
  bool _leaveRequestsError = false;

  /// Published Parents/Public calendar items (CalendarService).
  List<CalendarEventModel> _events = const [];
  bool _eventsLoading = true;
  bool _eventsError = false;

  /// The dashboard page's scroll position: back to the top when switching
  /// between the family overview and a child's dashboard, so each opens at
  /// its start (selector and Family overview button in view).
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToTop() {
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _loadDashboard() async {
    setState(() {
      _loading = true;
      _familyError = false;
      _unlinkedParent = false;
    });
    final user = ref.read(currentUserProvider);
    final userId = user?.id ?? '';
    // No session user yet (it is still being set): which children are
    // linked can't be known, so the dashboard keeps loading and loads once
    // the user is set (see build), rather than showing "no children".
    if (userId.isEmpty) return;

    final ParentFamily family;
    final List<QueryDocumentSnapshot<Map<String, dynamic>>> classes;
    try {
      family = await _parentService.getFamily(userId);
      classes = await _classService.getClasses();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _linked = const [];
        _children = const [];
        _unavailableChildren = 0;
        _familyError = true;
        _loading = false;
      });
      return;
    }
    final linkedChildren = family.children;
    final children = [for (final c in linkedChildren) c.student];
    final unlinkedParent = (user?.role ?? '').toLowerCase() == 'parent' && linkedChildren.isEmpty && family.unavailable == 0;
    final linkedById = {for (final c in linkedChildren) c.student.id: c};
    final fileService = linkedChildren.any((c) => c.fromProjection) ? ParentFileService(parentUserId: userId, firestore: _parentService.firestore, save: widget.fileSaver) : null;
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
    List<AdminNotificationModel> parentNotifications = const [];
    var notificationsError = false;
    // An unlinked parent has no notification access: nothing is queried.
    if (!unlinkedParent) {
      try {
        // Only notices this parent may receive are queried — never ones
        // targeted at other students (AdminNotificationService.
        // getNotificationsForParent); per-child relevance is still decided
        // at build time below.
        parentNotifications = await _notificationService
            .getNotificationsForParent(
              parentUserId: userId,
              childStudentIds: {for (final c in children) c.id},
              childClassIds: {for (final c in children) if (c.classId.isNotEmpty) c.classId},
            );
      } catch (_) {
        notificationsError = true;
      }
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
    final generation = ++_loadGeneration;
    setState(() {
      _linked = linkedChildren;
      _children = children;
      _unavailableChildren = family.unavailable;
      _linkedById = linkedById;
      _fileService = fileService;
      _classNames = classNames;
      _classAcademicYears = classAcademicYears;
      _parentNotifications = parentNotifications;
      _notificationsError = notificationsError;
      _unlinkedParent = unlinkedParent;
      _studentLeaveRequests = studentLeaveRequests;
      _leaveRequestsError = leaveRequestsError;
      // The selected child stays selected while still linked.
      if (!children.any((c) => c.id == _selectedChildId)) {
        _selectedChildId = children.isNotEmpty ? children.first.id : '';
      }
      if (children.length < 2) _showingChild = false;
      // Every child's figures are reloaded (each card shows it is loading)
      // rather than showing the previous load's figures as current.
      _overviews = const {};
      _updatedAt = null;
      _loading = false;
    });

    await Future.wait([
      _loadEvents(generation),
      _loadOverviews(generation, linkedChildren, studentLeaveRequests),
    ]);
  }

  ParentFamilyOverviewLoader get _overviewLoader => ParentFamilyOverviewLoader(
        parentService: _parentService,
        attendanceService: _attendanceService,
        feeService: _feeService,
        fileService: _fileService,
      );

  /// Each child's overview, one child at a time (a family's requests are
  /// never all fired at once); each card appears as soon as its child is
  /// done, and one child's failure stays on that child's card.
  Future<void> _loadOverviews(int generation, List<LinkedChild> children, List<LeaveRequestModel> leave) async {
    final loader = _overviewLoader;
    for (final child in children) {
      final overview = await loader.load(child, leaveRequests: leave);
      if (!mounted || generation != _loadGeneration) return;
      setState(() => _overviews = {..._overviews, child.student.id: overview});
    }
    if (!mounted || generation != _loadGeneration) return;
    setState(() => _updatedAt = DateTime.now());
  }

  /// Reloads one child's overview (its card's Retry).
  Future<void> _retryChild(String studentId) async {
    final linked = _linkedById[studentId];
    if (linked == null) return;
    final generation = _loadGeneration;
    setState(() => _overviews = {..._overviews}..remove(studentId));
    final overview = await _overviewLoader.load(linked, leaveRequests: _studentLeaveRequests);
    if (!mounted || generation != _loadGeneration) return;
    setState(() => _overviews = {..._overviews, studentId: overview});
  }

  Future<void> _loadEvents(int generation) async {
    setState(() {
      _eventsLoading = true;
      _eventsError = false;
    });
    var events = const <CalendarEventModel>[];
    var failed = false;
    try {
      // The same Published Parents/Public items the Calendar tab shows.
      events = await (widget.calendarService ?? CalendarService(firestore: _parentService.firestore)).getEventsForAudience('Parents');
    } catch (_) {
      failed = true;
    }
    if (!mounted || generation != _loadGeneration) return;
    setState(() {
      _events = events;
      _eventsError = failed;
      _eventsLoading = false;
    });
  }

  /// Opens [studentId]'s own dashboard (for a family, from the overview).
  void _selectChild(String studentId) {
    final fromFamily = !_showingChild;
    setState(() {
      _selectedChildId = studentId;
      _showingChild = _children.length > 1;
    });
    if (fromFamily) _scrollToTop();
  }

  void _showFamilyOverview() {
    setState(() => _showingChild = false);
    _scrollToTop();
  }

  void _openTab(int index) => setState(() => selectedIndex = index);

  void _openEvent(CalendarEventModel event) => showCalendarEventDetail(context, event, isAdmin: false);

  void _openPayments(LinkedChild child) {
    final finance = _overviews[child.student.id]?.finance;
    if (finance == null) return;
    showParentPaymentHistory(context, childName: child.student.name, payments: finance.payments);
  }

  void _openBills(LinkedChild child) {
    final finance = _overviews[child.student.id]?.finance;
    if (finance == null) return;
    // The dialog says why when the bills can't be shown.
    showParentIssuedBills(
      context,
      childName: child.student.name,
      finance: finance,
      onRetry: () => _retryChild(child.student.id),
      // The service re-reads the bill and checks this parent's access
      // before building the PDF.
      onDownload: _fileService == null ? null : (bill) => _fileService!.downloadFeeBillById(bill.id),
    );
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
    // No notification access for an unlinked parent: stays on the dashboard
    // (which shows the not-linked message), whatever the way in.
    if (_unlinkedParent) return;
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
          parentUserId: ref.read(currentUserProvider)?.id ?? '',
        ),
      ),
    );
  }

  /// Notices relevant to [children] (the same relevance rule as the
  /// Notifications screen).
  List<AdminNotificationModel> _noticesFor(Iterable<AdminStudentModel> children) => [
        for (final n in _parentNotifications)
          if (isNotificationRelevantToParent(
            n,
            childStudentIds: {for (final c in children) c.id},
            childClassIds: {for (final c in children) if (c.classId.isNotEmpty) c.classId},
          ))
            n,
      ];

  /// Notices aimed at [child] or their class specifically (not
  /// school-wide).
  int _childNotices(AdminStudentModel child) => _noticesFor([child])
      .where((n) => !(n.audience == 'Public' || n.isPublic || n.appliesToAllClasses || n.appliesToAllStudents))
      .length;

  List<ParentSummaryTile> _summaryTiles() {
    final totals = ParentFamilyTotals.of(_linked, _overviews);
    final family = _children.length > 1;
    final upcoming = upcomingParentEvents(_events);
    final soon = DateUtils.dateOnly(DateTime.now()).add(const Duration(days: 30));
    String todayValue() {
      if (totals.presentToday == null) return _overviews.length < _linked.length ? '…' : 'Unavailable';
      if (!family) return parentAttendanceStyle(_overviews[_children.first.id]?.attendance?.todayStatus).$1;
      return '${totals.presentToday} of ${totals.children}';
    }

    return [
      if (family)
        ParentSummaryTile(key: const Key('parent-summary-children'), icon: Icons.family_restroom_outlined, label: 'Children', value: '${totals.children}', caption: 'linked to your account'),
      ParentSummaryTile(
        key: const Key('parent-summary-attendance'),
        icon: Icons.how_to_reg_outlined,
        label: 'Attendance today',
        value: todayValue(),
        caption: family ? 'present today' : '',
      ),
      // Only children whose Father or Mother this parent is; none: no
      // financial figure at all.
      if (totals.financeChildren > 0)
        ParentSummaryTile(
          key: const Key('parent-summary-outstanding'),
          icon: Icons.account_balance_wallet_outlined,
          label: 'Outstanding fees',
          value: totals.outstanding != null
              ? parentMoney(totals.outstanding!)
              : totals.financeIncomplete
                  ? 'Unavailable'
                  : '…',
          caption: totals.financeIncomplete
              ? "Some fees couldn't load"
              : family && totals.financeChildren < totals.children
                  ? 'for ${totals.financeChildren} of ${totals.children} children'
                  : '',
          onTap: () => _openTab(_feesTab),
        ),
      ParentSummaryTile(
        key: const Key('parent-summary-events'),
        icon: Icons.event_outlined,
        label: 'Upcoming events',
        value: _eventsLoading ? '…' : _eventsError ? 'Unavailable' : '${upcoming.where((e) => e.date.isBefore(soon)).length}',
        caption: 'next 30 days',
        onTap: () => _openTab(_calendarTab),
      ),
      ParentSummaryTile(
        key: const Key('parent-summary-notices'),
        icon: Icons.campaign_outlined,
        label: 'School notices',
        value: _notificationsError ? 'Unavailable' : '${_noticesFor(_children).length}',
        caption: 'for your family',
        onTap: _openAllNotifications,
      ),
    ];
  }

  Widget _childCard(AdminStudentModel child) {
    final linked = _linkedById[child.id]!;
    return ParentChildOverviewCard(
      student: child,
      className: _classNames[child.classId] ?? '',
      overview: _overviews[child.id],
      photoPath: linked.photoPath,
      fileService: _fileService,
      childNotices: _childNotices(child),
      onOpen: () => _selectChild(child.id),
      onPayments: () => _openPayments(linked),
      onBills: () => _openBills(linked),
      onRetry: () => _retryChild(child.id),
    );
  }

  List<Widget> _familyOverview() => [
        // The family's everyday actions; each child's own are on its card
        // and in its dashboard.
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(key: const Key('parent-family-request-leave'), onPressed: _openRequestLeave, icon: const Icon(Icons.add, size: 18), label: const Text('Request Leave')),
            OutlinedButton.icon(onPressed: () => _openTab(_calendarTab), icon: const Icon(Icons.calendar_month_outlined, size: 18), label: const Text('Calendar')),
            if (_linked.any((c) => c.canViewFinance != false))
              OutlinedButton.icon(key: const Key('parent-family-fees'), onPressed: () => _openTab(_feesTab), icon: const Icon(Icons.account_balance_wallet_outlined, size: 18), label: const Text('Fees')),
          ],
        ),
        const SizedBox(height: 16),
        if (_unavailableChildren > 0) ...[
          ParentUnavailableChildrenNotice(count: _unavailableChildren),
          const SizedBox(height: 16),
        ],
        ParentChildCardGrid(cards: [for (final c in _children) _childCard(c)]),
        const SizedBox(height: 20),
        _NotificationsSection(
          notifications: _noticesFor(_children).take(3).toList(),
          hasError: _notificationsError,
          onViewAll: _openAllNotifications,
          onRetry: _loadDashboard,
        ),
        const SizedBox(height: 20),
        _upcomingEvents(),
      ];

  Widget _upcomingEvents() => ParentUpcomingEvents(
        events: upcomingParentEvents(_events),
        loading: _eventsLoading,
        failed: _eventsError,
        onOpenCalendar: () => _openTab(_calendarTab),
        onOpenEvent: _openEvent,
        onRetry: () => _loadEvents(_loadGeneration),
      );

  List<Widget> _childDashboard(AdminStudentModel selectedChild) {
    final family = _children.length > 1;
    final linked = _linkedById[selectedChild.id]!;
    final overview = _overviews[selectedChild.id];
    final className = _classNames[selectedChild.classId] ?? '-';
    final academicYear = _classAcademicYears[selectedChild.classId] ?? '';
    // Scoped to exactly the *selected* child's own studentId/classId — not
    // the union across every linked child — so a notification targeted to
    // one child (selected-student or class targeting) never bleeds into
    // another child's dashboard.
    final notifications = _noticesFor([selectedChild]).take(3).toList();
    return [
      // (A family's child switcher is at the top of the page — see build.)
      if (!family && _unavailableChildren > 0) ...[
        ParentUnavailableChildrenNotice(count: _unavailableChildren),
        const SizedBox(height: 16),
      ],
      _ChildCard(
        child: selectedChild,
        className: className,
        overview: overview,
        photoPath: linked.photoPath,
        fileService: _fileService,
        onRetry: () => _retryChild(selectedChild.id),
        onViewProfile: () => showChildProfile(
          fileService: _fileService,
          context,
          child: selectedChild,
          photoPath: linked.photoPath,
          documents: linked.documents,
          guardians: linked.guardians,
          className: className,
          academicYear: academicYear,
        ),
        onViewHistory: () => showChildAttendanceHistory(
          context,
          studentId: selectedChild.id,
          studentName: selectedChild.name,
          attendanceService: widget.attendanceService,
        ),
      ),
      const SizedBox(height: 20),
      _FeeSummarySection(
        overview: overview,
        onRetry: () => _retryChild(selectedChild.id),
        onPayments: () => _openPayments(linked),
        onBills: () => _openBills(linked),
        onAllFees: () => _openTab(_feesTab),
      ),
      const SizedBox(height: 20),
      _StudentLeaveSection(
        loading: _loading,
        hasError: _leaveRequestsError,
        requests: _studentLeaveRequests
            .where((r) => r.studentId == selectedChild.id)
            .toList(),
        onRequestLeave: _openRequestLeave,
        onRetry: _loadDashboard,
      ),
      const SizedBox(height: 20),
      _NotificationsSection(
        notifications: notifications,
        hasError: _notificationsError,
        onViewAll: _openAllNotifications,
        onRetry: _loadDashboard,
      ),
      // A single child's dashboard is also the home page.
      if (!family) ...[
        const SizedBox(height: 20),
        _upcomingEvents(),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    // Opened before the session user was set: load once it is.
    ref.listen(currentUserProvider, (previous, next) {
      if ((previous?.id ?? '').isEmpty && (next?.id ?? '').isNotEmpty) _loadDashboard();
    });
    final isMobile =
        MediaQuery.of(context).size.width < AppSizes.mobileBreakpoint;

    final selectedChild = _children.isEmpty
        ? null
        : _children.firstWhere(
            (c) => c.id == _selectedChildId,
            orElse: () => _children.first,
          );
    final familyHome = _children.length > 1 && !_showingChild;
    final onHome = familyHome || _children.length <= 1;

    final dashboardContent = _loading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _loadDashboard,
            child: SingleChildScrollView(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                isMobile ? 16 : 32,
                24,
                isMobile ? 16 : 32,
                40,
              ),
              // Stretched: every section card spans the page width, however
              // little it holds.
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // A family looking at one child: the way back to the
                  // family and to the other children comes first.
                  if (!familyHome && _children.length > 1) ...[
                    ParentChildSwitcher(
                      children: _children,
                      classNames: _classNames,
                      selectedId: selectedChild!.id,
                      onSelected: _selectChild,
                      onFamilyOverview: _showFamilyOverview,
                    ),
                    const SizedBox(height: 12),
                  ],
                  ParentFamilyHeader(
                    parentName: user?.name ?? '',
                    childCount: _children.length,
                    viewingChild: !familyHome && _children.length > 1 ? selectedChild!.name : null,
                    updatedAt: _updatedAt,
                    onOpenNotifications: _unlinkedParent ? null : _openAllNotifications,
                  ),
                  if (onHome && _children.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    ParentFamilySummary(tiles: _summaryTiles()),
                  ],
                  const SizedBox(height: 20),
                  // Belongs to the authenticated parent account, not to
                  // whichever child happens to be selected — rendered in
                  // every view (even with zero linked children) and built
                  // as a fully self-contained widget that never reads
                  // `_selectedChildId`, so switching the selected child
                  // structurally cannot affect it.
                  _ParentMoodSection(
                    parentUserId: user?.id ?? '',
                    parentName: user?.name ?? '',
                    moodCheckinService: _moodCheckinService,
                  ),
                  const SizedBox(height: 20),
                  if (_children.isEmpty) ...[
                    if (_familyError)
                      _FamilyLoadErrorCard(onRetry: _loadDashboard)
                    else if (_unavailableChildren > 0)
                      ParentUnavailableChildrenNotice(count: _unavailableChildren)
                    else
                      // Confirmed: the lookup succeeded and no child is
                      // linked to this parent account.
                      _NoChildrenLinkedCard(parent: (user?.role ?? '').toLowerCase() == 'parent'),
                    if (!_unlinkedParent) ...[
                      const SizedBox(height: 20),
                      _NotificationsSection(
                        notifications: const [],
                        hasError: _notificationsError,
                        onViewAll: _openAllNotifications,
                        onRetry: _loadDashboard,
                      ),
                    ],
                  ] else if (familyHome)
                    ..._familyOverview()
                  else
                    ..._childDashboard(selectedChild!),
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
      (title: 'Calendar', body: () => CalendarView(service: widget.calendarService)),
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

    Future<void> logout() async {
      await ref.read(authServiceProvider).logout(ref, context);
      if (context.mounted) {
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil('/login', (route) => false);
      }
    }

    // Mirrors DashboardScreen's shell exactly: same ResponsiveLayout,
    // AppSidebar/AppBottomNav (already role-aware and Dashboard-only for
    // 'parent'), background, and AppBar structure — only the body content
    // differs, so switching from Staff to Parent feels like the same
    // application with different navigation/content, not a separate app.
    return ResponsiveLayout(
      mobile: Scaffold(
        backgroundColor: Colors.grey[50],
        // Responsive: never overflows, however narrow the window
        // (ParentAppBar).
        appBar: ParentAppBar(title: currentTitle, onLogout: logout),
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
                  ParentAppBar(title: currentTitle, onLogout: logout),
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

/// No child is linked to the account (the lookup succeeded). A parent is
/// told their login worked and the school links their child; any other
/// account shown this dashboard keeps the earlier wording.
class _NoChildrenLinkedCard extends StatelessWidget {
  const _NoChildrenLinkedCard({required this.parent});

  final bool parent;

  static const title = 'Your account is not linked to a student yet';
  static const body = [
    'Your login was successful, but we could not find any children linked to your account.',
    'Please contact the school administrator to register your parent details and link your child to your account.',
    "Once your account is linked, you will be able to view your child's dashboard, attendance, fees and other available information here.",
  ];

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const Key('parent-no-children'),
      elevation: 0,
      color: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(
              Icons.family_restroom_outlined,
              size: 36,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 12),
            if (parent) ...[
              const Text(
                title,
                key: Key('parent-no-children-title'),
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
              ),
              for (final line in body) ...[
                const SizedBox(height: 8),
                Text(line, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
              ],
            ] else ...[
              const Text(
                'No children linked to your account yet.',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              const Text(
                "Ask the school office to link your child's profile to this account.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The linked children couldn't be read (a network or access problem):
/// said plainly, with Retry. Never "no children".
class _FamilyLoadErrorCard extends StatelessWidget {
  const _FamilyLoadErrorCard({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const Key('parent-family-error'),
      elevation: 0,
      color: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.cloud_off_outlined, size: 36, color: AppColors.textSecondary),
            const SizedBox(height: 12),
            const Text(
              "Your children's details couldn't be loaded right now.",
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            const Text(
              'Check your connection and try again.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('parent-family-retry'),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChildCard extends StatelessWidget {
  const _ChildCard({
    required this.child,
    required this.className,
    required this.overview,
    required this.onViewProfile,
    required this.onViewHistory,
    this.onRetry,
    this.photoPath = '',
    this.fileService,
  });

  final AdminStudentModel child;

  /// Protected photo download for the signed-in parent.
  final ParentFileService? fileService;

  /// The photo's Storage path from the parent-safe profile ('' before it).
  final String photoPath;
  final String className;

  /// The child's loaded overview; null while it loads.
  final ParentChildOverview? overview;
  final VoidCallback onViewProfile;
  final VoidCallback onViewHistory;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final loading = overview == null;
    final snapshot = overview?.attendance;
    // Today's record in its parent-facing form (photo by path, never URL);
    // the status as displayed (an approved leave on an unmarked day shows
    // as On leave, the attendance screens' rule).
    final status = snapshot?.todayStatus;
    final checkInTime = _formatCheckInTime(snapshot?.today?['updatedAt']);

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
                ParentChildAvatar(name: child.name, studentId: child.id, photoPath: photoPath, photoUrl: child.profileImageUrl, radius: 28, fileService: fileService),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        child.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        parentClassLine(child, className).isEmpty ? className : parentClassLine(child, className),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
            else if (overview!.attendanceFailed)
              ParentAttendanceLine(attendance: null, failed: true, onRetry: onRetry)
            else ...[
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
              if (snapshot != null) ...[
                const SizedBox(height: 8),
                Text(
                  snapshot.hasAnyRecord || snapshot.onLeave > 0
                      ? 'Last ${snapshot.days} days: ${snapshot.present} present · ${snapshot.absent} absent · ${snapshot.onLeave} on leave'
                      : 'No attendance marked in the last ${snapshot.days} days.',
                  key: const Key('parent-attendance-30-days'),
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ],
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
    final (label, color) = parentAttendanceStyle(status);
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
            // Title and action share one line when they fit; on a narrow
            // phone the action moves below the title instead of
            // overflowing.
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text(
                  'Leave Requests',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
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
  const _FeeSummarySection({required this.overview, required this.onRetry, required this.onPayments, required this.onBills, required this.onAllFees});

  /// Null while loading. Its finance is null when restricted (not the
  /// child's Father or Mother — nothing financial was read) or failed.
  final ParentChildOverview? overview;
  final VoidCallback onRetry, onPayments, onBills, onAllFees;

  @override
  Widget build(BuildContext context) {
    final o = overview;
    final finance = o?.finance;
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
            if (o == null)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (o.financeRestricted)
              const Text(
                parentFeesRestrictedMessage,
                key: Key('parent-fees-restricted'),
                style: TextStyle(color: AppColors.textSecondary),
              )
            else if (finance == null)
              Row(
                children: [
                  const Expanded(child: Text("Couldn't load fees.", style: TextStyle(color: AppColors.textSecondary))),
                  TextButton(onPressed: onRetry, child: const Text('Retry')),
                ],
              )
            else ...[
              if (finance.assignments.isEmpty)
                const Text(
                  'No fee assignments yet.',
                  style: TextStyle(color: AppColors.textSecondary),
                )
              else ...[
                ParentFeeFigures(finance: finance),
                const Divider(height: 24),
                for (final assignment in finance.assignments) ...[
                  _FeeAssignmentRow(assignment: assignment),
                  const SizedBox(height: 10),
                ],
              ],
              const SizedBox(height: 4),
              // Three different things, never merged: what is charged (All
              // fees), what was actually paid (Payment history) and the
              // supplementary bills the school issued (Issued bills).
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  OutlinedButton.icon(key: const Key('parent-fees-payment-history'), onPressed: onPayments, icon: const Icon(Icons.receipt_long_outlined, size: 18), label: const Text('Payment history')),
                  OutlinedButton.icon(key: const Key('parent-fees-issued-bills'), onPressed: onBills, icon: const Icon(Icons.description_outlined, size: 18), label: Text(parentBillsLabel(finance))),
                  TextButton(key: const Key('parent-fees-all'), onPressed: onAllFees, child: const Text('All fees')),
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
          // The status chip sits beside the fee name, or below it when the
          // card is too narrow for both.
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                assignment.feeStructureName.isNotEmpty
                    ? assignment.feeStructureName
                    : 'Fee',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
              FinanceStatusChip(label: label, color: color),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _FeeAmountColumn(
                label: 'Net payable',
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
            parentMoney(amount),
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
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
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
        onTap: () => showNotificationDetail(
          context,
          notification,
          parentUserId: ProviderScope.containerOf(context, listen: false).read(currentUserProvider)?.id ?? '',
        ),
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
