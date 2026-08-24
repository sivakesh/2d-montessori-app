import 'package:cloud_firestore/cloud_firestore.dart';

/// Fixed category list for the school calendar's "Event Type" field, per the
/// School Operations MVP spec. Kept as plain string constants (not a Dart
/// `enum`) to match every other status/category field in this codebase
/// (AdminNotificationModel.status, StudentFeeAssignmentModel.status, etc.),
/// none of which use enums.
class CalendarEventType {
  static const schoolHoliday = 'School Holiday';
  static const workingDay = 'Working Day';
  static const event = 'Event';
  static const exam = 'Exam';
  static const parentMeeting = 'Parent Meeting';
  static const staffMeeting = 'Staff Meeting';
  static const otherActivity = 'Other School Activity';

  static const all = [
    schoolHoliday,
    workingDay,
    event,
    exam,
    parentMeeting,
    staffMeeting,
    otherActivity,
  ];
}

/// Lifecycle status, mirroring AdminNotificationModel's Draft/Published/
/// Archived convention exactly (minus 'Scheduled', which the calendar MVP
/// doesn't need) so a reader already familiar with that model recognizes
/// this one immediately.
class CalendarEventStatus {
  static const draft = 'Draft';
  static const published = 'Published';
  static const archived = 'Archived';
}

class CalendarEventModel {
  CalendarEventModel({
    required this.id,
    required this.title,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.eventType,
    required this.description,
    required this.location,
    required this.audience,
    required this.status,
    required this.createdBy,
    required this.createdByName,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final DateTime date;
  /// Optional "HH:mm" (24-hour) time-of-day strings — kept as plain text
  /// rather than a second Timestamp field since a calendar item's time is
  /// always on the same day as [date] and never needs its own date part.
  final String? startTime;
  final String? endTime;
  final String eventType;
  final String description;
  final String location;
  /// 'Parents' | 'Staff' | 'Public' — reuses AdminNotificationModel's exact
  /// audience vocabulary so `isNotificationRelevantToParent`/
  /// `isNotificationRelevantToStaff`-style "Public reaches everyone" logic
  /// stays consistent across the app.
  final String audience;
  final String status;
  final String createdBy;
  final String createdByName;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isPublished => status == CalendarEventStatus.published;

  factory CalendarEventModel.fromMap(String id, Map<String, dynamic> map) {
    DateTime? parseDate(dynamic v) {
      if (v is DateTime) return v;
      if (v is Timestamp) return v.toDate();
      return null;
    }

    return CalendarEventModel(
      id: id,
      title: map['title']?.toString() ?? '',
      date: parseDate(map['date']) ?? DateTime(2000),
      startTime: (map['startTime']?.toString().isEmpty ?? true)
          ? null
          : map['startTime'].toString(),
      endTime: (map['endTime']?.toString().isEmpty ?? true)
          ? null
          : map['endTime'].toString(),
      eventType: map['eventType']?.toString() ?? CalendarEventType.event,
      description: map['description']?.toString() ?? '',
      location: map['location']?.toString() ?? '',
      audience: map['audience']?.toString() ?? 'Public',
      status: map['status']?.toString() ?? CalendarEventStatus.draft,
      createdBy: map['createdBy']?.toString() ?? '',
      createdByName: map['createdByName']?.toString() ?? '',
      createdAt: parseDate(map['createdAt']),
      updatedAt: parseDate(map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() => {
        'title': title,
        'date': date,
        'startTime': startTime ?? '',
        'endTime': endTime ?? '',
        'eventType': eventType,
        'description': description,
        'location': location,
        'audience': audience,
        'status': status,
        'createdBy': createdBy,
        'createdByName': createdByName,
      };
}
