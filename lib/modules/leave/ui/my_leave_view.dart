import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../admin/ui/admin_fab.dart';
import '../../auth/providers/auth_provider.dart';
import '../../finance/widgets/finance_status_chip.dart';
import '../../students/data/student_service.dart';
import '../models/leave_request_model.dart';
import '../services/leave_service.dart';
import 'dialogs/leave_request_dialog.dart';
import 'dialogs/student_leave_request_dialog.dart';
import 'widgets/student_leave_card.dart';

/// Staff's Leave area — "My Leave" (submit/view their own leave, unchanged
/// from before) and "Student Leave" (submit/view leave they've raised on
/// behalf of a student), as two tabs of the same screen rather than a
/// second navigation destination, per the task's "extend the existing
/// Leave area" direction.
class MyLeaveView extends ConsumerWidget {
  const MyLeaveView({super.key, this.service, this.studentService});

  final LeaveService? service;
  /// Overridable only so tests can inject a fake-Firestore-backed
  /// StudentService for the Student Leave tab's student picker — the same
  /// DI seam every service here already exposes on its own constructor.
  final StudentService? studentService;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leaveService = service ?? LeaveService();
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const Material(
            color: Colors.transparent,
            child: TabBar(
              tabs: [
                Tab(text: 'My Leave'),
                Tab(text: 'Student Leave'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _MyOwnLeaveTab(service: leaveService),
                _StudentLeaveTab(service: leaveService, studentService: studentService),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Unchanged staff self-service: submit a leave request and see the status
/// of their own past requests. Scoped by `requesterId == the signed-in
/// AppUser.id` at the query level (LeaveService.getRequestsForStaff), so a
/// staff member can never see another staff member's requests, even in a
/// client bug.
class _MyOwnLeaveTab extends ConsumerStatefulWidget {
  const _MyOwnLeaveTab({required this.service});

  final LeaveService service;

  @override
  ConsumerState<_MyOwnLeaveTab> createState() => _MyOwnLeaveTabState();
}

class _MyOwnLeaveTabState extends ConsumerState<_MyOwnLeaveTab> {
  bool _loading = true;
  bool _loadError = false;
  List<LeaveRequestModel> _requests = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = ref.read(currentUserProvider);
    if (user == null || user.id.isEmpty) {
      setState(() {
        _loading = false;
        _requests = const [];
      });
      return;
    }
    setState(() {
      _loading = true;
      _loadError = false;
    });
    try {
      final requests = await widget.service.getRequestsForStaff(user.id);
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

  Future<void> _openSubmit() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    final submitted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => LeaveRequestDialog(
        requesterId: user.id,
        requesterName: user.name?.isNotEmpty == true ? user.name! : user.phone,
        service: widget.service,
      ),
    );
    if (submitted == true) {
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Leave request submitted')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : _loadError
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        "Couldn't load your leave requests.",
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 8),
                      TextButton(onPressed: _load, child: const Text('Retry')),
                    ],
                  ),
                ),
              )
            : _requests.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.event_busy_outlined, size: 40, color: AppColors.textSecondary),
                          SizedBox(height: 12),
                          Text(
                            'No leave requests yet.',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.md,
                        AppSpacing.md,
                        AppSpacing.md,
                        96,
                      ),
                      itemCount: _requests.length,
                      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                      itemBuilder: (context, index) => _LeaveRequestCard(request: _requests[index]),
                    ),
                  );

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: AdminFab(icon: Icons.add, onPressed: _openSubmit),
      body: body,
    );
  }
}

/// Staff's Student Leave tab: raise a leave request for any active student
/// (via a searchable picker inside StudentLeaveRequestDialog) and see only
/// the student leave requests this staff member themselves submitted —
/// query-scoped by requesterId, the same isolation shape as "My Leave".
class _StudentLeaveTab extends ConsumerStatefulWidget {
  const _StudentLeaveTab({required this.service, this.studentService});

  final LeaveService service;
  final StudentService? studentService;

  @override
  ConsumerState<_StudentLeaveTab> createState() => _StudentLeaveTabState();
}

class _StudentLeaveTabState extends ConsumerState<_StudentLeaveTab> {
  bool _loading = true;
  bool _loadError = false;
  List<LeaveRequestModel> _requests = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = ref.read(currentUserProvider);
    if (user == null || user.id.isEmpty) {
      setState(() {
        _loading = false;
        _requests = const [];
      });
      return;
    }
    setState(() {
      _loading = true;
      _loadError = false;
    });
    try {
      final requests = await widget.service.getStudentRequestsSubmittedBy(user.id);
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

  Future<void> _openSubmit() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    final submitted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => StudentLeaveRequestDialog(
        requesterId: user.id,
        requesterName: user.name?.isNotEmpty == true ? user.name! : user.phone,
        requesterRole: LeaveRequesterRole.staff,
        service: widget.service,
        studentService: widget.studentService,
      ),
    );
    if (submitted == true) {
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Student leave request submitted')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : _loadError
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
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
                ),
              )
            : _requests.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.event_busy_outlined, size: 40, color: AppColors.textSecondary),
                          SizedBox(height: 12),
                          Text(
                            'No student leave requests submitted yet.',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.md,
                        AppSpacing.md,
                        AppSpacing.md,
                        96,
                      ),
                      itemCount: _requests.length,
                      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                      itemBuilder: (context, index) => StudentLeaveCard(request: _requests[index]),
                    ),
                  );

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: AdminFab(icon: Icons.add, onPressed: _openSubmit),
      body: body,
    );
  }
}

class _LeaveRequestCard extends StatelessWidget {
  const _LeaveRequestCard({required this.request});

  final LeaveRequestModel request;

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
    final sameDay = request.startDate.year == request.endDate.year &&
        request.startDate.month == request.endDate.month &&
        request.startDate.day == request.endDate.day;
    final dateRange = sameDay
        ? dateFormat.format(request.startDate)
        : '${dateFormat.format(request.startDate)} - ${dateFormat.format(request.endDate)}';

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
                    request.leaveType,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
                FinanceStatusChip(label: statusLabel, color: statusColor),
              ],
            ),
            const SizedBox(height: 6),
            Text(dateRange, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            Text(
              request.reason,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
            if (request.reviewRemarks?.isNotEmpty == true) ...[
              const Divider(height: 20),
              Text(
                'Admin remarks: ${request.reviewRemarks}',
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
