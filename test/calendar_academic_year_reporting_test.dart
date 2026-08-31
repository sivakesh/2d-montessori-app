// AY-IMPLEMENT-03 coverage (items 16-18): CalendarService.getEventsForAcademicYear
// — date-derived reporting support keyed off each event's own single `date`
// field. Never writes or reads academicYearId; the calendar schema itself
// is untouched.
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/admin/settings/data/academic_year_service.dart';
import 'package:montessori_app/modules/admin/settings/models/academic_year_date_range.dart';
import 'package:montessori_app/modules/admin/settings/models/school_settings_model.dart';
import 'package:montessori_app/modules/calendar/services/calendar_service.dart';

Future<void> _seedEvent(
  FakeFirebaseFirestore firestore, {
  required String id,
  required DateTime date,
}) {
  return firestore.collection('school_calendar_events').doc(id).set({
    'title': 'Event $id',
    'date': date,
    'eventType': 'event',
    'audience': 'Public',
    'status': 'published',
    'createdBy': 'admin-1',
    'createdByName': 'Admin',
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
  group('CalendarService academic-year reporting (AY-IMPLEMENT-03)', () {
    test('16. An event on the Academic Year start date is included', () async {
      final firestore = FakeFirebaseFirestore();
      await _seedEvent(firestore, id: 'e1', date: DateTime(2026, 6, 1));
      final range = await _seedCurrentYearRange(firestore);
      final service = CalendarService(firestore: firestore);

      final result = await service.getEventsForAcademicYear(range);
      expect(result.any((e) => e.id == 'e1'), isTrue);
    });

    test('17. An event outside the Academic Year range is excluded', () async {
      final firestore = FakeFirebaseFirestore();
      await _seedEvent(firestore, id: 'inside', date: DateTime(2026, 12, 25));
      await _seedEvent(firestore, id: 'before', date: DateTime(2026, 5, 31));
      await _seedEvent(firestore, id: 'after', date: DateTime(2027, 3, 31));
      final range = await _seedCurrentYearRange(firestore);
      final service = CalendarService(firestore: firestore);

      final result = await service.getEventsForAcademicYear(range);
      final ids = result.map((e) => e.id).toSet();
      expect(ids, contains('inside'));
      expect(ids, isNot(contains('before')));
      expect(ids, isNot(contains('after')));
    });

    test('18. No academicYearId is written to any calendar event document by this feature', () async {
      final firestore = FakeFirebaseFirestore();
      await _seedEvent(firestore, id: 'e2', date: DateTime(2026, 12, 25));
      final range = await _seedCurrentYearRange(firestore);
      final service = CalendarService(firestore: firestore);

      await service.getEventsForAcademicYear(range);

      final doc = await firestore.collection('school_calendar_events').doc('e2').get();
      expect(doc.data()!.containsKey('academicYearId'), isFalse);
    });
  });
}
