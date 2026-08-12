/// Viewport tokens from PRD §3.2. Mobile (`compact`) is the implementation
/// baseline, not a compressed desktop layout — every responsive decision
/// must live here or in template contracts, never as page-specific magic
/// numbers (PRD §3.2 bullet 3).
enum ViewportToken { compact, medium, expanded, wide }

abstract final class Breakpoints {
  static const double compactMin = 320;
  static const double mediumMin = 600;
  static const double expandedMin = 1024;
  static const double wideMin = 1440;

  static ViewportToken tokenForWidth(double width) {
    if (width >= wideMin) return ViewportToken.wide;
    if (width >= expandedMin) return ViewportToken.expanded;
    if (width >= mediumMin) return ViewportToken.medium;
    return ViewportToken.compact;
  }
}
