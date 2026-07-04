import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../attendance/providers/attendance_provider.dart';
import '../../auth/data/user_service.dart';
import '../../auth/models/app_user.dart';
import '../../auth/providers/auth_provider.dart';
import '../../classes/providers/class_provider.dart';
import '../../students/providers/student_provider.dart';
import 'admin_layout.dart';

class AdminAttendanceManagementScreen extends ConsumerStatefulWidget {
  const AdminAttendanceManagementScreen({super.key});

  @override
  ConsumerState<AdminAttendanceManagementScreen> createState() =>
      _AdminAttendanceManagementScreenState();
}

class _AdminAttendanceManagementScreenState
    extends ConsumerState<AdminAttendanceManagementScreen> {
  DateTime _selectedDate = DateTime.now().toLocal();
  bool _loading = true;
  String? _errorMessage;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _students = [];
  List<AppUser> _staff = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _classes = [];
  Map<String, Map<String, dynamic>> _attendanceMap = {};
  final Set<String> _selectedClassIds = {};
  final Map<String, String> _draftStatuses = {};
  String _selectedScope = 'student';

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now().toLocal();
    _loadData();
  }

  DateTime get _academicYearStart =>
      ref.read(attendanceServiceProvider).getAcademicYearStart(DateTime.now());

  String _dateKey(DateTime date) =>
      ref.read(attendanceServiceProvider).dateKeyFor(date);

  String _recordKey(String entityType, String entityId) =>
      '${entityType}_$entityId';

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      final attendanceService = ref.read(attendanceServiceProvider);
      final studentService = ref.read(studentServiceProvider);
      final classService = ref.read(classServiceProvider);
      final userService = UserService();

      final classes = await classService.getClasses();
      final students = await studentService.getAllStudents();
      final staff = await userService.getAttendanceStaffUsers();
      final attendanceMap = await attendanceService.getAttendanceByDate(
        date: _selectedDate,
      );

      final draft = <String, String>{};
      for (final student in students) {
        final record = attendanceMap[_recordKey('student', student.id)];
        draft[student.id] =
            (record?['status']?.toString().toLowerCase() ?? '').isEmpty
            ? 'not_marked'
            : record!['status'].toString().toLowerCase();
      }
      for (final user in staff) {
        final record = attendanceMap[_recordKey('staff', user.id)];
        draft[user.id] =
            (record?['status']?.toString().toLowerCase() ?? '').isEmpty
            ? 'not_marked'
            : record!['status'].toString().toLowerCase();
      }

      if (!mounted) return;
      setState(() {
        _classes = classes;
        _students = students;
        _staff = staff;
        _attendanceMap = attendanceMap;
        _draftStatuses
          ..clear()
          ..addAll(draft);
      });
    } catch (e) {
      if (mounted) setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: _academicYearStart,
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    setState(() => _selectedDate = picked);
    await _loadData();
  }

  String _classNameFor(Map<String, dynamic> data) {
    final classId = data['classId']?.toString() ?? '';
    if (classId.isEmpty || _classes.isEmpty) return '-';
    final matches = _classes.where((doc) => doc.id == classId);
    if (matches.isEmpty) return '-';
    return matches.first.data()['name']?.toString() ?? '-';
  }

  bool get _canSave => _draftStatuses.isNotEmpty;

  Future<void> _saveAll() async {
    final currentUser = ref.read(currentUserProvider);
    if (currentUser == null) return;
    final attendanceService = ref.read(attendanceServiceProvider);
    final selectedClassIds = _selectedClassIds.isEmpty
        ? null
        : _selectedClassIds;

    Future<void> saveEntity({
      required String entityType,
      required String entityId,
      required String entityName,
      required String classId,
    }) async {
      final status = _draftStatuses[entityId] ?? 'not_marked';
      if (status == 'not_marked') {
        await attendanceService.clearAdminAttendance(
          entityType: entityType,
          entityId: entityId,
          selectedDate: _selectedDate,
        );
        return;
      }

      await attendanceService.saveAdminAttendance(
        entityType: entityType,
        entityId: entityId,
        entityName: entityName,
        classId: classId,
        status: status,
        selectedDate: _selectedDate,
        markedBy: currentUser.id,
      );
    }

    final students = _students.where((doc) {
      if (selectedClassIds == null) return true;
      return selectedClassIds.contains(doc.data()['classId']?.toString() ?? '');
    }).toList();

    final staff = _staff.where((user) {
      if (selectedClassIds == null) return true;
      return true;
    }).toList();

    for (final student in students) {
      await saveEntity(
        entityType: 'student',
        entityId: student.id,
        entityName: student.data()['name']?.toString() ?? '',
        classId: student.data()['classId']?.toString() ?? '',
      );
    }

    for (final user in staff) {
      await saveEntity(
        entityType: 'staff',
        entityId: user.id,
        entityName: user.name ?? user.phone,
        classId: '',
      );
    }

    await _loadData();
  }

  Widget _statusButtons(String entityId) {
    final status = _draftStatuses[entityId] ?? 'not_marked';
    return Wrap(
      spacing: 8,
      children: [
        TextButton(
          onPressed: () => setState(() => _draftStatuses[entityId] = 'present'),
          style: TextButton.styleFrom(
            foregroundColor: status == 'present' ? Colors.white : Colors.green,
            backgroundColor: status == 'present'
                ? Colors.green
                : Colors.green.shade50,
          ),
          child: const Text('Present'),
        ),
        TextButton(
          onPressed: () => setState(() => _draftStatuses[entityId] = 'absent'),
          style: TextButton.styleFrom(
            foregroundColor: status == 'absent' ? Colors.white : Colors.red,
            backgroundColor: status == 'absent'
                ? Colors.red
                : Colors.red.shade50,
          ),
          child: const Text('Absent'),
        ),
        TextButton(
          onPressed: () =>
              setState(() => _draftStatuses[entityId] = 'not_marked'),
          style: TextButton.styleFrom(
            foregroundColor: status == 'not_marked'
                ? Colors.white
                : Colors.grey,
            backgroundColor: status == 'not_marked'
                ? Colors.grey
                : Colors.grey.shade200,
          ),
          child: const Text('Clear'),
        ),
      ],
    );
  }

  Widget _buildBody(BuildContext context) {
    final filteredStudents = _students.where((doc) {
      if (_selectedClassIds.isEmpty) return true;
      return _selectedClassIds.contains(
        doc.data()['classId']?.toString() ?? '',
      );
    }).toList();

    final filteredStaff = _staff;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Backdated Attendance',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          'Create or edit attendance for previous dates.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.calendar_month),
            label: Text(_dateKey(_selectedDate)),
          ),
        ),
        const SizedBox(height: 16),
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
                },
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (_errorMessage != null) ...[
          Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
          const SizedBox(height: 12),
        ],
        if (_loading)
          const Center(child: CircularProgressIndicator())
        else ...[
          Row(
            children: [
              ChoiceChip(
                label: const Text('Students'),
                selected: _selectedScope == 'student',
                onSelected: (_) => setState(() => _selectedScope = 'student'),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Staff'),
                selected: _selectedScope == 'staff',
                onSelected: (_) => setState(() => _selectedScope = 'staff'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_selectedScope == 'student')
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: filteredStudents.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final student = filteredStudents[index];
                final data = student.data();
                final status =
                    _draftStatuses[student.id] ??
                    (_attendanceMap[_recordKey(
                              'student',
                              student.id,
                            )]?['status']
                            ?.toString()
                            .toLowerCase() ??
                        'not_marked');
                return Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          data['name']?.toString() ?? '',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Admission No: ${data['admissionNo']?.toString() ?? '-'}',
                        ),
                        Text('Class: ${_classNameFor(data)}'),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Text('Current Status: '),
                            Text(
                              status,
                              style: TextStyle(
                                color: status == 'present'
                                    ? Colors.green
                                    : status == 'absent'
                                    ? Colors.red
                                    : Colors.grey,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _statusButtons(student.id),
                      ],
                    ),
                  ),
                );
              },
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: filteredStaff.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final user = filteredStaff[index];
                final status =
                    _draftStatuses[user.id] ??
                    (_attendanceMap[_recordKey('staff', user.id)]?['status']
                            ?.toString()
                            .toLowerCase() ??
                        'not_marked');
                return Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.name ?? user.phone,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text('Phone: ${user.phone}'),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Text('Current Status: '),
                            Text(
                              status,
                              style: TextStyle(
                                color: status == 'present'
                                    ? Colors.green
                                    : status == 'absent'
                                    ? Colors.red
                                    : Colors.grey,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _statusButtons(user.id),
                      ],
                    ),
                  ),
                );
              },
            ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _canSave ? _saveAll : null,
            child: const Text('Save'),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AdminLayout(
      selectedIndex: 8,
      title: 'Attendance',
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(child: _buildBody(context)),
      ),
    );
  }
}
