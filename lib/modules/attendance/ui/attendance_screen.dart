import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../auth/data/user_service.dart';
import '../../auth/models/app_user.dart';
import '../../auth/providers/auth_provider.dart';
import '../../classes/providers/class_provider.dart';
import '../../mood_checkin/providers/mood_checkin_provider.dart';
import '../../mood_checkin/ui/mood_checkin_dialog.dart';
import '../../mood_checkin/services/mood_checkin_service.dart';
import '../../students/providers/student_provider.dart';
import '../providers/attendance_provider.dart';

DateTime getAcademicYearStart(DateTime today) {
  if (today.month >= 6) {
    return DateTime(today.year, 6, 1);
  }
  return DateTime(today.year - 1, 6, 1);
}

class AttendanceScreen extends ConsumerStatefulWidget {
  const AttendanceScreen({super.key});

  @override
  ConsumerState<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends ConsumerState<AttendanceScreen> {
  bool _loading = true;
  String? _errorMessage;
  final _searchController = TextEditingController();
  final Set<String> _selectedClassIds = {};
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _classes = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _allStudents = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _students = [];
  List<AppUser> _staff = [];
  Map<String, Map<String, dynamic>> _attendanceMap = {};
  Map<String, Map<String, dynamic>> _historyAttendanceMap = {};
  late DateTime _selectedHistoryWeekStart;
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
      final userService = UserService();
      final attendanceService = ref.read(attendanceServiceProvider);
      final moodService = ref.read(moodCheckinServiceProvider);

      final classes = await classService.getClasses();
      final allStudents = await studentService.getAllStudents();
      final staff = await userService.getAttendanceStaffUsers();
      final attendanceMap = await attendanceService.getTodayAttendanceMap();
      final historyAttendanceMap = await attendanceService
          .getAttendanceHistoryMap(
            startDate: _selectedHistoryWeekStart,
            endDate: _selectedHistoryWeekStart.add(const Duration(days: 6)),
          );
      final overview = await attendanceService.getAttendanceOverview(
        classIds: _selectedClassIds.toList(),
      );
      final notMarked = await attendanceService.getNotMarkedCount(
        classIds: _selectedClassIds.toList(),
      );
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

      if (!mounted) return;
      setState(() {
        _classes = classes;
        _allStudents = allStudents;
        _students = visibleStudents;
        _staff = filteredStaff;
        _attendanceMap = attendanceMap;
        _historyAttendanceMap = historyAttendanceMap;
        _classNames = classNames;
        _studentCount = overview.studentCount;
        _staffCount = overview.staffCount;
        _presentCount = overview.presentCount;
        _absentCount = overview.absentCount;
        _notMarkedCount = notMarked;
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

  String _statusLabel(Map<String, dynamic>? record) {
    if (record == null) return 'Not Marked';
    final status = (record['status']?.toString() ?? '').toLowerCase();
    final hasPhoto = _attendancePhotoUrl(record).isNotEmpty;
    if (status == 'absent') return 'Absent';
    if (status == 'present' || (status.isEmpty && hasPhoto)) return 'Present';
    return 'Not Marked';
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

  DateTime get _academicYearStart =>
      getAcademicYearStart(DateTime.now().toLocal());

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

  Widget _historyCell(
    String studentId,
    DateTime date,
    Map<String, Map<String, dynamic>> historyAttendanceMap,
  ) {
    final dateKey = DateFormat('yyyy-MM-dd').format(date);
    final record = historyAttendanceMap['student_${studentId}_$dateKey'];
    if (record == null) {
      return Text('-', style: TextStyle(color: Colors.grey.shade600));
    }
    final status = (record['status']?.toString() ?? '').toLowerCase();
    final hasPhoto = _attendancePhotoUrl(record).isNotEmpty;
    if (status == 'present' || (status.isEmpty && hasPhoto)) {
      return const Icon(Icons.check_circle, color: Colors.green, size: 20);
    }
    if (status == 'absent') {
      return const Icon(Icons.cancel, color: Colors.red, size: 20);
    }
    return Text('-', style: TextStyle(color: Colors.grey.shade600));
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
      default:
        return Colors.grey.shade700;
    }
  }

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
    try {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Uploading photo...')));
      final photoUrl = await service.captureAndUploadPhoto(
        entityType: entityType,
        entityId: entityId,
      );
      if (photoUrl == null || !mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Saving attendance...')));
      final attendanceId = await service.markPresent(
        entityType: entityType,
        entityId: entityId,
        entityName: entityName,
        classId: classId,
        markedBy: markedBy,
        photoUrl: photoUrl,
        role: role,
        phone: phone,
        email: email,
      );
      if (mounted) {
        setState(() {
          _attendanceMap[_attendanceKey(entityType, entityId)] = {
            'entityType': entityType,
            'entityId': entityId,
            'entityName': entityName,
            'classId': classId ?? '',
            'date': DateTime.now().toLocal().toIso8601String().split('T').first,
            'photoUrl': photoUrl,
            'markedBy': markedBy,
            'status': 'present',
            'role': role,
            'phone': phone,
            'email': email,
          };
        });
      }
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Saving mood check-in...')));
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
        photoUrl: photoUrl,
        createdBy: markedBy,
      );
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Attendance marked')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to mark attendance: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _marking[entityId] = false);
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
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Attendance marked')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to mark attendance: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _marking[entityId] = false);
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
                  final status = _statusLabel(record);
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
                  final status = _statusLabel(record);
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
          (doc) => _HistoryStudentRow(
            id: doc.id,
            name: doc.data()['name']?.toString() ?? '',
          ),
        )
        .toList();
    if (activeStudents.isEmpty) {
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
      children: [
        Text(
          'Attendance History',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton.icon(
              onPressed: _canGoBack ? _goPreviousWeek : null,
              icon: const Icon(Icons.chevron_left),
              label: const Text('Back'),
            ),
            Text(
              '${DateFormat('dd MMM').format(_selectedHistoryWeekStart)} - ${DateFormat('dd MMM').format(weekEnd)}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            TextButton.icon(
              onPressed: _canGoNext ? _goNextWeek : null,
              icon: const Icon(Icons.chevron_right),
              label: const Text('Next'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Card(
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
                  const DataColumn(label: Text('Student')),
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
                rows: activeStudents.map((student) {
                  return DataRow(
                    cells: [
                      DataCell(Text(student.name)),
                      ...weekDays.map(
                        (date) => DataCell(
                          Center(
                            child: _historyCell(
                              student.id,
                              date,
                              _historyAttendanceMap,
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
        ),
      ],
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
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
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
                  Text(name, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    secondary,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(tertiary, style: Theme.of(context).textTheme.bodyMedium),
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
            Column(
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
                            : 'Mark present with photo',
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
                        message: 'Mark absent',
                        child: Material(
                          color: Colors.red.shade500,
                          shape: const CircleBorder(),
                          child: IconButton(
                            onPressed: status == 'Absent' ? null : onAbsent,
                            icon: const Icon(Icons.person_off),
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
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

class _HistoryStudentRow {
  _HistoryStudentRow({required this.id, required this.name});

  final String id;
  final String name;
}
