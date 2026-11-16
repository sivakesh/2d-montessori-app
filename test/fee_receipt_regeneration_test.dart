// Regenerate PDF for an existing fee receipt: the professional receipt
// (RegeneratedReceipt, FeeReceiptRegenerateDialog), Amount in Words
// (IndianAmount) and the school profile it prints (School Settings: the
// address fields, website and GSTIN).
//
// The regenerated copy is downloaded separately and writes nothing; the
// default receipt (collection, Generate PDF) and its stored PDF are
// unchanged. Numbers refer to the task's test list.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:montessori_app/modules/admin/settings/data/academic_year_service.dart';
import 'package:montessori_app/modules/admin/settings/data/school_settings_service.dart';
import 'package:montessori_app/modules/admin/settings/models/school_settings_model.dart';
import 'package:montessori_app/modules/admin/settings/ui/school_settings_screen.dart';
import 'package:montessori_app/modules/auth/models/app_user.dart';
import 'package:montessori_app/modules/auth/providers/auth_provider.dart';
import 'package:montessori_app/modules/fees/models/amount_in_words.dart';
import 'package:montessori_app/modules/fees/models/fee_component_model.dart';
import 'package:montessori_app/modules/fees/models/fee_receipt_model.dart';
import 'package:montessori_app/modules/fees/models/fee_structure_model.dart';
import 'package:montessori_app/modules/fees/models/student_fee_assignment_model.dart';
import 'package:montessori_app/modules/fees/services/fee_receipt_regeneration.dart';
import 'package:montessori_app/modules/fees/services/fee_service.dart';
import 'package:montessori_app/modules/fees/ui/dialogs/fee_receipt_regenerate_dialog.dart';
import 'package:montessori_app/modules/fees/ui/dialogs/fee_receipt_view_dialog.dart';
import 'package:montessori_app/modules/finance/services/finance_service.dart';

import 'support/buffered_transaction_firestore.dart';

/// The words a PDF made by the `pdf` package draws (each `[(word)]TJ`),
/// in order, separated by spaces.
/// The page content streams of [bytes], decompressed.
String pdfContent(Uint8List bytes) {
  final raw = latin1.decode(bytes);
  final out = StringBuffer();
  for (final m in RegExp(r'stream\r?\n').allMatches(raw)) {
    final end = raw.indexOf('endstream', m.end);
    if (end < 0) continue;
    try {
      out.write(latin1.decode(ZLibDecoder().convert(bytes.sublist(m.end, end))));
    } catch (_) {}
  }
  return out.toString();
}

String pdfText(Uint8List bytes) {
  final raw = latin1.decode(bytes);
  final words = <String>[];
  for (final m in RegExp(r'stream\r?\n').allMatches(raw)) {
    final end = raw.indexOf('endstream', m.end);
    if (end < 0) continue;
    try {
      final content = latin1.decode(ZLibDecoder().convert(bytes.sublist(m.end, end)));
      for (final w in RegExp(r'\[\((.*?)\)\]TJ').allMatches(content)) {
        words.add(w.group(1)!.replaceAllMapped(RegExp(r'\\([()\\])'), (x) => x.group(1)!));
      }
    } catch (_) {}
  }
  return words.join(' ');
}

const validGstin = '27AAPFU0939F1ZV';

const school = SchoolSettingsModel(
  schoolId: kDefaultSchoolId,
  name: '2D Eduvance Montessori',
  logoUrl: '',
  address: '12, Lake View Road',
  addressLine2: 'Near Park Gate',
  locality: 'Anna Nagar',
  city: 'Chennai',
  state: 'Tamil Nadu',
  pinCode: '600040',
  phone: '+91 98400 12345',
  email: 'office@2dmontessori.example',
  website: 'https://2dmontessori.example',
  description: '',
  gstin: validGstin,
  updatedAt: null,
  updatedBy: null,
  updatedByName: null,
);

FeeReceiptModel receiptOf({double amount = 52500, String className = 'Mont 1', String feeMonth = '', String reference = 'UPI-778899', String mode = 'upi'}) =>
    FeeReceiptModel(
      id: 'r1', receiptNo: 'RCPT-0001', transactionId: 't1', assignmentId: 'a1', studentId: 's1', studentName: 'Anu Raman', admissionNo: 'ADM-101',
      className: className, feeStructureName: 'Term Fees', amount: amount, paymentMode: mode, paymentDate: DateTime(2026, 11, 5), referenceNo: reference,
      createdAt: DateTime(2026, 11, 5), createdBy: 'Admin', pdfUrl: 'https://x/r.pdf', pdfPath: 'fee_receipts/r1/RCPT-0001.pdf', pdfGeneratedAt: DateTime(2026, 11, 5),
      feeMonth: feeMonth,
    );

const fullOptions = ReceiptRegenerationOptions(
  className: 'Mont 2',
  parentRelation: 'Father',
  parentName: 'Raman K',
  natureOfFee: 'Day Care Fee',
  servicePeriod: 'November 2026',
);

String? valueIn(List<(String, String)> rows, String label) => rows.where((e) => e.$1 == label).map((e) => e.$2).firstOrNull;

class _NoFilePicker extends FilePicker {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ------------------------------------------------------ Amount in Words
  group('17. Amount in Words (Indian numbering)', () {
    String w(double rupees) => IndianAmount.words(IndianAmount.paiseOf(rupees));

    test('zero, single digits, hundreds', () {
      expect(w(0), 'Rupees Zero Only');
      expect(w(7), 'Rupees Seven Only');
      expect(w(19), 'Rupees Nineteen Only');
      expect(w(100), 'Rupees One Hundred Only');
      expect(w(522), 'Rupees Five Hundred Twenty-Two Only');
    });

    test('thousands (the task\'s examples)', () {
      expect(w(2600), 'Rupees Two Thousand Six Hundred Only');
      expect(w(4200), 'Rupees Four Thousand Two Hundred Only');
      expect(w(52500), 'Rupees Fifty-Two Thousand Five Hundred Only');
      expect(w(1000), 'Rupees One Thousand Only');
      expect(w(99999), 'Rupees Ninety-Nine Thousand Nine Hundred Ninety-Nine Only');
    });

    test('lakhs and crores', () {
      expect(w(100000), 'Rupees One Lakh Only');
      expect(w(125000), 'Rupees One Lakh Twenty-Five Thousand Only');
      expect(w(1250000), 'Rupees Twelve Lakh Fifty Thousand Only');
      expect(w(10000000), 'Rupees One Crore Only');
      expect(w(12345678), 'Rupees One Crore Twenty-Three Lakh Forty-Five Thousand Six Hundred Seventy-Eight Only');
    });

    test('paise', () {
      expect(w(1250.5), 'Rupees One Thousand Two Hundred Fifty and Fifty Paise Only');
      expect(w(0.05), 'Rupees Zero and Five Paise Only');
      expect(w(2600.99), 'Rupees Two Thousand Six Hundred and Ninety-Nine Paise Only');
    });

    test('large amounts: crores of crores', () {
      expect(w(1234567890), 'Rupees One Hundred Twenty-Three Crore Forty-Five Lakh Sixty-Seven Thousand Eight Hundred Ninety Only');
      expect(IndianAmount.number(1000000000000), 'One Lakh Crore');
    });

    test('figures with Indian grouping, from the same paise', () {
      expect(IndianAmount.figures(IndianAmount.paiseOf(0)), '0.00');
      expect(IndianAmount.figures(IndianAmount.paiseOf(999)), '999.00');
      expect(IndianAmount.figures(IndianAmount.paiseOf(52500)), '52,500.00');
      expect(IndianAmount.figures(IndianAmount.paiseOf(125000.5)), '1,25,000.50');
      expect(IndianAmount.figures(IndianAmount.paiseOf(123456789)), '12,34,56,789.00');
      // The recorded double as stored: never rounded differently.
      expect(IndianAmount.paiseOf(1250.1 + 0.2), 125030);
      expect(() => IndianAmount.paiseOf(-1), throwsArgumentError);
      expect(() => IndianAmount.paiseOf(double.nan), throwsArgumentError);
    });
  });

  // ------------------------------------------------- the document content
  group('regenerated receipt content (from the PDF text)', () {
    late String text;
    setUpAll(() async {
      text = pdfText(await RegeneratedReceipt.build(receiptOf(), fullOptions, school: school).toPdf());
    });

    test('1, 2, 3. school name, full address, phone, email and website, in order', () {
      final order = [
        '2D Eduvance Montessori',
        '12, Lake View Road',
        'Near Park Gate',
        'Anna Nagar, Chennai, Tamil Nadu - 600040',
        'Phone: +91 98400 12345',
        'Email: office@2dmontessori.example',
        'Website: https://2dmontessori.example',
        'FEE PAYMENT RECEIPT',
      ];
      var at = -1;
      for (final s in order) {
        final i = text.indexOf(s);
        expect(i, greaterThan(at), reason: '"$s" after the previous header line');
        at = i;
      }
    });

    test('1. the logo: the school\'s own when given, else the bundled one', () async {
      final png = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg==');
      final doc = RegeneratedReceipt.build(receiptOf(), fullOptions, school: school);
      // An image drawn on the page (`/I<n> Do`).
      expect(pdfContent(await doc.toPdf(logo: png)), matches(RegExp(r'/I\d+ Do')));
      expect(pdfContent(await doc.toPdf()), matches(RegExp(r'/I\d+ Do')), reason: 'assets/logo.png');
    });

    test('5, 7, 8, 10. student details: parent, student, admission number, chosen class', () {
      expect(text, contains("STUDENT DETAILS Father's Name Raman K Student Name Anu Raman Admission No ADM-101 Class Mont 2"));
    });

    test('11-16. payment details and the amount', () {
      expect(text, contains('PAYMENT DETAILS Nature of Fee Day Care Fee Service Period November 2026 Payment Mode UPI Transaction Reference UPI-778899 Payment Date 05 Nov 2026'));
      expect(text, contains('Receipt No: RCPT-0001'));
      expect(text, contains('Receipt Date: 05 Nov 2026'));
      expect(text, contains('Amount Paid Rs. 52,500.00'));
      expect(text, contains('Amount in Words: Rupees Fifty-Two Thousand Five Hundred Only'));
    });

    test('18, 19, 20. the signature-free footer; no Fee Name, Generated Date or signature', () {
      expect(text, contains('System-generated fee receipt. No signature required.'));
      for (final gone in ['Fee Name', 'Term Fees', 'Generated', 'Signature', 'Authori']) {
        expect(text, isNot(contains(gone)));
      }
    });

    test('4, 22. GSTIN: omitted unless included; included only when configured and valid', () async {
      expect(text, isNot(contains('GSTIN')));
      final included = pdfText(await RegeneratedReceipt.build(receiptOf(), const ReceiptRegenerationOptions(className: 'Mont 2', showGstin: true, gstin: validGstin), school: school).toPdf());
      expect(included, contains('GSTIN: $validGstin'));
      expect(included.indexOf('GSTIN'), lessThan(included.indexOf('FEE PAYMENT RECEIPT')), reason: 'in the header');
      for (final bad in ['', '27AAPFU0939F1ZA']) {
        final o = ReceiptRegenerationOptions(className: 'Mont 2', showGstin: true, gstin: bad);
        expect(RegeneratedReceipt.validate(o), bad.isEmpty ? RegeneratedReceipt.gstinMissingMessage : contains('not valid'));
        expect(() => RegeneratedReceipt.build(receiptOf(), o, school: school), throwsArgumentError);
      }
    });

    test('23, 24, 25. GST checkboxes, all four combinations: the GSTIN and "(GST Included)" are independent; the amount never changes', () async {
      for (final (show, includes) in [(false, false), (true, false), (false, true), (true, true)]) {
        final reason = 'Show GSTIN $show, Amount includes GST $includes';
        final doc = RegeneratedReceipt.build(
          receiptOf(),
          ReceiptRegenerationOptions(className: 'Mont 2', showGstin: show, gstin: validGstin, amountIncludesGst: includes),
          school: school,
        );
        expect(doc.gstin, show ? validGstin : '', reason: reason);
        expect(doc.amountFigures, 'Rs. 52,500.00', reason: reason);
        expect(doc.amountLabel, includes ? 'Rs. 52,500.00 (GST Included)' : 'Rs. 52,500.00', reason: reason);
        expect(doc.amountWords, 'Rupees Fifty-Two Thousand Five Hundred Only', reason: reason);
        final t = pdfText(await doc.toPdf());
        expect(t.contains('GSTIN: $validGstin'), show, reason: reason);
        expect(t.contains('GSTIN'), show, reason: reason);
        expect(t.contains('Amount Paid Rs. 52,500.00 (GST Included)'), includes, reason: reason);
        expect(t.contains('GST Included'), includes, reason: reason);
        expect(t, contains('Amount in Words: Rupees Fifty-Two Thousand Five Hundred Only'), reason: reason);
        expect(RegExp(r'Rs\. [0-9,]+\.[0-9]{2}').allMatches(t).map((m) => m.group(0)).toSet(), {'Rs. 52,500.00'}, reason: '$reason: no other amount (no GST figure)');
      }
      // "Amount includes GST" needs no GSTIN at all: the two are different things.
      final noGstin = RegeneratedReceipt.build(receiptOf(), const ReceiptRegenerationOptions(className: 'Mont 2', amountIncludesGst: true), school: school);
      expect(noGstin.amountLabel, 'Rs. 52,500.00 (GST Included)');
      expect(pdfText(await noGstin.toPdf()), isNot(contains('GSTIN')));
    });

    test('16, 17. paise kept: figures and words agree', () async {
      final t = pdfText(await RegeneratedReceipt.build(receiptOf(amount: 125000.5), fullOptions, school: school).toPdf());
      expect(t, contains('Rs. 1,25,000.50'));
      expect(t, contains('Rupees One Lakh Twenty-Five Thousand and Fifty Paise Only'));
    });

    test('empty optional fields are left out cleanly, never blank placeholders', () async {
      final t = pdfText(await RegeneratedReceipt.build(receiptOf(reference: ''), const ReceiptRegenerationOptions(className: 'Mont 1')).toPdf());
      expect(t, contains('2D Montessori'), reason: 'the app\'s default name when no profile is saved');
      for (final gone in ['Phone', 'Email', 'Website', 'GSTIN', "'s Name", 'Nature of Fee', 'Service Period', 'Transaction Reference']) {
        expect(t, isNot(contains(gone)));
      }
      expect(t, contains('Payment Mode UPI'));
    });

    test('5, 6. parents from the student record; Father preferred; Guardian for other relations', () {
      final parents = ReceiptParent.fromStudent({
        'parentLinks': [
          {'name': 'Lakshmi R', 'relation': 'Mother'},
          {'name': 'Raman K', 'relation': 'Father'},
          {'name': 'Uncle Ravi', 'relation': 'Other'},
          {'name': '  ', 'relation': 'Father'},
        ],
      });
      expect([for (final p in parents) '${p.relation}:${p.name}'], ['Mother:Lakshmi R', 'Father:Raman K', 'Guardian:Uncle Ravi']);
      expect(ReceiptParent.preferred(parents)!.name, 'Raman K');
      expect(ReceiptParent.preferred(ReceiptParent.fromStudent({'parentLinks': [{'name': 'Lakshmi R', 'relation': 'Mother'}]}))!.relation, 'Mother');
      expect(ReceiptParent.fromStudent({}), isEmpty);
      expect(ReceiptParent.fromStudent(null), isEmpty);
      for (final (rel, label) in [('Father', "Father's Name"), ('Mother', "Mother's Name"), ('Guardian', "Guardian's Name")]) {
        final r = RegeneratedReceipt.build(receiptOf(), ReceiptRegenerationOptions(className: 'Mont 1', parentRelation: rel, parentName: 'X Y'));
        expect(valueIn(r.studentRows, label), 'X Y');
      }
    });

    test('11, 12. nature of fee and service period only from saved data', () {
      FeeStructureModel structure({String description = '', List<FeeComponentModel> components = const []}) => FeeStructureModel.fromMap('st', {
            'name': 'Term Fees', 'description': description, 'totalAmount': 1, 'academicYear': '2026-2027', 'isActive': true,
            'components': [for (final c in components) c.toMap()],
          });
      expect(RegeneratedReceipt.natureOfFeeFrom(structure(description: 'Montessori Fee')), 'Montessori Fee');
      expect(RegeneratedReceipt.natureOfFeeFrom(structure(components: [
        FeeComponentModel(name: 'Tuition Fee', amount: 1, frequency: 'monthly', isOptional: false),
        FeeComponentModel(name: 'Day Care Fee', amount: 1, frequency: 'monthly', isOptional: false),
      ])), 'Tuition Fee, Day Care Fee');
      expect(RegeneratedReceipt.natureOfFeeFrom(structure()), '');
      expect(RegeneratedReceipt.natureOfFeeFrom(null), '');

      StudentFeeAssignmentModel assignment({String feeMonth = '', String year = '2026-2027'}) => StudentFeeAssignmentModel.fromMap('a1', {
            'studentId': 's1', 'feeStructureId': 'st', 'academicYear': year, 'feeMonth': feeMonth, 'totalFee': 1, 'payableAmount': 1,
          });
      expect(RegeneratedReceipt.servicePeriodFrom(receiptOf(feeMonth: '2026-11'), null), 'November 2026');
      expect(RegeneratedReceipt.servicePeriodFrom(receiptOf(), assignment(feeMonth: '2026-10')), 'October 2026');
      expect(RegeneratedReceipt.servicePeriodFrom(receiptOf(), assignment()), 'Academic Year 2026-2027');
      expect(RegeneratedReceipt.servicePeriodFrom(receiptOf(), assignment(year: '')), '');
      expect(RegeneratedReceipt.servicePeriodFrom(receiptOf(), null), '');
    });

    test('the copy\'s file name is never the stored original\'s', () {
      expect(RegeneratedReceipt.fileName(receiptOf()), 'RCPT-0001-copy.pdf');
    });
  });

  // ------------------------------------------- School Settings: the service
  group('School Settings profile', () {
    late FakeFirebaseFirestore firestore;
    late SchoolSettingsService service;
    setUp(() {
      firestore = FakeFirebaseFirestore();
      service = SchoolSettingsService(firestore: firestore, storage: MockFirebaseStorage(), filePicker: _NoFilePicker());
    });

    Future<void> save(String school, {String name = 'School', String? gstin, String? city, String? pinCode}) => service.saveSettings(
          schoolId: school, requesterRole: 'admin', name: name, gstin: gstin, city: city, pinCode: pinCode, updatedBy: 'u', updatedByName: 'U',
        );

    test('GSTIN format and check character; PIN code', () {
      expect(SchoolSettingsValidation.validateGstin(''), isNull);
      expect(SchoolSettingsValidation.validateGstin(validGstin), isNull);
      expect(SchoolSettingsValidation.validateGstin(' 27aapfu0939f1zv '), isNull, reason: 'normalised');
      expect(SchoolSettingsValidation.validateGstin('29AAGCB7383J1Z4'), isNull);
      expect(SchoolSettingsValidation.validateGstin('27AAPFU0939F1ZA'), contains('check character'));
      expect(SchoolSettingsValidation.validateGstin('27AAPFU0939F1Z'), isNotNull);
      expect(SchoolSettingsValidation.validatePinCode('600040'), isNull);
      expect(SchoolSettingsValidation.validatePinCode(''), isNull);
      for (final bad in ['060004', '60004', '6000401', 'ABCDEF']) {
        expect(SchoolSettingsValidation.validatePinCode(bad), isNotNull, reason: bad);
      }
    });

    test('34. per school: never another school\'s, never overwritten by it; admins only', () async {
      await save('school_a', name: 'A', gstin: validGstin, city: 'Chennai');
      await save('school_b', name: 'B', city: 'Madurai');
      final a = (await service.getSchoolIdentity(schoolId: 'school_a'))!;
      final b = (await service.getSchoolIdentity(schoolId: 'school_b'))!;
      expect([a.name, a.gstin, a.city], ['A', validGstin, 'Chennai']);
      expect([b.name, b.gstin, b.city], ['B', '', 'Madurai']);
      await expectLater(save('school_b', gstin: '27AAPFU0939F1ZA'), throwsArgumentError);
      await expectLater(save('school_b', pinCode: '12'), throwsArgumentError);
      expect((await service.getSchoolIdentity(schoolId: 'school_b'))!.gstin, '');
      await expectLater(
        service.saveSettings(schoolId: 'school_a', requesterRole: 'staff', name: 'X', gstin: '', updatedBy: 'u', updatedByName: 'U'),
        throwsA(isA<UnauthorizedSchoolSettingsException>()),
      );
      expect((await service.getSchoolIdentity(schoolId: 'school_a'))!.gstin, validGstin);
    });

    test('33. a save that doesn\'t pass the GSTIN or address parts keeps them, and other fields', () async {
      await firestore.collection('school_settings').doc('school_a').set({'schoolId': 'school_a', 'name': 'A', 'publicFormSubmissions': {'enabled': true}, 'logoUrl': 'https://x/logo.png'});
      await save('school_a', name: 'A', gstin: validGstin, city: 'Chennai', pinCode: '600040');
      await save('school_a', name: 'Renamed');
      final data = (await firestore.collection('school_settings').doc('school_a').get()).data()!;
      expect([data['name'], data['gstin'], data['city'], data['pinCode'], data['logoUrl'], data['publicFormSubmissions']],
          ['Renamed', validGstin, 'Chennai', '600040', 'https://x/logo.png', {'enabled': true}]);
      await save('school_a', name: 'Renamed', gstin: '');
      expect((await service.getSchoolIdentity(schoolId: 'school_a'))!.gstin, '', reason: 'cleared only explicitly');
    });

    test('the postal address as printed, and an address saved before (Line 1) kept', () {
      expect(school.postalAddressLines, ['12, Lake View Road', 'Near Park Gate', 'Anna Nagar, Chennai, Tamil Nadu - 600040']);
      final legacy = SchoolSettingsModel.fromMap('s', {'name': 'S', 'address': 'No. 4, First Street\nT. Nagar, Chennai'});
      expect(legacy.postalAddressLines, ['No. 4, First Street', 'T. Nagar, Chennai']);
      expect(SchoolSettingsModel.fromMap('s', {'name': 'S', 'city': 'Chennai'}).postalAddressLines, ['Chennai']);
      expect(SchoolSettingsModel.fromMap('s', {'name': 'S'}).postalAddressLines, isEmpty);
    });
  });

  // ---------------------------------------------- School Settings: the form
  group('School Settings form', () {
    late FakeFirebaseFirestore firestore;
    late SchoolSettingsService service;
    setUp(() async {
      firestore = FakeFirebaseFirestore();
      service = SchoolSettingsService(firestore: firestore, storage: MockFirebaseStorage(), filePicker: _NoFilePicker());
      await firestore.collection('school_settings').doc(kDefaultSchoolId).set({'schoolId': kDefaultSchoolId, 'name': '2D Montessori', 'address': '12, Lake View Road', 'description': 'Kept'});
    });

    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(ProviderScope(
        key: UniqueKey(),
        overrides: [currentUserProvider.overrideWith((ref) => AppUser(id: 'u1', phone: '9999999999', role: 'admin', isActive: true, name: 'Admin'))],
        child: MaterialApp(home: SchoolSettingsScreen(service: service)),
      ));
      await tester.pumpAndSettle();
    }

    Future<void> enter(WidgetTester tester, String key, String value) async {
      await tester.ensureVisible(find.byKey(Key(key)));
      await tester.enterText(find.byKey(Key(key)), value);
      await tester.pumpAndSettle();
    }

    Future<void> saveForm(WidgetTester tester) async {
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
    }

    String field(WidgetTester tester, String key) => tester.widget<TextFormField>(find.byKey(Key(key))).controller!.text;

    testWidgets('an invalid GSTIN or PIN is refused with its message and nothing is saved', (tester) async {
      await open(tester);
      expect(field(tester, 'school-settings-address-line1'), '12, Lake View Road', reason: 'the address saved before, as Line 1');
      await enter(tester, 'school-settings-gstin', '27AAPFU0939F1ZA');
      await enter(tester, 'school-settings-pin-code', '12345');
      await saveForm(tester);
      expect(find.textContaining('check character does not match'), findsOneWidget);
      expect(find.text('Enter a valid 6-digit PIN code.'), findsOneWidget);
      final data = (await firestore.collection('school_settings').doc(kDefaultSchoolId).get()).data()!;
      expect(data.containsKey('gstin'), isFalse);
    });

    testWidgets('GSTIN, address and website entered, saved, and shown again on reopening', (tester) async {
      await open(tester);
      await enter(tester, 'school-settings-address-line2', 'Near Park Gate');
      await enter(tester, 'school-settings-locality', 'Anna Nagar');
      await enter(tester, 'school-settings-city', 'Chennai');
      await enter(tester, 'school-settings-state', 'Tamil Nadu');
      await enter(tester, 'school-settings-pin-code', '600040');
      await enter(tester, 'school-settings-website', 'https://2dmontessori.example');
      await enter(tester, 'school-settings-phone', '+91 98400 12345');
      await enter(tester, 'school-settings-gstin', '27aapfu0939f1zv');
      await saveForm(tester);
      expect(find.text('School settings saved'), findsOneWidget);
      final data = (await firestore.collection('school_settings').doc(kDefaultSchoolId).get()).data()!;
      expect([data['address'], data['addressLine2'], data['locality'], data['city'], data['state'], data['pinCode'], data['website'], data['phone'], data['gstin'], data['description']],
          ['12, Lake View Road', 'Near Park Gate', 'Anna Nagar', 'Chennai', 'Tamil Nadu', '600040', 'https://2dmontessori.example', '+91 98400 12345', validGstin, 'Kept']);

      await open(tester);
      expect(field(tester, 'school-settings-gstin'), validGstin);
      expect(field(tester, 'school-settings-city'), 'Chennai');
      expect(field(tester, 'school-settings-pin-code'), '600040');
      expect(field(tester, 'school-settings-website'), 'https://2dmontessori.example');
      expect(field(tester, 'school-settings-address-line2'), 'Near Park Gate');
    });
  });

  // --------------------------------------------- real receipts, the dialogs
  group('with a collected receipt', () {
    late BufferedTransactionFirestore firestore;
    late MockFirebaseStorage storage;
    late FeeService fees;
    late FeeReceiptModel receipt;

    setUp(() async {
      firestore = BufferedTransactionFirestore();
      storage = MockFirebaseStorage();
      final auth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'admin-1', displayName: 'Test Admin'));
      final finance = FinanceService(firestore: firestore, auth: auth);
      await finance.ensureDefaults();
      fees = FeeService(firestore: firestore, auth: auth, storage: storage, financeService: finance, clock: () => DateTime(2026, 11, 5));
      final yearId = await AcademicYearService(firestore: firestore).createAcademicYear(
        schoolId: kDefaultSchoolId, requesterRole: 'admin', name: '2026-2027',
        startDate: DateTime(2026, 6, 1), endDate: DateTime(2027, 5, 31), createdBy: 'admin-1', setAsCurrent: true,
      );
      await firestore.collection('fee_structures').doc('term').set({
        'name': 'Term Fees', 'description': 'Montessori Fee', 'totalAmount': 52500, 'academicYear': '2026-2027', 'academicYearId': yearId, 'isActive': true, 'createdBy': 't', 'components': [],
      });
      await firestore.collection('classes').doc('c1').set({'name': 'Mont 1', 'isActive': true});
      await firestore.collection('classes').doc('c2').set({'name': 'Mont 2', 'isActive': true});
      await firestore.collection('classes').doc('c3').set({'name': 'Mont 3', 'isActive': false});
      await firestore.collection('students').doc('s1').set({
        'name': 'Anu Raman', 'admissionNo': 'ADM-101', 'classId': 'c1', 'isActive': true, 'admissionDate': DateTime(2020, 1, 1),
        'parentLinks': [
          {'userId': 'p2', 'name': 'Lakshmi R', 'email': '', 'relation': 'Mother'},
          {'userId': 'p1', 'name': 'Raman K', 'email': '', 'relation': 'Father'},
        ],
      });
      final id = (await fees.assignFee({
        'studentId': 's1', 'studentName': 'Anu Raman', 'admissionNo': 'ADM-101', 'classId': 'c1', 'className': 'Mont 1',
        'feeStructureId': 'term', 'feeStructureName': 'Term Fees', 'academicYearId': yearId, 'academicYear': '2026-2027',
        'totalFee': 52500, 'discountAmount': 0, 'payableAmount': 52500, 'paidAmount': 0, 'balanceAmount': 52500, 'status': 'unpaid', 'dueDate': DateTime(2026, 11, 30),
      }))!;
      await fees.collectFee(assignmentId: id, amount: 52500, paymentDate: DateTime(2026, 11, 5), paymentMode: 'upi', referenceNo: 'UPI-778899', remarks: '');
      // The student has since moved to Mont 2; the receipt says Mont 1.
      await firestore.collection('students').doc('s1').update({'classId': 'c2'});
      await firestore.collection('school_settings').doc(kDefaultSchoolId).set(school.toMap());
      receipt = (await fees.getReceipts()).single;
    });

    /// Every record regeneration must never touch, exactly as stored.
    Future<Map<String, Object?>> records() async => {
          for (final c in ['fee_receipts', 'fee_transactions', 'student_fee_assignments', 'fee_structures', 'students', 'classes', 'finance_income', 'finance_ledger', 'finance_expenses', 'school_settings'])
            c: {for (final d in (await firestore.collection(c).get()).docs) d.id: d.data()},
        };

    Future<SchoolSettingsModel?> loadSchool() async {
      final d = (await firestore.collection('school_settings').doc(kDefaultSchoolId).get()).data();
      return d == null ? null : SchoolSettingsModel.fromMap(kDefaultSchoolId, d);
    }

    Future<void> openView(WidgetTester tester, FeeReceiptModel r, {SchoolProfileLoader? schoolLoader, List<(Uint8List, String)>? saved}) async {
      tester.view.physicalSize = const Size(1200, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        key: UniqueKey(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => FeeReceiptViewDialog(
                  receipt: r,
                  service: fees,
                  loadSchool: schoolLoader ?? loadSchool,
                  loadLogo: (_) async => null,
                  saveRegeneratedPdf: (bytes, name) async => saved?.add((bytes, name)),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    Future<void> openRegenerate(WidgetTester tester) async {
      await tester.tap(find.text('Regenerate PDF'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
      await tester.pumpAndSettle();
    }

    String? selectedClass(WidgetTester tester) =>
        tester.widget<DropdownButton<String>>(find.descendant(of: find.byKey(const Key('receipt-regen-class')), matching: find.byType(DropdownButton<String>))).value;
    String fieldText(WidgetTester tester, String key) => tester.widget<TextField>(find.byKey(Key(key))).controller!.text;

    Future<void> tap(WidgetTester tester, Finder f) async {
      await tester.ensureVisible(f);
      await tester.pumpAndSettle();
      await tester.tap(f);
      await tester.pumpAndSettle();
    }

    Future<void> download(WidgetTester tester) async {
      await tester.ensureVisible(find.byKey(const Key('receipt-regen-generate')));
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('receipt-regen-generate')));
        await Future<void>.delayed(const Duration(milliseconds: 800));
      });
      await tester.pumpAndSettle();
    }

    test('26. the default receipt is unchanged: stored, with Fee Name, Generated Date and the signature line', () async {
      expect(receipt.pdfUrl, isNotEmpty, reason: 'generated when collected');
      expect(receipt.pdfPath, 'fee_receipts/${receipt.id}/${receipt.receiptNo}.pdf');
      final text = pdfText((await storage.ref(receipt.pdfPath).getData())!);
      for (final kept in ['FEE RECEIPT', 'Fee Name', 'Term Fees', 'Generated Date', 'Class Mont 1', 'Payment Date', 'Authorized Signature', 'System generated receipt', 'Rs. 52500']) {
        expect(text, contains(kept));
      }
      for (final absent in ['FEE PAYMENT RECEIPT', 'GSTIN', 'No signature required', 'Amount in Words', 'Lake View']) {
        expect(text, isNot(contains(absent)));
      }
    });

    testWidgets('26. Generate PDF (no PDF yet) is still the default receipt, not the regeneration dialog', (tester) async {
      await tester.runAsync(() => firestore.collection('fee_receipts').doc(receipt.id).update({'pdfUrl': '', 'pdfPath': '', 'pdfGeneratedAt': null}));
      final noPdf = (await tester.runAsync(() => fees.getReceiptById(receipt.id)))!;
      await openView(tester, noPdf);
      expect(find.text('Fee Name'), findsOneWidget, reason: 'the receipt view itself is unchanged');
      expect(find.text('Generated Date'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.text('Generate PDF'));
        await Future<void>.delayed(const Duration(milliseconds: 500));
      });
      await tester.pumpAndSettle();
      expect(find.byType(FeeReceiptRegenerateDialog), findsNothing);
      final stored = (await tester.runAsync(() => fees.getReceiptById(receipt.id)))!;
      expect(stored.pdfPath, 'fee_receipts/${receipt.id}/${receipt.receiptNo}.pdf');
      final text = pdfText((await tester.runAsync<Uint8List?>(() => storage.ref(stored.pdfPath).getData()))!);
      expect(text, contains('Fee Name'));
      expect(text, isNot(contains('FEE PAYMENT RECEIPT')));
    });

    testWidgets('5, 9, 11, 12, 21. defaults: Father preselected, current class, nature and period from saved data, both GST checkboxes unticked; the review shows the amount in words', (tester) async {
      await openView(tester, receipt);
      await openRegenerate(tester);
      expect(find.byType(FeeReceiptRegenerateDialog), findsOneWidget);
      expect(find.byKey(const Key('receipt-regen-note')), findsOneWidget);
      expect(fieldText(tester, 'receipt-regen-parent-name'), 'Raman K');
      expect(find.text("Father's Name"), findsOneWidget);
      expect(selectedClass(tester), 'Mont 2', reason: 'the student\'s current class, not the receipt\'s Mont 1');
      expect(fieldText(tester, 'receipt-regen-nature'), 'Montessori Fee');
      expect(fieldText(tester, 'receipt-regen-period'), 'Academic Year 2026-2027');
      expect(tester.widget<CheckboxListTile>(find.byKey(const Key('receipt-regen-show-gstin'))).value, isFalse);
      expect(find.text('Show GSTIN on receipt'), findsOneWidget);
      expect(tester.widget<CheckboxListTile>(find.byKey(const Key('receipt-regen-amount-includes-gst'))).value, isFalse);
      expect(find.text('Amount includes GST'), findsOneWidget);
      expect(find.byKey(const Key('receipt-regen-gstin')), findsNothing);
      expect(tester.widget<Text>(find.byKey(const Key('receipt-regen-amount'))).data, 'Rs. 52,500.00');
      expect(tester.widget<Text>(find.byKey(const Key('receipt-regen-amount-words'))).data, 'Rupees Fifty-Two Thousand Five Hundred Only');
      await tap(tester, find.byKey(const Key('receipt-regen-class')));
      for (final c in ['Mont 1', 'Mont 2', 'Mont 3']) {
        expect(find.text(c), findsWidgets);
      }
    });

    testWidgets('4, 5, 10, 24, 27-33. Mother, another class and the GSTIN on the copy; nothing stored changes', (tester) async {
      final before = (await tester.runAsync(records))!;
      final saved = <(Uint8List, String)>[];
      await openView(tester, receipt, saved: saved);
      await openRegenerate(tester);
      await tap(tester, find.byKey(const Key('receipt-regen-parent-0')));
      expect(fieldText(tester, 'receipt-regen-parent-name'), 'Lakshmi R');
      await tap(tester, find.byKey(const Key('receipt-regen-class')));
      await tester.tap(find.text('Mont 3').last);
      await tester.pumpAndSettle();
      await tap(tester, find.byKey(const Key('receipt-regen-show-gstin')));
      expect(find.text('GSTIN: $validGstin'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('receipt-regen-amount'))).data, 'Rs. 52,500.00', reason: '24. no label from the checkbox');
      await download(tester);

      expect(find.byType(FeeReceiptRegenerateDialog), findsNothing);
      expect(find.text('Receipt PDF regenerated'), findsWidgets);
      expect(saved.single.$2, RegeneratedReceipt.fileName(receipt));
      expect(saved.single.$2, allOf(endsWith('-copy.pdf'), isNot(receipt.pdfPath.split('/').last)));
      final text = pdfText(saved.single.$1);
      expect(text, contains("Mother's Name Lakshmi R"));
      expect(text, contains('Class Mont 3'));
      expect(text, contains('GSTIN: $validGstin'));
      expect(text, contains('2D Eduvance Montessori'));
      expect(text, contains('Anna Nagar, Chennai, Tamil Nadu - 600040'));
      expect(text, contains('Receipt No: ${receipt.receiptNo}'));
      expect(text, contains('Nature of Fee Montessori Fee Service Period Academic Year 2026-2027'));
      expect(text, contains('Amount Paid Rs. 52,500.00 Amount in Words: Rupees Fifty-Two Thousand Five Hundred Only'));
      expect(text, isNot(contains('GST Included')));

      final after = (await tester.runAsync(records))!;
      expect(after, before, reason: 'receipt (number, amount, class, stored PDF fields), transaction, assignment, structure, student and parents, classes, Finance and School Settings unchanged');
      final original = pdfText((await tester.runAsync<Uint8List?>(() => storage.ref(receipt.pdfPath).getData()))!);
      expect(original, contains('Fee Name'), reason: '27. the stored PDF is still the original default receipt');
      expect(original, isNot(contains('Lakshmi')));
    });

    testWidgets('6, 31. no linked parent: a name entered for the copy only; blank leaves the row out', (tester) async {
      await tester.runAsync(() => firestore.collection('students').doc('s1').update({'parentLinks': []}));
      final before = (await tester.runAsync(records))!;
      final saved = <(Uint8List, String)>[];
      await openView(tester, receipt, saved: saved);
      await openRegenerate(tester);
      expect(fieldText(tester, 'receipt-regen-parent-name'), '');
      expect(find.textContaining('No parent or guardian is linked'), findsOneWidget);
      await download(tester);
      expect(pdfText(saved.last.$1), isNot(contains("'s Name")));

      await openView(tester, receipt, saved: saved);
      await openRegenerate(tester);
      await tap(tester, find.byKey(const Key('receipt-regen-parent-relation')));
      await tester.tap(find.text('Guardian').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('receipt-regen-parent-name')), 'Ravi S');
      await tester.pumpAndSettle();
      await download(tester);
      expect(pdfText(saved.last.$1), contains("Guardian's Name Ravi S"));
      expect((await tester.runAsync(records))!, before, reason: 'the student and parent records unchanged');
    });

    testWidgets('22. Show GSTIN on receipt with no GSTIN configured: the message, and nothing can be downloaded', (tester) async {
      final saved = <(Uint8List, String)>[];
      await openView(tester, receipt, saved: saved, schoolLoader: () async => SchoolSettingsModel.fromMap(kDefaultSchoolId, {...school.toMap(), 'gstin': ''}));
      await openRegenerate(tester);
      await tap(tester, find.byKey(const Key('receipt-regen-show-gstin')));
      expect(find.text(RegeneratedReceipt.gstinMissingMessage), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(const Key('receipt-regen-generate'))).onPressed, isNull);
      await tap(tester, find.byKey(const Key('receipt-regen-show-gstin')));
      expect(find.text(RegeneratedReceipt.gstinMissingMessage), findsNothing);
      await download(tester);
      expect(pdfText(saved.single.$1), isNot(contains('GST')));
    });

    testWidgets('23, 24, 25, 28. the dialog\'s two GST checkboxes, all four combinations: PDF text per choice; nothing stored changes', (tester) async {
      final before = (await tester.runAsync(records))!;
      final saved = <(Uint8List, String)>[];
      for (final (show, includes) in [(false, false), (true, false), (false, true), (true, true)]) {
        final reason = 'Show GSTIN $show, Amount includes GST $includes';
        await openView(tester, receipt, saved: saved);
        await openRegenerate(tester);
        if (show) await tap(tester, find.byKey(const Key('receipt-regen-show-gstin')));
        if (includes) await tap(tester, find.byKey(const Key('receipt-regen-amount-includes-gst')));
        expect(tester.widget<CheckboxListTile>(find.byKey(const Key('receipt-regen-show-gstin'))).value, show, reason: reason);
        expect(tester.widget<CheckboxListTile>(find.byKey(const Key('receipt-regen-amount-includes-gst'))).value, includes, reason: reason);
        expect(find.byKey(const Key('receipt-regen-gstin')), show ? findsOneWidget : findsNothing, reason: reason);
        expect(tester.widget<Text>(find.byKey(const Key('receipt-regen-amount'))).data, includes ? 'Rs. 52,500.00 (GST Included)' : 'Rs. 52,500.00', reason: reason);
        await download(tester);
        expect(find.byType(FeeReceiptRegenerateDialog), findsNothing, reason: reason);

        final t = pdfText(saved.last.$1);
        expect(t.contains('GSTIN: $validGstin'), show, reason: reason);
        expect(t.contains('GST Included'), includes, reason: reason);
        expect(t, contains(includes ? 'Amount Paid Rs. 52,500.00 (GST Included) Amount in Words: Rupees Fifty-Two Thousand Five Hundred Only' : 'Amount Paid Rs. 52,500.00 Amount in Words: Rupees Fifty-Two Thousand Five Hundred Only'), reason: reason);

        expect((await tester.runAsync(records))!, before, reason: '$reason: neither choice is saved; receipt, payment, assignment, Finance and School Settings unchanged');
        final original = pdfText((await tester.runAsync<Uint8List?>(() => storage.ref(receipt.pdfPath).getData()))!);
        expect(original, allOf(contains('Fee Name'), isNot(contains('GST'))), reason: '$reason: the stored PDF is still the original default receipt');
      }
      expect(saved, hasLength(4));
    });

    testWidgets('a voided receipt still cannot be regenerated', (tester) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: FeeReceiptViewDialog(receipt: receipt, service: fees, voided: true))));
      await tester.pumpAndSettle();
      expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'Regenerate PDF')).onPressed, isNull);
    });
  });
}
