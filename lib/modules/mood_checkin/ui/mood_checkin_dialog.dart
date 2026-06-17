import 'package:flutter/material.dart';

import '../models/mood_option_model.dart';
import '../widgets/mood_intensity_selector.dart';
import '../widgets/mood_option_chip.dart';

class MoodCheckinDialogResult {
  const MoodCheckinDialogResult({
    required this.moodCode,
    required this.moodLabel,
    required this.moodCategory,
    required this.intensity,
    this.notes,
  });

  final String moodCode;
  final String moodLabel;
  final String moodCategory;
  final int intensity;
  final String? notes;
}

class MoodCheckinDialog extends StatefulWidget {
  const MoodCheckinDialog({super.key, required this.entityType});

  final String entityType;

  static Future<MoodCheckinDialogResult?> show(
    BuildContext context, {
    required String entityType,
  }) {
    return showDialog<MoodCheckinDialogResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: MoodCheckinDialog(entityType: entityType),
      ),
    );
  }

  @override
  State<MoodCheckinDialog> createState() => _MoodCheckinDialogState();
}

class _MoodCheckinDialogState extends State<MoodCheckinDialog> {
  MoodOptionModel? _selected;
  int _intensity = 3;
  final _notesController = TextEditingController();

  bool get _isStaff => widget.entityType == 'staff';
  List<MoodOptionModel> get _options => _isStaff ? staffMoodOptions : studentMoodOptions;

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  String get _title => _isStaff ? 'Staff Wellbeing Check-In' : 'Student Mood Check-In';
  String get _subtitle =>
      _isStaff ? 'How does the staff member appear today?' : 'How does the child appear right now?';
  String get _notesHint => _isStaff
      ? 'Add a short note if needed'
      : 'Add a short observation if needed';
  String get _intensityHelper => _isStaff
      ? 'How strongly is this wellbeing state observed?'
      : 'How strongly is this mood observed?';

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            _subtitle,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final option in _options)
                MoodOptionChip(
                  option: option,
                  selected: _selected?.moodCode == option.moodCode,
                  onTap: () => setState(() => _selected = option),
                ),
            ],
          ),
          const SizedBox(height: 20),
          MoodIntensitySelector(
            value: _intensity,
            onChanged: (value) => setState(() => _intensity = value),
            helperText: _intensityHelper,
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _notesController,
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: 'Notes',
              hintText: _notesHint,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _selected == null
                      ? null
                      : () {
                          Navigator.of(context).pop(
                            MoodCheckinDialogResult(
                              moodCode: _selected!.moodCode,
                              moodLabel: _selected!.moodLabel,
                              moodCategory: _selected!.moodCategory,
                              intensity: _intensity,
                              notes: _notesController.text.trim().isEmpty
                                  ? null
                                  : _notesController.text.trim(),
                            ),
                          );
                        },
                  child: const Text('Continue'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
