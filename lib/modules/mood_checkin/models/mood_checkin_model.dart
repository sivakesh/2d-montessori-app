import 'package:cloud_firestore/cloud_firestore.dart';

class MoodCheckinModel {
  const MoodCheckinModel({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.entityName,
    required this.moodCode,
    required this.moodLabel,
    required this.moodCategory,
    required this.intensity,
    required this.source,
    required this.checkInAt,
    required this.createdAt,
    required this.createdBy,
    this.classId,
    this.className,
    this.notes,
    this.attendanceId,
    this.photoUrl,
  });

  final String id;
  final String entityType;
  final String entityId;
  final String entityName;
  final String? classId;
  final String? className;
  final String moodCode;
  final String moodLabel;
  final String moodCategory;
  final int intensity;
  final String? notes;
  final String source;
  final String? attendanceId;
  final String? photoUrl;
  final DateTime? checkInAt;
  final DateTime? createdAt;
  final String createdBy;

  factory MoodCheckinModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return MoodCheckinModel(
      id: doc.id,
      entityType: data['entityType']?.toString() ?? '',
      entityId: data['entityId']?.toString() ?? '',
      entityName: data['entityName']?.toString() ?? '',
      classId: data['classId']?.toString(),
      className: data['className']?.toString(),
      moodCode: data['moodCode']?.toString() ?? '',
      moodLabel: data['moodLabel']?.toString() ?? '',
      moodCategory: data['moodCategory']?.toString() ?? '',
      intensity: int.tryParse(data['intensity']?.toString() ?? '') ?? 3,
      notes: data['notes']?.toString(),
      source: data['source']?.toString() ?? 'manual',
      attendanceId: data['attendanceId']?.toString(),
      photoUrl: data['photoUrl']?.toString(),
      checkInAt: (data['checkInAt'] as Timestamp?)?.toDate(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      createdBy: data['createdBy']?.toString() ?? '',
    );
  }
}
