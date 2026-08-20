import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../attendance/providers/attendance_provider.dart';
import '../../auth/data/user_service.dart';
import '../../auth/models/app_user.dart';
import '../../auth/providers/auth_provider.dart';
import '../../classes/providers/class_provider.dart';
import '../../finance/widgets/finance_status_chip.dart';
import '../../finance/widgets/finance_summary_card.dart';
import '../../students/providers/student_provider.dart';
import 'admin_layout.dart';

/// Pure summary calculation over already-loaded attendance statuses — no
/// Firestore access. Public (not `_`-prefixed) so it can be unit tested
/// directly.
({int present, int absent, int notMarked, int total}) computeAttendanceSummary(
  List<String> statuses,
) {
  return (
    present: statuses.where((s) => s == 'present').length,
    absent: statuses.where((s) => s == 'absent').length,
    notMarked: statuses.where((s) => s == 'not_marked').length,
    total: statuses.length,
  );
}

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

  // Same status-resolution rule already used per row (draft override, else
  // the loaded attendance record, else not_marked) — extracted so the new
  // summary section reads it from one place instead of duplicating it.
  String _statusFor(String entityType, String entityId) {
    return _draftStatuses[entityId] ??
        (_attendanceMap[_recordKey(entityType, entityId)]?['status']
                ?.toString()
                .toLowerCase() ??
            'not_marked');
  }

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

  Widget _buildBody(BuildContext context) {
    final filteredStudents = _students.where((doc) {
      if (_selectedClassIds.isEmpty) return true;
      return _selectedClassIds.contains(
        doc.data()['classId']?.toString() ?? '',
      );
    }).toList();

    final filteredStaff = _staff;

    // Summary reflects exactly the currently-displayed population (current
    // date, current Students/Staff view, current class filter) — no new
    // query, computed from the same _students/_staff/_attendanceMap/
    // _draftStatuses already loaded for the list below.
    final displayedStatuses = _selectedScope == 'student'
        ? filteredStudents.map((doc) => _statusFor('student', doc.id)).toList()
        : filteredStaff.map((user) => _statusFor('staff', user.id)).toList();
    final summary = computeAttendanceSummary(displayedStatuses);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Attendance',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
        ),
        const SizedBox(height: 4),
        const Text(
          'Manage daily attendance for students and staff.',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 20),
        const Text(
          'Attendance Summary',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
        ),
        const SizedBox(height: 12),
        _AttendanceSummaryGrid(
          children: [
            FinanceSummaryCard(
              label: 'Present',
              value: '${summary.present}',
              icon: Icons.check_circle_outline,
              color: AppColors.secondary,
            ),
            FinanceSummaryCard(
              label: 'Absent',
              value: '${summary.absent}',
              icon: Icons.cancel_outlined,
              color: const Color(0xFFD32F2F),
            ),
            FinanceSummaryCard(
              label: 'Not Marked',
              value: '${summary.notMarked}',
              icon: Icons.help_outline,
              color: const Color(0xFFB26A00),
            ),
            FinanceSummaryCard(
              label: 'Total',
              value: '${summary.total}',
              icon: Icons.groups_outlined,
              color: AppColors.primary,
            ),
          ],
        ),
        const SizedBox(height: 24),
        const Text(
          'Date / View',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_month, size: 18),
              label: Text(_dateKey(_selectedDate)),
            ),
            ChoiceChip(
              label: const Text('Students'),
              selected: _selectedScope == 'student',
              onSelected: (_) => setState(() => _selectedScope = 'student'),
            ),
            ChoiceChip(
              label: const Text('Staff'),
              selected: _selectedScope == 'staff',
              onSelected: (_) => setState(() => _selectedScope = 'staff'),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const Text(
          'Class / Group',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
        ),
        const SizedBox(height: 12),
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
        const SizedBox(height: 24),
        if (_errorMessage != null) ...[
          Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
          const SizedBox(height: 12),
        ],
        if (_loading)
          const Center(child: CircularProgressIndicator())
        else ...[
          if (_selectedScope == 'student')
            filteredStudents.isEmpty
                ? const _AttendanceEmptyState(
                    title: 'No students found',
                    subtitle: 'No students match the selected class or filters.',
                  )
                : Column(
                    children: filteredStudents.map((student) {
                      final data = student.data();
                      final status = _statusFor('student', student.id);
                      final subtitle = [
                        data['admissionNo']?.toString() ?? '',
                        _classNameFor(data),
                      ].where((v) => v.isNotEmpty && v != '-').join(' • ');
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _AttendanceRow(
                          name: data['name']?.toString() ?? '',
                          subtitle: subtitle,
                          status: status,
                          onPresent: () => setState(() => _draftStatuses[student.id] = 'present'),
                          onAbsent: () => setState(() => _draftStatuses[student.id] = 'absent'),
                          onClear: () => setState(() => _draftStatuses[student.id] = 'not_marked'),
                        ),
                      );
                    }).toList(),
                  )
          else
            filteredStaff.isEmpty
                ? const _AttendanceEmptyState(
                    title: 'No staff found',
                    subtitle: 'No staff match the current view.',
                  )
                : Column(
                    children: filteredStaff.map((user) {
                      final status = _statusFor('staff', user.id);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _AttendanceRow(
                          name: user.name ?? user.phone,
                          subtitle: user.phone,
                          status: status,
                          onPresent: () => setState(() => _draftStatuses[user.id] = 'present'),
                          onAbsent: () => setState(() => _draftStatuses[user.id] = 'absent'),
                          onClear: () => setState(() => _draftStatuses[user.id] = 'not_marked'),
                        ),
                      );
                    }).toList(),
                  ),
          const SizedBox(height: 20),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
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

/// Lays summary cards out at up to 4 per row, stepping down to 2 then 1 as
/// width shrinks — the same LayoutBuilder + Wrap responsive pattern used by
/// the Finance module's summary grid (that one is private to
/// admin_finance_screen.dart, so it isn't importable here; this replicates
/// the same behavior rather than modifying Finance to export it).
class _AttendanceSummaryGrid extends StatelessWidget {
  const _AttendanceSummaryGrid({required this.children});

  final List<Widget> children;

  static const _spacing = 16.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1000
            ? 4
            : constraints.maxWidth >= 640
                ? 2
                : 1;
        final cardWidth = (constraints.maxWidth - (_spacing * (columns - 1))) / columns;
        return Wrap(
          spacing: _spacing,
          runSpacing: _spacing,
          children: children.map((child) => SizedBox(width: cardWidth, child: child)).toList(),
        );
      },
    );
  }
}

/// A compact attendance row for one student or staff member. Presentation
/// only — the three actions call back into the existing draft-status
/// handlers already wired in the parent; no attendance data is written
/// here.
class _AttendanceRow extends StatelessWidget {
  const _AttendanceRow({
    required this.name,
    required this.subtitle,
    required this.status,
    required this.onPresent,
    required this.onAbsent,
    required this.onClear,
  });

  final String name;
  final String subtitle;
  final String status;
  final VoidCallback onPresent;
  final VoidCallback onAbsent;
  final VoidCallback onClear;

  static String _initialsFor(String value) {
    final parts = value.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  ({String label, Color color}) get _statusPresentation => switch (status) {
        'present' => (label: 'PRESENT', color: AppColors.secondary),
        'absent' => (label: 'ABSENT', color: const Color(0xFFD32F2F)),
        _ => (label: 'NOT MARKED', color: Colors.grey),
      };

  @override
  Widget build(BuildContext context) {
    final statusInfo = _statusPresentation;

    final avatar = Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), shape: BoxShape.circle),
      child: Text(
        _initialsFor(name),
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.primary),
      ),
    );

    final info = Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            name.isEmpty ? '-' : name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textPrimary),
          ),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ],
      ),
    );

    final chip = FinanceStatusChip(label: statusInfo.label, color: statusInfo.color);

    final actions = Wrap(
      spacing: 6,
      children: [
        _AttendanceActionButton(label: 'Present', active: status == 'present', color: AppColors.secondary, onPressed: onPresent),
        _AttendanceActionButton(label: 'Absent', active: status == 'absent', color: const Color(0xFFD32F2F), onPressed: onAbsent),
        _AttendanceActionButton(label: 'Clear', active: status == 'not_marked', color: Colors.grey.shade700, onPressed: onClear),
      ],
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 560) {
            return Row(
              children: [
                avatar,
                const SizedBox(width: 12),
                info,
                const SizedBox(width: 12),
                chip,
                const SizedBox(width: 12),
                actions,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  avatar,
                  const SizedBox(width: 12),
                  info,
                  const SizedBox(width: 8),
                  chip,
                ],
              ),
              const SizedBox(height: 10),
              actions,
            ],
          );
        },
      ),
    );
  }
}

class _AttendanceActionButton extends StatelessWidget {
  const _AttendanceActionButton({
    required this.label,
    required this.active,
    required this.color,
    required this.onPressed,
  });

  final String label;
  final bool active;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          backgroundColor: active ? color : color.withValues(alpha: 0.08),
          foregroundColor: active ? Colors.white : color,
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Text(label),
      ),
    );
  }
}

/// Empty-state card matching the Finance module's styling (icon + title +
/// supporting text inside a left-flowing bordered card). Finance's own
/// version of this is private to admin_finance_screen.dart, so it isn't
/// importable here; this replicates the same look rather than modifying
/// Finance to export it.
class _AttendanceEmptyState extends StatelessWidget {
  const _AttendanceEmptyState({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Column(
        children: [
          Icon(Icons.groups_outlined, size: 36, color: AppColors.textSecondary.withValues(alpha: 0.6)),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}
