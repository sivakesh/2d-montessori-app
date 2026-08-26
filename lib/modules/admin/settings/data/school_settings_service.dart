import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../models/school_settings_model.dart';

/// Reads/writes the single School Settings document per `schoolId`, and
/// manages its logo in Firebase Storage. Mirrors the DI shape already used
/// by AdminDocumentsService/FeeService/LeaveService (constructor-injected
/// Firestore/Storage/FilePicker, each defaulting to the real platform
/// singleton) and AdminDocumentsService's own Storage path convention
/// (`<collection>/<id>/<timestamp>_<filename>`, best-effort delete on
/// replace/remove) — no new upload architecture introduced.
///
/// Every method takes an explicit `requesterRole` and re-checks it's
/// 'admin' itself (throwing [UnauthorizedSchoolSettingsException]
/// otherwise), the same "never trust the caller, verify server-side" shape
/// [LeaveService.submitStudentLeaveRequest] already uses for its own
/// authorization check — so Staff/Parent are blocked at this service
/// boundary even if a UI slip ever let one reach this screen.
class SchoolSettingsService {
  SchoolSettingsService({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
    FilePicker? filePicker,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance,
        _filePicker = filePicker ?? FilePicker.platform;

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;
  final FilePicker _filePicker;

  CollectionReference<Map<String, dynamic>> get _settings =>
      _firestore.collection('school_settings');

  void _requireAdmin(String requesterRole) {
    if (requesterRole.toLowerCase() != 'admin') {
      throw UnauthorizedSchoolSettingsException(requesterRole);
    }
  }

  /// The settings for [schoolId], or null if none has ever been saved for
  /// it — never a different school's document, since the Firestore path is
  /// always `school_settings/{schoolId}` (this is the schoolId isolation
  /// boundary: two different schoolIds can never read/overwrite each
  /// other's document through this service). Callers should treat null as
  /// "show an empty/default form", not as an error.
  Future<SchoolSettingsModel?> getSettings({
    required String schoolId,
    required String requesterRole,
  }) async {
    _requireAdmin(requesterRole);
    final doc = await _settings.doc(schoolId).get();
    final data = doc.data();
    if (!doc.exists || data == null) return null;
    return SchoolSettingsModel.fromMap(doc.id, data);
  }

  /// Read-only brand-identity projection (name + logo, alongside the rest
  /// of the record) for app chrome — AppSidebar/AdminSidebar show the
  /// school's saved name/logo to every signed-in user (Admin/Staff/
  /// Parent), not just Admin, so unlike [getSettings] this has no role
  /// check. Only *editing* the full record (contact details included)
  /// stays Admin-only via [getSettings]/[saveSettings]/logo methods. Same
  /// `school_settings/{schoolId}` document, same collection — this is a
  /// narrower read of the one settings record, not a second source of
  /// truth. Returns null if nothing has been saved yet, exactly like
  /// [getSettings] — callers should fall back to the app's own hardcoded
  /// default identity rather than treating null as an error.
  Future<SchoolSettingsModel?> getSchoolIdentity({required String schoolId}) async {
    final doc = await _settings.doc(schoolId).get();
    final data = doc.data();
    if (!doc.exists || data == null) return null;
    return SchoolSettingsModel.fromMap(doc.id, data);
  }

  /// Creates the settings document for [schoolId] on the first call, or
  /// updates that exact same document on every subsequent call — always a
  /// merge-set on the fixed `schoolId` doc id, never `.add()`/a new id, so
  /// repeated saves can never produce duplicate settings documents.
  /// Validates [name]/[email]/[website] (the same functions the form's own
  /// fields validate with) before writing anything, so a direct call can
  /// never persist an invalid record even if a UI slip skipped its own
  /// validation. [phone] is intentionally never format-validated — normal
  /// school phone formats (country codes, extensions, spaces/dashes) must
  /// keep working.
  Future<void> saveSettings({
    required String schoolId,
    required String requesterRole,
    required String name,
    String? logoUrl,
    String address = '',
    String phone = '',
    String email = '',
    String website = '',
    String description = '',
    required String updatedBy,
    required String updatedByName,
  }) async {
    _requireAdmin(requesterRole);

    final nameError = SchoolSettingsValidation.validateName(name);
    if (nameError != null) throw ArgumentError(nameError);
    final emailError = SchoolSettingsValidation.validateEmail(email);
    if (emailError != null) throw ArgumentError(emailError);
    final websiteError = SchoolSettingsValidation.validateWebsite(website);
    if (websiteError != null) throw ArgumentError(websiteError);

    final data = <String, dynamic>{
      'schoolId': schoolId,
      'name': name.trim(),
      'address': address.trim(),
      'phone': phone.trim(),
      'email': email.trim(),
      'website': website.trim(),
      'description': description.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': updatedBy,
      'updatedByName': updatedByName,
    };
    if (logoUrl != null) data['logoUrl'] = logoUrl;

    await _settings.doc(schoolId).set(data, SetOptions(merge: true));
  }

  /// Opens the platform file picker restricted to images. Returns null if
  /// the user cancels.
  Future<PlatformFile?> pickLogoFile() async {
    final result = await _filePicker.pickFiles(withData: true, type: FileType.image);
    if (result == null || result.files.isEmpty) return null;
    return result.files.first;
  }

  /// Uploads [file] as the new logo for [schoolId] and returns its download
  /// URL. Does not itself touch Firestore — callers pass the returned URL
  /// into [saveSettings]'s `logoUrl` so the logo and the rest of the form
  /// save as one write, and nothing is uploaded at all unless/until the
  /// user actually saves (picking a file alone never writes to Storage,
  /// so cancelling the form never leaves an orphaned upload behind).
  ///
  /// If [previousLogoUrl] is given, it is deleted from Storage only after
  /// the new file's own upload succeeds, and only best-effort — a delete
  /// failure (e.g. the object was already gone) never fails the new
  /// upload, since the new logo is already live at that point.
  Future<String> uploadLogo({
    required String schoolId,
    required String requesterRole,
    required PlatformFile file,
    String? previousLogoUrl,
  }) async {
    _requireAdmin(requesterRole);
    final bytes = file.bytes;
    if (bytes == null) {
      throw StateError('File bytes were not available for upload');
    }
    final safeName = '${DateTime.now().millisecondsSinceEpoch}_${file.name}';
    final ref = _storage.ref().child('school_settings/$schoolId/$safeName');
    final snapshot = await ref.putData(bytes);
    final url = await snapshot.ref.getDownloadURL();

    if (previousLogoUrl != null && previousLogoUrl.isNotEmpty) {
      try {
        await _storage.refFromURL(previousLogoUrl).delete();
      } catch (_) {
        // Best-effort cleanup only — see doc comment above.
      }
    }
    return url;
  }

  /// Deletes [logoUrl] from Storage (best-effort — a missing/already-
  /// deleted object never blocks clearing the field) and clears `logoUrl`
  /// on the settings document for [schoolId].
  Future<void> removeLogo({
    required String schoolId,
    required String requesterRole,
    required String logoUrl,
    required String updatedBy,
    required String updatedByName,
  }) async {
    _requireAdmin(requesterRole);
    if (logoUrl.isNotEmpty) {
      try {
        await _storage.refFromURL(logoUrl).delete();
      } catch (_) {}
    }
    await _settings.doc(schoolId).set({
      'logoUrl': '',
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': updatedBy,
      'updatedByName': updatedByName,
    }, SetOptions(merge: true));
  }
}
