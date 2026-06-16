import 'package:flutter/material.dart';

class FinanceStatusChip extends StatelessWidget {
  const FinanceStatusChip({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(label),
      backgroundColor: color.withOpacity(0.12),
      labelStyle: TextStyle(color: color, fontWeight: FontWeight.w600),
      side: BorderSide(color: color.withOpacity(0.3)),
    );
  }
}
