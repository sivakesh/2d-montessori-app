import 'package:flutter/material.dart';

import '../models/mood_option_model.dart';

class MoodOptionChip extends StatelessWidget {
  const MoodOptionChip({
    super.key,
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final MoodOptionModel option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: selected ? theme.colorScheme.primary.withOpacity(0.08) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: selected ? theme.colorScheme.primary : Colors.grey.shade300),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(option.icon, size: 20, color: selected ? theme.colorScheme.primary : Colors.grey.shade700),
              const SizedBox(width: 8),
              Text(option.moodLabel),
            ],
          ),
        ),
      ),
    );
  }
}
