// AY-IMPLEMENT-02-B coverage: AdminClassModel's additive `academicYearId`
// field — pure model-level round-tripping, no Firestore/widget setup
// needed. Service/UI-level resolution (which field wins, mismatch
// handling, ...) is covered separately in class_form_academic_year_test.dart
// and admin_student_form_academic_year_test.dart.
import 'package:flutter_test/flutter_test.dart';
import 'package:montessori_app/modules/admin/models/admin_class_model.dart';

void main() {
  group('AdminClassModel — academicYearId (AY-IMPLEMENT-02-B)', () {
    test('1. Legacy Class with academicYear only loads, academicYearId empty', () {
      final model = AdminClassModel.fromMap('c1', {
        'name': 'Mont 2',
        'academicYear': '2026-2027',
        'isActive': true,
      });

      expect(model.academicYear, '2026-2027');
      expect(model.academicYearId, '');
    });

    test('2. New Class with academicYear + academicYearId loads both', () {
      final model = AdminClassModel.fromMap('c1', {
        'name': 'Mont 2',
        'academicYear': '2026-2027',
        'academicYearId': 'ay-2026',
        'isActive': true,
      });

      expect(model.academicYear, '2026-2027');
      expect(model.academicYearId, 'ay-2026');
    });

    test('3. Missing both fields loads safely — never invented, never throws', () {
      final model = AdminClassModel.fromMap('c1', {
        'name': 'Mont 2',
        'isActive': true,
      });

      expect(model.academicYear, '');
      expect(model.academicYearId, '');
    });

    test('4. toMap() writes both fields for a new record', () {
      final model = AdminClassModel.fromMap('c1', {
        'name': 'Mont 2',
        'section': 'A',
        'academicYear': '2026-2027',
        'academicYearId': 'ay-2026',
        'capacity': 20,
        'teacherId': '',
        'teacherName': 'Ms. Priya',
        'description': '',
        'isActive': true,
        'approvalStatus': 'Approved',
        'createdBy': 'admin',
      });

      final map = model.toMap();
      expect(map['academicYear'], '2026-2027');
      expect(map['academicYearId'], 'ay-2026');
    });

    test('A non-empty academicYearId is never guessed/derived from the name — fromMap is a literal read', () {
      // Same academicYear text, deliberately different (even disagreeing)
      // academicYearId values — fromMap must reflect exactly what's stored,
      // never re-deriving the id from the name.
      final agreeing = AdminClassModel.fromMap('c1', {
        'academicYear': '2026-2027',
        'academicYearId': 'ay-2026',
      });
      final disagreeing = AdminClassModel.fromMap('c2', {
        'academicYear': '2026-2027',
        'academicYearId': 'ay-2025',
      });

      expect(agreeing.academicYearId, 'ay-2026');
      expect(disagreeing.academicYearId, 'ay-2025');
      expect(disagreeing.academicYear, agreeing.academicYear, reason: 'text is identical; only the id differs');
    });
  });
}
