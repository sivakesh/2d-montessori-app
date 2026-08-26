import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/school_settings_service.dart';
import '../models/school_settings_model.dart';

/// The school's saved brand identity (name + logo), read via
/// [SchoolSettingsService.getSchoolIdentity] — the single source of truth
/// every piece of app chrome (AppSidebar, AdminSidebar) watches instead of
/// hardcoding "2D Montessori"/`assets/logo.png` directly. Not a second
/// piece of school-identity state: this provider holds no data of its own,
/// it's just a cached read of the same `school_settings` document
/// SchoolSettingsScreen edits.
///
/// Resolves to null — never throws — whenever there's nothing to show yet
/// (no settings saved, a transient read failure, etc.), so every watcher
/// can fall back to the app's existing hardcoded default identity rather
/// than ever rendering a blank/broken sidebar.
///
/// Call `ref.invalidate(schoolIdentityProvider)` after a save/logo change
/// so already-open sidebars pick up the new identity without an app
/// restart; a fresh app load re-fetches from Firestore from scratch, so
/// the new identity also survives a refresh with no extra persistence.
final schoolIdentityProvider = FutureProvider<SchoolSettingsModel?>((ref) async {
  try {
    return await SchoolSettingsService().getSchoolIdentity(schoolId: kDefaultSchoolId);
  } catch (_) {
    return null;
  }
});
