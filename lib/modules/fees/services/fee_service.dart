import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';

import '../models/fee_component_model.dart';
import '../models/fee_receipt_model.dart';
import '../models/fee_structure_model.dart';
import '../models/fee_transaction_model.dart';
import '../models/student_fee_assignment_model.dart';

class FeeService {
  FeeService({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _storage = FirebaseStorage.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final FirebaseStorage _storage;

  CollectionReference<Map<String, dynamic>> get _structures => _firestore.collection('fee_structures');
  CollectionReference<Map<String, dynamic>> get _assignments => _firestore.collection('student_fee_assignments');
  CollectionReference<Map<String, dynamic>> get _transactions => _firestore.collection('fee_transactions');
  CollectionReference<Map<String, dynamic>> get _receipts => _firestore.collection('fee_receipts');
  CollectionReference<Map<String, dynamic>> get _students => _firestore.collection('students');
  CollectionReference<Map<String, dynamic>> get _classes => _firestore.collection('classes');

  Future<List<FeeStructureModel>> getFeeStructures() async {
    final snap = await _structures.orderBy('createdAt', descending: true).get();
    return snap.docs.map((d) => FeeStructureModel.fromMap(d.id, d.data())).toList();
  }

  Future<List<StudentFeeAssignmentModel>> getAssignments() async {
    final snap = await _assignments.orderBy('assignedAt', descending: true).get();
    return snap.docs.map((d) => StudentFeeAssignmentModel.fromMap(d.id, d.data())).toList();
  }

  Future<List<FeeReceiptModel>> getReceipts() async {
    final snap = await _receipts.orderBy('createdAt', descending: true).get();
    return snap.docs.map((d) => FeeReceiptModel.fromMap(d.id, d.data())).toList();
  }

  Future<FeeReceiptModel?> getReceiptById(String id) async {
    final snap = await _receipts.doc(id).get();
    if (!snap.exists || snap.data() == null) return null;
    return FeeReceiptModel.fromMap(snap.id, snap.data()!);
  }

  Future<List<FeeTransactionModel>> getTransactions() async {
    final snap = await _transactions.orderBy('createdAt', descending: true).get();
    return snap.docs.map((d) => FeeTransactionModel.fromMap(d.id, d.data())).toList();
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> getActiveClasses() async {
    final snap = await _classes.where('isActive', isEqualTo: true).get();
    return snap.docs;
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> getStudentsByClassId(String classId) async {
    final snap = await _students.where('classId', isEqualTo: classId).where('isActive', isEqualTo: true).get();
    return snap.docs;
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> getStudentsByClassIds(List<String> classIds) async {
    if (classIds.isEmpty) return [];
    final results = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (final classId in classIds) {
      final snap = await getStudentsByClassId(classId);
      results.addAll(snap);
    }
    final seen = <String>{};
    return results.where((doc) => seen.add(doc.id)).toList();
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> getActiveStudents() async {
    final snap = await _students.where('isActive', isEqualTo: true).get();
    return snap.docs;
  }

  Future<List<FeeStructureModel>> getActiveStructuresForClass(String classId) async {
    final all = await getFeeStructures();
    return all.where((s) => s.isActive).toList();
  }

  Future<List<FeeStructureModel>> getActiveStructuresForStudent(String studentId) async {
    final all = await getFeeStructures();
    return all.where((s) => s.isActive).toList();
  }

  Future<String> createFeeStructure(Map<String, dynamic> data) async {
    final doc = _structures.doc();
    await doc.set({
      ...data,
      'id': doc.id,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  Future<void> updateFeeStructure(String id, Map<String, dynamic> data) async {
    await _structures.doc(id).set({...data, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
  }

  Future<void> deactivateFeeStructure(String id) async {
    await updateFeeStructure(id, {'isActive': false});
  }

  Future<String?> assignFee(Map<String, dynamic> data) async {
    final studentId = data['studentId']?.toString() ?? '';
    final feeStructureId = data['feeStructureId']?.toString() ?? '';
    final academicYear = data['academicYear']?.toString() ?? '';
    final dup = await _assignments
        .where('studentId', isEqualTo: studentId)
        .where('feeStructureId', isEqualTo: feeStructureId)
        .where('academicYear', isEqualTo: academicYear)
        .limit(1)
        .get();
    if (dup.docs.isNotEmpty) return null;
    final doc = _assignments.doc();
    await doc.set({
      ...data,
      'id': doc.id,
      'discountAmount': (data['discountAmount'] as num?)?.toDouble() ?? 0,
      'paidAmount': (data['paidAmount'] as num?)?.toDouble() ?? 0,
      'balanceAmount': (data['balanceAmount'] as num?)?.toDouble() ?? 0,
      'assignedBy': _auth.currentUser?.uid ?? data['assignedBy']?.toString() ?? 'admin',
      'assignedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  Future<Map<String, int>> syncAssignmentsForFeeStructure({
    required String feeStructureId,
    required String feeStructureName,
    required String academicYear,
    required double totalFee,
    required String assignmentScope,
    required List<String> classIds,
    required List<String> studentIds,
  }) async {
    final targetStudents = assignmentScope == 'student'
        ? await _fetchStudentsByIds(studentIds)
        : await getStudentsByClassIds(classIds);

    var created = 0;
    var updated = 0;
    var skipped = 0;

    for (final student in targetStudents) {
      final studentData = student.data();
      final studentId = student.id;
      final existingQuery = await _assignments
          .where('studentId', isEqualTo: studentId)
          .where('feeStructureId', isEqualTo: feeStructureId)
          .where('academicYear', isEqualTo: academicYear)
          .limit(1)
          .get();

      final existing = existingQuery.docs.isNotEmpty ? existingQuery.docs.first : null;
      final discountAmount = existing?['discountAmount'] is num ? (existing?['discountAmount'] as num).toDouble() : 0.0;
      final paidAmount = existing?['paidAmount'] is num ? (existing?['paidAmount'] as num).toDouble() : 0.0;
      final payableAmount = totalFee - discountAmount;
      final balanceAmount = (payableAmount - paidAmount).clamp(0, double.infinity);
      final status = balanceAmount == 0
          ? 'paid'
          : paidAmount > 0
              ? 'partial'
              : 'unpaid';

      if (existing == null) {
        final doc = _assignments.doc();
        await doc.set({
          'id': doc.id,
          'studentId': studentId,
          'studentName': studentData['name']?.toString() ?? '',
          'admissionNo': studentData['admissionNo']?.toString() ?? '',
          'classId': studentData['classId']?.toString() ?? '',
          'className': studentData['className']?.toString() ?? studentData['classId']?.toString() ?? '',
          'feeStructureId': feeStructureId,
          'feeStructureName': feeStructureName,
          'academicYear': academicYear,
          'totalFee': totalFee,
          'discountAmount': 0,
          'payableAmount': payableAmount,
          'paidAmount': 0,
          'balanceAmount': payableAmount,
          'status': 'unpaid',
          'assignedBy': _auth.currentUser?.uid ?? 'admin',
          'assignedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        created++;
      } else if (paidAmount <= 0) {
        await existing.reference.update({
          'studentName': studentData['name']?.toString() ?? '',
          'admissionNo': studentData['admissionNo']?.toString() ?? '',
          'classId': studentData['classId']?.toString() ?? '',
          'className': studentData['className']?.toString() ?? studentData['classId']?.toString() ?? '',
          'feeStructureId': feeStructureId,
          'feeStructureName': feeStructureName,
          'academicYear': academicYear,
          'totalFee': totalFee,
          'discountAmount': discountAmount,
          'payableAmount': payableAmount,
          'balanceAmount': balanceAmount,
          'status': status,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        updated++;
      } else {
        skipped++;
      }
    }

    return {'created': created, 'updated': updated, 'skipped': skipped};
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _fetchStudentsByIds(List<String> studentIds) async {
    if (studentIds.isEmpty) return [];
    final results = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (final studentId in studentIds) {
      final snap = await _students.where(FieldPath.documentId, isEqualTo: studentId).limit(1).get();
      results.addAll(snap.docs);
    }
    return results;
  }

  Future<Map<String, int>> bulkAssignClassFees({
    required String classId,
    required String className,
    required String feeStructureId,
    required String feeStructureName,
    required String academicYear,
    required double totalFee,
    required double discountAmount,
  }) async {
    final students = await getStudentsByClassId(classId);
    var assigned = 0;
    var skipped = 0;
    final batch = _firestore.batch();
    for (final student in students) {
      final studentData = student.data();
      final duplicate = await _assignments
          .where('studentId', isEqualTo: student.id)
          .where('feeStructureId', isEqualTo: feeStructureId)
          .where('academicYear', isEqualTo: academicYear)
          .limit(1)
          .get();
      if (duplicate.docs.isNotEmpty) {
        skipped++;
        continue;
      }
      final payable = totalFee - discountAmount;
      final doc = _assignments.doc();
      batch.set(doc, {
        'id': doc.id,
        'studentId': student.id,
        'studentName': studentData['name']?.toString() ?? '',
        'admissionNo': studentData['admissionNo']?.toString() ?? '',
        'classId': classId,
        'className': className,
        'feeStructureId': feeStructureId,
        'feeStructureName': feeStructureName,
        'academicYear': academicYear,
        'totalFee': totalFee,
        'discountAmount': discountAmount,
        'payableAmount': payable,
        'paidAmount': 0,
        'balanceAmount': payable,
        'status': 'unpaid',
        'assignedBy': _auth.currentUser?.uid ?? 'admin',
        'assignedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      assigned++;
    }
    await batch.commit();
    return {'assigned': assigned, 'skipped': skipped};
  }

  Future<FeeReceiptModel> collectFee({
    required String assignmentId,
    required double amount,
    required DateTime paymentDate,
    required String paymentMode,
    required String referenceNo,
    required String remarks,
  }) async {
    final assignmentRef = _assignments.doc(assignmentId);
    final txRef = _transactions.doc();
    final assignmentSnap = await assignmentRef.get();
    if (!assignmentSnap.exists) {
      throw StateError('Assignment not found');
    }
    final a = StudentFeeAssignmentModel.fromMap(assignmentSnap.id, assignmentSnap.data()!);
    if (amount <= 0 || amount > a.balanceAmount) {
      throw StateError('Invalid amount');
    }
    final paidAmount = a.paidAmount + amount;
    final balanceAmount = (a.payableAmount - paidAmount).clamp(0, double.infinity);
    final status = balanceAmount == 0 ? 'paid' : paidAmount > 0 ? 'partial' : 'unpaid';
    final receiptNo = 'REC-2026-${DateTime.now().millisecondsSinceEpoch}';
    final currentUser = _auth.currentUser;
    final currentName = currentUser?.displayName ?? currentUser?.email ?? 'Admin';
    final receiptDoc = _receipts.doc();
    final batch = _firestore.batch();
    batch.set(txRef, {
      'assignmentId': assignmentId,
      'studentId': a.studentId,
      'studentName': a.studentName,
      'admissionNo': a.admissionNo,
      'classId': a.classId,
      'className': a.className,
      'feeStructureId': a.feeStructureId,
      'feeStructureName': a.feeStructureName,
      'amount': amount,
      'paymentDate': paymentDate,
      'paymentMode': paymentMode,
      'referenceNo': referenceNo,
      'remarks': remarks,
      'collectedBy': currentName,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.set(receiptDoc, {
      'receiptNo': receiptNo,
      'transactionId': txRef.id,
      'assignmentId': assignmentId,
      'studentId': a.studentId,
      'studentName': a.studentName,
      'admissionNo': a.admissionNo,
      'className': a.className,
      'feeStructureName': a.feeStructureName,
      'amount': amount,
      'paymentMode': paymentMode,
      'paymentDate': paymentDate,
      'referenceNo': referenceNo,
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': currentName,
      'pdfUrl': '',
      'pdfPath': '',
      'pdfGeneratedAt': null,
    });
    batch.update(assignmentRef, {
      'paidAmount': paidAmount,
      'balanceAmount': balanceAmount,
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
    final receiptSnap = await receiptDoc.get();
    final receipt = FeeReceiptModel.fromMap(receiptSnap.id, receiptSnap.data() ?? {
      'receiptNo': receiptNo,
      'transactionId': txRef.id,
      'assignmentId': assignmentId,
      'studentId': a.studentId,
      'studentName': a.studentName,
      'admissionNo': a.admissionNo,
      'className': a.className,
      'feeStructureName': a.feeStructureName,
      'amount': amount,
      'paymentMode': paymentMode,
      'paymentDate': paymentDate,
      'referenceNo': referenceNo,
      'createdAt': DateTime.now(),
      'createdBy': currentName,
      'pdfUrl': '',
      'pdfPath': '',
      'pdfGeneratedAt': null,
    });
    final generated = await generateAndUploadReceiptPdf(receipt);
    if (!generated) {
      throw StateError('PDF generation failed');
    }
    return receipt;
  }

  Future<bool> generateAndUploadReceiptPdf(FeeReceiptModel receipt) async {
    final pdf = pw.Document();
    pw.ImageProvider? logo;
    try {
      final data = await rootBundle.load('assets/logo.png');
      logo = pw.MemoryImage(data.buffer.asUint8List());
    } catch (_) {}
    String safe(String? value) => (value == null || value.trim().isEmpty) ? '-' : value.trim();
    final rows = <Map<String, String>>[
      {'label': 'Receipt No', 'value': safe(receipt.receiptNo)},
      {'label': 'Student Name', 'value': safe(receipt.studentName)},
      {'label': 'Admission No', 'value': safe(receipt.admissionNo)},
      {'label': 'Class', 'value': safe(receipt.className)},
      {'label': 'Fee Name', 'value': safe(receipt.feeStructureName)},
      {'label': 'Amount Paid', 'value': 'Rs. ${receipt.amount.toStringAsFixed(0)}'},
      {'label': 'Payment Mode', 'value': safe(receipt.paymentMode)},
      {'label': 'Reference No', 'value': safe(receipt.referenceNo)},
      {'label': 'Payment Date', 'value': safe(receipt.paymentDate?.toIso8601String().split('T').first)},
      {'label': 'Generated Date', 'value': DateTime.now().toIso8601String().split('T').first},
    ];
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Center(
              child: pw.Column(
                children: [
                  if (logo != null) pw.Image(logo, height: 42),
                  pw.SizedBox(height: 6),
                  pw.Text('2D Montessori', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 2),
                  pw.Text('FEE RECEIPT', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, letterSpacing: 1.2)),
                ],
              ),
            ),
            pw.SizedBox(height: 10),
            pw.TableHelper.fromTextArray(
              border: pw.TableBorder.all(color: PdfColors.grey700, width: 0.8),
              columnWidths: const {
                0: pw.FixedColumnWidth(150),
                1: pw.FlexColumnWidth(),
              },
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9.5),
              cellStyle: const pw.TextStyle(fontSize: 9.5),
              cellAlignment: pw.Alignment.centerLeft,
              headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
              oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
              data: <List<String>>[
                ['Label', 'Value'],
                ...rows.map((row) => [row['label']!, row['value']!]),
              ],
              cellPadding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            ),
            pw.Spacer(),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('System generated receipt', style: const pw.TextStyle(fontSize: 8)),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('Authorized Signature', style: const pw.TextStyle(fontSize: 8)),
                    pw.SizedBox(height: 10),
                    pw.Container(width: 110, height: 0.6, color: PdfColors.grey700),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
    final bytes = await pdf.save();
    final path = 'fee_receipts/${receipt.id}/${receipt.receiptNo}.pdf';
    try {
      final ref = _storage.ref(path);
      await ref.putData(bytes, SettableMetadata(contentType: 'application/pdf'));
      final url = await ref.getDownloadURL();
      await _receipts.doc(receipt.id).set({
        'pdfUrl': url,
        'pdfPath': path,
        'pdfGeneratedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> getDashboardSummary() async {
    final assignments = await getAssignments();
    final receipts = await getReceipts();
    final totalExpected = assignments.fold<double>(0, (total, a) => total + a.payableAmount);
    final totalCollected = assignments.fold<double>(0, (total, a) => total + a.paidAmount);
    final outstanding = assignments.fold<double>(0, (total, a) => total + a.balanceAmount);
    final overdue = assignments.where((a) => a.status == 'overdue').length;
    final today = DateTime.now();
    final todayCollected = receipts.where((r) => r.paymentDate != null && r.paymentDate!.year == today.year && r.paymentDate!.month == today.month && r.paymentDate!.day == today.day).fold<double>(0, (total, r) => total + r.amount);
    return {
      'totalExpected': totalExpected,
      'totalCollected': totalCollected,
      'outstanding': outstanding,
      'collectionPercent': totalExpected == 0 ? 0 : (totalCollected / totalExpected) * 100,
      'overdueStudents': overdue,
      'todayCollection': todayCollected,
    };
  }

  Future<void> seedSampleFeeStructures() async {
    final existing = await _structures.get();
    final names = existing.docs.map((d) => d.data()['name']?.toString().trim().toLowerCase() ?? '').toSet();
    final samples = [
      {
        'name': 'Montessori Core Fees',
        'description': 'Primary tuition and activity fees.',
        'components': [
          FeeComponentModel(name: 'Tuition', amount: 25000, frequency: 'term', termName: 'Term 1', isOptional: false).toMap(),
          FeeComponentModel(name: 'Activity', amount: 5000, frequency: 'oneTime', isOptional: false).toMap(),
        ],
        'totalAmount': 30000,
        'academicYear': '2026-2027',
        'isActive': true,
        'createdBy': 'seed',
      },
    ];
    for (final s in samples) {
      if (names.contains(s['name'].toString().trim().toLowerCase())) continue;
      await createFeeStructure(s);
    }
  }
}
