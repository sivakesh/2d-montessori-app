// AY-IMPLEMENT-03 coverage (items 24-27): MoodCheckinService.getMoodCheckinsForAcademicYear
// — the one module in this task that uses a genuine server-side range
// query (two clauses on the single checkInAt field, no other filter
// combined, so no composite index is required — see _academicYearQuery's
// own doc comment). Never writes or reads academicYearId; the mood
// check-in schema itself is untouched.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/admin/settings/data/academic_year_service.dart';
import 'package:montessori_app/modules/admin/settings/models/academic_year_date_range.dart';
import 'package:montessori_app/modules/admin/settings/models/school_settings_model.dart';
import 'package:montessori_app/modules/mood_checkin/services/mood_checkin_service.dart';

Future<void> _seedCheckin(
  FakeFirebaseFirestore firestore, {
  required String id,
  required DateTime checkInAt,
}) {
  return firestore.collection('mood_checkins').doc(id).set({
    'entityType': 'student',
    'entityId': 's1',
    'entityName': 'Student One',
    'moodCode': 'happy',
    'moodLabel': 'Happy',
    'moodCategory': 'positive',
    'intensity': 3,
    'source': 'self',
    'checkInAt': Timestamp.fromDate(checkInAt),
    'createdAt': Timestamp.fromDate(checkInAt),
    'createdBy': 'u1',
  });
}

Future<AcademicYearDateRange> _seedCurrentYearRange(FakeFirebaseFirestore firestore) async {
  final ayService = AcademicYearService(firestore: firestore);
  final id = await ayService.createAcademicYear(
    schoolId: kDefaultSchoolId,
    requesterRole: 'admin',
    name: '2026-2027',
    startDate: DateTime(2026, 6, 1),
    endDate: DateTime(2027, 3, 30),
    createdBy: 'admin-1',
  );
  final year = await ayService.getAcademicYearById(schoolId: kDefaultSchoolId, id: id);
  return AcademicYearDateRange.fromAcademicYear(year!);
}

void main() {
  group('MoodCheckinService academic-year reporting (AY-IMPLEMENT-03)', () {
    test('24. A check-in within the Academic Year is included', () async {
      final firestore = FakeFirebaseFirestore();
      await _seedCheckin(firestore, id: 'c1', checkInAt: DateTime(2026, 12, 25, 10, 30));
      final range = await _seedCurrentYearRange(firestore);
      final service = MoodCheckinService(firestore: firestore, storage: MockFirebaseStorage());

      final result = await service.getMoodCheckinsForAcademicYear(range);
      expect(result.any((c) => c.id == 'c1'), isTrue);
    });

    test('25. A check-in outside the Academic Year range is excluded', () async {
      final firestore = FakeFirebaseFirestore();
      await _seedCheckin(firestore, id: 'before', checkInAt: DateTime(2026, 5, 31, 23, 59));
      await _seedCheckin(firestore, id: 'after', checkInAt: DateTime(2027, 3, 31, 0, 0));
      final range = await _seedCurrentYearRange(firestore);
      final service = MoodCheckinService(firestore: firestore, storage: MockFirebaseStorage());

      final result = await service.getMoodCheckinsForAcademicYear(range);
      final ids = result.map((c) => c.id).toSet();
      expect(ids, isNot(contains('before')));
      expect(ids, isNot(contains('after')));
    });

    test('26. A check-in late in the evening on the Academic Year end date is still included (queryUpperBound boundary correctness)', () async {
      final firestore = FakeFirebaseFirestore();
      await _seedCheckin(firestore, id: 'lateOnEndDate', checkInAt: DateTime(2027, 3, 30, 23, 59, 59));
      final range = await _seedCurrentYearRange(firestore);
      final service = MoodCheckinService(firestore: firestore, storage: MockFirebaseStorage());

      final result = await service.getMoodCheckinsForAcademicYear(range);
      expect(result.any((c) => c.id == 'lateOnEndDate'), isTrue,
          reason: 'using range.end (midnight) directly as the upper bound would have wrongly excluded this');
    });

    test('27. No academicYearId is written to any mood check-in document by this feature', () async {
      final firestore = FakeFirebaseFirestore();
      await _seedCheckin(firestore, id: 'c2', checkInAt: DateTime(2026, 12, 25, 10, 30));
      final range = await _seedCurrentYearRange(firestore);
      final service = MoodCheckinService(firestore: firestore, storage: MockFirebaseStorage());

      await service.getMoodCheckinsForAcademicYear(range);

      final doc = await firestore.collection('mood_checkins').doc('c2').get();
      expect(doc.data()!.containsKey('academicYearId'), isFalse);
    });
  });
}
