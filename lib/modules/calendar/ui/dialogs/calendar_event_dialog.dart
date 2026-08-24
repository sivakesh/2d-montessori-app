import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/widgets/responsive_dialog_shell.dart';
import '../../models/calendar_event_model.dart';
import '../../services/calendar_service.dart';

/// Create/edit form for a single calendar item. Saves always as a Draft on
/// create, or preserve the existing status on edit — Publish/Archive are
/// separate explicit actions on the list (mirrors AdminNotificationService's
/// create-then-publish shape), so this dialog only ever needs to know the
/// item's content fields, never its lifecycle state.
class CalendarEventDialog extends StatefulWidget {
  const CalendarEventDialog({
    super.key,
    this.event,
    required this.createdBy,
    required this.createdByName,
    this.service,
  });

  final CalendarEventModel? event;
  final String createdBy;
  final String createdByName;
  final CalendarService? service;

  @override
  State<CalendarEventDialog> createState() => _CalendarEventDialogState();
}

class _CalendarEventDialogState extends State<CalendarEventDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _service = widget.service ?? CalendarService();

  late final _titleController =
      TextEditingController(text: widget.event?.title ?? '');
  late final _descriptionController =
      TextEditingController(text: widget.event?.description ?? '');
  late final _locationController =
      TextEditingController(text: widget.event?.location ?? '');

  late DateTime _date = widget.event?.date ?? DateTime.now();
  late String _eventType = widget.event?.eventType ?? CalendarEventType.event;
  late String _audience = widget.event?.audience ?? 'Public';
  late TimeOfDay? _startTime = _parseTime(widget.event?.startTime);
  late TimeOfDay? _endTime = _parseTime(widget.event?.endTime);
  bool _saving = false;

  static TimeOfDay? _parseTime(String? value) {
    if (value == null || value.isEmpty) return null;
    final parts = value.split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    return TimeOfDay(hour: hour, minute: minute);
  }

  String? _formatTime(TimeOfDay? time) {
    if (time == null) return null;
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime({required bool isStart}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: (isStart ? _startTime : _endTime) ?? TimeOfDay.now(),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startTime = picked;
      } else {
        _endTime = picked;
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_startTime != null &&
        _endTime != null &&
        _endTime!.hour * 60 + _endTime!.minute <
            _startTime!.hour * 60 + _startTime!.minute) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('End time cannot be before start time.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final data = {
        'title': _titleController.text.trim(),
        'date': DateTime(_date.year, _date.month, _date.day),
        'startTime': _formatTime(_startTime) ?? '',
        'endTime': _formatTime(_endTime) ?? '',
        'eventType': _eventType,
        'description': _descriptionController.text.trim(),
        'location': _locationController.text.trim(),
        'audience': _audience,
        'createdBy': widget.createdBy,
        'createdByName': widget.createdByName,
      };
      if (widget.event == null) {
        await _service.createEvent({
          ...data,
          'status': CalendarEventStatus.draft,
        });
      } else {
        await _service.updateEvent(widget.event!.id, data);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save calendar item: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.event != null;
    return ResponsiveDialogShell.form(
      desktopWidth: 560,
      title: isEditing ? 'Edit Calendar Item' : 'New Calendar Item',
      content: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: 'Title'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Title is required' : null,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _eventType,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Event Type'),
              items: [
                for (final type in CalendarEventType.all)
                  DropdownMenuItem(
                    value: type,
                    child: Text(type, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) => setState(() => _eventType = v ?? _eventType),
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: _pickDate,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Date',
                  suffixIcon: Icon(Icons.calendar_month),
                ),
                child: Text(DateFormat('EEE, MMM d, yyyy').format(_date)),
              ),
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 420;
                final startField = InkWell(
                  onTap: () => _pickTime(isStart: true),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Start Time (optional)',
                      suffixIcon: Icon(Icons.access_time),
                    ),
                    child: Text(_startTime?.format(context) ?? '-'),
                  ),
                );
                final endField = InkWell(
                  onTap: () => _pickTime(isStart: false),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'End Time (optional)',
                      suffixIcon: Icon(Icons.access_time),
                    ),
                    child: Text(_endTime?.format(context) ?? '-'),
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
            DropdownButtonFormField<String>(
              initialValue: _audience,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Audience'),
              items: const [
                DropdownMenuItem(value: 'Public', child: Text('Everyone')),
                DropdownMenuItem(value: 'Parents', child: Text('Parents')),
                DropdownMenuItem(value: 'Staff', child: Text('Staff')),
              ],
              onChanged: (v) => setState(() => _audience = v ?? _audience),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _locationController,
              decoration: const InputDecoration(labelText: 'Location (optional)'),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(labelText: 'Description'),
              maxLines: 3,
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
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}
