/// Subtle 150–300ms transitions per PRD §3.1 "Motion". System reduced-motion
/// preference always overrides (PRD §3.6) — read it via
/// `MediaQuery.disableAnimationsOf(context)` at the call site.
abstract final class MotionTokens {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration standard = Duration(milliseconds: 220);
  static const Duration slow = Duration(milliseconds: 300);

  /// Minimum interactive touch target, both axes (PRD §3.2 bullet 2).
  static const double minTouchTarget = 44;
}
