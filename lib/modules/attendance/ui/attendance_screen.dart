import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/user_service.dart';
import '../../auth/models/app_user.dart';
import '../../auth/providers/auth_provider.dart';
import '../../classes/providers/class_provider.dart';
import '../../students/providers/student_provider.dart';
import '../providers/attendance_provider.dart';

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
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _students = [];
  List<AppUser> _staff = [];
  Map<String, Map<String, dynamic>> _attendanceMap = {};
  Map<String, String> _classNames = {};
  int _studentCount = 0;
  int _staffCount = 0;
  int _presentCount = 0;
  int _absentCount = 0;
  int _notMarkedCount = 0;
  final Map<String, bool> _marking = {};

  @override
  void initState() {
    super.initState();
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

      final classes = await classService.getClasses();
      final allStudents = await studentService.getAllStudents();
      final staff = await userService.getStaffUsers();
      final attendanceMap = await attendanceService.getTodayAttendanceMap();
      final overview = await attendanceService.getAttendanceOverview(
        classIds: _selectedClassIds.toList(),
      );
      final notMarked = await attendanceService.getNotMarkedCount(
        classIds: _selectedClassIds.toList(),
      );

      final classNames = <String, String>{
        for (final doc in classes) doc.id: doc.data()['name']?.toString() ?? '-',
      };
      final visibleStudents = allStudents.where((doc) {
        final data = doc.data();
        if (data['isActive'] != true) return false;
        if (_selectedClassIds.isNotEmpty &&
            !_selectedClassIds.contains(data['classId']?.toString() ?? '')) {
          return false;
        }
        return _matchesStudent(doc, _searchController.text.trim().toLowerCase());
      }).toList();
      final filteredStaff = staff
          .where((user) => _matchesStaff(user, _searchController.text.trim().toLowerCase()))
          .toList();

      if (!mounted) return;
      setState(() {
        _classes = classes;
        _students = visibleStudents;
        _staff = filteredStaff;
        _attendanceMap = attendanceMap;
        _classNames = classNames;
        _studentCount = overview.studentCount;
        _staffCount = overview.staffCount;
        _presentCount = overview.presentCount;
        _absentCount = overview.absentCount;
        _notMarkedCount = notMarked;
      });
    } catch (e) {
      if (mounted) setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _matchesStudent(QueryDocumentSnapshot<Map<String, dynamic>> doc, String query) {
    if (query.isEmpty) return true;
    final data = doc.data();
    final name = data['name']?.toString().toLowerCase() ?? '';
    final admissionNo = data['admissionNo']?.toString().toLowerCase() ?? '';
    final className = _resolveClassName(data).toLowerCase();
    return name.contains(query) || admissionNo.contains(query) || className.contains(query);
  }

  bool _matchesStaff(AppUser user, String query) {
    if (query.isEmpty) return true;
    final name = (user.name ?? '').toLowerCase();
    final phone = user.phone.toLowerCase();
    final role = user.role.toLowerCase();
    return name.contains(query) || phone.contains(query) || role.contains(query);
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
    final hasPhoto = (record['photoUrl']?.toString() ?? '').isNotEmpty;
    if (status == 'absent') return 'Absent';
    if (status == 'present' || (status.isEmpty && hasPhoto)) return 'Present';
    return 'Not Marked';
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
  }) async {
    final service = ref.read(attendanceServiceProvider);
    setState(() => _marking[entityId] = true);
    try {
      final photoUrl = await service.captureAndUploadPhoto(
        entityType: entityType,
        entityId: entityId,
      );
      if (photoUrl == null) return;
      await service.markPresent(
        entityType: entityType,
        entityId: entityId,
        entityName: entityName,
        classId: classId,
        markedBy: markedBy,
        photoUrl: photoUrl,
      );
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Attendance marked')),
        );
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
      );
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Attendance marked')),
        );
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
      );
    }
  }

  String _attendanceKey(String entityType, String entityId) => '${entityType}_$entityId';

  void _openAddAttendanceFlow() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Use the row actions below to add attendance')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider);
    if (currentUser == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final searchQuery = _searchController.text.trim().toLowerCase();
    final studentRows = _students.where((doc) => _matchesStudent(doc, searchQuery)).toList();
    final staffRows = _staff.where((user) => _matchesStaff(user, searchQuery)).toList();

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadData,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'Today\'s Attendance Overview',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                    Material(
                      color: Colors.green,
                      shape: const CircleBorder(),
                      child: Tooltip(
                        message: 'Add Attendance',
                        child: IconButton(
                          onPressed: _openAddAttendanceFlow,
                          icon: const Icon(Icons.add),
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Mark students and staff directly from the lists below.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey.shade600,
                      ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    labelText: 'Search students or staff',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 16),
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
                if (_loading)
                  const Center(child: CircularProgressIndicator())
                else ...[
                  _SummaryCard(
                    studentCount: _studentCount,
                    staffCount: _staffCount,
                    totalCount: _studentCount + _staffCount,
                    presentCount: _presentCount,
                    absentCount: _absentCount,
                    notMarkedCount: _notMarkedCount,
                  ),
                  const SizedBox(height: 16),
                  Text('Class Filter', style: Theme.of(context).textTheme.titleMedium),
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
                      separatorBuilder: (context, index) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final doc = studentRows[index];
                        final data = doc.data();
                        final record = _attendanceMap[_attendanceKey('student', doc.id)];
                        final status = _statusLabel(record);
                        return _AttendanceCard(
                          name: data['name']?.toString() ?? '',
                          secondary: 'Admission No: ${data['admissionNo']?.toString() ?? '-'}',
                          tertiary: 'Class: ${_resolveClassName(data)}',
                          status: status,
                          statusBg: _statusBg(status),
                          statusFg: _statusFg(status),
                          recordExists: record != null,
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
                      separatorBuilder: (context, index) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final staff = staffRows[index];
                        final record = _attendanceMap[_attendanceKey('staff', staff.id)];
                        final status = _statusLabel(record);
                        final displayName = staff.name?.isNotEmpty == true ? staff.name! : staff.phone;
                        return _AttendanceCard(
                          name: displayName,
                          secondary: 'Phone/Email: ${staff.phone}',
                          tertiary: 'Role: ${staff.role}',
                          status: status,
                          statusBg: _statusBg(status),
                          statusFg: _statusFg(status),
                          recordExists: record != null,
                          marking: _marking[staff.id] == true,
                          onPresent: () => _markPresent(
                            entityType: 'staff',
                            entityId: staff.id,
                            entityName: displayName,
                            markedBy: currentUser.id,
                          ),
                          onAbsent: () => _confirmAbsent(
                            entityType: 'staff',
                            entityId: staff.id,
                            entityName: displayName,
                            markedBy: currentUser.id,
                          ),
                        );
                      },
                    ),
                ],
              ],
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
            _SummaryItem(label: 'Present', value: '$presentCount', color: Colors.green),
            _SummaryItem(label: 'Absent', value: '$absentCount', color: Colors.red),
            _SummaryItem(label: 'Not Marked', value: '$notMarkedCount', color: Colors.grey),
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
    required this.status,
    required this.statusBg,
    required this.statusFg,
    required this.onPresent,
    required this.onAbsent,
    required this.marking,
    required this.recordExists,
  });

  final String name;
  final String secondary;
  final String tertiary;
  final String status;
  final Color statusBg;
  final Color statusFg;
  final VoidCallback onPresent;
  final VoidCallback onAbsent;
  final bool marking;
  final bool recordExists;

  @override
  Widget build(BuildContext context) {
    final isMarked = status == 'Present' || status == 'Absent';
    return Card(
      elevation: 0,
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
                  Text(secondary, style: Theme.of(context).textTheme.bodyMedium),
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
                      _StatusPill(label: status, background: statusBg, foreground: statusFg),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
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
                    message: isMarked ? 'Attendance marked' : 'Mark present with photo',
                    child: Material(
                      color: Colors.green,
                      shape: const CircleBorder(),
                      child: IconButton(
                        onPressed: recordExists && status != 'Absent' ? null : onPresent,
                        icon: isMarked ? const Icon(Icons.check) : const Icon(Icons.camera_alt),
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
        style: TextStyle(
          color: foreground,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
