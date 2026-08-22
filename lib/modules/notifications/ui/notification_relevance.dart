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
bool isNotificationRelevantToParent(
  AdminNotificationModel notification, {
  required Set<String> childStudentIds,
  required Set<String> childClassIds,
}) {
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
/// and `_setStaffSelected` (`applicableStaffIds`) from the same form.
bool isNotificationRelevantToStaff(
  AdminNotificationModel notification, {
  required String staffUserId,
}) {
  if (notification.appliesToAllStaff) return true;
  if (staffUserId.isEmpty) return false;
  return notification.applicableStaffIds.contains(staffUserId);
}
