import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../admin/students/models/admin_student_model.dart';
import '../../admin/ui/admin_fab.dart';
import '../../auth/providers/auth_provider.dart';
import '../../parent/data/parent_service.dart';
import '../models/leave_request_model.dart';
import '../services/leave_service.dart';
import 'dialogs/student_leave_request_dialog.dart';
import 'widgets/student_leave_card.dart';

/// Parent's dedicated Leave destination — the same student-leave workflow
/// already used from the Parent Dashboard's per-child "Leave Requests"
/// section (LeaveService.getStudentRequestsForParent +
/// StudentLeaveRequestDialog), but showing every linked child's leave
/// history in one place rather than only the currently-selected child.
/// Never touches Staff Leave or admin approve/reject — StudentLeaveCard is
/// rendered here without onApprove/onReject, so there is no management
/// action surface for a parent to reach.
class ParentLeaveView extends ConsumerStatefulWidget {
  const ParentLeaveView({super.key, this.leaveService, this.parentService});

  final LeaveService? leaveService;
  final ParentService? parentService;

  @override
  ConsumerState<ParentLeaveView> createState() => _ParentLeaveViewState();
}

class _ParentLeaveViewState extends ConsumerState<ParentLeaveView> {
  late final _leaveService = widget.leaveService ?? LeaveService();
  late final _parentService = widget.parentService ?? ParentService();

  bool _loading = true;
  bool _loadError = false;
  List<AdminStudentModel> _children = const [];
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
        _children = const [];
        _requests = const [];
      });
      return;
    }
    setState(() {
      _loading = true;
      _loadError = false;
    });
    try {
      // Both calls are scoped server-side to this parent's own linked
      // children (ParentService.getLinkedStudents / LeaveService.
      // getStudentRequestsForParent) — never a client-supplied student id.
      final children = await _parentService.getLinkedStudents(user.id);
      final requests = await _leaveService.getStudentRequestsForParent(user.id);
      if (!mounted) return;
      setState(() {
        _children = children;
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
    if (user == null || _children.isEmpty) return;
    final submitted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => StudentLeaveRequestDialog(
        requesterId: user.id,
        requesterName: user.name?.isNotEmpty == true ? user.name! : user.phone,
        requesterRole: LeaveRequesterRole.parent,
        linkedStudents: _children,
        service: _leaveService,
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
                        "Couldn't load leave requests.",
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 8),
                      TextButton(onPressed: _load, child: const Text('Retry')),
                    ],
                  ),
                ),
              )
            : _children.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.family_restroom_outlined, size: 40, color: AppColors.textSecondary),
                          SizedBox(height: 12),
                          Text(
                            'No children linked to your account yet.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
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
                          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
                          itemBuilder: (context, index) => StudentLeaveCard(request: _requests[index]),
                        ),
                      );

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: _children.isEmpty
          ? null
          : AdminFab(icon: Icons.add, onPressed: _openSubmit),
      body: body,
    );
  }
}
