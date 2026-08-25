import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/widgets/responsive_dialog_shell.dart';
import '../../models/leave_request_model.dart';
import '../../services/leave_service.dart';

/// Staff self-service leave submission form. Uses the currently
/// authenticated AppUser as the requester identity — no separate employee
/// id is introduced.
class LeaveRequestDialog extends StatefulWidget {
  const LeaveRequestDialog({
    super.key,
    required this.requesterId,
    required this.requesterName,
    this.service,
  });

  final String requesterId;
  final String requesterName;
  final LeaveService? service;

  @override
  State<LeaveRequestDialog> createState() => _LeaveRequestDialogState();
}

class _LeaveRequestDialogState extends State<LeaveRequestDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _service = widget.service ?? LeaveService();
  final _reasonController = TextEditingController();

  String _leaveType = LeaveType.sick;
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now();
  bool _saving = false;

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
      firstDate: DateTime(2020),
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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
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
    if (workingDays > StaffLeavePolicy.maxWorkingDays) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Staff leave cannot exceed ${StaffLeavePolicy.maxWorkingDays} working days.',
          ),
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await _service.submitLeaveRequest(
        requesterId: widget.requesterId,
        requesterName: widget.requesterName,
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
      title: 'Request Leave',
      content: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
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
                    children: [
                      startField,
                      const SizedBox(height: 16),
                      endField,
                    ],
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
