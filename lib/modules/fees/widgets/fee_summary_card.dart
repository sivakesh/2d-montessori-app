import 'package:flutter/material.dart';

class FeeSummaryCard extends StatelessWidget {
  const FeeSummaryCard({super.key, required this.label, required this.value, this.icon, this.color});
  final String label;
  final String value;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? const Color(0xFF2E7D32);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(backgroundColor: c.withValues(alpha: 0.1), child: Icon(icon ?? Icons.payments, color: c)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label), const SizedBox(height: 4), Text(value, style: Theme.of(context).textTheme.titleLarge)])),
          ],
        ),
      ),
    );
  }
}
