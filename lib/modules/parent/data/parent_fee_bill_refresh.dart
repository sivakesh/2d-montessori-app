import 'package:cloud_firestore/cloud_firestore.dart';

import '../../fees/bill_issuance/fee_bill_service.dart';
import 'parent_projection_service.dart';

/// Keeps the parent-safe fee-bill copies (`parent_fee_bills`) current after
/// Fee Bill Issuance issues or cancels a bill: registered once at startup
/// (main.dart) as [FeeBillService.defaultAfterChange], so the Fees module
/// never imports the Parent module for this. Runs only after the bill
/// transaction has committed, re-derives the student's copies from the
/// original bills (idempotent), and never throws: a failure is recorded in
/// `parent_projection_failures` and repaired by a later refresh or the
/// Parent access rebuild.
Future<void> refreshParentFeeBills(FirebaseFirestore firestore, String studentId) =>
    ParentProjectionService(firestore: firestore).syncFeeBillsQuietly(studentId);

/// Writes any missing or outdated parent-safe bill copies for every bill
/// (bills issued before the automatic refresh existed, or whose refresh
/// failed): idempotent, original bills untouched, failures recorded.
Future<FeeBillsBackfillResult> backfillParentFeeBills(FirebaseFirestore firestore) async {
  final r = await ParentProjectionService(firestore: firestore).syncAllFeeBillsReport();
  return (found: r.originals, written: r.written, failed: r.failed, error: r.error);
}

void registerParentFeeBillRefresh() {
  FeeBillService.defaultAfterChange = refreshParentFeeBills;
  FeeBillService.defaultBackfill = backfillParentFeeBills;
}
