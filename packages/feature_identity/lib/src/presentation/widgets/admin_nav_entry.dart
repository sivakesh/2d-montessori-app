import 'package:flutter/widgets.dart';

/// One entry in [AdminShell]'s navigation drawer, supplied by the app's
/// composition root (`apps/admin_web/lib/main.dart`) rather than
/// hardcoded inside `feature_identity`. This is what lets [AdminShell]
/// stay generic infrastructure that knows nothing about which content
/// features exist — `feature_identity` must never import a sibling
/// feature package like `feature_pages` (PRD §11.1's "no feature-to-
/// feature imports" rule), and the composition root is the one place
/// that is allowed to depend on every feature and is therefore the right
/// place to decide what the admin nav contains.
@immutable
class AdminNavEntry {
  const AdminNavEntry({
    required this.icon,
    required this.label,
    required this.visible,
    required this.builder,
  });

  final IconData icon;
  final String label;

  /// Whether this entry should appear in the drawer at all — computed by
  /// the caller (typically `RolePermissionMatrix.hasFull(session.role,
  /// someCapability)`), not by [AdminShell]. Hidden, not just disabled,
  /// for roles that lack the capability: a permanently-disabled entry is
  /// noise, not a real affordance.
  final bool visible;

  /// Builds the section's body. Callers should still wrap privilege-
  /// gated content in `RoleGuardedSection` here as defense-in-depth, the
  /// same way the previous hardcoded "Users" entry did — hiding the nav
  /// entry alone is a UX nicety, never the actual access control.
  final WidgetBuilder builder;
}
