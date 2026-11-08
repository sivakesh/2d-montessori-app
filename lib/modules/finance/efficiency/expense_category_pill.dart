import 'package:flutter/material.dart';

import 'expense_efficiency_models.dart';

/// The one colour mapping for assessment categories, used everywhere a
/// category is shown in Expense Efficiency: a light tint background, a
/// darker border and dark text of the same hue (high contrast, not
/// saturated). Display only: categories and stored values are unchanged.
@immutable
class ExpenseCategoryStyle {
  const ExpenseCategoryStyle({required this.background, required this.border, required this.foreground});
  final Color background, border, foreground;

  static ExpenseCategoryStyle of(ExpenseAssessmentCategory c) => switch (c) {
        ExpenseAssessmentCategory.necessary => _from(Colors.green),
        ExpenseAssessmentCategory.useful => _from(Colors.blue),
        ExpenseAssessmentCategory.waste => _from(Colors.red),
        // orange.shade900 text is too light on its tint (3.5:1); a deeper
        // orange keeps the hue at 5.1:1.
        ExpenseAssessmentCategory.excessive =>
          ExpenseCategoryStyle(background: Colors.orange.shade50, border: Colors.orange.shade200, foreground: Colors.deepOrange.shade900),
        ExpenseAssessmentCategory.underReview => ExpenseCategoryStyle(background: Colors.grey.shade100, border: Colors.grey.shade400, foreground: Colors.grey.shade800),
      };

  static ExpenseCategoryStyle _from(MaterialColor c) => ExpenseCategoryStyle(background: c.shade50, border: c.shade200, foreground: c.shade900);
}

/// A rounded pill showing an assessment category's name in its colours.
/// Sized to its text, so long names are never clipped.
class ExpenseCategoryPill extends StatelessWidget {
  const ExpenseCategoryPill(this.category, {super.key});

  final ExpenseAssessmentCategory category;

  @override
  Widget build(BuildContext context) {
    final s = ExpenseCategoryStyle.of(category);
    return Semantics(
      label: 'Assessment: ${category.label}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(color: s.background, border: Border.all(color: s.border), borderRadius: BorderRadius.circular(999)),
        child: Text(
          category.label,
          softWrap: false,
          style: TextStyle(fontSize: 12, height: 1.3, fontWeight: FontWeight.w600, color: s.foreground),
        ),
      ),
    );
  }
}
