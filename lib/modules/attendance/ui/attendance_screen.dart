import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/providers/auth_provider.dart';
import '../../auth/data/user_service.dart';
import '../../auth/models/app_user.dart';
import '../../classes/providers/class_provider.dart';
import '../../students/providers/student_provider.dart';
import '../providers/attendance_provider.dart';

class AttendanceScreen extends ConsumerStatefulWidget {
  const AttendanceScreen({super.key});

  @override
  ConsumerState<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends ConsumerState<AttendanceScreen> {
  bool _isLoading = false;
  String? _errorMessage;
  bool isMarkMode = false;
  String _captureEntityType = 'students';

  final Set<String> _selectedClassIds = {};
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _todayRecords = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _classes = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _students = [];
  List<AppUser> _staff = [];
  Map<String, Map<String, dynamic>> _attendanceMap = {};
  int _overviewStudentCount = 0;
  int _overviewStaffCount = 0;
  int _overviewTotalCount = 0;
  int _overviewPresentCount = 0;
  int _overviewAbsentCount = 0;
  final Map<String, bool> _loadingMap = {};

  @override
  void initState() {
    super.initState();
    _loadClasses();
    _loadOverview();
  }

  String _todayKey() {
    final now = DateTime.now().toLocal();
    return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  Future<void> _loadOverview() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final service = ref.read(attendanceServiceProvider);
      final studentService = ref.read(studentServiceProvider);
      final userService = UserService();
      final attendanceMap = await service.getTodayAttendanceMap();
      final records = await service.filterByClasses(
        classIds: _selectedClassIds.toList(),
      );
      final students = _selectedClassIds.isEmpty
          ? await studentService.getAllStudents()
          : await Future.wait(
              _selectedClassIds.map(studentService.getStudentsByClass),
            ).then((lists) => lists.expand((x) => x).toList());
      final staff = await userService.getStaffUsers();
      if (!mounted) return;
      setState(() {
        _todayRecords = records;
        _attendanceMap = attendanceMap;
        _overviewStudentCount = students.length;
        _overviewStaffCount = staff.length;
        _overviewPresentCount = records
            .where(
              (record) =>
                  (record['status']?.toString() ?? '').toLowerCase() ==
                  'present',
            )
            .length;
        _overviewTotalCount = students.length + staff.length;
        _overviewAbsentCount = _overviewTotalCount - _overviewPresentCount;
      });
      // ignore: avoid_print
      print('Attendance count: ${records.length}');
    } catch (e) {
      // ignore: avoid_print
      print(e);
      if (mounted) {
        setState(() => _errorMessage = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadClasses() async {
    final classService = ref.read(classServiceProvider);
    final snap = await classService.getAllClasses();
    if (!mounted) return;
    setState(() => _classes = snap);
  }

  Future<void> _loadCaptureData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final attendanceService = ref.read(attendanceServiceProvider);
      _attendanceMap = await attendanceService.getTodayAttendanceMap();
      if (_captureEntityType == 'students') {
        if (_selectedClassIds.isEmpty) {
          _students = [];
        } else {
          final studentService = ref.read(studentServiceProvider);
          final studentsByClass = await Future.wait(
            _selectedClassIds.map(studentService.getStudentsByClass),
          ).then((lists) => lists.expand((x) => x).toList());
          final seen = <String>{};
          _students = studentsByClass.where((doc) => seen.add(doc.id)).toList();
        }
      } else {
        final userService = UserService();
        _staff = await userService.getStaffUsers();
      }
      await _loadOverview();
    } catch (e) {
      // ignore: avoid_print
      print(e);
      if (mounted) setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleCaptureMode() async {
    setState(() {
      isMarkMode = !isMarkMode;
      _errorMessage = null;
      if (!isMarkMode) {
        _students = [];
        _staff = [];
      }
    });
    if (isMarkMode) {
      await _loadCaptureData();
    } else {
      await _loadOverview();
    }
  }

  Future<void> _captureStudentAttendance(
    BuildContext context,
    String studentId,
    Map<String, dynamic> data,
  ) async {
    final service = ref.read(attendanceServiceProvider);
    setState(() => _loadingMap[studentId] = true);
    try {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Uploading photo...')));
      final url = await service.captureAndUploadPhoto(
        entityType: 'student',
        entityId: studentId,
      );
      if (url == null) return;

      await service.markStudentAttendance(
        studentId: studentId,
        studentName: data['name']?.toString() ?? '',
        classId: data['classId']?.toString() ?? '',
        markedBy: ref.read(currentUserProvider)!.id,
        photoUrl: url,
        status: 'present',
      );
      await _loadCaptureData();
      await _loadOverview();
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Attendance marked')));
    } catch (e) {
      // ignore: avoid_print
      print(e);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Upload failed')));
      }
    } finally {
      if (mounted) setState(() => _loadingMap[studentId] = false);
    }
  }

  Future<void> _captureStaffAttendance(
    BuildContext context,
    AppUser staff,
  ) async {
    final service = ref.read(attendanceServiceProvider);
    setState(() => _loadingMap[staff.id] = true);
    try {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Uploading photo...')));
      final url = await service.captureAndUploadPhoto(
        entityType: 'staff',
        entityId: staff.id,
      );
      if (url == null) return;

      await service.markStaffAttendance(
        staffId: staff.id,
        staffName: staff.name?.isNotEmpty == true ? staff.name! : staff.phone,
        markedBy: ref.read(currentUserProvider)!.id,
        photoUrl: url,
        status: 'present',
      );
      await _loadCaptureData();
      await _loadOverview();
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Attendance marked')));
    } catch (e) {
      // ignore: avoid_print
      print(e);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Upload failed')));
      }
    } finally {
      if (mounted) setState(() => _loadingMap[staff.id] = false);
    }
  }

  Future<void> _toggleStatus({
    required String entityId,
    required String entityType,
    required String status,
  }) async {
    final service = ref.read(attendanceServiceProvider);
    setState(() => _loadingMap[entityId] = true);
    try {
      await service.updateAttendanceStatus(
        entityId: entityId,
        date: _todayKey(),
        status: status,
        entityType: entityType,
      );
      await _loadCaptureData();
      await _loadOverview();
    } catch (e) {
      // ignore: avoid_print
      print(e);
    } finally {
      if (mounted) setState(() => _loadingMap[entityId] = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider);

    if (currentUser == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Today\'s Attendance Overview',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isMarkMode
                          ? 'Mark attendance for students or staff.'
                          : 'View today\'s records and switch to marking when needed.',
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              _ScreenActionButton(
                onPressed: _toggleCaptureMode,
                icon: isMarkMode ? Icons.check : Icons.add,
              ),
            ],
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
              child: Text(
                _errorMessage!,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.red.shade700),
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (!isMarkMode) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final doc in _classes)
                  FilterChip(
                    selected: _selectedClassIds.contains(doc.id),
                    label: Text(doc.data()['name']?.toString() ?? ''),
                    onSelected: (selected) async {
                      setState(() {
                        if (selected) {
                          _selectedClassIds.add(doc.id);
                        } else {
                          _selectedClassIds.remove(doc.id);
                        }
                      });
                      await _loadOverview();
                    },
                  ),
              ],
            ),
            const SizedBox(height: 16),
            _SummaryCard(
              total: _overviewTotalCount,
              present: _overviewPresentCount,
              absent: _overviewAbsentCount,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  'Students: $_overviewStudentCount',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
                ),
                const SizedBox(width: 16),
                Text(
                  'Staff: $_overviewStaffCount',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _todayRecords.isEmpty
                  ? const Center(child: Text('No attendance recorded today'))
                  : ListView.separated(
                      itemCount: _todayRecords.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final doc = _todayRecords[index];
                        final data = doc.data();
                        final photoUrl = data['photoUrl']?.toString();
                        final name = data['entityName']?.toString() ?? '';
                        final entityType = data['entityType']?.toString() ?? '';
                        final status = (data['status']?.toString() ?? 'present')
                            .toLowerCase();
                        final typeLabel = entityType == 'staff'
                            ? 'Staff'
                            : 'Student';
                        return Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundImage:
                                  (photoUrl != null && photoUrl.isNotEmpty)
                                  ? NetworkImage(photoUrl)
                                  : null,
                              child: (photoUrl == null || photoUrl.isEmpty)
                                  ? Text(
                                      name.isNotEmpty
                                          ? name[0].toUpperCase()
                                          : '?',
                                    )
                                  : null,
                            ),
                            title: Text(name),
                            subtitle: Row(
                              children: [
                                _Pill(label: typeLabel, color: Colors.blueGrey),
                                const SizedBox(width: 8),
                                _Pill(
                                  label: status == 'absent'
                                      ? 'Absent'
                                      : 'Present',
                                  color: status == 'absent'
                                      ? Colors.red
                                      : Colors.green,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ] else ...[
            _EntityToggle(
              currentValue: _captureEntityType,
              onChanged: (value) async {
                setState(() => _captureEntityType = value);
                await _loadCaptureData();
              },
            ),
            const SizedBox(height: 16),
            if (_captureEntityType == 'students') ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Select Class',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const SizedBox(height: 8),
              if (_classes.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'No classes available. Please create a class first.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey.shade600,
                    ),
                  ),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final doc in _classes)
                      FilterChip(
                        selected: _selectedClassIds.contains(doc.id),
                        label: Text(doc.data()['name']?.toString() ?? ''),
                        onSelected: (selected) async {
                          setState(() {
                            if (selected) {
                              _selectedClassIds.add(doc.id);
                            } else {
                              _selectedClassIds.remove(doc.id);
                            }
                          });
                          await _loadCaptureData();
                        },
                      ),
                  ],
                ),
              const SizedBox(height: 16),
            ],
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _captureEntityType == 'students'
                  ? _selectedClassIds.isEmpty
                        ? Center(
                            child: Text(
                              'Select one or more classes to begin attendance',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(color: Colors.grey.shade600),
                            ),
                          )
                        : _students.isEmpty
                        ? const Center(child: Text('No students found'))
                        : ListView.separated(
                            itemCount: _students.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final doc = _students[index];
                              return _CaptureRow(
                                doc: doc,
                                loadingMap: _loadingMap,
                                attendanceMap: _attendanceMap,
                                onCapture: (context, id, data) =>
                                    _captureStudentAttendance(
                                      context,
                                      id,
                                      data,
                                    ),
                                onToggleStatus: _toggleStatus,
                              );
                            },
                          )
                  : _staff.isEmpty
                  ? const Center(child: Text('No staff found'))
                  : ListView.separated(
                      itemCount: _staff.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final staff = _staff[index];
                        return _StaffCaptureRow(
                          staff: staff,
                          loadingMap: _loadingMap,
                          attendanceMap: _attendanceMap,
                          onCapture: (context, staff) =>
                              _captureStaffAttendance(context, staff),
                          onToggleStatus: _toggleStatus,
                        );
                      },
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  const _SummaryItem({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.total,
    required this.present,
    required this.absent,
  });

  final int total;
  final int present;
  final int absent;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: _SummaryItem(label: 'Total', value: '$total'),
            ),
            Expanded(
              child: _SummaryItem(
                label: 'Present',
                value: '$present',
                valueColor: Colors.green,
              ),
            ),
            Expanded(
              child: _SummaryItem(
                label: 'Absent',
                value: '$absent',
                valueColor: Colors.red,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 12),
      ),
    );
  }
}

class _ScreenActionButton extends StatelessWidget {
  const _ScreenActionButton({required this.onPressed, required this.icon});

  final VoidCallback onPressed;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.green,
      shape: const CircleBorder(),
      elevation: 2,
      shadowColor: Colors.black26,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon),
        iconSize: 22,
        color: Colors.white,
        constraints: const BoxConstraints.tightFor(width: 48, height: 48),
        style: IconButton.styleFrom(
          backgroundColor: Colors.green,
          shape: const CircleBorder(),
        ),
      ),
    );
  }
}

class _EntityToggle extends StatelessWidget {
  const _EntityToggle({required this.currentValue, required this.onChanged});

  final String currentValue;
  final Future<void> Function(String value) onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ChoiceChip(
          label: const Text('Students'),
          selected: currentValue == 'students',
          onSelected: (_) => onChanged('students'),
        ),
        const SizedBox(width: 8),
        ChoiceChip(
          label: const Text('Staff'),
          selected: currentValue == 'staff',
          onSelected: (_) => onChanged('staff'),
        ),
      ],
    );
  }
}

class _CaptureRow extends StatelessWidget {
  const _CaptureRow({
    required this.doc,
    required this.loadingMap,
    required this.attendanceMap,
    required this.onCapture,
    required this.onToggleStatus,
  });

  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final Map<String, bool> loadingMap;
  final Map<String, Map<String, dynamic>> attendanceMap;
  final Future<void> Function(
    BuildContext context,
    String id,
    Map<String, dynamic> data,
  )
  onCapture;
  final Future<void> Function({
    required String entityId,
    required String entityType,
    required String status,
  })
  onToggleStatus;

  @override
  Widget build(BuildContext context) {
    final data = doc.data();
    final id = doc.id;
    final isLoading = loadingMap[id] ?? false;
    final entityType = data['entityType']?.toString() == 'staff'
        ? 'staff'
        : 'student';
    final record = attendanceMap['${entityType}_$id'];
    final recordExists = record != null;
    final status = (record?['status']?.toString() ?? 'not_marked')
        .toLowerCase();
    final isAbsent = status == 'absent';
    final name =
        data['entityName']?.toString() ??
        data['name']?.toString() ??
        data['phone']?.toString() ??
        '';
    final typeLabel = entityType == 'staff' ? 'Staff' : 'Student';
    final photoUrl = data['photoUrl']?.toString();

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            CircleAvatar(
              backgroundImage: (photoUrl != null && photoUrl.isNotEmpty)
                  ? NetworkImage(photoUrl)
                  : null,
              child: (photoUrl == null || photoUrl.isEmpty)
                  ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?')
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _Pill(label: typeLabel, color: Colors.blueGrey),
                      const SizedBox(width: 8),
                      _Pill(
                        label: isAbsent
                            ? 'Absent'
                            : recordExists
                            ? 'Present'
                            : 'Not Marked',
                        color: isAbsent
                            ? Colors.red
                            : recordExists
                            ? Colors.green
                            : Colors.grey,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (!recordExists)
              isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : _CaptureIconButton(
                      onPressed: () => onCapture(context, id, data),
                    )
            else
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _PresentBadge(label: 'Present'),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: isLoading
                        ? null
                        : () => onToggleStatus(
                            entityId: id,
                            entityType:
                                data['entityType']?.toString() ?? 'student',
                            status: isAbsent ? 'present' : 'absent',
                          ),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.green.shade700,
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(isAbsent ? 'Mark Present' : 'Mark Absent'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _StaffCaptureRow extends StatelessWidget {
  const _StaffCaptureRow({
    required this.staff,
    required this.loadingMap,
    required this.attendanceMap,
    required this.onCapture,
    required this.onToggleStatus,
  });

  final AppUser staff;
  final Map<String, bool> loadingMap;
  final Map<String, Map<String, dynamic>> attendanceMap;
  final Future<void> Function(BuildContext context, AppUser staff) onCapture;
  final Future<void> Function({
    required String entityId,
    required String entityType,
    required String status,
  })
  onToggleStatus;

  @override
  Widget build(BuildContext context) {
    final isLoading = loadingMap[staff.id] ?? false;
    final record = attendanceMap['staff_${staff.id}'];
    final recordExists = record != null;
    final status = (record?['status']?.toString() ?? 'not_marked')
        .toLowerCase();
    final isAbsent = status == 'absent';
    final name = staff.name?.isNotEmpty == true ? staff.name! : staff.phone;
    final photoUrl = '';

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            CircleAvatar(
              backgroundImage: (photoUrl.isNotEmpty)
                  ? NetworkImage(photoUrl)
                  : null,
              child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _Pill(label: 'Staff', color: Colors.blueGrey),
                      const SizedBox(width: 8),
                      _Pill(
                        label: isAbsent
                            ? 'Absent'
                            : recordExists
                            ? 'Present'
                            : 'Not Marked',
                        color: isAbsent
                            ? Colors.red
                            : recordExists
                            ? Colors.green
                            : Colors.grey,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (!recordExists)
              isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : _CaptureIconButton(
                      onPressed: () => onCapture(context, staff),
                    )
            else
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _PresentBadge(label: 'Present'),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: isLoading
                        ? null
                        : () => onToggleStatus(
                            entityId: staff.id,
                            entityType: 'staff',
                            status: isAbsent ? 'present' : 'absent',
                          ),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.green.shade700,
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(isAbsent ? 'Mark Present' : 'Mark Absent'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _CaptureIconButton extends StatelessWidget {
  const _CaptureIconButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.green.shade50,
      shape: const CircleBorder(),
      child: IconButton(
        onPressed: onPressed,
        icon: const Icon(Icons.camera_alt_outlined),
        color: Colors.green.shade700,
        style: IconButton.styleFrom(
          backgroundColor: Colors.green.shade50,
          shape: const CircleBorder(),
        ),
      ),
    );
  }
}

class _PresentBadge extends StatelessWidget {
  const _PresentBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: Colors.green.shade800,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
