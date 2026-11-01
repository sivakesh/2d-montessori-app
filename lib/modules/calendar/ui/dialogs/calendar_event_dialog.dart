import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/widgets/responsive_dialog_shell.dart';
import '../../../admin/website/ui/website_item_image_section.dart';
import '../../../auth/models/app_user.dart';
import '../../../public_website/content/website_public_item.dart';
import '../../models/calendar_event_model.dart';
import '../../services/calendar_service.dart';
import '../../services/calendar_website_publisher.dart';

/// Create/edit form for a single calendar item. Saves always as a Draft on
/// create, or preserve the existing status on edit — Publish/Archive are
/// separate explicit actions on the list (mirrors AdminNotificationService's
/// create-then-publish shape), so this dialog only ever needs to know the
/// item's content fields, never its lifecycle state.
///
/// With a [websitePublisher] (Admin), it also has a "Public website"
/// section: a new item can't be shown there yet (it is saved as a Draft),
/// and an existing one can be shown, updated or removed by its "Show on
/// website" switch, applied after the item itself is saved.
class CalendarEventDialog extends StatefulWidget {
  const CalendarEventDialog({
    super.key,
    this.event,
    required this.createdBy,
    required this.createdByName,
    this.service,
    this.websitePublisher,
    this.requesterRole = '',
    this.websiteItem,
    this.websiteStatusKnown = true,
    this.actor,
  });

  final CalendarEventModel? event;
  final String createdBy;
  final String createdByName;
  final CalendarService? service;

  /// Shows the "Public website" section when given.
  final CalendarWebsitePublisher? websitePublisher;
  final String requesterRole;

  /// The event's copy on the website, if it has one.
  final WebsitePublicItem? websiteItem;

  /// False when the website couldn't be read: the switch is then
  /// unavailable, so saving can't show or remove anything by mistake.
  final bool websiteStatusKnown;

  /// The signed-in admin, who uploads an event image (recorded in the
  /// image's audit trail). Without one, images can be chosen but not
  /// uploaded here.
  final AppUser? actor;

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
  late bool _showOnWebsite = widget.websiteItem != null;
  bool _saving = false;

  bool get _wasOnWebsite => widget.websiteItem != null;

  // The event's website image: a website media id (never a URL). Changed
  // only by Choose, Upload or Remove; otherwise the copy keeps its image.
  late String? _imageId = widget.websiteItem?.imageMediaId;
  bool _imageChanged = false;
  void _setImage(String? id) => setState(() {
        _imageId = id;
        _imageChanged = id != widget.websiteItem?.imageMediaId;
      });

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
        final websiteMessage = await _applyWebsiteChoice(_eventWith(data));
        if (websiteMessage != null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(websiteMessage)));
        }
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

  /// The edited event as the form has it, with its unchanged status.
  CalendarEventModel _eventWith(Map<String, dynamic> data) => CalendarEventModel.fromMap(widget.event!.id, {
        ...widget.event!.toMap(),
        ...data,
        'status': widget.event!.status,
      });

  CalendarEventModel _formEvent() => _eventWith({
        'title': _titleController.text.trim(),
        'date': DateTime(_date.year, _date.month, _date.day),
        'startTime': _formatTime(_startTime) ?? '',
        'endTime': _formatTime(_endTime) ?? '',
        'eventType': _eventType,
        'description': _descriptionController.text.trim(),
        'location': _locationController.text.trim(),
        'audience': _audience,
      });

  /// Applies "Show on website" once the event is saved. Returns what to
  /// tell the admin, or null when the website wasn't involved. A failure
  /// here leaves the saved event as it is: the message says the website
  /// wasn't changed, and the calendar shows where its copy stands.
  Future<String?> _applyWebsiteChoice(CalendarEventModel saved) async {
    final publisher = widget.websitePublisher;
    if (publisher == null) return null;
    // Said after saving too (not only in the form): the website may still
    // show this event's earlier details.
    if (!widget.websiteStatusKnown) {
      return 'Calendar item saved. The public website couldn’t be checked, so it wasn’t changed. '
          'If this event is shown there, update it once the calendar shows its website status.';
    }
    try {
      final change = await publisher.applyChoice(
        requesterRole: widget.requesterRole,
        event: saved,
        showOnWebsite: _showOnWebsite,
        wasOnWebsite: _wasOnWebsite,
        image: _imageChanged ? () => _imageId : null,
      );
      // Never reported as shown when visitors won't see it.
      final ended = CalendarWebsitePublisher.endedReason(saved);
      if (ended != null && (change == CalendarWebsiteChange.shown || change == CalendarWebsiteChange.updated)) {
        return 'Calendar item saved and copied to the public website, but not shown to visitors. $ended';
      }
      return switch (change) {
        CalendarWebsiteChange.none => null,
        CalendarWebsiteChange.shown => 'Calendar item saved and shown on the public website.',
        CalendarWebsiteChange.updated => 'Calendar item saved and updated on the public website.',
        CalendarWebsiteChange.withdrawn => 'Calendar item saved and removed from the public website.',
      };
    } catch (e) {
      return 'Calendar item saved, but the public website wasn’t changed: $e';
    }
  }

  Widget _websiteSection() {
    const heading = Text('Public website', style: TextStyle(fontWeight: FontWeight.w700));
    Widget note(String text, {Key? key}) => Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(text, key: key, style: const TextStyle(fontSize: 13)),
        );
    if (widget.event == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          heading,
          note(
            'Nothing is shown on the website automatically. After this item is saved and published, '
            'edit it to show it on the public website.',
            key: const Key('calendar-website-new-note'),
          ),
        ],
      );
    }
    if (!widget.websiteStatusKnown) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          heading,
          note(
            'The website status couldn’t be loaded, so it can’t be changed here. Reload the calendar to try again.',
            key: const Key('calendar-website-unknown-note'),
          ),
        ],
      );
    }
    // An event that is already over can't be newly shown (visitors wouldn't
    // see it); one already on the website can still be updated or removed.
    final problem = CalendarWebsitePublisher.ineligibility(_formEvent()) ?? (_wasOnWebsite ? null : CalendarWebsitePublisher.endedReason(_formEvent()));
    final on = _showOnWebsite && problem == null;
    final differences = widget.websiteItem == null ? const <String>[] : CalendarWebsitePublisher.differences(widget.event!, widget.websiteItem!);
    final explanation = switch ((problem, on, _wasOnWebsite)) {
      (final String problem, _, true) => 'Saving removes it from the website. $problem',
      (final String problem, _, false) => problem,
      (null, true, true) => differences.isNotEmpty
          ? 'The website shows an older ${differences.join(', ')}. Saving updates it with these details.'
          : 'Saving updates the website with these details.',
      (null, true, false) => 'Saving shows this event on the public website, to anyone on the internet.',
      (null, false, true) => 'Saving removes this event from the public website.',
      (null, false, false) => 'Not shown on the public website.',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        heading,
        SwitchListTile(
          key: const Key('calendar-website-switch'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Show on website'),
          value: on,
          onChanged: problem == null ? (value) => setState(() => _showOnWebsite = value) : null,
        ),
        note(explanation, key: const Key('calendar-website-explanation')),
        if (on)
          WebsiteItemImageSection(
            media: widget.websitePublisher!.mediaIfAvailable,
            requesterRole: widget.requesterRole,
            actor: widget.actor,
            initialMediaId: _imageId,
            keyPrefix: 'calendar-website-image',
            onChanged: _setImage,
          ),
      ],
    );
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
              key: const Key('calendar-event-description'),
              controller: _descriptionController,
              // Counted as the limit counts (never cut off while typing or
              // pasting): over the limit, the form says by how much and
              // can't be saved.
              decoration: InputDecoration(
                labelText: 'Description',
                counterText: '${CalendarEventModel.descriptionLength(_descriptionController.text)} / ${CalendarEventModel.maxDescriptionLength}',
                counterStyle: CalendarEventModel.descriptionProblem(_descriptionController.text) == null ? null : const TextStyle(color: Colors.red),
              ),
              maxLines: 3,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              validator: (v) => CalendarEventModel.descriptionProblem(v ?? ''),
              onChanged: (_) => setState(() {}),
            ),
            if (widget.websitePublisher != null) ...[
              const Divider(height: 32),
              _websiteSection(),
            ],
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
