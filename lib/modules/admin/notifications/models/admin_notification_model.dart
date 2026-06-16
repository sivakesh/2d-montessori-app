import 'package:cloud_firestore/cloud_firestore.dart';

class AdminNotificationModel {
  AdminNotificationModel({
    required this.id,
    required this.title,
    required this.message,
    required this.notificationType,
    required this.category,
    required this.priority,
    required this.audience,
    required this.visibility,
    required this.status,
    required this.academicYear,
    required this.publishDate,
    required this.expiryDate,
    required this.createdBy,
    required this.createdByName,
    required this.createdAt,
    required this.updatedAt,
    required this.sentAt,
    required this.isPinned,
    required this.requiresAcknowledgement,
    required this.attachmentName,
    required this.attachmentUrl,
    required this.attachmentSize,
    required this.attachmentMimeType,
    required this.appliesToAllClasses,
    required this.applicableClassIds,
    required this.applicableClassNames,
    required this.appliesToAllStudents,
    required this.applicableStudentIds,
    required this.applicableStudentNames,
    required this.appliesToAllStaff,
    required this.applicableStaffIds,
    required this.applicableStaffNames,
    required this.isPublic,
  });

  final String id;
  final String title;
  final String message;
  final String notificationType;
  final String category;
  final String priority;
  final String audience;
  final String visibility;
  final String status;
  final String academicYear;
  final DateTime? publishDate;
  final DateTime? expiryDate;
  final String createdBy;
  final String createdByName;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? sentAt;
  final bool isPinned;
  final bool requiresAcknowledgement;
  final String attachmentName;
  final String attachmentUrl;
  final int? attachmentSize;
  final String attachmentMimeType;
  final bool appliesToAllClasses;
  final List<String> applicableClassIds;
  final List<String> applicableClassNames;
  final bool appliesToAllStudents;
  final List<String> applicableStudentIds;
  final List<String> applicableStudentNames;
  final bool appliesToAllStaff;
  final List<String> applicableStaffIds;
  final List<String> applicableStaffNames;
  final bool isPublic;

  factory AdminNotificationModel.fromMap(String id, Map<String, dynamic> map) {
    DateTime? parseDate(dynamic v) {
      if (v is DateTime) return v;
      if (v is Timestamp) return v.toDate();
      return null;
    }

    List<String> parseList(dynamic v) => (v as List<dynamic>? ?? const []).map((e) => e.toString()).toList();

    return AdminNotificationModel(
      id: id,
      title: map['title']?.toString() ?? '',
      message: map['message']?.toString() ?? '',
      notificationType: map['notificationType']?.toString() ?? '',
      category: map['category']?.toString() ?? '',
      priority: map['priority']?.toString() ?? 'Normal',
      audience: map['audience']?.toString() ?? 'Parents',
      visibility: map['visibility']?.toString() ?? 'Parents',
      status: map['status']?.toString() ?? 'Draft',
      academicYear: map['academicYear']?.toString() ?? '',
      publishDate: parseDate(map['publishDate']),
      expiryDate: parseDate(map['expiryDate']),
      createdBy: map['createdBy']?.toString() ?? '',
      createdByName: map['createdByName']?.toString() ?? '',
      createdAt: parseDate(map['createdAt']),
      updatedAt: parseDate(map['updatedAt']),
      sentAt: parseDate(map['sentAt']),
      isPinned: map['isPinned'] == true,
      requiresAcknowledgement: map['requiresAcknowledgement'] == true,
      attachmentName: map['attachmentName']?.toString() ?? '',
      attachmentUrl: map['attachmentUrl']?.toString() ?? '',
      attachmentSize: int.tryParse(map['attachmentSize']?.toString() ?? ''),
      attachmentMimeType: map['attachmentMimeType']?.toString() ?? '',
      appliesToAllClasses: map['appliesToAllClasses'] == true,
      applicableClassIds: parseList(map['applicableClassIds']),
      applicableClassNames: parseList(map['applicableClassNames']),
      appliesToAllStudents: map['appliesToAllStudents'] == true,
      applicableStudentIds: parseList(map['applicableStudentIds']),
      applicableStudentNames: parseList(map['applicableStudentNames']),
      appliesToAllStaff: map['appliesToAllStaff'] == true,
      applicableStaffIds: parseList(map['applicableStaffIds']),
      applicableStaffNames: parseList(map['applicableStaffNames']),
      isPublic: map['isPublic'] == true,
    );
  }

  Map<String, dynamic> toMap() => {
        'title': title,
        'message': message,
        'notificationType': notificationType,
        'category': category,
        'priority': priority,
        'audience': audience,
        'visibility': visibility,
        'status': status,
        'academicYear': academicYear,
        'publishDate': publishDate,
        'expiryDate': expiryDate,
        'createdBy': createdBy,
        'createdByName': createdByName,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'sentAt': sentAt,
        'isPinned': isPinned,
        'requiresAcknowledgement': requiresAcknowledgement,
        'attachmentName': attachmentName,
        'attachmentUrl': attachmentUrl,
        'attachmentSize': attachmentSize,
        'attachmentMimeType': attachmentMimeType,
        'appliesToAllClasses': appliesToAllClasses,
        'applicableClassIds': applicableClassIds,
        'applicableClassNames': applicableClassNames,
        'appliesToAllStudents': appliesToAllStudents,
        'applicableStudentIds': applicableStudentIds,
        'applicableStudentNames': applicableStudentNames,
        'appliesToAllStaff': appliesToAllStaff,
        'applicableStaffIds': applicableStaffIds,
        'applicableStaffNames': applicableStaffNames,
        'isPublic': isPublic,
      };
}
