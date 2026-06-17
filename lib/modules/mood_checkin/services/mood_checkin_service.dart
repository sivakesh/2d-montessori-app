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

  Query<Map<String, dynamic>> _todayCreatedAtQuery() {
    final today = DateTime.now().toLocal();
    final start = DateTime(today.year, today.month, today.day);
    final end = start.add(const Duration(days: 1));
    return _collection
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('createdAt', isLessThan: Timestamp.fromDate(end));
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
    await doc.set({
      'id': doc.id,
      'entityType': entityType,
      'entityId': entityId,
      'entityName': entityName,
      'classId': classId,
      'className': className,
      'moodCode': moodCode,
      'moodLabel': moodLabel,
      'moodCategory': moodCategory,
      'intensity': intensity,
      'notes': notes ?? '',
      'source': source,
      'attendanceId': attendanceId,
      'photoUrl': photoUrl,
      'checkInAt': checkInAt ?? FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': createdBy,
    });
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
    final todayDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    final byCheckInAt = await _todayQuery().get();
    final byCreatedAt = await _todayCreatedAtQuery().get();

    final seenIds = <String>{};
    for (final doc in byCheckInAt.docs) {
      if (seenIds.add(doc.id)) todayDocs.add(doc);
    }
    for (final doc in byCreatedAt.docs) {
      if (seenIds.add(doc.id)) todayDocs.add(doc);
    }

    final matchingDocs = todayDocs.where((doc) {
      final data = doc.data();
      return data['entityType']?.toString() == entityType &&
          data['entityId']?.toString() == entityId;
    }).toList();

    if (matchingDocs.isEmpty) return null;

    matchingDocs.sort((a, b) {
      DateTime? resolve(Map<String, dynamic> data) {
        final checkIn = data['checkInAt'];
        if (checkIn is Timestamp) return checkIn.toDate();
        final created = data['createdAt'];
        if (created is Timestamp) return created.toDate();
        return null;
      }

      final aTime = resolve(a.data()) ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bTime = resolve(b.data()) ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bTime.compareTo(aTime);
    });

    return MoodCheckinModel.fromFirestore(matchingDocs.first);
  }
}
