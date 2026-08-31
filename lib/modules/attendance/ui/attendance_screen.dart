import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../admin/settings/models/school_settings_model.dart' show kDefaultSchoolId;
import '../../admin/settings/providers/academic_year_provider.dart';
import '../../admin/ui/admin_attendance_management_screen.dart'
    show resolveAttendanceDisplayStatus;
import '../../auth/data/user_service.dart';
import '../../auth/models/app_user.dart';
import '../../auth/providers/auth_provider.dart';
import '../../classes/providers/class_provider.dart';
import '../../leave/services/leave_service.dart';
import '../../mood_checkin/providers/mood_checkin_provider.dart';
import '../../mood_checkin/ui/mood_checkin_dialog.dart';
import '../../mood_checkin/services/mood_checkin_service.dart';
import '../../students/providers/student_provider.dart';
import '../providers/attendance_provider.dart';

/// AY-IMPLEMENT-03: the fallback used only when no current Academic Year
/// is configured yet (or it hasn't finished loading) — see
/// `_AttendanceScreenState._academicYearStart`'s doc comment for why this
/// is no longer the primary source once a real Academic Year exists. Kept
/// exactly as it always was so behavior is unchanged in that fallback case.
DateTime getAcademicYearStart(DateTime today) {
  if (today.month >= 6) {
    return DateTime(today.year, 6, 1);
  }
  return DateTime(today.year - 1, 6, 1);
}

class AttendanceScreen extends ConsumerStatefulWidget {
  const AttendanceScreen({super.key, this.leaveService, this.userService});

  /// Overridable only so tests can inject a fake-Firestore-backed
  /// LeaveService — the same DI seam AdminAttendanceManagementScreen already
  /// exposes on its own constructor. Production callers never pass this.
  final LeaveService? leaveService;

  /// Overridable for the same reason as [leaveService] — UserService is
  /// instantiated directly here rather than via a riverpod provider, so a
  /// widget test needs its own seam to inject a fake-Firestore-backed
  /// instance. Production callers never pass this.
  final UserService? userService;

  @override
  ConsumerState<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends ConsumerState<AttendanceScreen> {
  late final _leaveService = widget.leaveService ?? LeaveService();
  late final _userService = widget.userService ?? UserService();
  bool _loading = true;
  String? _errorMessage;
  final _searchController = TextEditingController();
  final Set<String> _selectedClassIds = {};
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _classes = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _allStudents = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _students = [];
  List<AppUser> _staff = [];
  /// Every active staff member returned by the attendance roster query,
  /// unfiltered by the search box — [_staff] above is the search-filtered
  /// list used by the Today tab; History always shows the full roster, the
  /// same way [_allStudents] (vs. [_students]) already does for students.
  List<AppUser> _allStaff = [];
  Map<String, Map<String, dynamic>> _attendanceMap = {};
  Map<String, Map<String, dynamic>> _historyAttendanceMap = {};
  /// Student ids with an Approved leave request covering today — recomputed
  /// on every `_loadData` so a student's leave on any other date never
  /// appears here.
  Set<String> _studentIdsOnLeave = {};
  /// Staff ids with an Approved leave request covering today — same shape
  /// as [_studentIdsOnLeave], for Staff Leave.
  Set<String> _staffIdsOnLeave = {};
  /// Student ids on Approved leave for each date in the currently displayed
  /// History week, keyed by `yyyy-MM-dd` — recomputed on every `_loadData`
  /// (i.e. whenever the selected History week changes) against exactly that
  /// week's range, so navigating weeks never shows stale leave data.
  Map<String, Set<String>> _historyStudentIdsOnLeave = {};
  /// Staff ids on Approved leave for each date in the currently displayed
  /// History week — same shape as [_historyStudentIdsOnLeave], for Staff
  /// Leave.
  Map<String, Set<String>> _historyStaffIdsOnLeave = {};
  late DateTime _selectedHistoryWeekStart;
  /// The canonical current Academic Year's own `startDate`, resolved
  /// best-effort in [_loadData] — see [_academicYearStart]'s doc comment.
  /// `null` until it loads, or if no current Academic Year is configured,
  /// in which case [_academicYearStart] falls back to
  /// [getAcademicYearStart] exactly as before AY-IMPLEMENT-03.
  DateTime? _canonicalAcademicYearStart;
  Map<String, String> _classNames = {};
  int _studentCount = 0;
  int _staffCount = 0;
  int _presentCount = 0;
  int _absentCount = 0;
  int _notMarkedCount = 0;
  final Map<String, bool> _marking = {};
  final Map<String, String> _latestMoodLabels = {};

  @override
  void initState() {
    super.initState();
    _selectedHistoryWeekStart = _startOfWeek(DateTime.now().toLocal());
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      final classService = ref.read(classServiceProvider);
      final studentService = ref.read(studentServiceProvider);
      final userService = _userService;
      final attendanceService = ref.read(attendanceServiceProvider);
      final moodService = ref.read(moodCheckinServiceProvider);
      // Best-effort, same shape as the on-leave resolutions below: a
      // failure (or no current Academic Year configured yet) must never
      // block attendance from loading — `_academicYearStart` simply keeps
      // using its existing hardcoded fallback in that case.
      DateTime? canonicalAcademicYearStart;
      try {
        final currentYear = await ref
            .read(academicYearServiceProvider)
            .getCurrentAcademicYear(schoolId: kDefaultSchoolId);
        canonicalAcademicYearStart = currentYear?.startDate;
      } catch (_) {
        canonicalAcademicYearStart = null;
      }

      final classes = await classService.getClasses();
      final allStudents = await studentService.getAllStudents();
      final staff = await userService.getAttendanceStaffUsers();
      final attendanceMap = await attendanceService.getTodayAttendanceMap();
      final historyAttendanceMap = await attendanceService
          .getAttendanceHistoryMap(
            startDate: _selectedHistoryWeekStart,
            endDate: _selectedHistoryWeekStart.add(const Duration(days: 6)),
          );
      // Best-effort: a failure to resolve on-leave students/staff must not
      // block attendance from loading — it just means the On Leave
      // indicator is temporarily unavailable for today.
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
      // Same best-effort fallback, resolved for the whole displayed History
      // week rather than a single date.
      Map<String, Set<String>> historyStudentIdsOnLeave = {};
      try {
        historyStudentIdsOnLeave =
            await _leaveService.getStudentIdsOnApprovedLeaveForRange(
          startDate: _selectedHistoryWeekStart,
          endDate: _selectedHistoryWeekStart.add(const Duration(days: 6)),
        );
      } catch (_) {
        historyStudentIdsOnLeave = {};
      }
      Map<String, Set<String>> historyStaffIdsOnLeave = {};
      try {
        historyStaffIdsOnLeave =
            await _leaveService.getStaffIdsOnApprovedLeaveForRange(
          startDate: _selectedHistoryWeekStart,
          endDate: _selectedHistoryWeekStart.add(const Duration(days: 6)),
        );
      } catch (_) {
        historyStaffIdsOnLeave = {};
      }
      final latestMoodLabels = <String, String>{};
      for (final doc in allStudents) {
        final label = await _latestMoodLabel(moodService, 'student', doc.id);
        if (label != null) {
          latestMoodLabels[_attendanceKey('student', doc.id)] = label;
        }
      }
      for (final user in staff) {
        final label = await _latestMoodLabel(moodService, 'staff', user.id);
        if (label != null) {
          latestMoodLabels[_attendanceKey('staff', user.id)] = label;
        }
      }

      final classNames = <String, String>{
        for (final doc in classes)
          doc.id: doc.data()['name']?.toString() ?? '-',
      };
      final staffById = <String, AppUser>{};
      for (final user in staff) {
        staffById[user.id] = user;
      }
      final visibleStudents = allStudents.where((doc) {
        final data = doc.data();
        if (data['isActive'] != true) return false;
        if (_selectedClassIds.isNotEmpty &&
            !_selectedClassIds.contains(data['classId']?.toString() ?? '')) {
          return false;
        }
        return _matchesStudent(
          doc,
          _searchController.text.trim().toLowerCase(),
        );
      }).toList();
      final filteredStaff = staffById.values
          .where(
            (user) => _matchesStaff(
              user,
              _searchController.text.trim().toLowerCase(),
            ),
          )
          .toList();

      // Summary population respects the class filter for students (matching
      // what the class chips above are already understood to scope) but not
      // the search box — the same scope the old service-computed
      // Students/Staff/Total/Present/Absent counts used. Present/Absent/Not
      // Marked are now resolved per entity via the same
      // resolveAttendanceDisplayStatus pipeline the rows/history use, rather
      // than a second "Total - Present - Absent" calculation — so Total =
      // Present + Absent + On Leave + Not Marked holds by construction, for
      // both Students and Staff, instead of silently double-counting an
      // approved leave as Not Marked.
      final summaryStudents = allStudents.where((doc) {
        final data = doc.data();
        if (data['isActive'] != true) return false;
        if (_selectedClassIds.isNotEmpty &&
            !_selectedClassIds.contains(data['classId']?.toString() ?? '')) {
          return false;
        }
        return true;
      }).toList();

      var presentCount = 0;
      var absentCount = 0;
      var notMarkedCount = 0;
      for (final doc in summaryStudents) {
        final record = attendanceMap[_attendanceKey('student', doc.id)];
        final display = resolveAttendanceDisplayStatus(
          rawStatus: _rawStatus(record),
          isOnApprovedLeave: studentIdsOnLeave.contains(doc.id),
        );
        switch (display) {
          case 'present':
            presentCount++;
          case 'absent':
            absentCount++;
          case 'on_leave':
            break;
          default:
            notMarkedCount++;
        }
      }
      for (final user in staff) {
        final record = attendanceMap[_attendanceKey('staff', user.id)];
        final display = resolveAttendanceDisplayStatus(
          rawStatus: _rawStatus(record),
          isOnApprovedLeave: staffIdsOnLeave.contains(user.id),
        );
        switch (display) {
          case 'present':
            presentCount++;
          case 'absent':
            absentCount++;
          case 'on_leave':
            break;
          default:
            notMarkedCount++;
        }
      }

      if (!mounted) return;
      setState(() {
        _classes = classes;
        _allStudents = allStudents;
        _students = visibleStudents;
        _staff = filteredStaff;
        _allStaff = staff;
        _attendanceMap = attendanceMap;
        _historyAttendanceMap = historyAttendanceMap;
        _studentIdsOnLeave = studentIdsOnLeave;
        _staffIdsOnLeave = staffIdsOnLeave;
        _historyStudentIdsOnLeave = historyStudentIdsOnLeave;
        _historyStaffIdsOnLeave = historyStaffIdsOnLeave;
        _classNames = classNames;
        _canonicalAcademicYearStart = canonicalAcademicYearStart;
        _studentCount = summaryStudents.length;
        _staffCount = staff.length;
        _presentCount = presentCount;
        _absentCount = absentCount;
        _notMarkedCount = notMarkedCount;
        _latestMoodLabels
          ..clear()
          ..addAll(latestMoodLabels);
      });
    } catch (e) {
      if (mounted) setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _matchesStudent(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    String query,
  ) {
    if (query.isEmpty) return true;
    final data = doc.data();
    final name = data['name']?.toString().toLowerCase() ?? '';
    final admissionNo = data['admissionNo']?.toString().toLowerCase() ?? '';
    final className = _resolveClassName(data).toLowerCase();
    return name.contains(query) ||
        admissionNo.contains(query) ||
        className.contains(query);
  }

  bool _matchesStaff(AppUser user, String query) {
    if (query.isEmpty) return true;
    final name = (user.name ?? '').toLowerCase();
    final phone = user.phone.toLowerCase();
    final role = user.role.toLowerCase();
    return name.contains(query) ||
        phone.contains(query) ||
        role.contains(query);
  }

  String _resolveClassName(Map<String, dynamic> data) {
    final explicit = data['className']?.toString().trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;
    final classId = data['classId']?.toString().trim();
    if (classId != null && classId.isNotEmpty) {
      return _classNames[classId] ?? '-';
    }
    return '-';
  }

  String _rawStatus(Map<String, dynamic>? record) {
    if (record == null) return 'not_marked';
    final status = (record['status']?.toString() ?? '').toLowerCase();
    final hasPhoto = _attendancePhotoUrl(record).isNotEmpty;
    if (status == 'absent') return 'absent';
    if (status == 'present' || (status.isEmpty && hasPhoto)) return 'present';
    return 'not_marked';
  }

  /// Resolves the display label for a row, folding in the Student Leave ->
  /// Attendance integration via the same pure [resolveAttendanceDisplayStatus]
  /// helper AdminAttendanceManagementScreen uses — an existing Present/Absent
  /// record is a real fact about today and is never overridden by an
  /// approved leave; only the "nothing recorded yet" case is.
  String _statusLabel(
    Map<String, dynamic>? record, {
    bool isOnApprovedLeave = false,
  }) {
    final display = resolveAttendanceDisplayStatus(
      rawStatus: _rawStatus(record),
      isOnApprovedLeave: isOnApprovedLeave,
    );
    switch (display) {
      case 'present':
        return 'Present';
      case 'absent':
        return 'Absent';
      case 'on_leave':
        return 'On Leave';
      default:
        return 'Not Marked';
    }
  }

  String _attendancePhotoUrl(Map<String, dynamic>? record) {
    if (record == null) return '';
    final candidates = [
      record['photoUrl'],
      record['imageUrl'],
      record['attendancePhotoUrl'],
      record['profileImageUrl'],
      record['url'],
    ];
    for (final value in candidates) {
      final url = value?.toString().trim() ?? '';
      if (url.isNotEmpty) return url;
    }
    return '';
  }

  static DateTime _startOfWeek(DateTime date) {
    return DateTime(
      date.year,
      date.month,
      date.day,
    ).subtract(Duration(days: date.weekday - 1));
  }

  /// AY-IMPLEMENT-03: the earliest date History week-navigation can scroll
  /// back to. Prefers the canonical current Academic Year's own
  /// `startDate` (resolved in [_loadData]) once one is configured;
  /// falls back to the pre-existing hardcoded June-1 heuristic
  /// ([getAcademicYearStart]) only while that hasn't loaded yet or no
  /// current Academic Year exists — never invents one, exactly like every
  /// other `currentAcademicYearProvider` consumer's null-safe contract.
  DateTime get _academicYearStart =>
      _canonicalAcademicYearStart ?? getAcademicYearStart(DateTime.now().toLocal());

  DateTime get _academicYearWeekStart => _startOfWeek(_academicYearStart);

  bool get _canGoBack {
    return _selectedHistoryWeekStart.isAfter(_academicYearWeekStart);
  }

  bool get _canGoNext {
    final currentWeekStart = _startOfWeek(DateTime.now().toLocal());
    return _selectedHistoryWeekStart.isBefore(currentWeekStart);
  }

  void _goPreviousWeek() {
    if (!_canGoBack) return;
    setState(() {
      final previousWeek = _selectedHistoryWeekStart.subtract(
        const Duration(days: 7),
      );
      _selectedHistoryWeekStart = previousWeek.isBefore(_academicYearWeekStart)
          ? _academicYearWeekStart
          : previousWeek;
    });
    _loadData();
  }

  void _goNextWeek() {
    if (!_canGoNext) return;
    setState(() {
      _selectedHistoryWeekStart = _selectedHistoryWeekStart.add(
        const Duration(days: 7),
      );
    });
    _loadData();
  }

  /// Resolves one History cell for [entityType]/[entityId] on [date] — an
  /// existing attendance record (Present/Absent) is a real fact about that
  /// date and always wins; only a date with no record at all falls through
  /// to [historyIdsOnLeave] for that exact date. Reuses the same
  /// [_rawStatus] + [resolveAttendanceDisplayStatus] pipeline the Today tab
  /// uses — and is shared between Students and Staff via [entityType]
  /// rather than duplicated per entity type.
  Widget _historyCell({
    required String entityType,
    required String entityId,
    required DateTime date,
    required Map<String, Map<String, dynamic>> historyAttendanceMap,
    required Map<String, Set<String>> historyIdsOnLeave,
  }) {
    final dateKey = DateFormat('yyyy-MM-dd').format(date);
    final record = historyAttendanceMap['${entityType}_${entityId}_$dateKey'];
    final isOnApprovedLeave =
        historyIdsOnLeave[dateKey]?.contains(entityId) ?? false;
    final display = resolveAttendanceDisplayStatus(
      rawStatus: _rawStatus(record),
      isOnApprovedLeave: isOnApprovedLeave,
    );
    switch (display) {
      case 'present':
        return const Icon(Icons.check_circle, color: Colors.green, size: 20);
      case 'absent':
        return const Icon(Icons.cancel, color: Colors.red, size: 20);
      case 'on_leave':
        return const _HistoryOnLeavePill();
      default:
        return Text('-', style: TextStyle(color: Colors.grey.shade600));
    }
  }

  Future<String?> _latestMoodLabel(
    MoodCheckinService moodService,
    String entityType,
    String entityId,
  ) async {
    final latest = await moodService.getLatestMoodForEntity(
      entityType,
      entityId,
    );
    return latest?.moodLabel;
  }

  Color _statusBg(String label) {
    switch (label) {
      case 'Present':
        return Colors.green.shade50;
      case 'Absent':
        return Colors.red.shade50;
      case 'On Leave':
        return Colors.blue.shade50;
      default:
        return Colors.grey.shade200;
    }
  }

  Color _statusFg(String label) {
    switch (label) {
      case 'Present':
        return Colors.green.shade700;
      case 'Absent':
        return Colors.red.shade700;
      case 'On Leave':
        return Colors.blue.shade700;
      default:
        return Colors.grey.shade700;
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? Colors.red.shade600 : null,
        ),
      );
  }

  // Present is a strict sequence — mood, then camera, then upload, then the
  // attendance write, then the mood-checkin write — and each stage can fail
  // independently. The mood check-in must never be written unless the
  // attendance record was actually saved, and a photo that was uploaded but
  // never ended up referenced by a saved attendance record must not be left
  // behind, so each stage is handled (and reported) on its own rather than
  // behind one broad try/catch.
  Future<void> _markPresent({
    required String entityType,
    required String entityId,
    required String entityName,
    required String markedBy,
    String? classId,
    String? role,
    String? phone,
    String? email,
  }) async {
    final service = ref.read(attendanceServiceProvider);
    final moodService = ref.read(moodCheckinServiceProvider);

    final mood = await MoodCheckinDialog.show(context, entityType: entityType);
    if (mood == null || !mounted) return;

    setState(() => _marking[entityId] = true);

    String? photoUrl;
    try {
      _showSnack('Opening camera…');
      photoUrl = await service.captureAndUploadPhoto(
        entityType: entityType,
        entityId: entityId,
      );
    } catch (_) {
      if (mounted) setState(() => _marking[entityId] = false);
      _showSnack('Could not upload the photo. Please try again.', isError: true);
      return;
    }

    if (photoUrl == null) {
      // User cancelled the camera (or it was unavailable) — nothing was
      // written, and the mood already selected is intentionally discarded.
      if (mounted) setState(() => _marking[entityId] = false);
      _showSnack(
        'Attendance not marked. A photo is required to mark Present.',
        isError: true,
      );
      return;
    }

    final uploadedPhotoUrl = photoUrl;
    String attendanceId;
    try {
      _showSnack('Saving attendance…');
      attendanceId = await service.markPresent(
        entityType: entityType,
        entityId: entityId,
        entityName: entityName,
        classId: classId,
        markedBy: markedBy,
        photoUrl: uploadedPhotoUrl,
        role: role,
        phone: phone,
        email: email,
      );
    } catch (_) {
      // The photo is already in Storage but no attendance record ended up
      // referencing it — clean it up rather than leaving it orphaned.
      await service.deleteAttendancePhoto(
        entityType: entityType,
        entityId: entityId,
        date: service.dateKeyFor(DateTime.now()),
      );
      if (mounted) setState(() => _marking[entityId] = false);
      _showSnack('Could not save attendance. Please try again.', isError: true);
      return;
    }

    // Attendance is saved from this point on — everything below is best
    // effort and must not make attendance look like it failed.
    if (mounted) {
      setState(() {
        _attendanceMap[_attendanceKey(entityType, entityId)] = {
          'entityType': entityType,
          'entityId': entityId,
          'entityName': entityName,
          'classId': classId ?? '',
          'date': DateTime.now().toLocal().toIso8601String().split('T').first,
          'photoUrl': uploadedPhotoUrl,
          'markedBy': markedBy,
          'status': 'present',
          'role': role,
          'phone': phone,
          'email': email,
        };
      });
    }

    try {
      _showSnack('Saving mood check-in…');
      await moodService.createMoodCheckin(
        entityType: entityType,
        entityId: entityId,
        entityName: entityName,
        classId: classId,
        moodCode: mood.moodCode,
        moodLabel: mood.moodLabel,
        moodCategory: mood.moodCategory,
        intensity: mood.intensity,
        notes: mood.notes,
        source: 'attendance',
        attendanceId: attendanceId,
        photoUrl: uploadedPhotoUrl,
        createdBy: markedBy,
      );
      await _loadData();
      if (mounted) setState(() => _marking[entityId] = false);
      _showSnack('Attendance marked.');
    } catch (_) {
      await _loadData();
      if (mounted) setState(() => _marking[entityId] = false);
      _showSnack(
        'Attendance marked, but mood check-in could not be saved.',
        isError: true,
      );
    }
  }

  Future<void> _markAbsent({
    required String entityType,
    required String entityId,
    required String entityName,
    required String markedBy,
    String? classId,
    String? role,
    String? phone,
    String? email,
  }) async {
    final service = ref.read(attendanceServiceProvider);
    setState(() => _marking[entityId] = true);
    try {
      await service.markAbsent(
        entityType: entityType,
        entityId: entityId,
        entityName: entityName,
        classId: classId,
        markedBy: markedBy,
        role: role,
        phone: phone,
        email: email,
      );
      if (!mounted) return;
      setState(() {
        _attendanceMap[_attendanceKey(entityType, entityId)] = {
          'entityType': entityType,
          'entityId': entityId,
          'entityName': entityName,
          'classId': classId ?? '',
          'date': DateTime.now().toLocal().toIso8601String().split('T').first,
          'markedBy': markedBy,
          'status': 'absent',
          'role': role,
          'phone': phone,
          'email': email,
        };
      });
      await _loadData();
      if (mounted) setState(() => _marking[entityId] = false);
      _showSnack('Attendance marked.');
    } catch (_) {
      if (mounted) setState(() => _marking[entityId] = false);
      _showSnack('Could not save attendance. Please try again.', isError: true);
    }
  }

  Future<void> _confirmAbsent({
    required String entityType,
    required String entityId,
    required String entityName,
    required String markedBy,
    String? classId,
    String? role,
    String? phone,
    String? email,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Mark absent?'),
        content: Text('Mark $entityName as absent for today?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Mark Absent'),
          ),
        ],
      ),
    );
    if (result == true) {
      await _markAbsent(
        entityType: entityType,
        entityId: entityId,
        entityName: entityName,
        markedBy: markedBy,
        classId: classId,
        role: role,
        phone: phone,
        email: email,
      );
    }
  }

  String _attendanceKey(String entityType, String entityId) =>
      '${entityType}_$entityId';

  Widget _buildTodayTab(
    BuildContext context,
    AppUser currentUser,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> studentRows,
    List<AppUser> staffRows,
  ) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(top: 40),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            if (_errorMessage != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Text(_errorMessage!),
              ),
              const SizedBox(height: 16),
            ],
            _SummaryCard(
              studentCount: _studentCount,
              staffCount: _staffCount,
              totalCount: _studentCount + _staffCount,
              presentCount: _presentCount,
              absentCount: _absentCount,
              notMarkedCount: _notMarkedCount,
            ),
            const SizedBox(height: 16),
            Text(
              'Class Filter',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final doc in _classes)
                  FilterChip(
                    selected: _selectedClassIds.contains(doc.id),
                    label: Text(doc.data()['name']?.toString() ?? ''),
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _selectedClassIds.add(doc.id);
                        } else {
                          _selectedClassIds.remove(doc.id);
                        }
                      });
                      _loadData();
                    },
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Text('Students', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            if (studentRows.isEmpty)
              const Text('No students available.')
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: studentRows.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final doc = studentRows[index];
                  final data = doc.data();
                  final record =
                      _attendanceMap[_attendanceKey('student', doc.id)];
                  final status = _statusLabel(
                    record,
                    isOnApprovedLeave: _studentIdsOnLeave.contains(doc.id),
                  );
                  final photoUrl = _attendancePhotoUrl(record);
                  return _AttendanceCard(
                    name: data['name']?.toString() ?? '',
                    secondary:
                        'Admission No: ${data['admissionNo']?.toString() ?? '-'}',
                    tertiary: 'Class: ${_resolveClassName(data)}',
                    entityType: 'student',
                    status: status,
                    statusBg: _statusBg(status),
                    statusFg: _statusFg(status),
                    recordExists: record != null,
                    latestMoodLabel:
                        _latestMoodLabels[_attendanceKey('student', doc.id)],
                    photoUrl: photoUrl,
                    marking: _marking[doc.id] == true,
                    onPresent: () => _markPresent(
                      entityType: 'student',
                      entityId: doc.id,
                      entityName: data['name']?.toString() ?? '',
                      classId: data['classId']?.toString(),
                      markedBy: currentUser.id,
                    ),
                    onAbsent: () => _confirmAbsent(
                      entityType: 'student',
                      entityId: doc.id,
                      entityName: data['name']?.toString() ?? '',
                      classId: data['classId']?.toString(),
                      markedBy: currentUser.id,
                    ),
                  );
                },
              ),
            const SizedBox(height: 20),
            Text('Staff', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            if (staffRows.isEmpty)
              const Text('No staff available.')
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: staffRows.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final staff = staffRows[index];
                  final record =
                      _attendanceMap[_attendanceKey('staff', staff.id)];
                  final status = _statusLabel(
                    record,
                    isOnApprovedLeave: _staffIdsOnLeave.contains(staff.id),
                  );
                  final photoUrl = _attendancePhotoUrl(record);
                  final displayName = staff.name?.isNotEmpty == true
                      ? staff.name!
                      : staff.phone;
                  return _AttendanceCard(
                    name: displayName,
                    secondary: 'Phone/Email: ${staff.phone}',
                    tertiary: 'Role: ${staff.role}',
                    entityType: 'staff',
                    status: status,
                    statusBg: _statusBg(status),
                    statusFg: _statusFg(status),
                    recordExists: record != null,
                    latestMoodLabel:
                        _latestMoodLabels[_attendanceKey('staff', staff.id)],
                    photoUrl: photoUrl,
                    marking: _marking[staff.id] == true,
                    onPresent: () => _markPresent(
                      entityType: 'staff',
                      entityId: staff.id,
                      entityName: displayName,
                      markedBy: currentUser.id,
                      role: staff.role,
                      phone: staff.phone,
                    ),
                    onAbsent: () => _confirmAbsent(
                      entityType: 'staff',
                      entityId: staff.id,
                      entityName: displayName,
                      markedBy: currentUser.id,
                      role: staff.role,
                      phone: staff.phone,
                    ),
                  );
                },
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildHistoryTab(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final activeStudents = _allStudents
        .where((doc) => doc.data()['isActive'] == true)
        .map(
          (doc) => _HistoryRow(
            id: doc.id,
            name: doc.data()['name']?.toString() ?? '',
          ),
        )
        .toList();
    // _allStaff is already active-only (UserService.getAttendanceStaffUsers
    // filters isActive == true server-side), matching how the Today tab's
    // own Staff section is already scoped.
    final activeStaff = _allStaff
        .map(
          (user) => _HistoryRow(
            id: user.id,
            name: user.name?.isNotEmpty == true ? user.name! : user.phone,
          ),
        )
        .toList();
    if (activeStudents.isEmpty && activeStaff.isEmpty) {
      return const Center(child: Text('No attendance history available.'));
    }
    final weekEnd = _selectedHistoryWeekStart.add(const Duration(days: 6));
    final weekDays = List.generate(
      7,
      (index) => _selectedHistoryWeekStart.add(Duration(days: index)),
    );
    final dayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 40),
      children: [
        Text(
          'Attendance History',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            IconButton(
              tooltip: 'Previous week',
              onPressed: _canGoBack ? _goPreviousWeek : null,
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Text(
                '${DateFormat('dd MMM').format(_selectedHistoryWeekStart)} - ${DateFormat('dd MMM').format(weekEnd)}',
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            IconButton(
              tooltip: 'Next week',
              onPressed: _canGoNext ? _goNextWeek : null,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text('Students', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        _historyTable(
          context,
          entityType: 'student',
          entityColumnLabel: 'Student',
          rows: activeStudents,
          weekDays: weekDays,
          dayLabels: dayLabels,
          historyIdsOnLeave: _historyStudentIdsOnLeave,
          // Unprefixed — the format every existing caller/test already
          // keys off; changing it would be a silent breaking change for
          // anything addressing a student cell by key.
          keyPrefix: 'history-cell_',
          emptyMessage: 'No student attendance history available.',
        ),
        const SizedBox(height: 24),
        Text('Staff', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        _historyTable(
          context,
          entityType: 'staff',
          entityColumnLabel: 'Staff Member',
          rows: activeStaff,
          weekDays: weekDays,
          dayLabels: dayLabels,
          historyIdsOnLeave: _historyStaffIdsOnLeave,
          keyPrefix: 'history-cell-staff_',
          emptyMessage: 'No staff attendance history available.',
        ),
      ],
    );
  }

  /// One History week table — used for both Students and Staff so the two
  /// sections share exactly the same visual language (same Card, same
  /// DataTable, same day columns, same cell-resolution pipeline) instead of
  /// Staff getting a separately-designed UI. [keyPrefix] lets each
  /// section's cells carry distinct, addressable keys.
  Widget _historyTable(
    BuildContext context, {
    required String entityType,
    required String entityColumnLabel,
    required List<_HistoryRow> rows,
    required List<DateTime> weekDays,
    required List<String> dayLabels,
    required Map<String, Set<String>> historyIdsOnLeave,
    required String keyPrefix,
    required String emptyMessage,
  }) {
    if (rows.isEmpty) {
      return Text(emptyMessage, style: TextStyle(color: Colors.grey.shade600));
    }
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: [
              DataColumn(label: Text(entityColumnLabel)),
              for (var i = 0; i < weekDays.length; i++)
                DataColumn(
                  label: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(dayLabels[i]),
                      Text(
                        DateFormat('dd').format(weekDays[i]),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
            ],
            rows: rows.map((row) {
              return DataRow(
                cells: [
                  DataCell(Text(row.name)),
                  ...weekDays.map(
                    (date) => DataCell(
                      Center(
                        // Keyed so tests can locate exactly this
                        // entity/date cell — DataCell itself isn't a Widget
                        // subtype, so it can't be found via find.byType,
                        // and DataTable gives no other structural way to
                        // address one cell by column.
                        child: KeyedSubtree(
                          key: ValueKey(
                            '$keyPrefix${row.id}_${DateFormat('yyyy-MM-dd').format(date)}',
                          ),
                          child: _historyCell(
                            entityType: entityType,
                            entityId: row.id,
                            date: date,
                            historyAttendanceMap: _historyAttendanceMap,
                            historyIdsOnLeave: historyIdsOnLeave,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider);
    if (currentUser == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final searchQuery = _searchController.text.trim().toLowerCase();
    final studentRows = _students
        .where((doc) => _matchesStudent(doc, searchQuery))
        .toList();
    final staffRows = _staff
        .where((user) => _matchesStaff(user, searchQuery))
        .toList();

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadData,
          child: DefaultTabController(
            length: 2,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Attendance',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Track today’s attendance or review the last 5 weeks.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TabBar(
                    tabs: const [
                      Tab(text: 'Today'),
                      Tab(text: 'History'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _buildTodayTab(
                          context,
                          currentUser,
                          studentRows,
                          staffRows,
                        ),
                        _buildHistoryTab(context),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.studentCount,
    required this.staffCount,
    required this.totalCount,
    required this.presentCount,
    required this.absentCount,
    required this.notMarkedCount,
  });

  final int studentCount;
  final int staffCount;
  final int totalCount;
  final int presentCount;
  final int absentCount;
  final int notMarkedCount;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 24,
          runSpacing: 16,
          children: [
            _SummaryItem(label: 'Students', value: '$studentCount'),
            _SummaryItem(label: 'Staff', value: '$staffCount'),
            _SummaryItem(label: 'Total', value: '$totalCount'),
            _SummaryItem(
              label: 'Present',
              value: '$presentCount',
              color: Colors.green,
            ),
            _SummaryItem(
              label: 'Absent',
              value: '$absentCount',
              color: Colors.red,
            ),
            _SummaryItem(
              label: 'Not Marked',
              value: '$notMarkedCount',
              color: Colors.grey,
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  const _SummaryItem({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: color,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

class _AttendanceCard extends StatelessWidget {
  const _AttendanceCard({
    required this.name,
    required this.secondary,
    required this.tertiary,
    required this.entityType,
    required this.status,
    required this.statusBg,
    required this.statusFg,
    required this.onPresent,
    required this.onAbsent,
    required this.marking,
    required this.recordExists,
    required this.latestMoodLabel,
    required this.photoUrl,
  });

  final String name;
  final String secondary;
  final String tertiary;
  final String entityType;
  final String status;
  final Color statusBg;
  final Color statusFg;
  final VoidCallback onPresent;
  final VoidCallback onAbsent;
  final bool marking;
  final bool recordExists;
  final String? latestMoodLabel;
  final String photoUrl;

  void _openPhotoPreview(BuildContext context) {
    if (photoUrl.isEmpty) return;
    showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: InteractiveViewer(
            child: Image.network(
              photoUrl,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => Container(
                color: Colors.grey.shade100,
                padding: const EdgeInsets.all(24),
                child: const Text('Unable to load image'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMarked = status == 'Present' || status == 'Absent';
    final isOnLeave = status == 'On Leave';
    final moodLabel = latestMoodLabel;
    final hasPhoto = photoUrl.isNotEmpty;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    secondary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    tertiary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Text(
                        'Status:',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _StatusPill(
                        label: status,
                        background: statusBg,
                        foreground: statusFg,
                      ),
                    ],
                  ),
                  if (moodLabel != null && moodLabel.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _MoodPill(label: moodLabel),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 96,
              child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (hasPhoto) ...[
                  GestureDetector(
                    onTap: () => _openPhotoPreview(context),
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.grey.shade200),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Image.network(
                        photoUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Container(
                          color: Colors.grey.shade100,
                          alignment: Alignment.center,
                          child: const Icon(Icons.broken_image_outlined),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: [
                    if (marking)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else ...[
                      Tooltip(
                        message: isMarked
                            ? 'Attendance marked'
                            : 'Mark Present — photo + mood check-in required',
                        child: Material(
                          color: Colors.green,
                          shape: const CircleBorder(),
                          child: IconButton(
                            onPressed: recordExists && status != 'Absent'
                                ? null
                                : onPresent,
                            icon: isMarked
                                ? const Icon(Icons.check)
                                : const Icon(Icons.camera_alt),
                            color: Colors.white,
                          ),
                        ),
                      ),
                      Tooltip(
                        message: isOnLeave
                            ? (entityType == 'staff'
                                ? 'This staff member is on approved leave for this date.'
                                : 'On approved leave — cannot mark absent')
                            : 'Mark absent',
                        child: Material(
                          color: Colors.red.shade500,
                          shape: const CircleBorder(),
                          child: IconButton(
                            onPressed: (status == 'Absent' || isOnLeave)
                                ? null
                                : onAbsent,
                            icon: const Icon(Icons.person_off),
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (!isMarked && !marking) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Photo + mood required',
                    textAlign: TextAlign.right,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                ],
              ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(color: foreground, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _MoodPill extends StatelessWidget {
  const _MoodPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: Colors.blue.shade700,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Compact History-cell indicator for a date with no attendance record but
/// an Approved Student Leave covering it. Reuses the exact same blue pair
/// (`Colors.blue.shade50`/`Colors.blue.shade700`) as the Today tab's "On
/// Leave" status pill, sized down to fit the narrow History date cells —
/// the table's own horizontal scroll (see `_buildHistoryTab`) already
/// accommodates a slightly wider column the same way it does for long
/// student names, so this never overflows.
class _HistoryOnLeavePill extends StatelessWidget {
  const _HistoryOnLeavePill();

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'On Leave',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          'On Leave',
          style: TextStyle(
            color: Colors.blue.shade700,
            fontWeight: FontWeight.w600,
            fontSize: 10,
          ),
        ),
      ),
    );
  }
}

/// A single row in a History table — one entity (student or staff) and its
/// display name. Shared between the Students and Staff History sections
/// (see [_historyTable]) rather than duplicated per entity type.
class _HistoryRow {
  _HistoryRow({required this.id, required this.name});

  final String id;
  final String name;
}
