/// Parent-safe copies ("projections") of records parents may see but must
/// not read in full (docs/parent_access_security.md §3a). Pure: each builder
/// takes the original record and returns only the fields a parent may see —
/// an allowlist, so a field added to the original later is never exposed by
/// accident. The originals are never changed.
///
/// No projection carries a download URL. Files are referenced by their
/// Storage path and downloaded through the authenticated Storage SDK, which
/// checks the Storage rules on every download (ParentFileService).
library;

import '../../fees/models/student_fee_assignment_model.dart';
import '../../fees/bill_issuance/fee_bill_models.dart' show FeeBillStatus;

/// `parent_student_profiles/{studentId}`: the student record as every linked
/// parent (Father, Mother or Guardian) sees it.
abstract final class ParentStudentProfileFields {
  static const collection = 'parent_student_profiles';

  /// Copied as they are (the student's own details). `isActive` is kept
  /// only so inactive (soft-deleted) children are left out, as before.
  static const copied = [
    'name', 'admissionNo', 'admissionDate', 'classId', 'section', 'rollNumber', 'dateOfBirth', 'age', 'gender',
    'nationality', 'motherTongue', 'isActive',
  ];

  /// Never copied: admin or financial data, the admission approval status,
  /// other parents' contact details, download URLs (replaced by `photoPath`),
  /// and the Father/Mother-only details ([ParentStudentDetailsFields]).
  static const withheld = [
    'isApproved (admission approval, internal)', 'bloodGroup, address, documents (Father/Mother copy)',
    'feeDiscount (type, value, reason, effective dates)', 'createdAt', 'createdBy', 'updatedAt', 'updatedBy', 'profileImageUrl',
    'parentLinks (userId, phone, email)', 'documents (url, uploadedBy)',
  ];
}

/// The Storage path inside a Firebase Storage download URL
/// (`…/o/<encoded path>?alt=media&token=…`), or '' when [url] isn't one.
String storagePathFromDownloadUrl(Object? url) {
  final uri = Uri.tryParse(url?.toString() ?? '');
  if (uri == null || !uri.host.contains('firebasestorage') && !uri.path.contains('/v0/b/')) return '';
  final i = uri.pathSegments.indexOf('o');
  if (i < 0 || i + 1 >= uri.pathSegments.length) return '';
  return uri.pathSegments.sublist(i + 1).join('/');
}

/// `parent_student_details/{studentId}`: what only a linked Father or Mother
/// sees (owner decision): blood group, home address and the student's
/// documents (by Storage path).
abstract final class ParentStudentDetailsFields {
  static const collection = 'parent_student_details';

  static const copied = ['bloodGroup', 'addressLine1', 'addressLine2', 'city', 'state', 'pincode'];
}

/// The profile every linked parent sees for student [data].
Map<String, dynamic> parentStudentProfile(String studentId, Map<String, dynamic> data) {
  final guardians = <Map<String, dynamic>>[];
  for (final link in ((data['parentLinks'] as List?) ?? const []).whereType<Map>()) {
    final name = link['name']?.toString().trim() ?? '';
    final relation = link['relation']?.toString().trim() ?? '';
    if (name.isEmpty && relation.isEmpty) continue;
    guardians.add({'name': name, 'relation': relation});
  }
  return {
    'studentId': studentId,
    for (final k in ParentStudentProfileFields.copied)
      if (data.containsKey(k)) k: data[k],
    'photoPath': storagePathFromDownloadUrl(data['profileImageUrl']),
    'guardians': guardians,
    'schemaVersion': 2,
  };
}

/// The Father/Mother-only details of student [data] (documents from the
/// student record's `documents` list; the caller adds those of the
/// `documents` collection).
Map<String, dynamic> parentStudentDetails(String studentId, Map<String, dynamic> data) {
  final documents = <Map<String, dynamic>>[];
  for (final d in ((data['documents'] as List?) ?? const []).whereType<Map>()) {
    final path = (d['storagePath']?.toString().trim().isNotEmpty ?? false) ? d['storagePath'].toString().trim() : storagePathFromDownloadUrl(d['url']);
    if (path.isEmpty) continue;
    documents.add({
      'name': d['name']?.toString() ?? '',
      'type': d['type']?.toString() ?? d['documentType']?.toString() ?? '',
      'fileName': d['fileName']?.toString() ?? '',
      'storagePath': path,
      'uploadedAt': ?d['uploadedAt'],
    });
  }
  return {
    'studentId': studentId,
    for (final k in ParentStudentDetailsFields.copied)
      if (data.containsKey(k)) k: data[k],
    'documents': documents,
    'schemaVersion': 1,
  };
}

/// `parent_payments/{receiptId}`: one payment as a linked Father or Mother
/// sees it.
abstract final class ParentPaymentFields {
  static const collection = 'parent_payments';

  static const copied = ['studentId', 'assignmentId', 'receiptNo', 'amount', 'paymentDate', 'paymentMode', 'referenceNo', 'feeStructureName', 'feeMonth'];

  static const withheld = ['remarks', 'collectedBy', 'createdBy', 'pdfUrl', 'pdfPath', 'transactionId', 'voidedBy', 'deletedBy', 'studentName/admissionNo/className (already known)'];
}

/// The parent-safe copy of fee receipt [data] (the receipt is the record
/// that is marked voided — its transaction is not), or null when it is
/// voided and must not be shown.
Map<String, dynamic>? parentPayment(String receiptId, Map<String, dynamic> data) {
  if (data['isDeleted'] == true) return null;
  if ((data['studentId']?.toString() ?? '').isEmpty) return null;
  return {
    'receiptId': receiptId,
    for (final k in ParentPaymentFields.copied)
      if (data.containsKey(k)) k: data[k],
    'schemaVersion': 1,
  };
}

/// `parent_notices/{noticeId}`: a Published notification as parents see it.
abstract final class ParentNoticeFields {
  static const collection = 'parent_notices';

  static const copied = [
    'title', 'message', 'notificationType', 'category', 'priority', 'audience', 'status', 'academicYear', 'publishDate',
    'expiryDate', 'createdAt', 'sentAt', 'isPinned', 'requiresAcknowledgement', 'isPublic',
    'attachmentName', 'attachmentSize', 'attachmentMimeType', 'appliesToAllClasses', 'appliesToAllStudents',
  ];

  static const withheld = [
    'createdBy', 'createdByName', 'applicableStudentNames', 'applicableClassNames', 'appliesToAllStaff', 'applicableStaffIds',
    'applicableStaffNames', 'visibility', 'attachmentUrl', 'updatedAt',
  ];
}

/// The parent copy of notification [data], or null when parents must not
/// receive it (not Published, or not for Parents/Public).
///
/// Targeting is normalised so the server can enforce it:
/// - a notice naming students targets **only** those students — any class
///   list kept from the form's class filter is dropped (the app used to show
///   such a notice to the whole class);
/// - otherwise its class list targets those classes;
/// - Public, all-classes and all-students notices go to every parent.
Map<String, dynamic>? parentNotice(String noticeId, Map<String, dynamic> data, {String attachmentPath = ''}) {
  if (data['status'] != 'Published') return null;
  final audience = data['audience']?.toString() ?? '';
  if (audience != 'Parents' && audience != 'Public') return null;
  List<String> ids(Object? v) => [for (final x in (v as List?) ?? const []) if ((x?.toString() ?? '').isNotEmpty) x.toString()];
  final students = ids(data['applicableStudentIds']);
  final path = attachmentPath.isNotEmpty
      ? attachmentPath
      : (storagePathFromDownloadUrl(data['attachmentUrl']).isNotEmpty
          ? storagePathFromDownloadUrl(data['attachmentUrl'])
          : ((data['attachmentName']?.toString() ?? '').isNotEmpty ? 'school_notifications/$noticeId/${data['attachmentName']}' : ''));
  return {
    'noticeId': noticeId,
    for (final k in ParentNoticeFields.copied)
      if (data.containsKey(k)) k: data[k],
    'appliesToAllClasses': data['appliesToAllClasses'] == true,
    'appliesToAllStudents': data['appliesToAllStudents'] == true,
    'applicableStudentIds': students,
    'applicableClassIds': students.isEmpty ? ids(data['applicableClassIds']) : const <String>[],
    'attachmentPath': (data['attachmentName']?.toString() ?? '').isEmpty && (data['attachmentUrl']?.toString() ?? '').isEmpty ? '' : path,
    'schemaVersion': 1,
  };
}

/// `parent_fee_assignments/{assignmentId}`: one fee as a linked Father or
/// Mother sees it.
abstract final class ParentFeeAssignmentFields {
  static const collection = 'parent_fee_assignments';

  static const withheld = [
    'revision history (reasons, reviser names, previous amounts)', 'feeRevision, lastRevisedAt', 'assignedBy, deletedBy, createdBy',
    'studentDiscount configuration (type, value, reason, dates, config id, applied by, operation id)', 'feeStructureId, academicYearId',
  ];
}

/// The parent copy of fee assignment [assignment] (already read through the
/// existing StudentFeeAssignmentModel — every amount is the stored one,
/// nothing is recalculated), or null for a deleted assignment.
///
/// [structureComponents] (name, amount) are the fee structure's
/// particulars; they are shown only when they add up to this fee's gross
/// amount (a revised fee no longer matches its structure). When a student
/// discount was applied, its per-component allocation (name, gross,
/// discount) is used instead — the amounts applied, not the configuration.
Map<String, dynamic>? parentFeeAssignment(
  StudentFeeAssignmentModel assignment, {
  required bool isDeleted,
  List<(String, double)> structureComponents = const [],
  Object? dueDate,
}) {
  if (isDeleted || assignment.studentId.isEmpty) return null;
  int paise(double v) => (v * 100).round();
  final allocation = assignment.studentDiscount?.allocation ?? const [];
  final List<Map<String, dynamic>> components;
  if (allocation.isNotEmpty) {
    components = [for (final a in allocation) {'name': a.name, 'gross': a.gross, 'discount': a.discount}];
  } else if (structureComponents.isNotEmpty &&
      structureComponents.fold<int>(0, (t, c) => t + paise(c.$2)) == paise(assignment.totalFee)) {
    components = [for (final (name, amount) in structureComponents) {'name': name, 'gross': amount, 'discount': 0.0}];
  } else {
    components = const [];
  }
  return {
    'assignmentId': assignment.id,
    'studentId': assignment.studentId,
    'feeStructureName': assignment.feeStructureName,
    'academicYear': assignment.academicYear,
    'feeMonth': assignment.feeMonth,
    'dueDate': ?dueDate,
    'totalFee': assignment.totalFee,
    'discountAmount': assignment.discountAmount,
    'payableAmount': assignment.payableAmount,
    'paidAmount': assignment.paidAmount,
    'balanceAmount': assignment.balanceAmount,
    'status': assignment.status,
    'components': components,
    'schemaVersion': 1,
  };
}

/// `parent_fee_bills/{billId}`: a supplementary fee bill as a linked Father
/// or Mother sees it — the original bill snapshot minus administrator ids,
/// request ids and audit data, in the same shape, so FeeIssuedBill.fromMap
/// and FeeBillPdf build the very same document from it. Only **active
/// (issued)** bills have a copy: a cancelled bill's copy is removed by the
/// next refresh or rebuild, and copies carry no replacement links, so
/// parents never see a cancelled bill's reference, cancellation or history
/// (administrators still do, in Fee Bill Issuance).
abstract final class ParentFeeBillFields {
  static const collection = 'parent_fee_bills';

  static const copied = [
    'schoolId', 'billNo', 'status', 'studentId', 'studentName', 'admissionNo', 'className', 'issueDate', 'parentRelation',
    'parentName', 'amountIncludesGst', 'billingMonth', 'description', 'grossPaise', 'adjustmentType', 'adjustmentPaise',
    'adjustmentReason', 'netPaise', 'issuedAt',
  ];

  static const withheld = [
    'issuedBy', 'issueRequestId', 'cancellation.by', 'cancellation request id', 'adjustment.createdBy', 'updatedBy',
    'receiptId (internal record id)', 'audit history', 'school logo URL (token)',
    'cancelled bills (no copy at all)', 'cancellation', 'replacesBillId / replacedByBillId (name the cancelled bill)',
  ];
}

/// The parent copy of bill [data] (`fee_issued_bills/{billId}`), unchanged
/// in every amount and reference; null for a cancelled (or otherwise not
/// active) bill, which parents must not see.
Map<String, dynamic>? parentFeeBill(String billId, Map<String, dynamic> data) {
  if ((data['studentId']?.toString() ?? '').isEmpty || (data['billNo']?.toString() ?? '').isEmpty) return null;
  if (FeeBillStatus.of(data['status']) != FeeBillStatus.issued || data['cancellation'] != null) return null;
  final payment = Map<String, dynamic>.from((data['payment'] as Map?) ?? const {});
  final school = Map<String, dynamic>.from((data['school'] as Map?) ?? const {});
  return {
    'billId': billId,
    for (final k in ParentFeeBillFields.copied)
      if (data.containsKey(k)) k: data[k],
    'payment': {
      for (final k in ['receiptNo', 'amountPaise', 'paymentMode', 'referenceNo', 'paymentDate'])
        if (payment.containsKey(k)) k: payment[k],
    },
    // The payments supporting the bill as its PDF prints them (receipt
    // number, payment date, amount used); no receipt or allocation ids.
    if (data['allocations'] is List)
      'allocations': [
        for (final a in data['allocations'] as List)
          if (a is Map)
            {
              for (final k in ['receiptNo', 'paymentDate', 'allocatedPaise'])
                if (a.containsKey(k)) k: a[k],
            },
      ],
    'school': {
      for (final k in ['name', 'addressLines', 'contactLines', 'gstin'])
        if (school.containsKey(k)) k: school[k],
      'logoPath': storagePathFromDownloadUrl(school['logoUrl']),
    },
    // 2: active bills only, no replacement links. 3: the supporting
    // payments (`allocations`). Older copies are rewritten or removed by
    // the next refresh or rebuild.
    'schemaVersion': 3,
  };
}

/// An attendance record as parent screens receive it: the attendance photo
/// by Storage path (`attendance_photos/students/{date}/{studentId}.jpg`, the
/// path AttendanceService.uploadImage writes), never its download URL; no
/// marker or environment fields. Nothing in the original record changes.
Map<String, dynamic> parentAttendanceRecord(Map<String, dynamic> record) {
  final hasPhoto = (record['photoUrl']?.toString() ?? '').isNotEmpty;
  final studentId = record['entityId']?.toString() ?? '';
  final date = record['date']?.toString() ?? '';
  return {
    for (final k in ['date', 'status', 'entityType', 'entityId', 'entityName', 'classId', 'createdAt', 'updatedAt'])
      if (record.containsKey(k)) k: record[k],
    'photoPath': hasPhoto
        ? (storagePathFromDownloadUrl(record['photoUrl']).isNotEmpty
            ? storagePathFromDownloadUrl(record['photoUrl'])
            : (studentId.isEmpty || date.isEmpty ? '' : attendancePhotoPath(date, studentId)))
        : '',
  };
}

/// Where AttendanceService stores a student's attendance photo for [date].
String attendancePhotoPath(String date, String studentId) => 'attendance_photos/students/$date/$studentId.jpg';
