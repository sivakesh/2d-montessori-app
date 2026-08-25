import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// A single metric tile on the Fees Dashboard (Admin Fees screen). Purely
/// presentational — [value] is a pre-formatted display string, so this
/// widget never touches the underlying financial calculation it's showing.
class FeeSummaryCard extends StatelessWidget {
  const FeeSummaryCard({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.color,
    this.subtitle,
  });

  final String label;
  final String value;
  final IconData? icon;
  final Color? color;

  /// Optional short context line under the value (e.g. the reporting
  /// date for a today-scoped figure). Omitted entirely when null, so
  /// cards without a defined period don't imply a false one.
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.secondary;
    return Card(
      color: AppColors.card,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            CircleAvatar(backgroundColor: c.withValues(alpha: 0.1), child: Icon(icon ?? Icons.payments, color: c)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
