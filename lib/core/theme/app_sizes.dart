class AppSizes {
  static const double buttonHeightMobile = 48;
  static const double buttonHeightWeb = 52;

  static const double borderRadiusMobile = 14;
  static const double borderRadiusWeb = 16;

  /// Shared "mobile vs desktop" chrome boundary — matches the breakpoint
  /// already used by ResponsiveLayout and AdminLayout. Screens/dialogs
  /// should reuse this instead of hardcoding their own literal.
  static const double mobileBreakpoint = 800;

  /// Extra bottom clearance a scrollable screen must reserve so its last
  /// item can scroll fully clear of a floating AdminFab (which doesn't
  /// reserve layout space of its own). Screens with a FAB should add this
  /// to their trailing spacer instead of picking their own number.
  static const double fabScrollClearance = 96;
}
