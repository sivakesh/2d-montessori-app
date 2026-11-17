import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

import '../models/admin_student_model.dart';
import '../../../parent/data/parent_projection_service.dart';
import '../../../fees/models/fee_discount.dart';
import '../models/admission_date.dart';

class AdminStudentService {
  AdminStudentService({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
    ImagePicker? imagePicker,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance,
        _imagePicker = imagePicker ?? ImagePicker();

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;
  final ImagePicker _imagePicker;

  CollectionReference<Map<String, dynamic>> get _students =>
      _firestore.collection('students');
  CollectionReference<Map<String, dynamic>> get _classes =>
      _firestore.collection('classes');
  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> getStudents() async {
    final snapshot = await _students.orderBy('createdAt', descending: true).get();
    return snapshot.docs;
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> getClasses() async {
    final snapshot = await _classes.where('isActive', isEqualTo: true).get();
    return snapshot.docs;
  }

  /// A single class by id, regardless of `isActive` — unlike [getClasses],
  /// which only returns active classes. Used by the Student Edit form to
  /// resolve a student's own `classId` when a class has been archived
  /// (isActive: false) after the student was assigned to it, so that id
  /// can still be shown/selected instead of being silently dropped.
  /// Returns null if the class truly no longer exists.
  Future<DocumentSnapshot<Map<String, dynamic>>?> getClassById(
    String classId,
  ) async {
    if (classId.isEmpty) return null;
    final doc = await _classes.doc(classId).get();
    return doc.exists ? doc : null;
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> searchParentUsers(
    String query,
  ) async {
    final snapshot = await _users.where('role', isEqualTo: 'parent').get();
    final lowerQuery = query.trim().toLowerCase();
    return snapshot.docs.where((doc) {
      if (lowerQuery.isEmpty) return true;
      final data = doc.data();
      final name = data['name']?.toString().toLowerCase() ?? '';
      final phone = data['phone']?.toString().toLowerCase() ?? '';
      return name.contains(lowerQuery) || phone.contains(lowerQuery);
    }).toList();
  }

  Future<bool> isAdmissionNoTaken(String admissionNo, {String? ignoreId}) async {
    final snapshot = await _students.where('admissionNo', isEqualTo: admissionNo).get();
    return snapshot.docs.any((doc) => doc.id != ignoreId);
  }

  /// [feeDiscount]: the student's fee discount configuration, if any
  /// (validated; [feeDiscountMap]).
  Future<String> createStudent({
    required AdminStudentModel student,
    required String createdBy,
    StudentFeeDiscount? feeDiscount,
  }) async {
    if (AdmissionDate.error(student.admissionDate) case final e?) throw StateError(e);
    final doc = _students.doc();
    await doc.set({
      ...student.toMap(),
      if (feeDiscount != null) StudentFeeDiscount.field: feeDiscountMap(feeDiscount, null),
      'createdBy': createdBy,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await _refreshParentCopy(doc.id);
    return doc.id;
  }

  /// After a change to student [id]: refreshes the copy parents read
  /// (parent_student_profiles) and the class list on their access records
  /// (docs/parent_access_security.md). Runs after the change has been saved
  /// and never throws.
  Future<void> _refreshParentCopy(String id) => ParentProjectionService(firestore: _firestore).syncStudentQuietly(id);


  /// The stored map for [incoming], replacing [existing] (the student's
  /// current configuration, or null). A student has one configuration:
  /// saving replaces it. Refused when invalid. Its id is kept while the
  /// type, value and dates are unchanged (a reason or active-state edit),
  /// and is new otherwise; `createdAt` is kept, `updatedAt` set.
  Map<String, dynamic> feeDiscountMap(StudentFeeDiscount incoming, StudentFeeDiscount? existing) {
    if (incoming.error case final e?) throw StateError(e);
    final keepId = existing != null && existing.id.isNotEmpty && existing.sameTerms(incoming);
    return {
      ...incoming.toMap(),
      'id': keepId ? existing.id : _students.doc().id,
      'createdAt': existing?.createdAt != null ? Timestamp.fromDate(existing!.createdAt!) : FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  /// Merges [student] into the record. A stored Admission Date is kept
  /// unless [student] sets a new one, or [clearAdmissionDate] removes it.
  ///
  /// [feeDiscount]: a new or edited fee discount configuration (to stop a
  /// discount, save it with `isActive: false`); null keeps the stored one
  /// unchanged. Existing fee assignments are never changed here.
  Future<void> updateStudent({
    required String studentId,
    required AdminStudentModel student,
    bool clearAdmissionDate = false,
    StudentFeeDiscount? feeDiscount,
  }) async {
    if (AdmissionDate.error(student.admissionDate) case final e?) throw StateError(e);
    if (feeDiscount?.error case final e?) throw StateError(e);
    final existing = feeDiscount == null ? null : StudentFeeDiscount.fromStudent((await _students.doc(studentId).get()).data());
    await _students.doc(studentId).set({
      ...student.toMap(),
      if (feeDiscount != null) StudentFeeDiscount.field: feeDiscountMap(feeDiscount, existing),
      if (clearAdmissionDate && student.admissionDate == null) 'admissionDate': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await _refreshParentCopy(studentId);
  }

  Future<void> deleteStudent(String studentId) async {
    await _students.doc(studentId).delete();
    await _refreshParentCopy(studentId);
  }

  Future<void> linkParentToStudent({
    required String studentId,
    required Map<String, dynamic> parentData,
  }) async {
    await _students.doc(studentId).set({
      'parentLinks': FieldValue.arrayUnion([
        {
          'userId': parentData['userId'],
          'relation': parentData['relation'],
          'name': parentData['name'],
        },
      ]),
    }, SetOptions(merge: true));
    await _refreshParentCopy(studentId);
  }

  Future<void> removeParentLink({
    required String studentId,
    required String userId,
  }) async {
    final snapshot = await _students.doc(studentId).get();
    final links = (snapshot.data()?['parentLinks'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    links.removeWhere((link) => link['userId']?.toString() == userId);
    await _students.doc(studentId).set({
      'parentLinks': links,
    }, SetOptions(merge: true));
    await _refreshParentCopy(studentId);
  }

  Future<void> uploadStudentDocument({
    required String studentId,
    required String documentName,
  }) async {
    final picked = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    final isImage = picked.mimeType?.startsWith('image/') ?? false;
    final extension = isImage ? 'jpg' : 'pdf';
    final ref = _storage.ref().child(
          'students/$studentId/${DateTime.now().millisecondsSinceEpoch}.$extension',
        );
    final Uint8List bytes = await picked.readAsBytes();
    final snap = await ref.putData(bytes);
    final url = await snap.ref.getDownloadURL();

    await _students.doc(studentId).set({
      'documents': FieldValue.arrayUnion([
        {
          'name': documentName,
          'url': url,
          'uploadedAt': FieldValue.serverTimestamp(),
        },
      ]),
    }, SetOptions(merge: true));
    await _refreshParentCopy(studentId);
  }

  Future<void> removeStudentDocument({
    required String studentId,
    required String documentUrl,
  }) async {
    final snapshot = await _students.doc(studentId).get();
    final docs = (snapshot.data()?['documents'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    docs.removeWhere((doc) => doc['url']?.toString() == documentUrl);
    await _students.doc(studentId).set({
      'documents': docs,
    }, SetOptions(merge: true));
    await _refreshParentCopy(studentId);
  }

  Future<void> seedSampleStudents() async {
    final classes = await getClasses();
    if (classes.isEmpty) return;

    final existing = await _students.limit(1).get();
    if (existing.docs.isNotEmpty) return;

    final seeds = [
      ('Aarav Sharma', 'ADM-001', 'Male'),
      ('Ananya Patel', 'ADM-002', 'Female'),
      ('Ishaan Verma', 'ADM-003', 'Male'),
    ];

    for (var i = 0; i < seeds.length; i++) {
      final seed = seeds[i];
      final student = AdminStudentModel(
        id: '',
        name: seed.$1,
        admissionNo: seed.$2,
        classId: classes[i % classes.length].id,
        section: '',
        rollNumber: '',
        dateOfBirth: '',
        age: null,
        gender: seed.$3,
        bloodGroup: '',
        nationality: '',
        motherTongue: '',
        addressLine1: '',
        addressLine2: '',
        city: '',
        state: '',
        pincode: '',
        isActive: true,
        isApproved: true,
        createdAt: null,
        createdBy: null,
        profileImageUrl: '',
        parentLinks: const [],
        documents: const [],
      );
      await createStudent(student: student, createdBy: 'seed');
    }
  }
}
