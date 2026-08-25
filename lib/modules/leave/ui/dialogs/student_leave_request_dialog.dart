import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/responsive_dialog_shell.dart';
import '../../../admin/students/models/admin_student_model.dart';
import '../../../students/data/student_service.dart';
import '../../models/leave_request_model.dart';
import '../../services/leave_service.dart';

/// Student leave submission form, shared by both submitter roles:
///  - Parent: [linkedStudents] is provided (the parent's own linked
///    children, already resolved server-side) and rendered as a dropdown —
///    there is no free-form student picker, so a parent can only ever pick
///    from their own children in the first place. LeaveService still
///    re-verifies this server-side; the dropdown is a UX convenience, not
///    the security boundary.
///  - Staff: [linkedStudents] is omitted, and a "Select Student" field
///    opens a searchable picker over every active student instead.
class StudentLeaveRequestDialog extends StatefulWidget {
  const StudentLeaveRequestDialog({
    super.key,
    required this.requesterId,
    required this.requesterName,
    required this.requesterRole,
    this.linkedStudents,
    this.service,
    this.studentService,
  });

  final String requesterId;
  final String requesterName;
  final String requesterRole;
  /// Non-null for a parent submitter — the exact set of children they may
  /// choose from. Null for a staff submitter, who instead searches all
  /// active students via [studentService].
  final List<AdminStudentModel>? linkedStudents;
  final LeaveService? service;
  final StudentService? studentService;

  @override
  State<StudentLeaveRequestDialog> createState() => _StudentLeaveRequestDialogState();
}

class _StudentLeaveRequestDialogState extends State<StudentLeaveRequestDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _service = widget.service ?? LeaveService();
  late final _studentService = widget.studentService ?? StudentService();
  final _reasonController = TextEditingController();

  AdminStudentModel? _selectedStudent;
  String _leaveType = LeaveType.sick;
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now();
  bool _saving = false;

  bool get _isParent => widget.linkedStudents != null;

  @override
  void initState() {
    super.initState();
    if (_isParent && widget.linkedStudents!.length == 1) {
      _selectedStudent = widget.linkedStudents!.first;
    }
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initial = isStart ? _startDate : _endDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: isStart ? DateTime(2020) : _startDate,
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
        if (_endDate.isBefore(_startDate)) _endDate = _startDate;
      } else {
        _endDate = picked;
      }
    });
  }

  Future<void> _pickStaffStudent() async {
    final docs = await _studentService.getAllStudents();
    if (!mounted) return;
    final students = docs
        .map((d) => AdminStudentModel.fromMap(d.id, d.data()))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    final picked = await showDialog<AdminStudentModel>(
      context: context,
      builder: (dialogContext) {
        String query = '';
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final filtered = students.where((s) {
              final q = query.toLowerCase();
              return q.isEmpty ||
                  s.name.toLowerCase().contains(q) ||
                  s.admissionNo.toLowerCase().contains(q);
            }).toList();
            return ResponsiveDialogShell(
              desktopWidth: 480,
              desktopHeight: 520,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Select Student',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.of(dialogContext).maybePop(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      decoration: const InputDecoration(
                        labelText: 'Search student',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (v) => setDialogState(() => query = v),
                    ),
                    const SizedBox(height: 12),
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final student = filtered[index];
                          return ListTile(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            tileColor: Colors.grey.shade50,
                            title: Text(student.name),
                            subtitle: Text('Admission: ${student.admissionNo}'),
                            onTap: () => Navigator.of(dialogContext).pop(student),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    if (picked != null) setState(() => _selectedStudent = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedStudent == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a student.')),
      );
      return;
    }
    if (_endDate.isBefore(_startDate)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('End date cannot be before start date.')),
      );
      return;
    }
    final workingDays = countWorkingDays(_startDate, _endDate);
    if (workingDays == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Leave must include at least one working day (Monday-Friday).'),
        ),
      );
      return;
    }
    if (workingDays > StudentLeavePolicy.maxWorkingDays) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Student leave cannot exceed ${StudentLeavePolicy.maxWorkingDays} working days.',
          ),
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await _service.submitStudentLeaveRequest(
        requesterId: widget.requesterId,
        requesterName: widget.requesterName,
        requesterRole: widget.requesterRole,
        studentId: _selectedStudent!.id,
        studentName: _selectedStudent!.name,
        leaveType: _leaveType,
        startDate: _startDate,
        endDate: _endDate,
        reason: _reasonController.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not submit leave request: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveDialogShell.form(
      desktopWidth: 520,
      title: 'Request Student Leave',
      content: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isParent)
              DropdownButtonFormField<AdminStudentModel>(
                initialValue: _selectedStudent,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Child'),
                items: [
                  for (final student in widget.linkedStudents!)
                    DropdownMenuItem(
                      value: student,
                      child: Text(student.name, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) => setState(() => _selectedStudent = v),
                validator: (v) => v == null ? 'Please select a child' : null,
              )
            else
              InkWell(
                onTap: _pickStaffStudent,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Student',
                    suffixIcon: Icon(Icons.search),
                  ),
                  child: Text(
                    _selectedStudent?.name ?? 'Tap to select a student',
                    style: _selectedStudent == null
                        ? const TextStyle(color: AppColors.textSecondary)
                        : null,
                  ),
                ),
              ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _leaveType,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Leave Type'),
              items: [
                for (final type in LeaveType.all)
                  DropdownMenuItem(
                    value: type,
                    child: Text(type, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) => setState(() => _leaveType = v ?? _leaveType),
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 420;
                final startField = InkWell(
                  onTap: () => _pickDate(isStart: true),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Start Date',
                      suffixIcon: Icon(Icons.calendar_month),
                    ),
                    child: Text(DateFormat('MMM d, yyyy').format(_startDate)),
                  ),
                );
                final endField = InkWell(
                  onTap: () => _pickDate(isStart: false),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'End Date',
                      suffixIcon: Icon(Icons.calendar_month),
                    ),
                    child: Text(DateFormat('MMM d, yyyy').format(_endDate)),
                  ),
                );
                if (narrow) {
                  return Column(
                    children: [startField, const SizedBox(height: 16), endField],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: startField),
                    const SizedBox(width: 16),
                    Expanded(child: endField),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _reasonController,
              decoration: const InputDecoration(labelText: 'Reason / Remarks'),
              maxLines: 3,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Reason is required' : null,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Submit'),
        ),
      ],
    );
  }
}
