// SETTINGS-02 coverage for academicYearsProvider/currentAcademicYearProvider
// — the Riverpod layer every future module should read the current
// academic year through, per SETTINGS-02's "single central source of
// truth" requirement. Service-layer business rules live in
// academic_year_service_test.dart.
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/admin/settings/data/academic_year_service.dart';
import 'package:montessori_app/modules/admin/settings/models/school_settings_model.dart';
import 'package:montessori_app/modules/admin/settings/providers/academic_year_provider.dart';

void main() {
  group('currentAcademicYearProvider', () {
    test('16. Loads the current academic year correctly once one is set', () async {
      final firestore = FakeFirebaseFirestore();
      final service = AcademicYearService(firestore: firestore);
      await service.createAcademicYear(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        name: '2026-2027',
        startDate: DateTime(2026, 6, 1),
        endDate: DateTime(2027, 5, 31),
        createdBy: 'admin-1',
        setAsCurrent: true,
      );

      final container = ProviderContainer(
        overrides: [academicYearServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);

      final year = await container.read(currentAcademicYearProvider.future);
      expect(year, isNotNull);
      expect(year!.name, '2026-2027');
      expect(year.isCurrent, isTrue);
    });

    test('17. No current academic year is handled safely (resolves to null, never throws)', () async {
      final firestore = FakeFirebaseFirestore();
      final service = AcademicYearService(firestore: firestore);
      // An academic year exists, but none has been set current yet.
      await service.createAcademicYear(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        name: '2026-2027',
        startDate: DateTime(2026, 6, 1),
        endDate: DateTime(2027, 5, 31),
        createdBy: 'admin-1',
      );

      final container = ProviderContainer(
        overrides: [academicYearServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);

      final year = await container.read(currentAcademicYearProvider.future);
      expect(year, isNull);
    });

    test('No academic year at all resolves to null, never throws', () async {
      final firestore = FakeFirebaseFirestore();
      final service = AcademicYearService(firestore: firestore);

      final container = ProviderContainer(
        overrides: [academicYearServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);

      final year = await container.read(currentAcademicYearProvider.future);
      expect(year, isNull);
    });

    test('18. Provider refresh after a current-year change is reflected once invalidated', () async {
      final firestore = FakeFirebaseFirestore();
      final service = AcademicYearService(firestore: firestore);
      final firstId = await service.createAcademicYear(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        name: '2025-2026',
        startDate: DateTime(2025, 6, 1),
        endDate: DateTime(2026, 5, 31),
        createdBy: 'admin-1',
        setAsCurrent: true,
      );
      final secondId = await service.createAcademicYear(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        name: '2026-2027',
        startDate: DateTime(2026, 6, 1),
        endDate: DateTime(2027, 5, 31),
        createdBy: 'admin-1',
      );

      final container = ProviderContainer(
        overrides: [academicYearServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);

      final before = await container.read(currentAcademicYearProvider.future);
      expect(before!.id, firstId);

      await service.setCurrentAcademicYear(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        id: secondId,
        updatedBy: 'admin-1',
      );
      // Without invalidation the FutureProvider would still serve its
      // cached (stale) value — this is exactly why every mutation site in
      // the UI calls ref.invalidate(currentAcademicYearProvider).
      container.invalidate(currentAcademicYearProvider);

      final after = await container.read(currentAcademicYearProvider.future);
      expect(after!.id, secondId);
    });
  });

  group('academicYearsProvider', () {
    test('Lists every academic year, newest first', () async {
      final firestore = FakeFirebaseFirestore();
      final service = AcademicYearService(firestore: firestore);
      await service.createAcademicYear(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        name: '2025-2026',
        startDate: DateTime(2025, 6, 1),
        endDate: DateTime(2026, 5, 31),
        createdBy: 'admin-1',
      );
      await service.createAcademicYear(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        name: '2026-2027',
        startDate: DateTime(2026, 6, 1),
        endDate: DateTime(2027, 5, 31),
        createdBy: 'admin-1',
      );

      final container = ProviderContainer(
        overrides: [academicYearServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);

      final years = await container.read(academicYearsProvider.future);
      expect(years.map((y) => y.name), ['2026-2027', '2025-2026']);
    });
  });
}
