import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/amount_in_words.dart';
import '../models/fee_month.dart';
import '../services/fee_receipt_regeneration.dart' show ReceiptParent;
import 'fee_bill_models.dart';

/// The PDF of one fee bill (A4 portrait), laid out like the regenerated fee
/// receipt (RegeneratedReceipt): the school header (with the GSTIN only
/// when it was chosen), a double accent rule, the title, Bill Reference and Issue
/// Date, STUDENT DETAILS and BILL DETAILS tables, the net amount with its
/// words, and the system-generated footer. Built only from the bill's
/// stored snapshot, so a download or reprint is always the same document.
/// Separate from, and never changing, the fee receipt PDFs.
///
/// The built-in Helvetica font has no ₹ glyph, so amounts print as "Rs.".
abstract final class FeeBillPdf {
  static const title = 'FEE BILL';
  static const footer = 'System-generated fee bill. No signature required.';
  static const previewBanner = 'PREVIEW - NOT ISSUED. This bill has no Bill Reference yet and is not valid.';
  static const pendingNumber = 'Assigned when issued';
  static const gstIncludedLabel = '(GST Included)';

  static final _date = DateFormat('dd MMM yyyy');

  static String money(int paise) => 'Rs. ${IndianAmount.figures(paise)}';

  /// (label, value), in order; only rows with a value.
  static List<(String, String)> studentRows(FeeIssuedBill b) => [
        if (b.parentName.trim().isNotEmpty) (ReceiptParent.labelOf(b.parentRelation), b.parentName.trim()),
        if (b.payment.studentName.trim().isNotEmpty) ('Student Name', b.payment.studentName.trim()),
        if (b.payment.admissionNo.trim().isNotEmpty) ('Admission No', b.payment.admissionNo.trim()),
        if (b.payment.className.trim().isNotEmpty) ('Class', b.payment.className.trim()),
      ];

  static List<(String, String)> billRows(FeeIssuedBill b) => [
        ('Billing Month', FeeMonth.label(b.line.billingMonth)),
        ('Fee Particulars', b.line.description),
        ('Gross Amount', money(b.line.grossPaise)),
        if (b.line.adjustmentPaise > 0) ...[
          ('Bill-only Adjustment (${b.line.adjustmentType.label})', '- ${money(b.line.adjustmentPaise)}'),
          ('Adjustment Reason', b.line.adjustmentReason),
        ],
        ('Receipt Reference', receiptReference(b)),
      ];

  /// The receipt number of the bill's payment; for a bill supported by
  /// several payments, every one of them, primary first.
  static String receiptReference(FeeIssuedBill b) {
    if (!b.isMultiPayment) return b.payment.receiptNo.isEmpty ? '-' : b.payment.receiptNo;
    return [for (final a in b.allocations) a.receiptNo.isEmpty ? '-' : a.receiptNo].join(', ');
  }

  /// The PAYMENT ALLOCATION table's rows (payment reference, payment date,
  /// allocated amount), for a bill supported by several payments only; a
  /// one-payment bill has none, so its PDF is unchanged.
  static List<(String, String, String)> allocationRows(FeeIssuedBill b) => !b.isMultiPayment
      ? const []
      : [
          for (final a in b.allocations)
            (a.receiptNo.isEmpty ? '-' : a.receiptNo, a.paymentDate == null ? '-' : _date.format(a.paymentDate!), money(a.allocatedPaise)),
        ];

  static const allocationHeading = 'PAYMENT ALLOCATION';
  static const allocationTotalLabel = 'Total allocated';

  /// The net amount as printed, with "(GST Included)" only when "Amount
  /// includes GST" was ticked.
  static String netLabel(FeeIssuedBill b) => '${money(b.line.netPaise)}${b.amountIncludesGst ? ' $gstIncludedLabel' : ''}';

  /// The Bill Reference plus ".pdf", safe as a file name.
  static String fileName(FeeIssuedBill b) {
    final base = b.billNo.trim().replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-');
    return '${base.isEmpty ? 'fee-bill-preview' : base}.pdf';
  }

  // The regenerated receipt's colours.
  static const _ink = PdfColor.fromInt(0xFF1F2933);
  static const _muted = PdfColor.fromInt(0xFF52606D);
  static const _accent = PdfColor.fromInt(0xFF1D4E89);
  static const _line = PdfColor.fromInt(0xFFCBD2D9);
  static const _band = PdfColor.fromInt(0xFFF0F4F8);
  static const _warn = PdfColor.fromInt(0xFF9B1C1C);

  /// [b] as a PDF. [preview]: not yet issued (no number). [reprintedAt]:
  /// marks a reprint. [logo]: the school's logo bytes, else the app's.
  static Future<Uint8List> build(FeeIssuedBill b, {bool preview = false, DateTime? reprintedAt, Uint8List? logo}) async {
    pw.ImageProvider? image;
    try {
      image = pw.MemoryImage(logo ?? (await rootBundle.load('assets/logo.png')).buffer.asUint8List());
    } catch (_) {}
    final school = b.school.name.trim().isEmpty ? '2D Montessori' : b.school.name.trim();
    final issueDate = b.documentDate;

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
              columnWidths: const {0: pw.FixedColumnWidth(170), 1: pw.FlexColumnWidth()},
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

    // The payments supporting a multi-payment bill, in the same style.
    pw.Widget allocationTable() {
      pw.Widget cell(String text, {bool head = false, bool bold = false, bool right = false}) => pw.Container(
            color: head ? _band : null,
            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            alignment: right ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
            child: pw.Text(text,
                style: head || bold
                    ? pw.TextStyle(fontSize: head ? 9.5 : 10, fontWeight: pw.FontWeight.bold, color: head ? _muted : _ink)
                    : const pw.TextStyle(fontSize: 10, color: _ink)),
          );
      return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
        pw.Text(allocationHeading, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _accent, letterSpacing: 1)),
        pw.SizedBox(height: 5),
        pw.Table(
          border: const pw.TableBorder(
            top: pw.BorderSide(color: _line, width: 0.7),
            bottom: pw.BorderSide(color: _line, width: 0.7),
            left: pw.BorderSide(color: _line, width: 0.7),
            right: pw.BorderSide(color: _line, width: 0.7),
            horizontalInside: pw.BorderSide(color: _line, width: 0.5),
          ),
          columnWidths: const {0: pw.FlexColumnWidth(), 1: pw.FixedColumnWidth(110), 2: pw.FixedColumnWidth(120)},
          children: [
            pw.TableRow(children: [cell('Payment Reference', head: true), cell('Payment Date', head: true), cell('Allocated Amount', head: true, right: true)]),
            for (final (ref, date, amount) in allocationRows(b)) pw.TableRow(children: [cell(ref), cell(date), cell(amount, right: true)]),
            pw.TableRow(children: [cell(allocationTotalLabel, bold: true), cell(''), cell(money(b.allocatedPaise), bold: true, right: true)]),
          ],
        ),
      ]);
    }

    pw.Widget banner(String text) => pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(border: pw.Border.all(color: _warn, width: 1.2)),
          child: pw.Text(text, textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _warn)),
        );

    pw.Widget labelled(String label, String value) => pw.RichText(
          text: pw.TextSpan(children: [
            pw.TextSpan(text: '$label: ', style: const pw.TextStyle(fontSize: 10, color: _muted)),
            pw.TextSpan(text: value, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _ink)),
          ]),
        );

    final doc = pw.Document(title: '$title ${b.billNo}', author: school);
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.symmetric(horizontal: 42, vertical: 40),
      build: (_) => pw.Container(
        padding: const pw.EdgeInsets.all(22),
        decoration: pw.BoxDecoration(border: pw.Border.all(color: _line, width: 0.8)),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            // School identity.
            pw.Center(
              child: pw.Column(children: [
                if (image != null) ...[pw.Image(image, height: 58), pw.SizedBox(height: 8)],
                pw.Text(school, textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 19, fontWeight: pw.FontWeight.bold, color: _ink)),
                pw.SizedBox(height: 4),
                for (final l in [...b.school.addressLines, ...b.school.contactLines])
                  pw.Text(l, textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 9.5, color: _muted)),
                if (b.school.gstin.isNotEmpty) ...[
                  pw.SizedBox(height: 3),
                  pw.Text('GSTIN: ${b.school.gstin}', style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: _ink)),
                ],
              ]),
            ),
            pw.SizedBox(height: 12),
            pw.Container(height: 2, color: _accent),
            pw.SizedBox(height: 2),
            pw.Container(height: 0.6, color: _accent),
            pw.SizedBox(height: 14),
            pw.Center(child: pw.Text(title, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, letterSpacing: 2, color: _accent))),
            if (preview) ...[pw.SizedBox(height: 8), banner(previewBanner)],
            if (b.isCancelled) ...[
              pw.SizedBox(height: 8),
              banner('CANCELLED${b.cancelledAt == null ? '' : ' on ${_date.format(b.cancelledAt!)}'}: ${b.cancellationReason}'
                  '${b.replacedByBillId.isEmpty ? '' : ' (replaced by a new bill)'}. This bill is not valid.'),
            ],
            pw.SizedBox(height: 10),
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
              labelled('Bill Reference', preview ? pendingNumber : b.billNo),
              if (issueDate != null) labelled('Issue Date', _date.format(issueDate)),
            ]),
            pw.SizedBox(height: 16),
            if (studentRows(b).isNotEmpty) ...[section('STUDENT DETAILS', studentRows(b)), pw.SizedBox(height: 16)],
            section('BILL DETAILS', billRows(b)),
            if (allocationRows(b).isNotEmpty) ...[pw.SizedBox(height: 16), allocationTable()],
            pw.SizedBox(height: 18),
            // The net amount, prominently, and in words.
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: pw.BoxDecoration(color: _band, border: pw.Border.all(color: _accent, width: 1)),
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
                pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                  pw.Text('Net Bill Amount', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: _muted)),
                  pw.Text(netLabel(b), style: pw.TextStyle(fontSize: 17, fontWeight: pw.FontWeight.bold, color: _ink)),
                ]),
                pw.SizedBox(height: 8),
                pw.Container(height: 0.5, color: _line),
                pw.SizedBox(height: 7),
                pw.RichText(text: pw.TextSpan(children: [
                  pw.TextSpan(text: 'Amount in Words: ', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _muted)),
                  pw.TextSpan(text: IndianAmount.words(b.line.netPaise), style: pw.TextStyle(fontSize: 10, fontStyle: pw.FontStyle.italic, color: _ink)),
                ])),
              ]),
            ),
            pw.Spacer(),
            if (reprintedAt != null)
              pw.Text('Reprint generated on ${_date.format(reprintedAt)}. Bill number and contents are unchanged.', style: const pw.TextStyle(fontSize: 8, color: _muted)),
            pw.Container(height: 0.6, color: _line),
            pw.SizedBox(height: 6),
            pw.Center(child: pw.Text(footer, style: const pw.TextStyle(fontSize: 8.5, color: _muted))),
          ],
        ),
      ),
    ));
    return doc.save();
  }
}
