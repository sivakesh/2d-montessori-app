import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../finance/widgets/finance_status_chip.dart';
import '../../models/leave_request_model.dart';

/// One student leave request, shared by the Parent, Staff, and Admin
/// student-leave surfaces so status colors, date formatting, and the
/// approve/reject action row stay identical everywhere it appears.
class StudentLeaveCard extends StatelessWidget {
  const StudentLeaveCard({
    super.key,
    required this.request,
    this.onApprove,
    this.onReject,
    this.onLeaveDate,
  });

  final LeaveRequestModel request;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;

  /// When set, an Approved request whose `[startDate, endDate]` range
  /// includes this date (inclusive, date components only) additionally
  /// shows an "ON LEAVE" chip — the same date-coverage rule as
  /// [LeaveService.getStudentIdsOnApprovedLeave]. Null (the default) keeps
  /// the card exactly as it was for callers that don't pass it.
  final DateTime? onLeaveDate;

  bool get _isOnLeave {
    final date = onLeaveDate;
    if (date == null || request.status != LeaveStatus.approved) return false;
    final day = DateTime(date.year, date.month, date.day);
    final start = DateTime(request.startDate.year, request.startDate.month, request.startDate.day);
    final end = DateTime(request.endDate.year, request.endDate.month, request.endDate.day);
    return !day.isBefore(start) && !day.isAfter(end);
  }

  (String, Color) _statusStyle() {
    return switch (request.status) {
      LeaveStatus.approved => ('Approved', AppColors.secondary),
      LeaveStatus.rejected => ('Rejected', Colors.redAccent),
      _ => ('Pending', Colors.orange),
    };
  }

  @override
  Widget build(BuildContext context) {
    final (statusLabel, statusColor) = _statusStyle();
    final dateFormat = DateFormat('MMM d, yyyy');
    final requesterLabel = request.requesterRole == LeaveRequesterRole.parent
        ? 'Parent • ${request.requesterName}'
        : 'Staff • ${request.requesterName}';

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    request.studentName?.isNotEmpty == true
                        ? request.studentName!
                        : 'Student',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
                if (_isOnLeave) ...[
                  const FinanceStatusChip(label: 'ON LEAVE', color: Color(0xFF1565C0)),
                  const SizedBox(width: 6),
                ],
                FinanceStatusChip(label: statusLabel, color: statusColor),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              requesterLabel,
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 6),
            Text(
              '${request.leaveType} • ${dateFormat.format(request.startDate)} - ${dateFormat.format(request.endDate)}',
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            Text(request.reason, style: const TextStyle(fontSize: 13)),
            if (request.reviewRemarks?.isNotEmpty == true) ...[
              const SizedBox(height: 6),
              Text(
                'Remarks: ${request.reviewRemarks}',
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
            if (onApprove != null || onReject != null) ...[
              const Divider(height: 24),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (onReject != null)
                    TextButton.icon(
                      onPressed: onReject,
                      icon: const Icon(Icons.close, size: 18, color: Colors.redAccent),
                      label: const Text('Reject', style: TextStyle(color: Colors.redAccent)),
                    ),
                  if (onApprove != null)
                    FilledButton.icon(
                      onPressed: onApprove,
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('Approve'),
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
