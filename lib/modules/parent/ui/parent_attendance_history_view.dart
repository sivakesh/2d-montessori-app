import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/responsive_dialog_shell.dart';
import '../../admin/ui/admin_attendance_management_screen.dart'
    show computeAttendanceSummary;
import '../../attendance/data/attendance_service.dart';
import '../../finance/widgets/finance_status_chip.dart';

/// Read-only Parent attendance history for one linked child — reached from
/// the Dashboard's selected child card, never as its own navigation
/// destination. [studentId] is only ever the id of a student already
/// resolved through ParentService.getLinkedStudents (the Dashboard's
/// `_ChildCard`/`_ChildSelector` never expose a raw, un-validated id), so
/// this never queries a student the signed-in parent isn't linked to.
///
/// The summary reuses [computeAttendanceSummary] — the exact
/// present/absent/notMarked calculation the Admin Attendance screen already
/// established and has test coverage for — rather than inventing a new one.
/// There is no established "attendance rate" percentage anywhere in this
/// codebase, so none is shown here (see the Phase C report).
void showChildAttendanceHistory(
  BuildContext context, {
  required String studentId,
  required String studentName,
  AttendanceService? attendanceService,
}) {
  showDialog<void>(
    context: context,
    builder: (_) => ResponsiveDialogShell.form(
      desktopWidth: 560,
      desktopHeight: 680,
      title: 'Attendance History',
      content: _AttendanceHistoryContent(
        studentId: studentId,
        studentName: studentName,
        attendanceService: attendanceService,
      ),
    ),
  );
}

class _AttendanceHistoryContent extends StatefulWidget {
  const _AttendanceHistoryContent({
    required this.studentId,
    required this.studentName,
    this.attendanceService,
  });

  final String studentId;
  final String studentName;

  /// Overridable only so tests can inject a fake-Firestore-backed
  /// AttendanceService, the same way AttendanceService's own constructor
  /// already supports test injection — production callers never pass this.
  final AttendanceService? attendanceService;

  @override
  State<_AttendanceHistoryContent> createState() =>
      _AttendanceHistoryContentState();
}

class _AttendanceHistoryContentState
    extends State<_AttendanceHistoryContent> {
  late final _service = widget.attendanceService ?? AttendanceService();
  bool _loading = true;
  bool _hasError = false;
  List<Map<String, dynamic>> _records = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _hasError = false;
    });
    try {
      final records = await _service.getAttendanceHistoryForEntity(
        entityType: 'student',
        entityId: widget.studentId,
      );
      if (!mounted) return;
      setState(() {
        _records = records;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _hasError = true;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_hasError) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            const Text(
              "Couldn't load attendance history.",
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }

    final statuses = _records
        .map((r) => r['status']?.toString() ?? 'not_marked')
        .toList();
    final summary = computeAttendanceSummary(statuses);
    final hasAnyRecord = summary.present + summary.absent > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Attendance Summary',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FinanceStatusChip(
              label: 'Present: ${summary.present}',
              color: AppColors.secondary,
            ),
            FinanceStatusChip(
              label: 'Absent: ${summary.absent}',
              color: Colors.redAccent,
            ),
            FinanceStatusChip(
              label: 'Not Marked: ${summary.notMarked}',
              color: Colors.grey,
            ),
          ],
        ),
        const SizedBox(height: 24),
        const Text(
          'Recent Attendance (last 30 days)',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        if (!hasAnyRecord)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'No attendance records yet for this child.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          )
        else
          Column(
            children: [
              for (final record in _records) ...[
                const Divider(height: 1),
                _AttendanceHistoryRow(record: record),
              ],
            ],
          ),
      ],
    );
  }
}

class _AttendanceHistoryRow extends StatelessWidget {
  const _AttendanceHistoryRow({required this.record});

  final Map<String, dynamic> record;

  @override
  Widget build(BuildContext context) {
    final dateKey = record['date']?.toString() ?? '';
    final date = DateTime.tryParse(dateKey);
    final dateLabel = date != null
        ? DateFormat('EEE, d MMM').format(date)
        : dateKey;
    final status = (record['status']?.toString() ?? 'not_marked')
        .toLowerCase();
    final checkInTime = status == 'present'
        ? _formatCheckInTime(record['updatedAt'])
        : null;
    final (label, color) = switch (status) {
      'present' => ('Present', AppColors.secondary),
      'absent' => ('Absent', Colors.redAccent),
      _ => ('Not Marked', Colors.grey),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dateLabel,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (checkInTime != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'Checked in at $checkInTime',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FinanceStatusChip(label: label, color: color),
        ],
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
