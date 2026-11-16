import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../admin/settings/models/school_settings_model.dart';
import '../models/amount_in_words.dart';
import '../models/fee_month.dart';
import '../models/fee_receipt_model.dart';
import '../models/fee_structure_model.dart';
import '../models/student_fee_assignment_model.dart';

/// Hands a regenerated receipt PDF to the administrator (the browser
/// download on the web).
typedef ReceiptPdfSaver = Future<void> Function(Uint8List bytes, String fileName);

Future<void> shareReceiptPdf(Uint8List bytes, String fileName) => Printing.sharePdf(bytes: bytes, filename: fileName);

/// A parent or guardian named on a regenerated receipt.
class ReceiptParent {
  const ReceiptParent(this.relation, this.name);

  /// One of [relations].
  final String relation;
  final String name;

  static const relations = ['Father', 'Mother', 'Guardian'];

  /// "Father's Name", "Mother's Name", "Guardian's Name".
  static String labelOf(String relation) => "${relations.contains(relation) ? relation : 'Guardian'}'s Name";

  /// The student's linked parents (`students.parentLinks`: name, relation)
  /// with a name, as Father, Mother or (anything else) Guardian.
  static List<ReceiptParent> fromStudent(Map<String, dynamic>? student) => [
        for (final raw in (student?['parentLinks'] as List? ?? const []))
          if (raw is Map && (raw['name']?.toString().trim() ?? '').isNotEmpty)
            ReceiptParent(
              relations.contains(raw['relation']?.toString()) ? raw['relation'].toString() : 'Guardian',
              raw['name'].toString().trim(),
            ),
      ];

  /// The one preselected: the first father, else mother, else the first.
  static ReceiptParent? preferred(List<ReceiptParent> parents) {
    for (final r in relations) {
      for (final p in parents) {
        if (p.relation == r) return p;
      }
    }
    return null;
  }
}

/// What the administrator chose in the Regenerate PDF dialog. All of it is
/// for this document only: nothing is saved anywhere.
class ReceiptRegenerationOptions {
  const ReceiptRegenerationOptions({
    required this.className,
    this.parentRelation = 'Father',
    this.parentName = '',
    this.natureOfFee = '',
    this.servicePeriod = '',
    this.showGstin = false,
    this.gstin = '',
    this.amountIncludesGst = false,
  });

  /// The class printed (preselected: the student's current class). Never
  /// written to the student, admission, class or receipt.
  final String className;

  /// The parent or guardian printed ('' : the row is left out).
  final String parentRelation, parentName;

  /// Prefilled from the saved fee structure / assignment
  /// ([RegeneratedReceipt.natureOfFeeFrom], [RegeneratedReceipt.servicePeriodFrom]);
  /// '' : the row is left out.
  final String natureOfFee, servicePeriod;

  /// "Show GSTIN on receipt": prints the school's GSTIN in the header, and
  /// nothing else. Off unless explicitly ticked.
  final bool showGstin;

  /// The school's configured GSTIN (School Settings), '' if none.
  final String gstin;

  /// "Amount includes GST": the administrator states that the amount paid
  /// already includes GST, so "(GST Included)" is shown beside Amount Paid.
  /// Off unless explicitly ticked; independent of [showGstin] (either can be
  /// on without the other). It is a label only: no GST is calculated, the
  /// amount is not changed, and nothing is saved.
  final bool amountIncludesGst;
}

/// A regenerated fee receipt (Regenerate PDF only): a professional
/// institutional document built from the existing receipt, the school's
/// profile (School Settings) and the options chosen. The default receipt
/// (FeeService.generateAndUploadReceiptPdf, at collection and Generate
/// PDF) is separate and unchanged.
///
/// - Header: logo, school name, postal address, phone, email, website, and
///   the GSTIN only when opted in; whatever isn't configured is left out.
/// - FEE PAYMENT RECEIPT, the existing receipt number, and the original
///   payment date as the receipt date.
/// - Student details: parent / guardian, student, admission number, class.
/// - Payment details: nature of fee, service period, payment mode,
///   transaction reference, payment date (each only when known).
/// - Amount Paid and Amount in Words, both from the receipt's exact amount
///   in paise. No GST is ever added or derived.
/// - No Fee Name or Generated Date; the footer "System-generated fee
///   receipt. No signature required." and no signature line.
///
/// Building or saving it writes nothing: no payment, receipt, receipt
/// number, assignment, balance, student, parent, class, stored PDF,
/// School Settings or Finance record changes.
class RegeneratedReceipt {
  const RegeneratedReceipt._({
    required this.schoolName,
    required this.addressLines,
    required this.contactLines,
    required this.gstin,
    required this.receiptNo,
    required this.receiptDate,
    required this.studentRows,
    required this.paymentRows,
    required this.amountFigures,
    required this.amountLabel,
    required this.amountWords,
  });

  static const title = 'FEE PAYMENT RECEIPT';
  static const footer = 'System-generated fee receipt. No signature required.';
  static const gstIncludedLabel = '(GST Included)';
  static const defaultSchoolName = '2D Montessori';
  static const gstinMissingMessage =
      'No GSTIN is configured for this school. Add it in Settings → School Settings, or untick Show GSTIN on receipt.';
  static const classMissingMessage = 'Select the class to show on the receipt.';

  final String schoolName;
  final List<String> addressLines;

  /// "Phone: …", "Email: …", "Website: …" (only those configured).
  final List<String> contactLines;

  /// '' : not shown at all.
  final String gstin;
  final String receiptNo;

  /// The original payment date ('' when the receipt has none).
  final String receiptDate;

  /// (label, value), in order; only rows with a value.
  final List<(String, String)> studentRows, paymentRows;

  /// "Rs. 52,500.00".
  final String amountFigures;

  /// [amountFigures], with "(GST Included)" only when "Amount includes GST" is ticked.
  final String amountLabel;

  /// "Rupees Fifty-Two Thousand Five Hundred Only".
  final String amountWords;

  static final _date = DateFormat('dd MMM yyyy');

  /// Why [options] can't produce a document, or null.
  static String? validate(ReceiptRegenerationOptions options) {
    if (options.className.trim().isEmpty) return classMissingMessage;
    if (options.showGstin) {
      final g = SchoolSettingsValidation.normalizeGstin(options.gstin);
      if (g.isEmpty) return gstinMissingMessage;
      if (SchoolSettingsValidation.validateGstin(g) case final e?) {
        return 'The GSTIN saved in School Settings is not valid ($e) Correct it there, or untick Show GSTIN on receipt.';
      }
    }
    return null;
  }

  /// The Nature of Fee from saved data: the fee structure's description,
  /// else its components' names; '' when neither is saved (never made up).
  static String natureOfFeeFrom(FeeStructureModel? structure) {
    if (structure == null) return '';
    if (structure.description.trim().isNotEmpty) return structure.description.trim();
    return structure.components.map((c) => c.name.trim()).where((n) => n.isNotEmpty).join(', ');
  }

  /// The Service Period from saved data: the fee month ("November 2026"),
  /// else the assignment's academic year ("Academic Year 2026-2027"); ''
  /// when neither is saved (never inferred from dates).
  static String servicePeriodFrom(FeeReceiptModel receipt, StudentFeeAssignmentModel? assignment) {
    final month = FeeMonth.label(receipt.feeMonth.isNotEmpty ? receipt.feeMonth : assignment?.feeMonth ?? '');
    if (month.isNotEmpty) return month;
    final year = assignment?.academicYear.trim() ?? '';
    return year.isEmpty ? '' : 'Academic Year $year';
  }

  /// "Cash", "UPI", "Bank Transfer".
  static String paymentModeLabel(String mode) {
    final m = mode.trim();
    const upper = {'upi', 'neft', 'rtgs', 'imps', 'dd'};
    if (upper.contains(m.toLowerCase())) return m.toUpperCase();
    return m
        .replaceAll('_', ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  /// The document for [receipt] with [options] and [school] (null: none
  /// saved, the app's default name and nothing else). Throws
  /// [ArgumentError] when [validate] refuses (never a GST-labelled
  /// document without a valid GSTIN).
  static RegeneratedReceipt build(FeeReceiptModel receipt, ReceiptRegenerationOptions options, {SchoolSettingsModel? school}) {
    if (validate(options) case final e?) throw ArgumentError(e);
    String t(String? v) => v?.trim() ?? '';
    final paise = IndianAmount.paiseOf(receipt.amount);
    final figures = 'Rs. ${IndianAmount.figures(paise)}';
    final date = receipt.paymentDate == null ? '' : _date.format(receipt.paymentDate!);
    final reference = t(receipt.referenceNo);
    return RegeneratedReceipt._(
      schoolName: t(school?.name).isEmpty ? defaultSchoolName : t(school?.name),
      addressLines: school?.postalAddressLines ?? const [],
      contactLines: [
        if (t(school?.phone).isNotEmpty) 'Phone: ${t(school?.phone)}',
        if (t(school?.email).isNotEmpty) 'Email: ${t(school?.email)}',
        if (t(school?.website).isNotEmpty) 'Website: ${t(school?.website)}',
      ],
      gstin: options.showGstin ? SchoolSettingsValidation.normalizeGstin(options.gstin) : '',
      receiptNo: t(receipt.receiptNo),
      receiptDate: date,
      studentRows: [
        if (t(options.parentName).isNotEmpty) (ReceiptParent.labelOf(options.parentRelation), t(options.parentName)),
        if (t(receipt.studentName).isNotEmpty) ('Student Name', t(receipt.studentName)),
        if (t(receipt.admissionNo).isNotEmpty) ('Admission No', t(receipt.admissionNo)),
        ('Class', t(options.className)),
      ],
      paymentRows: [
        if (t(options.natureOfFee).isNotEmpty) ('Nature of Fee', t(options.natureOfFee)),
        if (t(options.servicePeriod).isNotEmpty) ('Service Period', t(options.servicePeriod)),
        if (t(receipt.paymentMode).isNotEmpty) ('Payment Mode', paymentModeLabel(receipt.paymentMode)),
        if (reference.isNotEmpty && reference != '-') ('Transaction Reference', reference),
        if (date.isNotEmpty) ('Payment Date', date),
      ],
      amountFigures: figures,
      amountLabel: '$figures${options.amountIncludesGst ? ' $gstIncludedLabel' : ''}',
      amountWords: IndianAmount.words(paise),
    );
  }

  /// The receipt number plus "-copy.pdf", safe as a file name (a separate
  /// copy, never the stored original's name).
  static String fileName(FeeReceiptModel receipt) {
    final base = receipt.receiptNo.trim().replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-');
    return '${base.isEmpty ? 'fee-receipt' : base}-copy.pdf';
  }

  static const _ink = PdfColor.fromInt(0xFF1F2933);
  static const _muted = PdfColor.fromInt(0xFF52606D);
  static const _accent = PdfColor.fromInt(0xFF1D4E89);
  static const _line = PdfColor.fromInt(0xFFCBD2D9);
  static const _band = PdfColor.fromInt(0xFFF0F4F8);

  /// The PDF (A4 portrait, print margins). [logo]: the school's logo image
  /// bytes; null: the app's bundled logo, or none.
  Future<Uint8List> toPdf({Uint8List? logo}) async {
    pw.ImageProvider? image;
    try {
      image = pw.MemoryImage(logo ?? (await rootBundle.load('assets/logo.png')).buffer.asUint8List());
    } catch (_) {}

    pw.Widget section(String heading, List<(String, String)> rows) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Text(heading, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _accent, letterSpacing: 1)),
            pw.SizedBox(height: 5),
            pw.Table(
              border: const pw.TableBorder(
                top: pw.BorderSide(color: _line, width: 0.7),
                bottom: pw.BorderSide(color: _line, width: 0.7),
                left: pw.BorderSide(color: _line, width: 0.7),
                right: pw.BorderSide(color: _line, width: 0.7),
                horizontalInside: pw.BorderSide(color: _line, width: 0.5),
              ),
              columnWidths: const {0: pw.FixedColumnWidth(150), 1: pw.FlexColumnWidth()},
              children: [
                for (final (label, value) in rows)
                  pw.TableRow(children: [
                    pw.Container(
                      color: _band,
                      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      child: pw.Text(label, style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: _muted)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      child: pw.Text(value, style: const pw.TextStyle(fontSize: 10, color: _ink)),
                    ),
                  ]),
              ],
            ),
          ],
        );

    final doc = pw.Document(title: '$title $receiptNo', author: schoolName);
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 42, vertical: 40),
        build: (context) => pw.Container(
          padding: const pw.EdgeInsets.all(22),
          decoration: pw.BoxDecoration(border: pw.Border.all(color: _line, width: 0.8)),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              // School identity.
              pw.Center(
                child: pw.Column(
                  children: [
                    if (image != null) ...[pw.Image(image, height: 58), pw.SizedBox(height: 8)],
                    pw.Text(schoolName, textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 19, fontWeight: pw.FontWeight.bold, color: _ink)),
                    pw.SizedBox(height: 4),
                    for (final l in addressLines) pw.Text(l, textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 9.5, color: _muted)),
                    for (final l in contactLines) pw.Text(l, textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 9.5, color: _muted)),
                    if (gstin.isNotEmpty) ...[
                      pw.SizedBox(height: 3),
                      pw.Text('GSTIN: $gstin', style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: _ink)),
                    ],
                  ],
                ),
              ),
              pw.SizedBox(height: 12),
              pw.Container(height: 2, color: _accent),
              pw.SizedBox(height: 2),
              pw.Container(height: 0.6, color: _accent),
              pw.SizedBox(height: 14),
              // Title, number and date.
              pw.Center(child: pw.Text(title, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, letterSpacing: 2, color: _accent))),
              pw.SizedBox(height: 10),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.RichText(text: pw.TextSpan(children: [
                    pw.TextSpan(text: 'Receipt No: ', style: const pw.TextStyle(fontSize: 10, color: _muted)),
                    pw.TextSpan(text: receiptNo, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _ink)),
                  ])),
                  if (receiptDate.isNotEmpty)
                    pw.RichText(text: pw.TextSpan(children: [
                      pw.TextSpan(text: 'Receipt Date: ', style: const pw.TextStyle(fontSize: 10, color: _muted)),
                      pw.TextSpan(text: receiptDate, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _ink)),
                    ])),
                ],
              ),
              pw.SizedBox(height: 16),
              section('STUDENT DETAILS', studentRows),
              if (paymentRows.isNotEmpty) ...[pw.SizedBox(height: 16), section('PAYMENT DETAILS', paymentRows)],
              pw.SizedBox(height: 18),
              // The amount, prominently, and in words.
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: pw.BoxDecoration(color: _band, border: pw.Border.all(color: _accent, width: 1)),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: [
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('Amount Paid', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: _muted)),
                        pw.Text(amountLabel, style: pw.TextStyle(fontSize: 17, fontWeight: pw.FontWeight.bold, color: _ink)),
                      ],
                    ),
                    pw.SizedBox(height: 8),
                    pw.Container(height: 0.5, color: _line),
                    pw.SizedBox(height: 7),
                    pw.RichText(text: pw.TextSpan(children: [
                      pw.TextSpan(text: 'Amount in Words: ', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _muted)),
                      pw.TextSpan(text: amountWords, style: pw.TextStyle(fontSize: 10, fontStyle: pw.FontStyle.italic, color: _ink)),
                    ])),
                  ],
                ),
              ),
              pw.Spacer(),
              pw.Container(height: 0.6, color: _line),
              pw.SizedBox(height: 6),
              pw.Center(child: pw.Text(footer, style: const pw.TextStyle(fontSize: 8.5, color: _muted))),
            ],
          ),
        ),
      ),
    );
    return doc.save();
  }
}
