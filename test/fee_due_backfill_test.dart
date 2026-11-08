// Fees -> Assignments -> Set Missing Due Dates: a read-only preview of every
// assignment without a due date, classified by its fee structure's
// configured due-date settings (FeeDueDate.defaultFor), then, once
// confirmed, only the missing `dueDate` written, each record re-read and
// rechecked inside a transaction. Existing due dates, amounts, payments,
// receipts and Finance entries are never touched. Synthetic test data only.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/admin/settings/data/academic_year_service.dart';
import 'package:montessori_app/modules/admin/settings/models/school_settings_model.dart';
import 'package:montessori_app/modules/admin/settings/providers/academic_year_provider.dart';
import 'package:montessori_app/modules/fees/models/fee_component_model.dart';
import 'package:montessori_app/modules/fees/models/fee_due_backfill.dart';
import 'package:montessori_app/modules/fees/models/fee_due_date.dart';
import 'package:montessori_app/modules/fees/models/fee_structure_model.dart';
import 'package:montessori_app/modules/fees/models/student_fee_assignment_model.dart';
import 'package:montessori_app/modules/fees/services/fee_service.dart';
import 'package:montessori_app/modules/fees/ui/admin_fees_screen.dart';
import 'package:montessori_app/modules/fees/ui/dialogs/fee_assignment_dialog.dart';
import 'package:montessori_app/modules/fees/ui/dialogs/fee_due_backfill_dialog.dart';
import 'package:montessori_app/modules/finance/services/finance_service.dart';

import 'support/buffered_transaction_firestore.dart';

FeeComponentModel _monthly({int? day}) => FeeComponentModel(name: 'Care', amount: 3000, frequency: 'monthly', dueDayOfMonth: day, isOptional: false);
FeeComponentModel _term({DateTime? due}) => FeeComponentModel(name: 'Term', amount: 8000, frequency: 'term', termName: 'Term 1', dueDate: due, isOptional: false);
FeeComponentModel _once({DateTime? due}) => FeeComponentModel(name: 'Kit', amount: 1500, frequency: 'oneTime', dueDate: due, isOptional: false);

typedef C = FeeDueBackfillCategory;

/// A structure built from [components] alone, for classify tests.
FeeStructureModel _s(List<FeeComponentModel> components) => FeeStructureModel.fromMap('x', {'name': 'S', 'components': [for (final c in components) c.toMap()]});

void main() {
  late BufferedTransactionFirestore firestore;
  late FeeService fees;
  late String year;

  Future<void> structure(String id, String name, List<FeeComponentModel> components, {bool deleted = false}) =>
      firestore.collection('fee_structures').doc(id).set({
        'name': name, 'description': '', 'totalAmount': components.fold<double>(0, (s, c) => s + c.amount), 'academicYear': '2026-2027',
        'academicYearId': year, 'isActive': true, 'createdBy': 't', 'createdAt': DateTime(2026, 1, 1),
        'components': [for (final c in components) c.toMap()],
        if (deleted) 'isDeleted': true,
      });

  /// An existing assignment as stored, with no due date unless [due].
  Future<void> assignment(String id, String structureId, {String student = 's1', String name = 'Anu', String? month, DateTime? due, double total = 3000, bool deleted = false}) =>
      firestore.collection('student_fee_assignments').doc(id).set({
        'id': id, 'studentId': student, 'studentName': name, 'admissionNo': 'ADM-$student', 'classId': 'c1', 'className': 'Mont 1',
        'feeStructureId': structureId, 'feeStructureName': 'Structure $structureId', 'academicYearId': year, 'academicYear': '2026-2027',
        'totalFee': total, 'discountAmount': 0, 'payableAmount': total, 'paidAmount': 0, 'balanceAmount': total, 'status': 'unpaid',
        'feeMonth': ?month, 'dueDate': ?due, if (deleted) 'isDeleted': true,
      });

  Future<Map<String, dynamic>> doc(String id) async => (await firestore.doc('student_fee_assignments/$id').get()).data()!;
  DateTime? dueOf(Map<String, dynamic> d) => (d['dueDate'] as Timestamp?)?.toDate();

  setUp(() async {
    firestore = BufferedTransactionFirestore();
    final auth = MockFirebaseAuth();
    final finance = FinanceService(firestore: firestore, auth: auth);
    await finance.ensureDefaults();
    fees = FeeService(firestore: firestore, auth: auth, storage: MockFirebaseStorage(), financeService: finance);
    year = await AcademicYearService(firestore: firestore).createAcademicYear(schoolId: kDefaultSchoolId, requesterRole: 'admin', name: '2026-2027',
        startDate: DateTime(2026, 6, 1), endDate: DateTime(2027, 5, 31), createdBy: 'admin-1', setAsCurrent: true);
    await firestore.collection('classes').doc('c1').set({'name': 'Mont 1', 'isActive': true});

    await structure('day5', 'Monthly Day5', [_monthly(day: 5)]);
    await structure('day31', 'Monthly Day31', [_monthly(day: 31)]);
    await structure('noday', 'Monthly NoDay', [_monthly()]);
    await structure('term', 'Term Fees', [_term(due: DateTime(2026, 7, 15))]);
    await structure('once', 'Kit', [_once(due: DateTime(2026, 9, 30))]);
    await structure('plain', 'Kit Plain', [_once()]);
    await structure('mixok', 'Mixed Agreeing', [_monthly(day: 10), _term(due: DateTime(2027, 6, 10))]);
    await structure('mixbad', 'Mixed Conflicting', [_monthly(day: 5), _once(due: DateTime(2027, 6, 10))]);
    await structure('gone', 'Deleted', [_once(due: DateTime(2026, 9, 1))], deleted: true);

    await assignment('m-jan', 'day5', month: '2027-01');
    await assignment('m-feb28', 'day31', month: '2027-02', student: 's2', name: 'Bala');
    await assignment('m-feb29', 'day31', month: '2028-02', student: 's2', name: 'Bala');
    await assignment('m-nomonth', 'day5');
    await assignment('m-badmonth', 'day5', month: '2027-13');
    await assignment('m-noday', 'noday', month: '2027-01');
    await assignment('t-term', 'term', student: 's3', name: 'Chitra', total: 8000);
    await assignment('o-once', 'once', student: 's3', name: 'Chitra', total: 1500);
    await assignment('o-plain', 'plain');
    await assignment('x-ok', 'mixok', student: 's4', name: 'Dev');
    await assignment('x-bad', 'mixbad', student: 's4', name: 'Dev');
    await assignment('s-deleted', 'gone');
    await assignment('s-ghost', 'ghost');
    await assignment('h-dated', 'day5', month: '2027-02', due: DateTime(2027, 2, 20));
    await assignment('z-removed', 'day5', month: '2027-03', deleted: true);
  });

  Map<String, FeeDueBackfillItem> byId(FeeDueBackfillPreview p) => {for (final i in p.items) i.assignment.id: i};

  group('preview: rules by frequency', () {
    test('1–10. each assignment classified by its structure’s settings, with a proposed date or a reason', () async {
      final p = byId(await fees.previewMissingDueDates());
      expect(p.containsKey('z-removed'), isFalse, reason: 'deleted assignments are not scanned');
      expect(p.length, 14);
      final eligible = {for (final MapEntry(:key, :value) in p.entries) if (value.category == C.eligible) key: value.proposedDate};
      expect(eligible, {
        'm-jan': DateTime(2027, 1, 5), // 1
        'm-feb28': DateTime(2027, 2, 28), // 2
        'm-feb29': DateTime(2028, 2, 29), // 2, leap year
        't-term': DateTime(2026, 7, 15), // 5
        'o-once': DateTime(2026, 9, 30), // 6
        'x-ok': DateTime(2027, 6, 10), // 7
      });
      expect(p['m-nomonth']!.category, C.configMissing); // 3
      expect(p['m-nomonth']!.reason, contains('No fee month is recorded'));
      expect(p['m-badmonth']!.category, C.configMissing);
      expect(p['m-badmonth']!.reason, contains('"2027-13" is not a valid month'));
      expect(p['m-noday']!.category, C.configMissing); // 4
      expect(p['m-noday']!.reason, contains('no Due Day of Month configured'));
      expect(p['o-plain']!.category, C.configMissing);
      expect(p['o-plain']!.reason, contains('no Default Due Date configured'));
      expect(p['x-bad']!.category, C.manualReview); // 8
      expect(p['x-bad']!.reason, contains('does not fall on the term or one-time due date'));
      expect(p['s-deleted']!.category, C.structureMissing); // 9
      expect(p['s-deleted']!.reason, contains('has been deleted'));
      expect(p['s-ghost']!.category, C.structureMissing);
      expect(p['s-ghost']!.reason, contains('was not found'));
      expect(p['h-dated']!.category, C.hasDueDate); // 10
      expect(p['h-dated']!.proposedDate, isNull);
    });

    test('counts per category', () async {
      final p = await fees.previewMissingDueDates();
      expect([p.scanned, for (final c in C.values) p.count(c)], [14, 1, 6, 1, 2, 4]);
    });

    test('Term or One-time components that disagree, or monthly components with different days: manual review', () {
      StudentFeeAssignmentModel a({String month = ''}) => StudentFeeAssignmentModel.fromMap('a', {'studentId': 's', 'feeMonth': month});
      final twoDates = FeeDueBackfill.classify(
          a(), _s([_term(due: DateTime(2026, 7, 1)), _once(due: DateTime(2026, 8, 1))]));
      expect((twoDates.category, twoDates.proposedDate), (C.manualReview, null));
      final twoDays = FeeDueBackfill.classify(a(month: '2027-01'), _s([_monthly(day: 5), _monthly(day: 7)]));
      expect(twoDays.category, C.manualReview);
      expect(twoDays.reason, contains('different due days (5, 7)'));
      expect(FeeDueBackfill.classify(a(month: '2027-01'), _s([])).category, C.configMissing, reason: 'no components');
    });

    test('11. the preview writes nothing', () async {
      final before = firestore.dump();
      await fees.previewMissingDueDates();
      await fees.previewMissingDueDates();
      expect(firestore.dump(), before);
    });
  });

  group('apply', () {
    test('12. only the missing dueDate is written, as a calendar date; nothing else on the assignment changes', () async {
      final before = {for (final d in (await firestore.collection('student_fee_assignments').get()).docs) d.id: d.data()};
      final r = await fees.applyMissingDueDates(await fees.previewMissingDueDates());
      expect(r.updated.map((i) => i.assignment.id).toSet(), {'m-jan', 'm-feb28', 'm-feb29', 't-term', 'o-once', 'x-ok'});
      expect([r.alreadyHadDate, r.changed, r.failed], [isEmpty, isEmpty, isEmpty]);
      expect(r.stillNeedAttention.map((i) => i.assignment.id).toSet(), {'m-nomonth', 'm-badmonth', 'm-noday', 'o-plain', 'x-bad', 's-deleted', 's-ghost'});
      final after = {for (final d in (await firestore.collection('student_fee_assignments').get()).docs) d.id: d.data()};
      for (final id in before.keys) {
        final updated = r.updated.any((i) => i.assignment.id == id);
        expect({...after[id]!}..remove(updated ? 'dueDate' : '__none'), before[id], reason: id);
        if (updated) expect(after[id]!['dueDate'], isA<Timestamp>(), reason: id);
      }
      expect(dueOf(after['m-feb28']!), DateTime(2027, 2, 28));
      expect(dueOf(after['x-ok']!), DateTime(2027, 6, 10));
      expect(dueOf(after['h-dated']!), DateTime(2027, 2, 20), reason: '10. never overwritten');
      expect(after['m-nomonth']!.containsKey('dueDate'), isFalse);
      expect(r.message, 'Updated 6, skipped 0 that already had a due date, skipped 0 that changed or disappeared, failed 0, 7 still need manual review.');
    });

    test('13. changed after the preview: rechecked; a new date is skipped, a changed structure recalculated or no longer used', () async {
      final preview = await fees.previewMissingDueDates();
      await firestore.doc('student_fee_assignments/m-jan').update({'dueDate': DateTime(2027, 1, 25)});
      await structure('term', 'Term Fees', [_term(due: DateTime(2026, 7, 20))]);
      await structure('mixok', 'Mixed Agreeing', [_monthly(day: 3), _term(due: DateTime(2027, 6, 10))]);
      final r = await fees.applyMissingDueDates(preview);
      expect(r.alreadyHadDate.map((i) => i.assignment.id), ['m-jan']);
      expect(dueOf(await doc('m-jan')), DateTime(2027, 1, 25), reason: 'the date someone set is kept');
      final term = r.updated.singleWhere((i) => i.assignment.id == 't-term');
      expect(term.proposedDate, DateTime(2026, 7, 20));
      expect(term.reason, contains('Recalculated'));
      expect(dueOf(await doc('t-term')), DateTime(2026, 7, 20));
      final mixed = r.changed.singleWhere((i) => i.assignment.id == 'x-ok');
      expect(mixed.reason, startsWith('Changed since the preview: '));
      expect(r.stillNeedAttention.map((i) => i.assignment.id), contains('x-ok'));
      expect((await doc('x-ok')).containsKey('dueDate'), isFalse);
    });

    test('14. deleted or removed after the preview: skipped and reported, nothing recreated', () async {
      final preview = await fees.previewMissingDueDates();
      await firestore.doc('student_fee_assignments/o-once').delete();
      await firestore.doc('student_fee_assignments/x-ok').update({'isDeleted': true});
      await structure('day31', 'Monthly Day31', [_monthly(day: 31)], deleted: true);
      final r = await fees.applyMissingDueDates(preview);
      final changed = {for (final i in r.changed) i.assignment.id: i.reason};
      expect(changed['o-once'], 'The assignment no longer exists.');
      expect(changed['x-ok'], 'The assignment has been deleted.');
      expect(changed['m-feb28'], contains('has been deleted'));
      expect((await firestore.doc('student_fee_assignments/o-once').get()).exists, isFalse);
      expect((await doc('x-ok')).containsKey('dueDate'), isFalse);
      expect((await doc('m-feb29')).containsKey('dueDate'), isFalse);
      expect(r.updated.map((i) => i.assignment.id).toSet(), {'m-jan', 't-term'});
    });

    test('15. running it again changes nothing', () async {
      await fees.applyMissingDueDates(await fees.previewMissingDueDates());
      final dump = firestore.dump();
      final again = await fees.previewMissingDueDates();
      expect(again.eligible, isEmpty);
      expect(again.count(C.hasDueDate), 7);
      final r = await fees.applyMissingDueDates(again);
      expect([r.updated, r.alreadyHadDate, r.changed, r.failed], [isEmpty, isEmpty, isEmpty, isEmpty]);
      expect(firestore.dump(), dump);
      // An old preview applied again: rechecked, nothing rewritten.
      final stale = FeeDueBackfillPreview([
        FeeDueBackfillItem(StudentFeeAssignmentModel.fromMap('m-jan', {}), C.eligible, proposedDate: DateTime(2027, 1, 9)),
      ]);
      final r2 = await fees.applyMissingDueDates(stale);
      expect(r2.alreadyHadDate.single.assignment.id, 'm-jan');
      expect(firestore.dump(), dump);
    });

    test('16. many records: several transactions, at most the chunk size each; every one updated once', () async {
      for (var i = 0; i < 205; i++) {
        await assignment('bulk-$i', 'once', student: 'b$i', name: 'Bulk $i', total: 1500);
      }
      final preview = await fees.previewMissingDueDates();
      expect(preview.eligible.length, 211);
      final attempts = firestore.attempts;
      final r = await fees.applyMissingDueDates(preview);
      expect(firestore.attempts - attempts, 2, reason: '211 records: 200 + 11');
      expect(r.updated.length, 211);
      expect(r.updated.map((i) => i.assignment.id).toSet().length, 211, reason: 'each once');
      expect(FeeService.dueBackfillChunk, lessThanOrEqualTo(FeeService.maxBatchWrites));
      expect(() => fees.applyMissingDueDates(preview, chunkSize: 501), throwsArgumentError);
    });

    test('17. a failed transaction writes nothing for its records, is reported as failed, and the others still save', () async {
      final preview = await fees.previewMissingDueDates();
      // Chunks of 2 in preview order (by student name); fail the one containing Chitra's Term fee.
      final order = [for (final i in preview.eligible) i.assignment.id];
      final failing = order.indexOf('t-term') ~/ 2;
      final failedIds = order.sublist(failing * 2, (failing * 2 + 2).clamp(0, order.length)).toSet();
      firestore.failCommitWhen = (path) => path == 'student_fee_assignments/t-term';
      final r = await fees.applyMissingDueDates(preview, chunkSize: 2);
      expect(r.failed.map((i) => i.assignment.id).toSet(), failedIds);
      expect(r.updated.length, 6 - failedIds.length);
      for (final id in failedIds) {
        expect((await doc(id)).containsKey('dueDate'), isFalse, reason: '$id: nothing written');
      }
      expect(r.errors.single, contains('Injected commit failure'));
      expect(r.message, contains('failed ${failedIds.length}, '));
      expect(r.message, contains('Some updates could not be saved'));
      expect(r.message, isNot(contains('failed 0')));
    });

    test('18, 19. payments, receipts, balances and Finance are unchanged; overdue follows the new due date', () async {
      final receipt = await fees.collectFee(assignmentId: 't-term', amount: 3000, paymentDate: DateTime(2026, 8, 1), paymentMode: 'cash', referenceNo: '', remarks: '');
      Future<String> money() async => [
            for (final c in ['fee_receipts', 'fee_transactions', 'finance_ledger', 'finance_accounts'])
              [for (final d in (await firestore.collection(c).get()).docs) '${d.id}:${d.data()}'].join('|'),
          ].join('\n');
      final ledgerBefore = await money();
      final termBefore = await doc('t-term');
      final today = DateTime(2026, 11, 7);
      bool overdue(Map<String, dynamic> d) => FeeDueDate.isOverdue(StudentFeeAssignmentModel.fromMap('t-term', d), today);
      expect(overdue(termBefore), isFalse, reason: 'no due date yet');

      await fees.applyMissingDueDates(await fees.previewMissingDueDates());
      expect(await money(), ledgerBefore);
      final termAfter = await doc('t-term');
      for (final k in ['totalFee', 'discountAmount', 'payableAmount', 'paidAmount', 'balanceAmount', 'status']) {
        expect(termAfter[k], termBefore[k], reason: k);
      }
      expect(termAfter['paidAmount'], 3000);
      expect(overdue(termAfter), isTrue, reason: 'due 15 Jul 2026 with a balance');
      final all = [
        for (final d in (await firestore.collection('student_fee_assignments').get()).docs)
          if (d.data()['isDeleted'] != true) StudentFeeAssignmentModel.fromMap(d.id, d.data()),
      ];
      expect(FeeDueDate.overdueStudents(all, today), 1, reason: 'Chitra (Term and Kit both past due)');
      expect(receipt.id, isNotEmpty);
    });
  });

  // ---------------------------------------------------------------- UI
  group('Set Missing Due Dates', () {
    Finder key(String k) => find.byKey(Key(k));
    Future<void> tap(WidgetTester tester, Finder f) async {
      await tester.ensureVisible(f);
      await tester.pumpAndSettle();
      await tester.tap(f);
      await tester.pumpAndSettle();
    }

    Future<void> pumpFees(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(ProviderScope(
        overrides: [academicYearServiceProvider.overrideWithValue(AcademicYearService(firestore: firestore))],
        child: MaterialApp(home: AdminFeesScreen(service: fees, clock: () => DateTime(2026, 11, 7))),
      ));
      await tester.pumpAndSettle();
      await tap(tester, find.widgetWithText(ChoiceChip, 'Assignments'));
    }

    String text(WidgetTester tester, String k) => tester.widget<Text>(key(k)).data!;

    testWidgets('the Assignments tab explains it; the preview shows counts and records and writes nothing', (tester) async {
      await pumpFees(tester);
      expect(find.text(FeeDueBackfillDialog.explanation), findsOneWidget);
      final before = firestore.dump();
      await tap(tester, key('fees-set-missing-due-dates'));
      expect(find.byType(FeeDueBackfillDialog), findsOneWidget);
      expect(text(tester, 'due-backfill-count-scanned'), 'Total assignments scanned: 14');
      expect(text(tester, 'due-backfill-unchanged'), contains('will remain unchanged'));
      expect(text(tester, 'due-backfill-hasDueDate-title'), 'Already have a due date: 1');
      expect(text(tester, 'due-backfill-eligible-title'), 'Eligible for automatic due date: 6');
      expect(text(tester, 'due-backfill-manualReview-title'), 'Require manual review: 1');
      expect(text(tester, 'due-backfill-structureMissing-title'), 'Fee structure missing or unavailable: 2');
      expect(text(tester, 'due-backfill-configMissing-title'), 'Fee month or due-date configuration missing: 4');
      expect(find.widgetWithText(FilledButton, 'Set 6 Due Dates'), findsOneWidget);

      await tap(tester, key('due-backfill-eligible'));
      expect(text(tester, 'due-backfill-row-text-m-feb28'), 'Structure day31 • 2026-2027 • February 2027\nDue date: 28 Feb 2027');
      await tap(tester, key('due-backfill-configMissing'));
      expect(text(tester, 'due-backfill-row-text-m-nomonth'), contains('No fee month is recorded'));
      expect(key('due-backfill-edit-m-nomonth'), findsOneWidget, reason: 'can be set by hand');
      await tap(tester, key('due-backfill-structureMissing'));
      expect(key('due-backfill-row-s-ghost'), findsOneWidget);
      expect(key('due-backfill-edit-s-ghost'), findsNothing, reason: 'not editable without its structure');
      expect(firestore.dump(), before, reason: 'preview only');

      await tap(tester, key('due-backfill-close'));
      expect(find.byType(FeeDueBackfillDialog), findsNothing);
      expect(firestore.dump(), before, reason: 'cancelled');
    });

    testWidgets('confirm saves, then the report lists each record and what still needs review; Scan Again shows none eligible', (tester) async {
      await pumpFees(tester);
      await tap(tester, key('fees-set-missing-due-dates'));
      await tap(tester, key('due-backfill-confirm'));
      expect(text(tester, 'due-backfill-summary'), startsWith('Updated 6, skipped 0'));
      expect(key('due-backfill-partial'), findsNothing);
      expect(text(tester, 'due-backfill-attention-title'), 'Still requiring manual review: 7');
      expect(key('due-backfill-row-x-bad'), findsOneWidget, reason: 'expanded');
      await tap(tester, key('due-backfill-updated'));
      expect(text(tester, 'due-backfill-row-text-t-term'), contains('Due date: 15 Jul 2026'));
      expect(dueOf(await tester.runAsync(() => doc('t-term')) as Map<String, dynamic>), DateTime(2026, 7, 15));

      await tap(tester, key('due-backfill-rescan'));
      expect(text(tester, 'due-backfill-eligible-title'), 'Eligible for automatic due date: 0');
      expect(key('due-backfill-confirm'), findsNothing, reason: 'shown only when there are eligible assignments');
      expect(key('due-backfill-none'), findsOneWidget);
      await tap(tester, key('due-backfill-close'));
      expect(find.text('Overdue • due 15 Jul 2026 • outstanding 8000'), findsOneWidget, reason: 'the list reloaded; overdue from the new date');
    });

    testWidgets('Set Date opens the stored assignment for a manual date; closing it scans again', (tester) async {
      await pumpFees(tester);
      await tap(tester, key('fees-set-missing-due-dates'));
      await tap(tester, key('due-backfill-configMissing'));
      final before = firestore.dump();
      await tap(tester, key('due-backfill-edit-m-noday'));
      expect(find.byType(FeeAssignmentDialog), findsOneWidget);
      expect(tester.widget<Text>(key('fee-due-date-value')).data, 'Due date not set');
      await tap(tester, find.widgetWithText(TextButton, 'Cancel').last);
      expect(find.byType(FeeAssignmentDialog), findsNothing);
      expect(text(tester, 'due-backfill-count-scanned'), 'Total assignments scanned: 14');
      expect(firestore.dump(), before, reason: 'cancelled: nothing written');
    });

    testWidgets('a failed update is reported as partial, never as complete', (tester) async {
      firestore.failCommitWhen = (path) => path.startsWith('student_fee_assignments/');
      await pumpFees(tester);
      await tap(tester, key('fees-set-missing-due-dates'));
      await tap(tester, key('due-backfill-confirm'));
      expect(text(tester, 'due-backfill-summary'), startsWith('Updated 0'));
      expect(text(tester, 'due-backfill-failed-title'), 'Failed updates: 6');
      expect(key('due-backfill-partial'), findsOneWidget);
    });
  });
}
