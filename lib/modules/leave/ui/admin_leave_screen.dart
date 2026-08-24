import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../admin/ui/admin_layout.dart';
import '../../auth/providers/auth_provider.dart';
import '../../finance/widgets/finance_status_chip.dart';
import '../models/leave_request_model.dart';
import '../services/leave_service.dart';
import 'widgets/student_leave_card.dart';

/// Admin management view. Wrapped in AdminLayout the same way
/// AdminFeesScreen/AdminFinanceScreen are, so it appears in the Admin
/// sidebar / mobile "More Modules" sheet exactly like every other
/// back-office module. Student Leave is added as a second tab here rather
/// than a new sidebar destination — the task explicitly calls for extending
/// the existing "Leave Requests" area instead of adding new primary
/// navigation.
class AdminLeaveScreen extends StatelessWidget {
  const AdminLeaveScreen({super.key, this.service});

  final LeaveService? service;

  @override
  Widget build(BuildContext context) {
    return AdminLayout(
      selectedIndex: 13,
      title: 'Leave Requests',
      body: DefaultTabController(
        length: 2,
        child: Column(
          children: [
            const Material(
              color: Colors.transparent,
              child: TabBar(
                tabs: [
                  Tab(text: 'Staff Leave'),
                  Tab(text: 'Student Leave'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _AdminLeaveBody(service: service),
                  _AdminStudentLeaveBody(service: service),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminLeaveBody extends ConsumerStatefulWidget {
  const _AdminLeaveBody({this.service});

  final LeaveService? service;

  @override
  ConsumerState<_AdminLeaveBody> createState() => _AdminLeaveBodyState();
}

class _AdminLeaveBodyState extends ConsumerState<_AdminLeaveBody> {
  late final _service = widget.service ?? LeaveService();
  bool _loading = true;
  bool _loadError = false;
  List<LeaveRequestModel> _requests = const [];
  String _filter = 'All';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = false;
    });
    try {
      final requests = await _service.getAllRequests();
      if (!mounted) return;
      setState(() {
        _requests = requests;
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

  Future<void> _review(LeaveRequestModel request, {required bool approve}) async {
    final remarksController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(approve ? 'Approve leave request?' : 'Reject leave request?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${request.requesterName} — ${request.leaveType}'),
            const SizedBox(height: 12),
            TextField(
              controller: remarksController,
              decoration: const InputDecoration(labelText: 'Remarks (optional)'),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(approve ? 'Approve' : 'Reject'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final reviewer = ref.read(currentUserProvider);
    try {
      if (approve) {
        await _service.approveLeaveRequest(
          request.id,
          reviewedBy: reviewer?.id ?? '',
          remarks: remarksController.text.trim(),
        );
      } else {
        await _service.rejectLeaveRequest(
          request.id,
          reviewedBy: reviewer?.id ?? '',
          remarks: remarksController.text.trim(),
        );
      }
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(approve ? 'Leave request approved' : 'Leave request rejected')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update the request: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _filter == 'All'
        ? _requests
        : _requests.where((r) => r.status == _filter).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, 0),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final option in const ['All', LeaveStatus.pending, LeaveStatus.approved, LeaveStatus.rejected])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(option),
                      selected: _filter == option,
                      onSelected: (_) => setState(() => _filter = option),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _loadError
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            "Couldn't load leave requests.",
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                          const SizedBox(height: 8),
                          TextButton(onPressed: _load, child: const Text('Retry')),
                        ],
                      ),
                    )
                  : visible.isEmpty
                      ? const Center(
                          child: Text(
                            'No leave requests here.',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.separated(
                            padding: const EdgeInsets.fromLTRB(
                              AppSpacing.md,
                              AppSpacing.md,
                              AppSpacing.md,
                              32,
                            ),
                            itemCount: visible.length,
                            separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                            itemBuilder: (context, index) {
                              final request = visible[index];
                              return _AdminLeaveCard(
                                request: request,
                                onApprove: request.status == LeaveStatus.pending
                                    ? () => _review(request, approve: true)
                                    : null,
                                onReject: request.status == LeaveStatus.pending
                                    ? () => _review(request, approve: false)
                                    : null,
                              );
                            },
                          ),
                        ),
        ),
      ],
    );
  }
}

class _AdminLeaveCard extends StatelessWidget {
  const _AdminLeaveCard({required this.request, this.onApprove, this.onReject});

  final LeaveRequestModel request;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;

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
                    request.requesterName.isNotEmpty ? request.requesterName : 'Staff',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
                FinanceStatusChip(label: statusLabel, color: statusColor),
              ],
            ),
            const SizedBox(height: 4),
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

/// Admin's Student Leave tab: every student leave request, filterable by
/// status, student name, and a single "on date" filter (a request is
/// included if that date falls within its start-end range).
class _AdminStudentLeaveBody extends ConsumerStatefulWidget {
  const _AdminStudentLeaveBody({this.service});

  final LeaveService? service;

  @override
  ConsumerState<_AdminStudentLeaveBody> createState() => _AdminStudentLeaveBodyState();
}

class _AdminStudentLeaveBodyState extends ConsumerState<_AdminStudentLeaveBody> {
  late final _service = widget.service ?? LeaveService();
  bool _loading = true;
  bool _loadError = false;
  List<LeaveRequestModel> _requests = const [];
  String _statusFilter = 'All';
  String _studentQuery = '';
  DateTime? _dateFilter;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = false;
    });
    try {
      final requests = await _service.getAllStudentLeaveRequests();
      if (!mounted) return;
      setState(() {
        _requests = requests;
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

  Future<void> _pickDateFilter() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateFilter ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _dateFilter = picked);
  }

  Future<void> _review(LeaveRequestModel request, {required bool approve}) async {
    final remarksController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(approve ? 'Approve student leave?' : 'Reject student leave?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${request.studentName ?? 'Student'} — ${request.leaveType}'),
            const SizedBox(height: 12),
            TextField(
              controller: remarksController,
              decoration: const InputDecoration(labelText: 'Remarks (optional)'),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(approve ? 'Approve' : 'Reject'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final reviewer = ref.read(currentUserProvider);
    try {
      if (approve) {
        await _service.approveLeaveRequest(
          request.id,
          reviewedBy: reviewer?.id ?? '',
          remarks: remarksController.text.trim(),
        );
      } else {
        await _service.rejectLeaveRequest(
          request.id,
          reviewedBy: reviewer?.id ?? '',
          remarks: remarksController.text.trim(),
        );
      }
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(approve ? 'Leave request approved' : 'Leave request rejected')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update the request: $e')),
        );
      }
    }
  }

  bool _dateWithinRange(DateTime date, LeaveRequestModel request) {
    final day = DateTime(date.year, date.month, date.day);
    final start = DateTime(request.startDate.year, request.startDate.month, request.startDate.day);
    final end = DateTime(request.endDate.year, request.endDate.month, request.endDate.day);
    return !day.isBefore(start) && !day.isAfter(end);
  }

  @override
  Widget build(BuildContext context) {
    final query = _studentQuery.trim().toLowerCase();
    final visible = _requests.where((r) {
      if (_statusFilter != 'All' && r.status != _statusFilter) return false;
      if (query.isNotEmpty && !(r.studentName ?? '').toLowerCase().contains(query)) {
        return false;
      }
      if (_dateFilter != null && !_dateWithinRange(_dateFilter!, r)) return false;
      return true;
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Filter by student name',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _studentQuery = v),
              ),
              const SizedBox(height: AppSpacing.sm),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final option in const ['All', LeaveStatus.pending, LeaveStatus.approved, LeaveStatus.rejected])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(option),
                          selected: _statusFilter == option,
                          onSelected: (_) => setState(() => _statusFilter = option),
                        ),
                      ),
                    ActionChip(
                      avatar: const Icon(Icons.event, size: 16),
                      label: Text(
                        _dateFilter == null
                            ? 'Filter by date'
                            : DateFormat('MMM d, yyyy').format(_dateFilter!),
                      ),
                      onPressed: _pickDateFilter,
                    ),
                    if (_dateFilter != null) ...[
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        tooltip: 'Clear date filter',
                        onPressed: () => setState(() => _dateFilter = null),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _loadError
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            "Couldn't load student leave requests.",
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                          const SizedBox(height: 8),
                          TextButton(onPressed: _load, child: const Text('Retry')),
                        ],
                      ),
                    )
                  : visible.isEmpty
                      ? const Center(
                          child: Text(
                            'No student leave requests here.',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.separated(
                            padding: const EdgeInsets.fromLTRB(
                              AppSpacing.md,
                              AppSpacing.md,
                              AppSpacing.md,
                              32,
                            ),
                            itemCount: visible.length,
                            separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                            itemBuilder: (context, index) {
                              final request = visible[index];
                              return StudentLeaveCard(
                                request: request,
                                onApprove: request.status == LeaveStatus.pending
                                    ? () => _review(request, approve: true)
                                    : null,
                                onReject: request.status == LeaveStatus.pending
                                    ? () => _review(request, approve: false)
                                    : null,
                              );
                            },
                          ),
                        ),
        ),
      ],
    );
  }
}
