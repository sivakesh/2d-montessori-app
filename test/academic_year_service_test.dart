// SETTINGS-02 coverage for AcademicYearService — the Academic Year
// data/authorization/business-rules layer. UI-level coverage (navigation,
// access-restricted rendering, responsive/no-overflow, create/edit/set-
// current flows) lives in academic_year_navigation_test.dart. Provider
// coverage lives in academic_year_provider_test.dart.
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/admin/settings/data/academic_year_service.dart';
import 'package:montessori_app/modules/admin/settings/models/academic_year_model.dart';
import 'package:montessori_app/modules/admin/settings/models/school_settings_model.dart';

AcademicYearService _service(FakeFirebaseFirestore firestore) =>
    AcademicYearService(firestore: firestore);

Future<String> _create(
  AcademicYearService service, {
  String schoolId = kDefaultSchoolId,
  String role = 'admin',
  required String name,
  required DateTime start,
  required DateTime end,
  bool setAsCurrent = false,
  String createdBy = 'admin-1',
}) {
  return service.createAcademicYear(
    schoolId: schoolId,
    requesterRole: role,
    name: name,
    startDate: start,
    endDate: end,
    createdBy: createdBy,
    setAsCurrent: setAsCurrent,
  );
}

void main() {
  group('AcademicYearService — load', () {
    test('1. Empty list when nothing has been created yet', () async {
      final service = _service(FakeFirebaseFirestore());
      final years = await service.getAllAcademicYears(schoolId: kDefaultSchoolId);
      expect(years, isEmpty);
    });

    test('2. Create academic year persists it', () async {
      final service = _service(FakeFirebaseFirestore());
      final id = await _create(
        service,
        name: '2026-2027',
        start: DateTime(2026, 6, 1),
        end: DateTime(2027, 5, 31),
      );
      expect(id, isNotEmpty);
      final years = await service.getAllAcademicYears(schoolId: kDefaultSchoolId);
      expect(years, hasLength(1));
      expect(years.single.name, '2026-2027');
      expect(years.single.isActive, isTrue);
      expect(years.single.isCurrent, isFalse);
    });

    test('3. Load a single academic year by id', () async {
      final service = _service(FakeFirebaseFirestore());
      final id = await _create(
        service,
        name: '2026-2027',
        start: DateTime(2026, 6, 1),
        end: DateTime(2027, 5, 31),
      );
      final year = await service.getAcademicYearById(schoolId: kDefaultSchoolId, id: id);
      expect(year, isNotNull);
      expect(year!.name, '2026-2027');
      expect(year.startDate, DateTime(2026, 6, 1));
      expect(year.endDate, DateTime(2027, 5, 31));
    });

    test('A non-existent id resolves to null, not an error', () async {
      final service = _service(FakeFirebaseFirestore());
      final year = await service.getAcademicYearById(schoolId: kDefaultSchoolId, id: 'ghost');
      expect(year, isNull);
    });
  });

  group('AcademicYearService — update', () {
    test('4. Update academic year changes name and dates', () async {
      final service = _service(FakeFirebaseFirestore());
      final id = await _create(
        service,
        name: '2026-2027',
        start: DateTime(2026, 6, 1),
        end: DateTime(2027, 5, 31),
      );

      await service.updateAcademicYear(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        id: id,
        name: '2026-2027 (Revised)',
        startDate: DateTime(2026, 6, 15),
        endDate: DateTime(2027, 5, 31),
        updatedBy: 'admin-2',
      );

      final year = await service.getAcademicYearById(schoolId: kDefaultSchoolId, id: id);
      expect(year!.name, '2026-2027 (Revised)');
      expect(year.startDate, DateTime(2026, 6, 15));
      expect(year.updatedBy, 'admin-2');
    });

    test('Updating a non-existent academic year throws AcademicYearNotFoundException', () async {
      final service = _service(FakeFirebaseFirestore());
      expect(
        () => service.updateAcademicYear(
          schoolId: kDefaultSchoolId,
          requesterRole: 'admin',
          id: 'ghost',
          name: 'X',
          startDate: DateTime(2026, 6, 1),
          endDate: DateTime(2027, 5, 31),
          updatedBy: 'admin-1',
        ),
        throwsA(isA<AcademicYearNotFoundException>()),
      );
    });

    test('Updating a year to its own unchanged range is allowed (self-excluded from overlap/duplicate checks)', () async {
      final service = _service(FakeFirebaseFirestore());
      final id = await _create(
        service,
        name: '2026-2027',
        start: DateTime(2026, 6, 1),
        end: DateTime(2027, 5, 31),
      );

      await expectLater(
        service.updateAcademicYear(
          schoolId: kDefaultSchoolId,
          requesterRole: 'admin',
          id: id,
          name: '2026-2027',
          startDate: DateTime(2026, 6, 1),
          endDate: DateTime(2027, 5, 31),
          updatedBy: 'admin-1',
        ),
        completes,
      );
    });
  });

  group('AcademicYearService — current year', () {
    test('5. Set current marks the target year current', () async {
      final service = _service(FakeFirebaseFirestore());
      final id = await _create(
        service,
        name: '2026-2027',
        start: DateTime(2026, 6, 1),
        end: DateTime(2027, 5, 31),
      );

      await service.setCurrentAcademicYear(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        id: id,
        updatedBy: 'admin-1',
      );

      final current = await service.getCurrentAcademicYear(schoolId: kDefaultSchoolId);
      expect(current, isNotNull);
      expect(current!.id, id);
      expect(current.isCurrent, isTrue);
    });

    test('6. Setting a new current year automatically unsets the previous current year', () async {
      final service = _service(FakeFirebaseFirestore());
      final firstId = await _create(
        service,
        name: '2025-2026',
        start: DateTime(2025, 6, 1),
        end: DateTime(2026, 5, 31),
        setAsCurrent: true,
      );
      final secondId = await _create(
        service,
        name: '2026-2027',
        start: DateTime(2026, 6, 1),
        end: DateTime(2027, 5, 31),
      );

      await service.setCurrentAcademicYear(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        id: secondId,
        updatedBy: 'admin-1',
      );

      final first = await service.getAcademicYearById(schoolId: kDefaultSchoolId, id: firstId);
      final second = await service.getAcademicYearById(schoolId: kDefaultSchoolId, id: secondId);
      expect(first!.isCurrent, isFalse, reason: 'the previous current year must be unset');
      expect(second!.isCurrent, isTrue);
    });

    test('7. There is only ever one current year across any number of academic years', () async {
      final service = _service(FakeFirebaseFirestore());
      final ids = <String>[];
      for (var y = 2023; y <= 2026; y++) {
        ids.add(await _create(
          service,
          name: '$y-${y + 1}',
          start: DateTime(y, 6, 1),
          end: DateTime(y + 1, 5, 31),
        ));
      }
      for (final id in ids) {
        await service.setCurrentAcademicYear(
          schoolId: kDefaultSchoolId,
          requesterRole: 'admin',
          id: id,
          updatedBy: 'admin-1',
        );
      }
      final years = await service.getAllAcademicYears(schoolId: kDefaultSchoolId);
      expect(years.where((y) => y.isCurrent), hasLength(1));
      expect(years.firstWhere((y) => y.isCurrent).id, ids.last);
    });

    test('createAcademicYear with setAsCurrent unsets any prior current year in the same call', () async {
      final service = _service(FakeFirebaseFirestore());
      final firstId = await _create(
        service,
        name: '2025-2026',
        start: DateTime(2025, 6, 1),
        end: DateTime(2026, 5, 31),
        setAsCurrent: true,
      );
      await _create(
        service,
        name: '2026-2027',
        start: DateTime(2026, 6, 1),
        end: DateTime(2027, 5, 31),
        setAsCurrent: true,
      );

      final years = await service.getAllAcademicYears(schoolId: kDefaultSchoolId);
      expect(years.where((y) => y.isCurrent), hasLength(1));
      final first = await service.getAcademicYearById(schoolId: kDefaultSchoolId, id: firstId);
      expect(first!.isCurrent, isFalse);
    });

    test('Setting current on an already-current year is a harmless no-op', () async {
      final service = _service(FakeFirebaseFirestore());
      final id = await _create(
        service,
        name: '2026-2027',
        start: DateTime(2026, 6, 1),
        end: DateTime(2027, 5, 31),
        setAsCurrent: true,
      );
      await expectLater(
        service.setCurrentAcademicYear(
          schoolId: kDefaultSchoolId,
          requesterRole: 'admin',
          id: id,
          updatedBy: 'admin-1',
        ),
        completes,
      );
      final years = await service.getAllAcademicYears(schoolId: kDefaultSchoolId);
      expect(years.where((y) => y.isCurrent), hasLength(1));
    });

    test('Setting current on a non-existent id throws AcademicYearNotFoundException', () async {
      final service = _service(FakeFirebaseFirestore());
      expect(
        () => service.setCurrentAcademicYear(
          schoolId: kDefaultSchoolId,
          requesterRole: 'admin',
          id: 'ghost',
          updatedBy: 'admin-1',
        ),
        throwsA(isA<AcademicYearNotFoundException>()),
      );
    });

    test('Setting an inactive (deactivated) year as current is rejected', () async {
      final service = _service(FakeFirebaseFirestore());
      final oldId = await _create(
        service,
        name: '2024-2025',
        start: DateTime(2024, 6, 1),
        end: DateTime(2025, 5, 31),
      );
      final currentId = await _create(
        service,
        name: '2026-2027',
        start: DateTime(2026, 6, 1),
        end: DateTime(2027, 5, 31),
        setAsCurrent: true,
      );
      await service.deactivateAcademicYear(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        id: oldId,
        updatedBy: 'admin-1',
      );

      expect(
        () => service.setCurrentAcademicYear(
          schoolId: kDefaultSchoolId,
          requesterRole: 'admin',
          id: oldId,
          updatedBy: 'admin-1',
        ),
        throwsA(isA<AcademicYearValidationException>()),
      );
      final current = await service.getCurrentAcademicYear(schoolId: kDefaultSchoolId);
      expect(current!.id, currentId, reason: 'the rejected attempt must not change who is current');
    });
  });

  group('AcademicYearService — validation', () {
    test('8. Overlapping academic year is rejected', () async {
      final service = _service(FakeFirebaseFirestore());
      await _create(
        service,
        name: '2026-27',
        start: DateTime(2026, 6, 1),
        end: DateTime(2027, 5, 31),
      );

      expect(
        () => _create(
          service,
          name: '2026-27-A',
          start: DateTime(2027, 1, 1),
          end: DateTime(2027, 12, 31),
        ),
        throwsA(isA<AcademicYearOverlapException>()),
      );
      final years = await service.getAllAcademicYears(schoolId: kDefaultSchoolId);
      expect(years, hasLength(1), reason: 'a rejected overlapping create must not write anything');
    });

    test('9. End date before start date is rejected', () async {
      final service = _service(FakeFirebaseFirestore());
      expect(
        () => _create(
          service,
          name: 'Backwards',
          start: DateTime(2027, 5, 31),
          end: DateTime(2026, 6, 1),
        ),
        throwsA(isA<AcademicYearValidationException>()),
      );
    });

    test('Same start/end date (zero-length range) is rejected', () async {
      final service = _service(FakeFirebaseFirestore());
      expect(
        () => _create(
          service,
          name: 'Zero Length',
          start: DateTime(2026, 6, 1),
          end: DateTime(2026, 6, 1),
        ),
        throwsA(isA<AcademicYearValidationException>()),
      );
    });

    test('10. Duplicate (identical) date range is rejected as an overlap', () async {
      final service = _service(FakeFirebaseFirestore());
      await _create(
        service,
        name: '2026-2027',
        start: DateTime(2026, 6, 1),
        end: DateTime(2027, 5, 31),
      );
      expect(
        () => _create(
          service,
          name: '2026-2027 Duplicate',
          start: DateTime(2026, 6, 1),
          end: DateTime(2027, 5, 31),
        ),
        throwsA(isA<AcademicYearOverlapException>()),
      );
    });

    test('Duplicate name (even with a non-overlapping range) is rejected', () async {
      final service = _service(FakeFirebaseFirestore());
      await _create(
        service,
        name: '2026-2027',
        start: DateTime(2026, 6, 1),
        end: DateTime(2027, 5, 31),
      );
      expect(
        () => _create(
          service,
          name: '2026-2027',
          start: DateTime(2028, 6, 1),
          end: DateTime(2029, 5, 31),
        ),
        throwsA(isA<AcademicYearValidationException>()),
      );
    });

    test('Blank name is rejected and nothing is written', () async {
      final service = _service(FakeFirebaseFirestore());
      expect(
        () => _create(
          service,
          name: '   ',
          start: DateTime(2026, 6, 1),
          end: DateTime(2027, 5, 31),
        ),
        throwsA(isA<AcademicYearValidationException>()),
      );
      final years = await service.getAllAcademicYears(schoolId: kDefaultSchoolId);
      expect(years, isEmpty);
    });

    test('Adjacent (back-to-back, non-overlapping) ranges are allowed', () async {
      final service = _service(FakeFirebaseFirestore());
      await _create(
        service,
        name: '2025-2026',
        start: DateTime(2025, 6, 1),
        end: DateTime(2026, 5, 31),
      );
      await expectLater(
        _create(
          service,
          name: '2026-2027',
          start: DateTime(2026, 6, 1),
          end: DateTime(2027, 5, 31),
        ),
        completes,
      );
    });

    test('Updating a year to overlap another existing year is rejected', () async {
      final service = _service(FakeFirebaseFirestore());
      await _create(
        service,
        name: '2025-2026',
        start: DateTime(2025, 6, 1),
        end: DateTime(2026, 5, 31),
      );
      final secondId = await _create(
        service,
        name: '2027-2028',
        start: DateTime(2027, 6, 1),
        end: DateTime(2028, 5, 31),
      );

      expect(
        () => service.updateAcademicYear(
          schoolId: kDefaultSchoolId,
          requesterRole: 'admin',
          id: secondId,
          name: '2027-2028',
          startDate: DateTime(2025, 12, 1),
          endDate: DateTime(2026, 12, 1),
          updatedBy: 'admin-1',
        ),
        throwsA(isA<AcademicYearOverlapException>()),
      );
    });
  });

  group('AcademicYearService — deactivate / activate', () {
    test('11. Deactivate keeps the record but marks it inactive', () async {
      final service = _service(FakeFirebaseFirestore());
      final id = await _create(
        service,
        name: '2024-2025',
        start: DateTime(2024, 6, 1),
        end: DateTime(2025, 5, 31),
      );
      await service.deactivateAcademicYear(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        id: id,
        updatedBy: 'admin-1',
      );
      final year = await service.getAcademicYearById(schoolId: kDefaultSchoolId, id: id);
      expect(year, isNotNull, reason: 'deactivating must never delete the record');
      expect(year!.isActive, isFalse);
      expect(year.name, '2024-2025', reason: 'deactivating must not alter any other field');
    });

    test('12. A deactivated (historical) year remains accessible via getAllAcademicYears/getAcademicYearById', () async {
      final service = _service(FakeFirebaseFirestore());
      final id = await _create(
        service,
        name: '2023-2024',
        start: DateTime(2023, 6, 1),
        end: DateTime(2024, 5, 31),
      );
      await service.deactivateAcademicYear(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        id: id,
        updatedBy: 'admin-1',
      );

      final years = await service.getAllAcademicYears(schoolId: kDefaultSchoolId);
      expect(years.map((y) => y.id), contains(id));
      final byId = await service.getAcademicYearById(schoolId: kDefaultSchoolId, id: id);
      expect(byId, isNotNull);
    });

    test('Reactivating a deactivated year via activateAcademicYear works', () async {
      final service = _service(FakeFirebaseFirestore());
      final id = await _create(
        service,
        name: '2024-2025',
        start: DateTime(2024, 6, 1),
        end: DateTime(2025, 5, 31),
      );
      await service.deactivateAcademicYear(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        id: id,
        updatedBy: 'admin-1',
      );
      await service.activateAcademicYear(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        id: id,
        updatedBy: 'admin-1',
      );
      final year = await service.getAcademicYearById(schoolId: kDefaultSchoolId, id: id);
      expect(year!.isActive, isTrue);
    });

    test('Deactivating the current academic year is rejected', () async {
      final service = _service(FakeFirebaseFirestore());
      final id = await _create(
        service,
        name: '2026-2027',
        start: DateTime(2026, 6, 1),
        end: DateTime(2027, 5, 31),
        setAsCurrent: true,
      );
      expect(
        () => service.deactivateAcademicYear(
          schoolId: kDefaultSchoolId,
          requesterRole: 'admin',
          id: id,
          updatedBy: 'admin-1',
        ),
        throwsA(isA<AcademicYearValidationException>()),
      );
      final year = await service.getAcademicYearById(schoolId: kDefaultSchoolId, id: id);
      expect(year!.isActive, isTrue, reason: 'the rejected attempt must not change anything');
    });
  });

  group('AcademicYearService — authorization', () {
    test('13. Staff is denied create/update/setCurrent/deactivate/activate', () async {
      final service = _service(FakeFirebaseFirestore());
      final id = await _create(
        service,
        name: '2026-2027',
        start: DateTime(2026, 6, 1),
        end: DateTime(2027, 5, 31),
      );

      expect(
        () => _create(service, role: 'staff', name: 'Hijack', start: DateTime(2030, 6, 1), end: DateTime(2031, 5, 31)),
        throwsA(isA<UnauthorizedAcademicYearException>()),
      );
      expect(
        () => service.updateAcademicYear(
          schoolId: kDefaultSchoolId,
          requesterRole: 'staff',
          id: id,
          name: 'Hijack',
          startDate: DateTime(2026, 6, 1),
          endDate: DateTime(2027, 5, 31),
          updatedBy: 'staff-1',
        ),
        throwsA(isA<UnauthorizedAcademicYearException>()),
      );
      expect(
        () => service.setCurrentAcademicYear(
          schoolId: kDefaultSchoolId,
          requesterRole: 'staff',
          id: id,
          updatedBy: 'staff-1',
        ),
        throwsA(isA<UnauthorizedAcademicYearException>()),
      );
      expect(
        () => service.deactivateAcademicYear(
          schoolId: kDefaultSchoolId,
          requesterRole: 'staff',
          id: id,
          updatedBy: 'staff-1',
        ),
        throwsA(isA<UnauthorizedAcademicYearException>()),
      );
      expect(
        () => service.activateAcademicYear(
          schoolId: kDefaultSchoolId,
          requesterRole: 'staff',
          id: id,
          updatedBy: 'staff-1',
        ),
        throwsA(isA<UnauthorizedAcademicYearException>()),
      );

      final years = await service.getAllAcademicYears(schoolId: kDefaultSchoolId);
      expect(years, hasLength(1), reason: 'no denied mutation may have written anything');
    });

    test('14. Parent is denied create/update/setCurrent/deactivate/activate', () async {
      final service = _service(FakeFirebaseFirestore());
      final id = await _create(
        service,
        name: '2026-2027',
        start: DateTime(2026, 6, 1),
        end: DateTime(2027, 5, 31),
      );

      expect(
        () => _create(service, role: 'parent', name: 'Hijack', start: DateTime(2030, 6, 1), end: DateTime(2031, 5, 31)),
        throwsA(isA<UnauthorizedAcademicYearException>()),
      );
      expect(
        () => service.updateAcademicYear(
          schoolId: kDefaultSchoolId,
          requesterRole: 'parent',
          id: id,
          name: 'Hijack',
          startDate: DateTime(2026, 6, 1),
          endDate: DateTime(2027, 5, 31),
          updatedBy: 'parent-1',
        ),
        throwsA(isA<UnauthorizedAcademicYearException>()),
      );
      expect(
        () => service.setCurrentAcademicYear(
          schoolId: kDefaultSchoolId,
          requesterRole: 'parent',
          id: id,
          updatedBy: 'parent-1',
        ),
        throwsA(isA<UnauthorizedAcademicYearException>()),
      );
      expect(
        () => service.deactivateAcademicYear(
          schoolId: kDefaultSchoolId,
          requesterRole: 'parent',
          id: id,
          updatedBy: 'parent-1',
        ),
        throwsA(isA<UnauthorizedAcademicYearException>()),
      );

      final years = await service.getAllAcademicYears(schoolId: kDefaultSchoolId);
      expect(years, hasLength(1));
    });

    test('Reads (list/current/byId) are never role-gated — Staff/Parent can read', () async {
      final service = _service(FakeFirebaseFirestore());
      await _create(
        service,
        name: '2026-2027',
        start: DateTime(2026, 6, 1),
        end: DateTime(2027, 5, 31),
        setAsCurrent: true,
      );
      final staffList = await service.getAllAcademicYears(schoolId: kDefaultSchoolId);
      final parentCurrent = await service.getCurrentAcademicYear(schoolId: kDefaultSchoolId);
      expect(staffList, hasLength(1));
      expect(parentCurrent, isNotNull);
    });
  });

  group('AcademicYearService — schoolId isolation', () {
    test('15. Academic years for one schoolId are never visible under, or affect overlap checks for, another schoolId', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);

      await _create(
        service,
        schoolId: 'school-a',
        name: '2026-2027',
        start: DateTime(2026, 6, 1),
        end: DateTime(2027, 5, 31),
      );

      final bYears = await service.getAllAcademicYears(schoolId: 'school-b');
      expect(bYears, isEmpty);

      // Same date range under a different schoolId must NOT be treated as
      // an overlap — the two schools' academic years are fully isolated.
      await expectLater(
        _create(
          service,
          schoolId: 'school-b',
          name: '2026-2027',
          start: DateTime(2026, 6, 1),
          end: DateTime(2027, 5, 31),
        ),
        completes,
      );

      final aYears = await service.getAllAcademicYears(schoolId: 'school-a');
      final bYearsAfter = await service.getAllAcademicYears(schoolId: 'school-b');
      expect(aYears, hasLength(1));
      expect(bYearsAfter, hasLength(1));

      final snap = await firestore.collection('academic_years').get();
      expect(snap.docs, hasLength(2));
    });
  });

  group('AcademicYearModel — helpers', () {
    test('suggestName derives a hyphenated year label from the date range', () {
      expect(
        AcademicYearValidation.suggestName(DateTime(2026, 6, 1), DateTime(2027, 5, 31)),
        '2026-2027',
      );
      expect(
        AcademicYearValidation.suggestName(DateTime(2026, 1, 1), DateTime(2026, 12, 31)),
        '2026',
      );
    });

    test('containsDate / overlaps are date-only (time-of-day ignored)', () {
      final year = AcademicYearModel(
        id: 'y1',
        schoolId: kDefaultSchoolId,
        name: '2026-2027',
        startDate: DateTime(2026, 6, 1),
        endDate: DateTime(2027, 5, 31),
        isCurrent: false,
        isActive: true,
        createdAt: null,
        updatedAt: null,
      );
      expect(year.containsDate(DateTime(2026, 8, 25, 23, 59)), isTrue);
      expect(year.containsDate(DateTime(2025, 12, 31)), isFalse);
      expect(year.containsDate(DateTime(2027, 6, 1)), isFalse);
      expect(year.overlaps(DateTime(2027, 1, 1), DateTime(2027, 12, 31)), isTrue);
      expect(year.overlaps(DateTime(2027, 6, 1), DateTime(2028, 5, 31)), isFalse);
    });
  });
}
