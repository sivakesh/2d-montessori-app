import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// Canonical Admin "Add" FAB — background, icon color, elevation, and
/// shape/size are defined once here so every Admin screen renders an
/// identical FAB instead of drifting (several screens had hardcoded a
/// brighter, unrelated green — Color(0xFF2E7D32) — instead of reusing
/// AppColors.primary, the app's actual dark-green brand token).
class AdminFab extends StatelessWidget {
  const AdminFab({super.key, required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      backgroundColor: AppColors.primary,
      elevation: 4,
      onPressed: onPressed,
      child: Icon(icon, color: Colors.white),
    );
  }
}
