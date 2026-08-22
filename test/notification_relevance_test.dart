// Regression coverage for the Parent/Staff notification feeds' relevance
// filter — a pure function over an already-fetched, audience-narrowed
// notification list, no Firestore access. See notification_relevance.dart
// for why appliesToAllClasses/appliesToAllStudents are both treated as
// broadcast signals.
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/admin/notifications/models/admin_notification_model.dart';
import 'package:montessori_app/modules/notifications/ui/notification_relevance.dart';

AdminNotificationModel _notification({
  bool appliesToAllClasses = false,
  List<String> applicableClassIds = const [],
  bool appliesToAllStudents = false,
  List<String> applicableStudentIds = const [],
  bool appliesToAllStaff = false,
  List<String> applicableStaffIds = const [],
}) {
  return AdminNotificationModel(
    id: 'n1',
    title: 'Title',
    message: 'Message',
    notificationType: 'General',
    category: 'General',
    priority: 'Normal',
    audience: 'Parents',
    visibility: 'Parents',
    status: 'Published',
    academicYear: '2026-2027',
    publishDate: null,
    expiryDate: null,
    createdBy: 'admin',
    createdByName: 'Admin',
    createdAt: null,
    updatedAt: null,
    sentAt: null,
    isPinned: false,
    requiresAcknowledgement: false,
    attachmentName: '',
    attachmentUrl: '',
    attachmentSize: null,
    attachmentMimeType: '',
    appliesToAllClasses: appliesToAllClasses,
    applicableClassIds: applicableClassIds,
    applicableClassNames: const [],
    appliesToAllStudents: appliesToAllStudents,
    applicableStudentIds: applicableStudentIds,
    applicableStudentNames: const [],
    appliesToAllStaff: appliesToAllStaff,
    applicableStaffIds: applicableStaffIds,
    applicableStaffNames: const [],
    isPublic: false,
  );
}

void main() {
  group('isNotificationRelevantToParent', () {
    test('appliesToAllClasses (the "All Classes" broadcast mode) is relevant to every parent', () {
      final n = _notification(appliesToAllClasses: true);
      expect(
        isNotificationRelevantToParent(n, childStudentIds: {}, childClassIds: {}),
        isTrue,
      );
    });

    test('appliesToAllStudents (the seed-data broadcast flag) is also relevant to every parent', () {
      final n = _notification(appliesToAllStudents: true);
      expect(
        isNotificationRelevantToParent(n, childStudentIds: {}, childClassIds: {}),
        isTrue,
      );
    });

    test('selected-classes targeting matches a parent whose child is in that class', () {
      final n = _notification(applicableClassIds: ['class-mont1']);
      expect(
        isNotificationRelevantToParent(
          n,
          childStudentIds: {'student-1'},
          childClassIds: {'class-mont1'},
        ),
        isTrue,
      );
    });

    test('selected-classes targeting excludes a parent whose child is in a different class', () {
      final n = _notification(applicableClassIds: ['class-mont1']);
      expect(
        isNotificationRelevantToParent(
          n,
          childStudentIds: {'student-1'},
          childClassIds: {'class-mont2'},
        ),
        isFalse,
      );
    });

    test('selected-students targeting matches only the explicitly listed child', () {
      final n = _notification(applicableStudentIds: ['student-1']);
      expect(
        isNotificationRelevantToParent(
          n,
          childStudentIds: {'student-1'},
          childClassIds: {},
        ),
        isTrue,
      );
      expect(
        isNotificationRelevantToParent(
          n,
          childStudentIds: {'student-2'},
          childClassIds: {},
        ),
        isFalse,
      );
    });

    test('no broadcast flag and empty target lists is not relevant to anyone', () {
      final n = _notification();
      expect(
        isNotificationRelevantToParent(
          n,
          childStudentIds: {'student-1'},
          childClassIds: {'class-mont1'},
        ),
        isFalse,
      );
    });
  });

  group('isNotificationRelevantToStaff', () {
    test('appliesToAllStaff is relevant to every staff member', () {
      final n = _notification(appliesToAllStaff: true);
      expect(isNotificationRelevantToStaff(n, staffUserId: 'staff-1'), isTrue);
    });

    test('selected-staff targeting matches only the listed staff id', () {
      final n = _notification(applicableStaffIds: ['staff-1']);
      expect(isNotificationRelevantToStaff(n, staffUserId: 'staff-1'), isTrue);
      expect(isNotificationRelevantToStaff(n, staffUserId: 'staff-2'), isFalse);
    });

    test('an empty staff id is never relevant unless the notification is a broadcast', () {
      final n = _notification(applicableStaffIds: ['staff-1']);
      expect(isNotificationRelevantToStaff(n, staffUserId: ''), isFalse);
    });
  });
}
