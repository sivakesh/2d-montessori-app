import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../public_website/content/website_public_item.dart';
import '../models/public_submission_settings.dart';
import '../models/website_form.dart';

/// What a visitor's browser sends. Nothing in it is trusted: the form, its
/// school, status and fields are all read again from stored data.
class FormSubmissionRequest {
  const FormSubmissionRequest({required this.formId, required this.answers, required this.submissionKey, this.formVersion, this.honeypot = ''});

  final String formId;

  /// Field id → answer (text, option id, `YYYY-MM-DD`, or true/false).
  final Map<String, Object?> answers;

  /// Chosen once per filled-in form ([FormIds.submissionKey]): sending the
  /// same key again stores nothing new.
  final String submissionKey;

  /// The version the visitor filled in, when known.
  final int? formVersion;

  /// A field hidden from people; anything in it marks the submission as
  /// spam.
  final String honeypot;
}

/// What the visitor is told after a submission is stored.
class FormSubmissionReceipt {
  const FormSubmissionReceipt({required this.submissionId, required this.reference, this.duplicate = false});

  final String submissionId;
  final String reference;

  /// The same submission was already stored (sent twice).
  final bool duplicate;
}

enum FormSubmissionErrorCode {
  /// The school has public submissions switched off ([PublicSubmissionSettings]),
  /// or its setting can't be read.
  unavailable,

  /// The form doesn't exist or isn't active.
  notAvailable,

  /// The form was changed since the visitor opened it.
  formChanged,

  /// Some answers aren't accepted ([FormSubmissionException.fieldErrors]).
  invalid,

  /// The request itself is malformed.
  badRequest,

  /// Firestore refused to store it (`permission-denied`): the database's
  /// rules don't allow this write. An operational problem, not the
  /// school's setting.
  permissionDenied,

  /// Storing it failed (connection, timeout).
  failed,
}

class FormSubmissionException implements Exception {
  FormSubmissionException(this.code, [this.fieldErrors = const {}]);

  final FormSubmissionErrorCode code;
  final Map<String, FormAnswerError> fieldErrors;

  @override
  String toString() => 'Form submission refused (${code.name}).';
}

/// Stores visitors' submissions straight to Firestore
/// ([FormCollections.submissions]), after checking everything against
/// stored data. In order:
/// - the school must have public submissions switched on
///   ([PublicSubmissionSettings]); not saved, unreadable or off is refused
///   as [FormSubmissionErrorCode.unavailable]. Read before anything else and
///   again inside the transaction that stores the submission, right before
///   the write, so a switch to off made meanwhile refuses it;
/// - the form's active version ([FormCollections.publicForms]) must be this
///   [schoolId]'s (and, with [FormSubmissionSource.storedDefinition],
///   active in [FormCollections.forms] at the same version);
/// - the version the visitor filled in must be that version;
/// - the answers are checked against that version's fields
///   ([validateFormAnswers]);
/// - the school, version, title and field snapshot come from the stored
///   form, never from the request;
/// - one submission per [FormSubmissionRequest.submissionKey]: a key that
///   is already stored stores nothing new.
///
/// A refusal by Firestore is never taken for success: a submission is
/// confirmed only once its write has committed. Answers are never logged.
///
/// This is not a security boundary: from a browser, someone can skip these
/// checks and write to Firestore directly. The rules must enforce them too
/// (proposal: `test/firebase_rules/forms.firestore.rules`), which is the
/// final security module (`docs/website_forms.md`).
class FormSubmissionService {
  FormSubmissionService({FirebaseFirestore? firestore, this.source = FormSubmissionSource.storedDefinition, this.schoolId = WebsitePublicItem.defaultSchoolId})
      : _firestore = firestore;

  final FirebaseFirestore? _firestore;
  final FormSubmissionSource source;

  /// The school whose website this is: another school's form is refused.
  final String schoolId;

  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;

  /// The school's switch: with [FormSubmissionSource.storedDefinition] its
  /// settings record (`publicFormSubmissions`); from a visitor's browser
  /// its visitor copy, written in the same transaction as the record (the
  /// copy a visitor can read).
  DocumentReference<Map<String, dynamic>> get _settings => source == FormSubmissionSource.storedDefinition
      ? _db.collection(PublicSubmissionSettings.schoolSettingsCollection).doc(schoolId)
      : _db.collection(PublicSubmissionSettings.publicCollection).doc(schoolId);

  bool _open(Map<String, dynamic>? data) => source == FormSubmissionSource.storedDefinition
      ? PublicSubmissionSettings.fromMap(schoolId, data?[PublicSubmissionSettings.field]).enabled
      : PublicSubmissionStatus.fromMap(schoolId, data).open;

  Future<void> _requireOpen(Future<DocumentSnapshot<Map<String, dynamic>>> read) async {
    final DocumentSnapshot<Map<String, dynamic>> settings;
    try {
      settings = await read;
    } catch (_) {
      // Can't be read (refused, offline): closed.
      throw FormSubmissionException(FormSubmissionErrorCode.unavailable);
    }
    if (!_open(settings.data())) throw FormSubmissionException(FormSubmissionErrorCode.unavailable);
  }

  /// Why Firestore refused [e], as the website says it. On the web, an
  /// error raised in a transaction can come back out of it wrapped, so its
  /// code is looked for in the message too.
  static FormSubmissionException _refusal(Object e) {
    final denied = (e is FirebaseException && e.code == 'permission-denied') || e.toString().contains('permission-denied');
    return FormSubmissionException(denied ? FormSubmissionErrorCode.permissionDenied : FormSubmissionErrorCode.failed);
  }

  Future<FormSubmissionReceipt> submit(FormSubmissionRequest request) async {
    if (!FormIds.docPattern.hasMatch(request.formId) || !FormIds.submissionKeyPattern.hasMatch(request.submissionKey) || request.honeypot.length > 500) {
      throw FormSubmissionException(FormSubmissionErrorCode.badRequest);
    }
    await _requireOpen(_settings.get());
    final PublicWebsiteForm? found;
    try {
      found = PublicWebsiteForm.tryParse((await _db.collection(FormCollections.publicForms).doc(request.formId).get()).data());
    } catch (e) {
      throw _refusal(e);
    }
    if (found == null || found.id != request.formId || found.schoolId != schoolId) throw FormSubmissionException(FormSubmissionErrorCode.notAvailable);
    final live = found;
    if (source == FormSubmissionSource.storedDefinition) {
      final stored = await _db.collection(FormCollections.forms).doc(request.formId).get();
      final formData = stored.data();
      if (!stored.exists || formData == null) throw FormSubmissionException(FormSubmissionErrorCode.notAvailable);
      final form = WebsiteForm.fromMap(stored.id, formData);
      if (form.status != WebsiteFormStatus.active || form.schoolId != live.schoolId || form.version != live.version) {
        throw FormSubmissionException(FormSubmissionErrorCode.notAvailable);
      }
    }
    if (request.formVersion != null && request.formVersion != live.version) throw FormSubmissionException(FormSubmissionErrorCode.formChanged);

    final checked = validateFormAnswers(live.fields, request.answers);
    if (checked.errors.isNotEmpty) throw FormSubmissionException(FormSubmissionErrorCode.invalid, checked.errors);

    final ref = _db.collection(FormCollections.submissions).doc(request.submissionKey);
    final reference = formSubmissionReference(request.submissionKey);
    // The transaction returns its refusal rather than throwing it: on the
    // web, an exception thrown inside a transaction doesn't come back out
    // of it as itself.
    final (FormSubmissionReceipt?, FormSubmissionErrorCode?) outcome;
    try {
      outcome = await _db.runTransaction<(FormSubmissionReceipt?, FormSubmissionErrorCode?)>((tx) async {
        // Switched off since the check above: refused.
        try {
          await _requireOpen(tx.get(_settings));
        } on FormSubmissionException catch (e) {
          return (null, e.code);
        }
        // A refused read here is an error, never "already sent": under
        // rules that hide submissions from visitors, it would otherwise
        // report every submission as stored when none was.
        final DocumentSnapshot<Map<String, dynamic>> existing;
        try {
          existing = await tx.get(ref);
        } catch (e) {
          return (null, _refusal(e).code);
        }
        if (existing.exists) {
          // Sent again: the first one stands.
          if (existing.data()?['formId'] != live.id) return (null, FormSubmissionErrorCode.badRequest);
          return (FormSubmissionReceipt(submissionId: ref.id, reference: reference, duplicate: true), null);
        }
        tx.set(ref, {
          'reference': reference,
          'formId': live.id,
          'formVersion': live.version,
          'formTitle': live.title.en,
          'schoolId': live.schoolId,
          'fields': [for (final f in live.fields) f.toMap()],
          'answers': checked.values,
          'status': request.honeypot.trim().isEmpty ? FormSubmissionStatus.newSubmission.id : FormSubmissionStatus.spam.id,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        return (FormSubmissionReceipt(submissionId: ref.id, reference: reference), null);
      });
    } catch (e) {
      // Not committed (refused by the rules, offline): never a receipt.
      throw _refusal(e);
    }
    final (receipt, refused) = outcome;
    if (refused != null) throw FormSubmissionException(refused);
    return receipt!;
  }
}

enum FormSubmissionSource {
  /// Also checks the admins' definition ([FormCollections.forms]) and reads
  /// the school's settings record: for a trusted caller with that access
  /// (tests, a future backend).
  storedDefinition,

  /// What a visitor's browser can read: the form's visitor copy (which
  /// exists only while the form is active: activation writes it and
  /// deactivation deletes it, each in one batch with the status) and the
  /// setting's visitor copy.
  visitorCopy,
}

/// How the public website sends a submission.
abstract class FormSubmissionGateway {
  Future<FormSubmissionReceipt> submit(FormSubmissionRequest request);
}

/// Sends submissions to [service] in-process. For tests.
class TrustedServiceGateway implements FormSubmissionGateway {
  const TrustedServiceGateway(this.service);

  final FormSubmissionService service;

  @override
  Future<FormSubmissionReceipt> submit(FormSubmissionRequest request) => service.submit(request);
}

/// The public website's way of sending: straight to Firestore from the
/// visitor's browser ([FormSubmissionSource.visitorCopy]), in the Firebase
/// project this build uses (DEV or production by `DEPLOY_TARGET`, or the
/// local emulator when `FIRESTORE_EMULATOR_HOST` is set; see `main.dart`).
class DirectFirestoreSubmissionGateway implements FormSubmissionGateway {
  DirectFirestoreSubmissionGateway({FirebaseFirestore? firestore}) : service = FormSubmissionService(firestore: firestore, source: FormSubmissionSource.visitorCopy);

  final FormSubmissionService service;

  @override
  Future<FormSubmissionReceipt> submit(FormSubmissionRequest request) => service.submit(request);
}

/// The public website's submission gateway: direct Firestore writes, the
/// same in every environment. Whether submissions are accepted is each
/// school's own setting.
final formSubmissionGatewayProvider = Provider<FormSubmissionGateway>((ref) => DirectFirestoreSubmissionGateway());
