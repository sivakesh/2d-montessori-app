import 'package:cloud_firestore/cloud_firestore.dart';

import '../../admin/notifications/data/admin_notification_service.dart';
import '../../admin/settings/models/academic_year_date_range.dart';
import '../models/calendar_event_model.dart';

class CalendarService {
  CalendarService({
    FirebaseFirestore? firestore,
    AdminNotificationService? notificationService,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _injectedNotificationService = notificationService;

  final FirebaseFirestore _firestore;
  final AdminNotificationService? _injectedNotificationService;

  // Lazily built exactly like FeeService's `_financeService` getter, so
  // publishing a calendar event can notify its audience via the existing
  // notification infrastructure without every caller having to construct
  // one.
  AdminNotificationService get _notificationService =>
      _injectedNotificationService ?? AdminNotificationService();

  CollectionReference<Map<String, dynamic>> get _events =>
      _firestore.collection('school_calendar_events');

  /// Every calendar item regardless of status — Admin management view only.
  Future<List<CalendarEventModel>> getAllEvents() async {
    final snap = await _events.get();
    final items = snap.docs
        .map((d) => CalendarEventModel.fromMap(d.id, d.data()))
        .toList();
    items.sort((a, b) => a.date.compareTo(b.date));
    return items;
  }

  /// AY-IMPLEMENT-03: every calendar item (any status) whose single [date]
  /// falls within one Academic Year — reuses [getAllEvents] and filters
  /// client-side, the same convention [getEventsForAudience] already uses
  /// for its own status filtering, rather than a server-side range query
  /// (this collection has no existing date-range query to build on, and no
  /// event model supports multi-day/recurring spans — see AY-AUDIT-02 §6).
  /// Never writes or reads an `academicYearId` — the calendar schema itself
  /// is completely untouched.
  Future<List<CalendarEventModel>> getEventsForAcademicYear(
    AcademicYearDateRange range,
  ) async {
    final all = await getAllEvents();
    return all.where((e) => range.contains(e.date)).toList();
  }

  /// Published items visible to one consumer audience ('Parents' or
  /// 'Staff'), matched against that audience or 'Public' — same shape as
  /// AdminNotificationService.getNotificationsForAudience, so a Draft or
  /// Archived item, or one published for the other audience only, never
  /// reaches Parents/Staff.
  Future<List<CalendarEventModel>> getEventsForAudience(
    String audience,
  ) async {
    final snap =
        await _events.where('audience', whereIn: [audience, 'Public']).get();
    final items = snap.docs
        .map((d) => CalendarEventModel.fromMap(d.id, d.data()))
        .where((e) => e.status == CalendarEventStatus.published)
        .toList();
    items.sort((a, b) => a.date.compareTo(b.date));
    return items;
  }

  Future<String> createEvent(Map<String, dynamic> data) async {
    final doc = _events.doc();
    await doc.set({
      ...data,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  Future<void> updateEvent(String id, Map<String, dynamic> data) async {
    await _events.doc(id).update({
      ...data,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> publishEvent(CalendarEventModel event) async {
    await _events.doc(event.id).set({
      'status': CalendarEventStatus.published,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // Best-effort: a calendar publish is useful to announce, but a
    // notification-write failure must never undo or fail the publish
    // itself.
    try {
      final notificationId = await _notificationService.createNotification({
        'title': 'Calendar: ${event.title}',
        'message': event.description.isNotEmpty
            ? event.description
            : '${event.eventType} on ${event.date.toIso8601String().split('T').first}',
        'notificationType': 'Calendar',
        'category': 'Calendar',
        'priority': 'Normal',
        'audience': event.audience,
        'visibility': event.audience,
        'status': 'Draft',
        'academicYear': '',
        'appliesToAllClasses': false,
        'applicableClassIds': const [],
        'applicableClassNames': const [],
        'appliesToAllStudents': event.audience != 'Staff',
        'applicableStudentIds': const [],
        'applicableStudentNames': const [],
        'appliesToAllStaff': event.audience != 'Parents',
        'applicableStaffIds': const [],
        'applicableStaffNames': const [],
        'isPublic': event.audience == 'Public',
        'createdBy': event.createdBy,
        'createdByName': event.createdByName,
      });
      await _notificationService.publishNotification(notificationId);
    } catch (_) {
      // Ignored — the calendar item is already published; notifying is a
      // secondary effect.
    }
  }

  Future<void> archiveEvent(String id) async {
    await _events.doc(id).set({
      'status': CalendarEventStatus.archived,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Permanently removes one calendar event by id. Unlike [archiveEvent]
  /// (a reversible status change that keeps the document for Admin
  /// history), this is a genuine Firestore delete — the document is gone
  /// from [getAllEvents] (Admin) and [getEventsForAudience] (Parent/Staff)
  /// alike. Scoped to exactly this one document id, so it cannot affect any
  /// other calendar event, and it never touches `school_notifications` —
  /// a calendar item's publish notification (if any was sent) is left
  /// exactly as it was.
  Future<void> deleteEvent(String id) async {
    await _events.doc(id).delete();
  }
}
