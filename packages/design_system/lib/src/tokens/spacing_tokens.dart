/// 4/8-point spacing scale (PRD §3.1 "Spacing"). Mobile gutters start at
/// 16px and step up to 24px on larger phones/tablets per §3.2.
abstract final class SpacingTokens {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;

  /// Page gutter at `compact` breakpoint (320–599px).
  static const double gutterCompact = md;

  /// Page gutter at `medium` breakpoint and above (600px+).
  static const double gutterMedium = lg;
}
