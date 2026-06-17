import 'package:flutter/material.dart';

class MoodIntensitySelector extends StatelessWidget {
  const MoodIntensitySelector({
    super.key,
    required this.value,
    required this.onChanged,
    required this.helperText,
  });

  final int value;
  final ValueChanged<int> onChanged;
  final String helperText;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Intensity', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          helperText,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: List.generate(5, (index) {
            final level = index + 1;
            return ChoiceChip(
              label: Text('$level'),
              selected: value == level,
              onSelected: (_) => onChanged(level),
            );
          }),
        ),
      ],
    );
  }
}
