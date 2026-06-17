import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../models/mood_checkin_model.dart';

class MoodCheckinService {
  MoodCheckinService({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
    ImagePicker? imagePicker,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance,
        _imagePicker = imagePicker ?? ImagePicker();

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;
  final ImagePicker _imagePicker;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('mood_checkins');

  Query<Map<String, dynamic>> _todayQuery() {
    final today = DateTime.now().toLocal();
    final start = DateTime(today.year, today.month, today.day);
    final end = start.add(const Duration(days: 1));
    return _collection
        .where('checkInAt', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('checkInAt', isLessThan: Timestamp.fromDate(end));
  }

  Future<int> getTodayMoodCheckinCount() async {
    final docs = await _todayQuery().get();
    return docs.docs.length;
  }

  Future<int> getTodayAlertCount() async {
    final docs = await _todayQuery().get();
    const alertCategories = {'distress', 'anger', 'worry', 'high_stress', 'health'};
    return docs.docs.where((doc) {
      final category = doc.data()['moodCategory']?.toString() ?? '';
      return alertCategories.contains(category);
    }).length;
  }

  Future<List<MoodCheckinModel>> getLatestTodayMoodCheckins({int limit = 5}) async {
    final snapshot = await _todayQuery()
        .orderBy('checkInAt', descending: true)
        .limit(limit)
        .get();
    return snapshot.docs.map(MoodCheckinModel.fromFirestore).toList();
  }

  Future<List<MoodCheckinModel>> getTodayMoodCheckinsForEntity({
    required String entityType,
    required String entityId,
    int limit = 20,
  }) async {
    final snapshot = await _collection
        .where('entityType', isEqualTo: entityType)
        .where('entityId', isEqualTo: entityId)
        .limit(limit)
        .get();

    final docs = snapshot.docs.toList();

    final today = DateTime.now().toLocal();
    final startOfToday = DateTime(today.year, today.month, today.day);
    final endOfToday = startOfToday.add(const Duration(days: 1));
    docs.sort((a, b) {
      DateTime resolve(Map<String, dynamic> data) {
        final checkIn = data['checkInAt'];
        if (checkIn is Timestamp) return checkIn.toDate();
        if (checkIn is DateTime) return checkIn;
        final created = data['createdAt'];
        if (created is Timestamp) return created.toDate();
        if (created is DateTime) return created;
        return DateTime.fromMillisecondsSinceEpoch(0);
      }

      return resolve(b.data()).compareTo(resolve(a.data()));
    });
    final filtered = docs.where((doc) {
      final data = doc.data();
      final resolved = data['checkInAt'] is Timestamp
          ? (data['checkInAt'] as Timestamp).toDate()
          : data['createdAt'] is Timestamp
              ? (data['createdAt'] as Timestamp).toDate()
              : data['checkInAt'] is DateTime
                  ? data['checkInAt'] as DateTime
                  : data['createdAt'] is DateTime
                      ? data['createdAt'] as DateTime
                      : null;
      if (resolved == null) return false;
      return !resolved.isBefore(startOfToday) && resolved.isBefore(endOfToday);
    }).toList();

    return filtered.map(MoodCheckinModel.fromFirestore).toList();
  }

  Future<String?> uploadOptionalMoodPhoto({
    required String entityType,
    required String entityId,
  }) async {
    final picked = await _imagePicker.pickImage(
      source: ImageSource.camera,
      imageQuality: 60,
      maxWidth: 1200,
    );
    if (picked == null) return null;

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final path = 'mood_checkins/$entityType/$entityId/${timestamp}_photo.jpg';
    final ref = _storage.ref().child(path);

    if (kIsWeb) {
      final bytes = await picked.readAsBytes();
      final snapshot = await ref.putData(bytes);
      return snapshot.ref.getDownloadURL();
    }

    final snapshot = await ref.putFile(File(picked.path));
    return snapshot.ref.getDownloadURL();
  }

  Future<String> createMoodCheckin({
    required String entityType,
    required String entityId,
    required String entityName,
    required String moodCode,
    required String moodLabel,
    required String moodCategory,
    required int intensity,
    required String source,
    required String createdBy,
    String? classId,
    String? className,
    String? notes,
    String? attendanceId,
    String? photoUrl,
    DateTime? checkInAt,
  }) async {
    final doc = _collection.doc();
    final model = MoodCheckinModel(
      id: doc.id,
      entityType: entityType,
      entityId: entityId,
      entityName: entityName,
      classId: classId,
      className: className,
      moodCode: moodCode,
      moodLabel: moodLabel,
      moodCategory: moodCategory,
      intensity: intensity,
      notes: notes,
      source: source,
      attendanceId: attendanceId,
      photoUrl: photoUrl,
      checkInAt: checkInAt ?? DateTime.now().toLocal(),
      createdAt: DateTime.now().toLocal(),
      createdBy: createdBy,
    );
    await doc.set(model.toMap());
    return doc.id;
  }

  Stream<List<MoodCheckinModel>> watchMoodCheckinsForEntity(
    String entityType,
    String entityId,
  ) {
    return _collection
        .where('entityType', isEqualTo: entityType)
        .where('entityId', isEqualTo: entityId)
        .orderBy('checkInAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(MoodCheckinModel.fromFirestore).toList());
  }

  Stream<List<MoodCheckinModel>> watchTodayMoodCheckins() {
    return _todayQuery()
        .orderBy('checkInAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(MoodCheckinModel.fromFirestore).toList());
  }

  Stream<List<MoodCheckinModel>> watchMoodCheckinsByDateRange({
    required DateTime start,
    required DateTime end,
  }) {
    return _collection
        .where('checkInAt', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('checkInAt', isLessThan: Timestamp.fromDate(end))
        .orderBy('checkInAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(MoodCheckinModel.fromFirestore).toList());
  }

  Future<MoodCheckinModel?> getLatestMoodForEntity(String entityType, String entityId) async {
    final items = await getTodayMoodCheckinsForEntity(
      entityType: entityType,
      entityId: entityId,
    );
    if (items.isEmpty) return null;
    return items.first;
  }
}
