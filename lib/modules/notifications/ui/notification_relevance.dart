import '../../admin/notifications/models/admin_notification_model.dart';

/// Whether a Parents-audience notification is relevant to a parent whose
/// children have [childStudentIds] (their own student ids) and
/// [childClassIds] (the classes those children belong to).
///
/// Traces the exact three targeting modes the Admin notification form
/// writes (admin_notification_form_dialog.dart's `_setParentsAllClasses` /
/// `_setParentsSelectedClasses` / `_setParentsSelectedStudents`):
///  - "All Classes" sets `appliesToAllClasses: true` — broadcast.
///  - "Selected Classes" sets `applicableClassIds` — relevant if any of the
///    parent's children is in one of those classes.
///  - "Selected Students" sets `applicableStudentIds` — relevant if any of
///    the parent's own children is explicitly listed.
///
/// `appliesToAllStudents` is also treated as a broadcast signal: the form
/// itself never sets it true, but AdminNotificationService.
/// seedSampleNotifications does, so both flags are honored to correctly
/// match notifications authored either way.
///
/// A `Public`-audience notification (`_setPublic()` in the form) carries
/// none of the above targeting flags — it clears them all, since Public
/// targeting is orthogonal to class/student targeting — so it's checked
/// first and short-circuits straight to relevant.
bool isNotificationRelevantToParent(
  AdminNotificationModel notification, {
  required Set<String> childStudentIds,
  required Set<String> childClassIds,
}) {
  if (notification.audience == 'Public' || notification.isPublic) {
    return true;
  }
  if (notification.appliesToAllClasses || notification.appliesToAllStudents) {
    return true;
  }
  if (notification.applicableClassIds.isNotEmpty &&
      notification.applicableClassIds.any(childClassIds.contains)) {
    return true;
  }
  if (notification.applicableStudentIds.isNotEmpty &&
      notification.applicableStudentIds.any(childStudentIds.contains)) {
    return true;
  }
  return false;
}

/// Whether a Staff-audience notification is relevant to the staff member
/// with id [staffUserId]. Mirrors `_setStaffAll` (`appliesToAllStaff: true`)
/// and `_setStaffSelected` (`applicableStaffIds`) from the same form. A
/// `Public`-audience notification is checked first, same reasoning as
/// [isNotificationRelevantToParent].
bool isNotificationRelevantToStaff(
  AdminNotificationModel notification, {
  required String staffUserId,
}) {
  if (notification.audience == 'Public' || notification.isPublic) {
    return true;
  }
  if (notification.appliesToAllStaff) return true;
  if (staffUserId.isEmpty) return false;
  return notification.applicableStaffIds.contains(staffUserId);
}
