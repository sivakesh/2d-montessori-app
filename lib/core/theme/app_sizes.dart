class AppSizes {
  static const double buttonHeightMobile = 48;
  static const double buttonHeightWeb = 52;

  static const double borderRadiusMobile = 14;
  static const double borderRadiusWeb = 16;

  /// Shared "mobile vs desktop" chrome boundary — matches the breakpoint
  /// already used by ResponsiveLayout and AdminLayout. Screens/dialogs
  /// should reuse this instead of hardcoding their own literal.
  static const double mobileBreakpoint = 800;
}
