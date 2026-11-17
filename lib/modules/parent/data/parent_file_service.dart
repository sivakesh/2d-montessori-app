import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:printing/printing.dart';

import '../../fees/bill_issuance/fee_bill_models.dart';
import '../../fees/bill_issuance/fee_bill_pdf.dart';
import 'parent_access.dart';
import 'parent_access_service.dart';
import 'parent_projection_service.dart';
import 'parent_projections.dart';

/// Hands downloaded bytes to the parent (browser download / share sheet).
typedef ParentFileSaver = Future<void> Function(Uint8List bytes, String fileName);

Future<void> shareParentFile(Uint8List bytes, String fileName) => Printing.sharePdf(bytes: bytes, filename: fileName);

/// The signed-in parent may not open this file (not linked to the child,
/// not the child's Father or Mother, or not a file of that child).
class ParentFileAccessDenied implements Exception {
  const ParentFileAccessDenied(this.reason);
  final String reason;
  @override
  String toString() => reason;
}

/// Protected downloads for parents (docs/parent_access_security.md §6).
///
/// Every method first checks, **in the app**, the signed-in parent's own
/// access record (`parent_access/{parentUserId}`) and the parent-safe copy
/// that lists the file:
/// - child photo, attendance photos: any linked parent;
/// - student documents: a linked **Father or Mother** only, and only a path
///   listed on that child's Father/Mother details copy;
/// - notice attachments: only while that notice's parent copy is targeted at
///   this parent;
/// - fee bills: a linked Father or Mother only (built from the parent-safe
///   bill copy with the unchanged FeeBillPdf).
/// Files are then fetched by **Storage path** through the signed-in Storage
/// SDK (`Reference.getData`) — never by a stored download URL. The
/// proposed Storage rules repeat the relationship check on the server; until
/// they are deployed, these app checks are the only enforcement.
/// Original receipt PDFs are never offered.
class ParentFileService {
  ParentFileService({required this.parentUserId, FirebaseStorage? storage, FirebaseFirestore? firestore, ParentFileSaver? save})
      : _storage = storage,
        _firestore = firestore ?? FirebaseFirestore.instance,
        _save = save ?? shareParentFile;

  /// The signed-in parent's `users` id.
  final String parentUserId;
  final FirebaseStorage? _storage;
  final FirebaseFirestore _firestore;
  final ParentFileSaver _save;

  /// Largest file a parent download accepts.
  static const maxBytes = 20 * 1024 * 1024;

  FirebaseStorage get _bucket => _storage ?? FirebaseStorage.instance;
  ParentProjectionService get _copies => ParentProjectionService(firestore: _firestore);

  Future<ParentAccessRecord> _access() async {
    final access = parentUserId.isEmpty ? null : await ParentAccessService(firestore: _firestore).getForParent(parentUserId);
    if (access == null) throw const ParentFileAccessDenied('No linked children.');
    return access;
  }

  Future<void> _requireLinked(String studentId) async {
    if (!(await _access()).studentIds.contains(studentId)) throw const ParentFileAccessDenied('Not a linked child.');
  }

  Future<void> _requireFatherOrMother(String studentId) async {
    if (!(await _access()).canViewFinance(studentId)) throw const ParentFileAccessDenied("Only the student's father or mother can open this.");
  }

  Future<Uint8List?> _read(String storagePath) async {
    if (storagePath.trim().isEmpty || storagePath.startsWith('http')) return null;
    return _bucket.ref(storagePath).getData(maxBytes);
  }

  /// A linked child's photo (its path from the child's profile copy).
  Future<Uint8List?> readChildPhoto(String studentId) async {
    await _requireLinked(studentId);
    final path = (await _copies.getProfile(studentId))?['photoPath']?.toString() ?? '';
    return path.isEmpty ? null : _read(path);
  }

  /// A linked child's attendance photo for [date] (yyyy-MM-dd), or null
  /// when that day has none.
  Future<Uint8List?> readAttendancePhoto(String studentId, String date) async {
    await _requireLinked(studentId);
    try {
      return await _read(attendancePhotoPath(date, studentId));
    } on FirebaseException catch (e) {
      if (e.code == 'object-not-found') return null;
      rethrow;
    }
  }

  /// Downloads one of a child's documents: Father or Mother only, and only a
  /// path listed on the child's Father/Mother details copy.
  Future<bool> downloadChildDocument({required String studentId, required String storagePath, String fileName = ''}) async {
    await _requireFatherOrMother(studentId);
    final documents = ((await _copies.getDetails(studentId))?['documents'] as List?) ?? const [];
    if (!documents.whereType<Map>().any((d) => d['storagePath'] == storagePath)) {
      throw const ParentFileAccessDenied('Not one of this child\'s documents.');
    }
    final bytes = await _read(storagePath);
    if (bytes == null) return false;
    await _save(bytes, fileName.trim().isEmpty ? storagePath.split('/').last : fileName);
    return true;
  }

  /// Downloads a notice's attachment while the notice is targeted at this
  /// parent (same targeting as the parent notices themselves).
  Future<bool> downloadNoticeAttachment({required String storagePath, String fileName = ''}) async {
    final parts = storagePath.split('/');
    if (parts.length < 3 || parts.first != 'school_notifications') throw const ParentFileAccessDenied('Not a notice attachment.');
    final notice = (await _firestore.collection(ParentNoticeFields.collection).doc(parts[1]).get()).data();
    final access = await _access();
    List<String> ids(Object? v) => [for (final x in (v as List?) ?? const []) x.toString()];
    final forMe = notice != null &&
        notice['attachmentPath'] == storagePath &&
        (notice['audience'] == 'Public' ||
            (notice['audience'] == 'Parents' &&
                (notice['appliesToAllClasses'] == true ||
                    notice['appliesToAllStudents'] == true ||
                    ids(notice['applicableClassIds']).any(access.classIds.contains) ||
                    ids(notice['applicableStudentIds']).any(access.studentIds.contains))));
    if (!forMe) throw const ParentFileAccessDenied('This notice is not for you.');
    final bytes = await _read(storagePath);
    if (bytes == null) return false;
    await _save(bytes, fileName.trim().isEmpty ? parts.last : fileName);
    return true;
  }

  /// A child's active supplementary fee bills (Father/Mother only), from
  /// the parent-safe copies, newest first. Cancelled bills have no copy; a
  /// copy written before that rule (until the next refresh or rebuild
  /// removes it) is left out here too.
  Future<List<FeeIssuedBill>> feeBillsForStudent(String studentId) async {
    await _requireFatherOrMother(studentId);
    return [
      for (final b in await _copies.getFeeBills(studentId))
        if (FeeBillStatus.of(b['status']) == FeeBillStatus.issued && b['cancellation'] == null) FeeIssuedBill.fromMap(b['billId']?.toString() ?? '', b),
    ];
  }

  /// Downloads the PDF of active bill [billId] — the same document Fee Bill
  /// Issuance produces for it: the unchanged [FeeBillPdf.build] from the
  /// bill's snapshot (its parent-safe copy keeps every printed field), saved
  /// through the same `Printing.sharePdf` path (a browser download on web)
  /// under [FeeBillPdf.fileName]. Access is decided from stored records
  /// only: the bill is re-read by id, must be an active (issued) bill, and
  /// its own student must be one this parent is Father or Mother of —
  /// nothing passed in from the screen is trusted. The school logo is read
  /// by its Storage path; if it can't be read, the PDF uses the app's logo,
  /// as the administrator's download does. Nothing is written.
  Future<void> downloadFeeBillById(String billId) async {
    if (billId.trim().isEmpty) throw const ParentFileAccessDenied('Not a bill.');
    final data = (await _firestore.collection(ParentFeeBillFields.collection).doc(billId).get()).data();
    if (data == null || FeeBillStatus.of(data['status']) != FeeBillStatus.issued || data['cancellation'] != null) {
      throw const ParentFileAccessDenied('This bill is not available.');
    }
    final bill = FeeIssuedBill.fromMap(billId, data);
    await _requireFatherOrMother(data['studentId']?.toString() ?? '');
    final bytes = await FeeBillPdf.build(bill, logo: await _schoolLogo(data));
    await _save(bytes, FeeBillPdf.fileName(bill));
  }

  /// [bill]'s PDF: see [downloadFeeBillById] (only the bill's id is used).
  Future<void> downloadFeeBill(FeeIssuedBill bill) => downloadFeeBillById(bill.id);

  Future<Uint8List?> _schoolLogo(Map<String, dynamic> bill) async {
    final path = ((bill['school'] as Map?)?['logoPath'])?.toString() ?? '';
    if (!path.startsWith('school_settings/')) return null;
    try {
      return await _read(path);
    } catch (_) {
      return null;
    }
  }
}
