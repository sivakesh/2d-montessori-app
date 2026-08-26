// FEES-AY-IMPLEMENT-01 coverage: the additive `academicYearId` field on
// FeeStructureModel/StudentFeeAssignmentModel — pure model-level
// round-tripping, no Firestore/widget setup needed. Service/UI-level
// resolution and duplicate-detection compatibility are covered separately
// in fee_structure_academic_year_test.dart, fee_assignment_academic_year_test.dart,
// and fee_service_academic_year_test.dart.
import 'package:flutter_test/flutter_test.dart';
import 'package:montessori_app/modules/fees/models/fee_structure_model.dart';
import 'package:montessori_app/modules/fees/models/student_fee_assignment_model.dart';

void main() {
  group('FeeStructureModel — academicYearId (FEES-AY-IMPLEMENT-01)', () {
    test('1. academicYearId round-trips through fromMap', () {
      final model = FeeStructureModel.fromMap('f1', {
        'name': 'Core Fees',
        'description': '',
        'components': [],
        'totalAmount': 30000,
        'academicYear': '2026-2027',
        'academicYearId': 'ay-2026',
        'isActive': true,
        'createdBy': 'admin',
      });

      expect(model.academicYear, '2026-2027');
      expect(model.academicYearId, 'ay-2026');
    });

    test('2. Missing academicYearId defaults to \'\' — never invented', () {
      final model = FeeStructureModel.fromMap('f1', {
        'name': 'Core Fees',
        'description': '',
        'components': [],
        'totalAmount': 30000,
        'academicYear': '2026-2027',
        'isActive': true,
        'createdBy': 'admin',
      });

      expect(model.academicYearId, '');
      expect(model.academicYear, '2026-2027');
    });

    test('3. A legacy document (academicYear only) remains fully readable', () {
      final model = FeeStructureModel.fromMap('f1', {
        'name': 'Legacy Fees',
        'description': 'Pre-migration structure',
        'components': [],
        'totalAmount': 15000,
        'academicYear': '2025-2026',
        'isActive': true,
        'createdBy': 'admin',
      });

      expect(model.name, 'Legacy Fees');
      expect(model.totalAmount, 15000.0);
      expect(model.academicYear, '2025-2026');
      expect(model.academicYearId, '');
    });

    test('toMap() writes both fields', () {
      final model = FeeStructureModel.fromMap('f1', {
        'name': 'Core Fees',
        'description': '',
        'components': [],
        'totalAmount': 30000,
        'academicYear': '2026-2027',
        'academicYearId': 'ay-2026',
        'isActive': true,
        'createdBy': 'admin',
      });

      final map = model.toMap();
      expect(map['academicYear'], '2026-2027');
      expect(map['academicYearId'], 'ay-2026');
    });
  });

  group('StudentFeeAssignmentModel — academicYearId (FEES-AY-IMPLEMENT-01)', () {
    Map<String, dynamic> baseAssignmentMap() => {
          'studentId': 's1',
          'studentName': 'Student One',
          'admissionNo': 'ADM1',
          'classId': 'class-1',
          'className': 'Mont 1',
          'feeStructureId': 'f1',
          'feeStructureName': 'Core Fees',
          'academicYear': '2026-2027',
          'totalFee': 20000,
          'discountAmount': 0,
          'payableAmount': 20000,
          'paidAmount': 0,
          'balanceAmount': 20000,
          'status': 'unpaid',
        };

    test('academicYearId round-trips through fromMap', () {
      final data = baseAssignmentMap()..['academicYearId'] = 'ay-2026';
      final model = StudentFeeAssignmentModel.fromMap('a1', data);

      expect(model.academicYear, '2026-2027');
      expect(model.academicYearId, 'ay-2026');
    });

    test('Missing academicYearId defaults to \'\' — never invented', () {
      final model = StudentFeeAssignmentModel.fromMap('a1', baseAssignmentMap());

      expect(model.academicYearId, '');
      expect(model.academicYear, '2026-2027');
    });

    test('A legacy assignment document remains fully readable', () {
      final model = StudentFeeAssignmentModel.fromMap('a1', baseAssignmentMap());

      expect(model.studentId, 's1');
      expect(model.feeStructureId, 'f1');
      expect(model.totalFee, 20000.0);
      expect(model.academicYear, '2026-2027');
      expect(model.academicYearId, '');
    });

    test('toMap() writes both fields', () {
      final data = baseAssignmentMap()..['academicYearId'] = 'ay-2026';
      final model = StudentFeeAssignmentModel.fromMap('a1', data);

      final map = model.toMap();
      expect(map['academicYear'], '2026-2027');
      expect(map['academicYearId'], 'ay-2026');
    });
  });
}
