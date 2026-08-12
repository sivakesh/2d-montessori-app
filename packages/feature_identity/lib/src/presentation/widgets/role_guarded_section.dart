import 'package:core_contracts/core_contracts.dart';
import 'package:flutter/widgets.dart';

import '../screens/access_denied_screen.dart';

/// Wraps a section of the admin app so navigating to it directly (now, a
/// nav item; later, a deep link) always re-checks the SRS §3 capability —
/// hiding the nav entry is a UX nicety, not the guard itself (SRS
/// "Security enforcement... UI hiding alone is never considered access
/// control" — same principle applied client-side as belt-and-braces on
/// top of the server-side Firestore/Functions checks).
class RoleGuardedSection extends StatelessWidget {
  const RoleGuardedSection({
    super.key,
    required this.role,
    required this.capability,
    required this.builder,
  });

  final UserRole role;
  final Capability capability;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    if (!RolePermissionMatrix.hasFull(role, capability)) {
      return const AccessDeniedScreen();
    }
    return Builder(builder: builder);
  }
}
