// Regression coverage for the Parents tab's "Relationship"
// DropdownButtonFormField in admin_student_form.dart's _buildParentsTab.
//
// CORRECTION: an earlier investigation attributed the production crash
// "There should be exactly one item with DropdownButton's value:
// KNNDWfwhf4MP04Uixcxp" to THIS dropdown and reported it fixed here. The
// actual runtime stack trace subsequently captured
// (admin_student_form.dart:798, inside the LayoutBuilder at :708) proved
// the real crash was the Students tab's *Class* dropdown, not this one —
// see admin_student_form_class_dropdown_test.dart for that root cause,
// the actual fix, and the full-widget reproduction. This file's fix is
// still real and worth keeping: the Relationship dropdown had the exact
// same class of latent bug (an insufficiently-validated stored value
// reaching a DropdownButtonFormField's `initialValue`), it was a genuine
// pre-existing defect independent of the reported crash, and nothing here
// needed to be reverted.
//
// Root cause (of this dropdown's own latent bug): its `initialValue` was
// taken straight from the stored `relation` field with only an
// `isNotEmpty` check — not a check that the value is actually one of the
// four static items (Father/Mother/Guardian/Other) it offers. Any
// non-empty value outside that set (a legacy value, or a stray id) would
// reach `initialValue` with zero matching `DropdownMenuItem`s.
//
// `sanitizeParentRelation` and `normalizeParentLinks` (public top-level
// functions in admin_student_form.dart, the same pattern already
// established by `computeAttendanceSummary` in
// admin_attendance_management_screen.dart) are the fix: every raw
// `parentLinks` entry is validated against the dropdown's own item set the
// moment it's loaded, so `initialValue` can never again fail to match an
// item.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/admin/ui/admin_student_form.dart';

void main() {
  group('sanitizeParentRelation', () {
    test('Test 1 — a valid, already-correct relation passes through unchanged', () {
      expect(sanitizeParentRelation('Father'), 'Father');
      expect(sanitizeParentRelation('Mother'), 'Mother');
      expect(sanitizeParentRelation('Guardian'), 'Guardian');
      expect(sanitizeParentRelation('Other'), 'Other');
    });

    test('Test 2 — a raw parent/user id stored in the relation field falls back to Guardian, not a crash', () {
      // The exact shape of the value from the production crash report.
      expect(sanitizeParentRelation('KNNDWfwhf4MP04Uixcxp'), 'Guardian');
    });

    test('a missing or empty relation falls back to Guardian', () {
      expect(sanitizeParentRelation(null), 'Guardian');
      expect(sanitizeParentRelation(''), 'Guardian');
    });

    test('every possible output is a member of relationOptions', () {
      for (final input in [null, '', 'Father', 'garbage', 'KNNDWfwhf4MP04Uixcxp']) {
        expect(relationOptions, contains(sanitizeParentRelation(input)));
      }
    });
  });

  group('normalizeParentLinks', () {
    test('Test 2 — a stored relation that is really a parent id is corrected on load, not carried through', () {
      final result = normalizeParentLinks([
        {
          'userId': 'parent-a',
          'name': 'Asha Rao',
          'email': 'asha@example.com',
          'relation': 'KNNDWfwhf4MP04Uixcxp',
        },
      ]);

      expect(result, hasLength(1));
      expect(result.single['id'], 'parent-a');
      expect(relationOptions, contains(result.single['relation']));
      expect(result.single['relation'], 'Guardian');
    });

    test('Test 3 — duplicate parent ids in raw parentLinks are deduplicated, keeping the first occurrence', () {
      final result = normalizeParentLinks([
        {'userId': 'parent-x', 'name': 'First Write', 'relation': 'Father'},
        {'userId': 'parent-y', 'name': 'Someone Else', 'relation': 'Mother'},
        {'userId': 'parent-x', 'name': 'Second Write (stale)', 'relation': 'Guardian'},
      ]);

      expect(result.map((e) => e['id']).toList(), ['parent-x', 'parent-y']);
      expect(
        result.firstWhere((e) => e['id'] == 'parent-x')['name'],
        'First Write',
      );
    });

    test('Test 4 — an existing parent link loads with its id/name/email/phone/relation intact', () {
      final result = normalizeParentLinks([
        {
          'userId': 'parent-a',
          'name': 'Asha Rao',
          'email': 'asha@example.com',
          'phone': '9999999999',
          'relation': 'Mother',
        },
      ]);

      expect(result.single, {
        'id': 'parent-a',
        'name': 'Asha Rao',
        'email': 'asha@example.com',
        'phone': '9999999999',
        'relation': 'Mother',
        'linkedAt': null,
      });
    });

    test('Test 5 — save-then-reload round trip: the exact shape _saveParentLinks writes reloads to the same parent selected', () {
      // Mirrors _saveParentLinks' normalizedParents map shape exactly.
      final savedPayload = [
        {
          'userId': 'parent-a',
          'name': 'Asha Rao',
          'email': 'asha@example.com',
          'phone': '9999999999',
          'relation': 'Father',
          'linkedAt': 'server-timestamp-placeholder',
        },
      ];

      final reloaded = normalizeParentLinks(savedPayload);

      expect(reloaded, hasLength(1));
      expect(reloaded.single['id'], 'parent-a');
      expect(reloaded.single['relation'], 'Father');
    });

    test('Test 6 — removing a parent before save means reload never resolves it again', () {
      // Simulates _parentLinks after the delete IconButton removed
      // parent-a: _saveParentLinks only ever persists what remains in
      // _parentLinks, so the saved payload here has already dropped it.
      final savedPayloadAfterRemoval = <Map<String, dynamic>>[];

      final reloaded = normalizeParentLinks(savedPayloadAfterRemoval);

      expect(reloaded, isEmpty);
    });

    test('entries with no id are dropped rather than crashing the dropdown on an empty identifier', () {
      final result = normalizeParentLinks([
        {'name': 'No id at all', 'relation': 'Father'},
      ]);

      expect(result, isEmpty);
    });

    test('a null/absent parentLinks list normalizes to an empty list, not an error', () {
      expect(normalizeParentLinks(null), isEmpty);
    });
  });

  group('Relationship dropdown — widget-level reproduction', () {
    Widget buildDropdown(dynamic rawRelation) {
      return MaterialApp(
        home: Scaffold(
          body: DropdownButtonFormField<String>(
            initialValue: sanitizeParentRelation(rawRelation),
            items: [
              for (final option in relationOptions)
                DropdownMenuItem(value: option, child: Text(option)),
            ],
            onChanged: (_) {},
          ),
        ),
      );
    }

    testWidgets('a corrupted relation value (a raw id) no longer throws the DropdownButton assertion', (
      tester,
    ) async {
      await tester.pumpWidget(buildDropdown('KNNDWfwhf4MP04Uixcxp'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Guardian'), findsOneWidget);
    });

    testWidgets('a valid relation value renders exactly as selected', (tester) async {
      await tester.pumpWidget(buildDropdown('Mother'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Mother'), findsOneWidget);
    });
  });
}
