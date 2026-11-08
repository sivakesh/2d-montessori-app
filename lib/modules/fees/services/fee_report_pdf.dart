import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../admin/students/models/admission_date.dart';
import '../models/fee_report.dart';

/// The heading every Fees report PDF starts with.
class FeeReportPdfHeader {
  const FeeReportPdfHeader({required this.schoolName, required this.title, required this.filters, required this.generatedAt, this.logo});

  final String schoolName, title;

  /// "Academic Year: 2026-2027", "Class: All Classes", …
  final List<String> filters;
  final DateTime generatedAt;
  final pw.ImageProvider? logo;

  /// The school logo bundled with the app (the receipt PDF's), or null.
  static Future<pw.ImageProvider?> bundledLogo() async {
    try {
      final data = await rootBundle.load('assets/logo.png');
      return pw.MemoryImage(data.buffer.asUint8List());
    } catch (_) {
      return null;
    }
  }
}

/// PDFs for Fees → Reports, built from the same [FeeSchoolReport] /
/// [FeeStudentStatement] the screen shows, so the PDF holds exactly the
/// filtered result: every student and every payment (the screen's paging
/// never limits it). Landscape A4; every table repeats its headings on
/// each page; the footer numbers the pages. The PDF's built-in font has no
/// rupee sign, so amounts read "Rs. 1,500" as on fee receipts.
abstract final class FeeReportPdf {
  /// Far above any school's report, so nothing is ever cut off (the
  /// library's own default is 20 pages).
  static const maxPages = 100000;

  static String _m(double v) => FeeReport.money(v, symbol: 'Rs. ');

  /// The built-in PDF font covers Latin-1 only: dashes, curly quotes and
  /// ellipses are written as their plain equivalents so nothing is lost.
  static String _s(String v) => v
      .replaceAll(RegExp('[\u2013\u2014\u2212]'), '-')
      .replaceAll(RegExp('[\u2018\u2019]'), "'")
      .replaceAll(RegExp('[\u201C\u201D]'), '"')
      .replaceAll('\u2026', '...')
      .replaceAll('\u2192', '->')
      .replaceAll('\u20B9', 'Rs. ');

  static pw.Widget _text(String v, {pw.TextStyle? style}) => pw.Text(_s(v), style: style);

  static Future<Uint8List> school(FeeSchoolReport r, FeeReportPdfHeader h, {bool compress = true}) {
    final doc = pw.Document(compress: compress, title: h.title, author: h.schoolName);
    doc.addPage(_page(h, [
      ..._heading(h),
      if (r.students.isEmpty)
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 24),
          child: _text('No students match the selected filters. Nothing to report.', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
        )
      else ...[
        _sectionTitle('School-wide summary'),
        _keyValues([
          ('Total students', '${r.totalStudents}'),
          ('Students with fee assignments', '${r.withAssignments}'),
          ('Fully paid', '${r.count(FeePaymentStatus.paid)}'),
          ('Partially paid', '${r.count(FeePaymentStatus.partial)}'),
          ('No payment', '${r.count(FeePaymentStatus.unpaid)}'),
          ('No assignments', '${r.count(FeePaymentStatus.none)}'),
          ('Total assigned', _m(r.assigned)),
          ('Total discounts', _m(r.discounts)),
          ('Student discounts', _m(r.studentDiscounts)),
          ('Manual discounts', _m(r.manualDiscounts)),
          ('Total payable', _m(r.payable)),
          ('Total collected', _m(r.collected)),
          ('Total outstanding', _m(r.outstanding)),
          ('Collection %', FeeReport.percentLabel(r.collectionPercent)),
        ]),
        _sectionTitle('Month-wise summary'),
        _summaryTable('Fee Month', r.monthlySummary, empty: 'No monthly fees in the selected period.'),
        _sectionTitle('${FeeReport.nonMonthlyTitle} summary'),
        _summaryTable('Fee Structure', r.nonMonthlySummary, empty: 'No term or one-time fees in the selected period.'),
        if (r.noMonthSummary case final row?) ...[
          _sectionTitle('${FeeReport.noMonthTitle} summary'),
          _summaryTable('Fees', [row], empty: ''),
        ],
        _sectionTitle('Students (${r.totalStudents})'),
        for (final s in r.students) ..._student(s),
      ],
    ]));
    return doc.save();
  }

  static Future<Uint8List> statement(FeeStudentStatement s, FeeReportPdfHeader h, {bool compress = true}) {
    final doc = pw.Document(compress: compress, title: h.title, author: h.schoolName);
    doc.addPage(_page(h, [
      ..._heading(h),
      _keyValues([
        ('Total assigned', _m(s.assigned)),
        ('Total discounts', _m(s.discounts)),
        ('Student discounts', _m(s.studentDiscounts)),
        ('Manual discounts', _m(s.manualDiscounts)),
        ('Net payable', _m(s.payable)),
        ('Total collected', _m(s.collected)),
        ('Total outstanding', _m(s.outstanding)),
        ('Collection %', FeeReport.percentLabel(s.collectionPercent)),
      ]),
      ..._student(s),
    ]));
    return doc.save();
  }

  static pw.MultiPage _page(FeeReportPdfHeader h, List<pw.Widget> content) => pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.fromLTRB(24, 20, 24, 20),
        maxPages: maxPages,
        theme: pw.ThemeData.withFont().copyWith(defaultTextStyle: const pw.TextStyle(fontSize: 8.5)),
        header: (context) => context.pageNumber == 1
            ? pw.SizedBox()
            : pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 6),
                child: _text('${h.schoolName} · ${h.title}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
              ),
        footer: (context) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 6),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              _text('Generated ${DateFormat('d MMM yyyy, h:mm a').format(h.generatedAt)}', style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700)),
              _text('Page ${context.pageNumber} of ${context.pagesCount}', style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700)),
            ],
          ),
        ),
        build: (_) => content,
      );

  static List<pw.Widget> _heading(FeeReportPdfHeader h) => [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            if (h.logo case final logo?) pw.Padding(padding: const pw.EdgeInsets.only(right: 10), child: pw.Image(logo, height: 36)),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _text(h.schoolName, style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
                  _text(h.title, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 4),
        _text(h.filters.join('   ·   '), style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey800)),
        _text('Generated ${DateFormat('d MMM yyyy, h:mm a').format(h.generatedAt)}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey800)),
        pw.Divider(color: PdfColors.grey500, thickness: 0.6),
      ];

  static pw.Widget _sectionTitle(String t) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 10, bottom: 4),
        child: _text(t, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
      );

  static pw.Widget _keyValues(List<(String, String)> items) => pw.Wrap(
        spacing: 18,
        runSpacing: 4,
        children: [
          for (final (k, v) in items)
            pw.RichText(
              text: pw.TextSpan(children: [
                pw.TextSpan(text: _s('$k: '), style: const pw.TextStyle(color: PdfColors.grey800)),
                pw.TextSpan(text: _s(v), style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              ]),
            ),
        ],
      );

  static pw.Widget _table(List<List<String>> rows, {int headerCount = 1, Map<int, pw.TableColumnWidth>? widths, Set<int> numeric = const {}}) =>
      pw.TableHelper.fromTextArray(
        data: [for (final r in rows) [for (final c in r) _s(c)]],
        headerCount: headerCount,
        border: pw.TableBorder.all(color: PdfColors.grey500, width: 0.5),
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
        cellStyle: const pw.TextStyle(fontSize: 8),
        cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        cellAlignment: pw.Alignment.centerLeft,
        cellAlignments: {for (final i in numeric) i: pw.Alignment.centerRight},
        headerAlignments: {for (final i in numeric) i: pw.Alignment.centerRight},
        columnWidths: widths,
      );

  static pw.Widget _summaryTable(String first, List<FeeReportSummaryRow> rows, {required String empty}) => rows.isEmpty
      ? _text(empty)
      : _table([
          [first, 'Students Assigned', 'Gross Assigned', 'Discounts', 'Total Payable', 'Total Collected', 'Outstanding', 'Collection %'],
          for (final r in rows)
            [r.label, '${r.students.length}', _m(r.assigned), _m(r.discounts), _m(r.payable), _m(r.collected), _m(r.outstanding), FeeReport.percentLabel(r.percent)],
        ], numeric: {1, 2, 3, 4, 5, 6, 7});

  static String _amount(FeeStatementRow r) => r.voided ? '${_m(r.payment!.receipt.amount)} (cancelled)' : _m(r.amount);

  /// One student: details, then each section's table (headings, with the
  /// student's name, repeat on every page a table continues onto).
  static List<pw.Widget> _student(FeeStudentStatement s) {
    final st = s.student;
    final name = '${st.name.isEmpty ? st.id : st.name}${st.admissionNo.isEmpty ? '' : ' (${st.admissionNo})'}';
    List<String> banner(String section, int columns) => [name, section, for (var i = 2; i < columns; i++) ''];
    const monthlyHead = ['Fee Month', 'Fee', 'Payment Date', 'Receipt No', 'Method', 'Status', 'Amount Paid', 'Total Paid', 'Outstanding', 'Discount', 'Total Payable'];
    const otherHead = ['Fee Structure', 'Assigned', 'Due Date', 'Payment Date', 'Receipt No', 'Status', 'Amount Paid', 'Total Paid', 'Outstanding', 'Discount', 'Total Payable'];
    // Receipt No (column 4) wide enough for a full receipt number on one line.
    final widths = {
      0: const pw.FlexColumnWidth(1.4), 1: const pw.FlexColumnWidth(1.4), 4: const pw.FlexColumnWidth(1.7),
      for (final i in [2, 3, 5, 6, 7, 8, 9, 10]) i: const pw.FlexColumnWidth(1),
    };
    List<String> otherRow(FeeStatementRow r) {
      final a = r.line.assignment;
      final rc = r.payment?.receipt;
      return [
        a.feeStructureName, FeeReport.date(a.assignedAt), FeeReport.date(a.dueDate), FeeReport.date(rc?.paymentDate), rc?.receiptNo ?? '—',
        r.status, _amount(r), _m(r.line.paid), _m(r.line.outstanding), _m(r.line.discount), _m(r.line.payable),
      ];
    }

    return [
      pw.Container(
        margin: const pw.EdgeInsets.only(top: 12, bottom: 4),
        padding: const pw.EdgeInsets.all(6),
        decoration: const pw.BoxDecoration(color: PdfColors.grey100, border: pw.Border(left: pw.BorderSide(color: PdfColors.grey700, width: 2))),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _text(name, style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold)),
            _text([
              'Admission date: ${AdmissionDate.label(st.admissionDate)}',
              'Class: ${s.className}',
              'Status: ${s.status.label}',
              if (!st.isActive) 'Inactive',
              if (s.recordMissing) 'Student record not found',
            ].join('   ·   ')),
            if (s.hasAssignments)
              _text('Assigned ${_m(s.assigned)}   ·   Discounts ${_m(s.discounts)}'
                  '${(s.studentDiscounts * 100).round() > 0 ? ' (student ${_m(s.studentDiscounts)}, manual ${_m(s.manualDiscounts)})' : ''}   ·   '
                  'Payable ${_m(s.payable)}   ·   Collected ${_m(s.collected)}   ·   Outstanding ${_m(s.outstanding)}   ·   '
                  '${FeeReport.percentLabel(s.collectionPercent)} collected'),
          ],
        ),
      ),
      if (!s.hasAssignments) _text(FeeReport.noAssignments, style: pw.TextStyle(fontStyle: pw.FontStyle.italic)),
      if (s.monthly.isNotEmpty)
        _table([
          banner('Monthly fees', 11),
          monthlyHead,
          for (final l in s.monthly)
            for (final r in l.rows)
              [
                l.feeMonthLabel, l.assignment.feeStructureName, FeeReport.date(r.payment?.receipt.paymentDate), r.payment?.receipt.receiptNo ?? '—',
                r.payment?.receipt.paymentMode ?? '—', r.status, _amount(r), _m(l.paid), _m(l.outstanding), _m(l.discount), _m(l.payable),
              ],
        ], headerCount: 2, widths: widths, numeric: {6, 7, 8, 9, 10}),
      if (s.nonMonthly.isNotEmpty) ...[
        pw.SizedBox(height: 4),
        _table([banner(FeeReport.nonMonthlyTitle, 11), otherHead, for (final l in s.nonMonthly) for (final r in l.rows) otherRow(r)],
            headerCount: 2, widths: widths, numeric: {6, 7, 8, 9, 10}),
      ],
      if (s.noMonth.isNotEmpty) ...[
        pw.SizedBox(height: 4),
        _table([banner(FeeReport.noMonthTitle, 11), otherHead, for (final l in s.noMonth) for (final r in l.rows) otherRow(r)],
            headerCount: 2, widths: widths, numeric: {6, 7, 8, 9, 10}),
      ],
      if (s.unlinked.isNotEmpty) ...[
        pw.SizedBox(height: 4),
        _table([
          [name, FeeReport.unlinkedTitle, '', '', '', ''],
          ['Payment Date', 'Receipt No', 'Method', 'Fee', 'Status', 'Amount'],
          for (final p in s.unlinked)
            [
              FeeReport.date(p.receipt.paymentDate), p.receipt.receiptNo, p.receipt.paymentMode, p.receipt.feeStructureName,
              p.voided ? 'Cancelled (voided)' : 'Completed', _m(p.receipt.amount),
            ],
        ], headerCount: 2, numeric: {5}),
      ],
      for (final w in s.warnings) _text('Reconciliation warning: $w', style: const pw.TextStyle(color: PdfColors.red800)),
    ];
  }
}
