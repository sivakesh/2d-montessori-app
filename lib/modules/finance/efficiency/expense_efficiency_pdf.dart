import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../fees/services/fee_report_pdf.dart' show FeeReportPdfHeader;
import 'expense_efficiency_analysis.dart';
import 'expense_efficiency_models.dart';

/// The Expense Efficiency report PDF, built from the same
/// [ExpenseEfficiencyReport] the screen shows (so every total matches), with
/// the Fees report PDFs' conventions: A4 landscape, the built-in font
/// (amounts as "Rs. 1,500"), table headings repeated on every page,
/// "Page X of Y". Every expense matching the filters is listed.
abstract final class ExpenseEfficiencyPdf {
  static const title = 'Expense Efficiency Report';
  static const adjustedLabel = 'Adjusted Operating Surplus - hypothetical, excluding identified avoidable spending';

  static String _m(double v) => efficiencyMoney(v, symbol: 'Rs. ');
  static String _s(String v) => v
      .replaceAll(RegExp('[–—−]'), '-')
      .replaceAll(RegExp('[‘’]'), "'")
      .replaceAll(RegExp('[“”]'), '"')
      .replaceAll('…', '...')
      .replaceAll('₹', 'Rs. ');
  static pw.Widget _text(String v, {pw.TextStyle? style}) => pw.Text(_s(v), style: style);
  static String _pct(double v) => '${v.toStringAsFixed(1)}%';

  static Future<Uint8List> build(ExpenseEfficiencyReport r, FeeReportPdfHeader h, {bool compress = true}) {
    final doc = pw.Document(compress: compress, title: h.title, author: h.schoolName);
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.fromLTRB(24, 20, 24, 20),
      maxPages: 100000,
      theme: pw.ThemeData.withFont().copyWith(defaultTextStyle: const pw.TextStyle(fontSize: 8.5)),
      footer: (c) => pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        _text('Generated ${DateFormat('d MMM yyyy, h:mm a').format(h.generatedAt)}', style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700)),
        _text('Page ${c.pageNumber} of ${c.pagesCount}', style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700)),
      ]),
      build: (_) => [
        pw.Row(children: [
          if (h.logo case final logo?) pw.Padding(padding: const pw.EdgeInsets.only(right: 10), child: pw.Image(logo, width: 36, height: 36)),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            _text(h.schoolName, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            _text(h.title, style: const pw.TextStyle(fontSize: 11)),
          ]),
        ]),
        pw.SizedBox(height: 4),
        _text('Period: ${r.period.label}'),
        for (final f in h.filters) _text(f),
        _text('Analytical report: Adjusted and Target figures are hypothetical. Actual figures are the Finance Ledger\'s.',
            style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700)),
        _section('Actual, Adjusted and Target'),
        _kv([
          ('Actual income', _m(r.income)),
          ('Actual expenses', _m(r.expenses)),
          ('Actual Operating Surplus', _m(r.actualSurplus)),
          ('Identified Potential Savings', _m(r.potentialSavings)),
          (adjustedLabel, _m(r.adjustedSurplus)),
          ('Target expenses', _m(r.targetExpenses)),
          ('Target Operating Surplus', _m(r.targetSurplus)),
          ('Adjusted minus Actual', _m(r.adjustedSurplus - r.actualSurplus)),
          ('Target minus Actual', _m(r.targetSurplus - r.actualSurplus)),
        ]),
        _section('Assessment'),
        _kv([
          for (final c in ExpenseAssessmentCategory.values) ('${c.label} (${r.count(c)})', _m(r.total(c))),
          ('Expenses in view', _m(r.filteredExpenses)),
          ('Assessed', '${r.assessedCount} (${_m(r.assessedAmount)})'),
          ('Not assessed', '${r.unassessedCount} (${_m(r.unassessedAmount)})'),
          ('Coverage', _pct(r.coveragePercent)),
        ]),
        _section('Category-wise actual vs target'),
        _table([
          ['Category', 'Actual', 'Target', 'Difference', 'Variance', 'Avoidable', 'Target scenario'],
          for (final c in r.categories)
            [
              c.name, _m(c.actual), !c.hasTarget ? 'Target not set' : c.fullyTargeted ? _m(c.target) : '${_m(c.target)} (${c.targetedMonths} of ${c.targetedMonths + c.untargetedMonths} months)', c.difference == null ? '-' : _m(c.difference!),
              c.variancePercent == null ? '-' : _pct(c.variancePercent!), _m(rupeesOf(c.avoidableP)), _m(c.scenario),
            ],
        ], numeric: {1, 3, 4, 5, 6}),
        if (r.untargetedCategories.isNotEmpty)
          _text('Without a target for every month (actual spending used in the Target scenario): ${r.untargetedCategories.map((c) => c.name).join(', ')}.',
              style: const pw.TextStyle(fontSize: 7.5)),
        _section('Monthly trend'),
        _table([
          ['Month', 'Income', 'Expenses', 'Surplus', 'Identified avoidable', 'Target scenario expenses'],
          for (final m in r.months)
            [m.label, _m(rupeesOf(m.incomeP)), _m(rupeesOf(m.expensesP)), _m(rupeesOf(m.incomeP - m.expensesP)), _m(rupeesOf(m.avoidableP)), _m(rupeesOf(m.targetScenarioP))],
        ], numeric: {1, 2, 3, 4, 5}),
        _section('Expenses (${r.items.length})'),
        if (r.items.isEmpty)
          _text('No expenses match the selected period and filters.')
        else
          _table([
            ['Date', 'Description', 'Category', 'Amount', 'Assessment', 'Avoidable', 'Reason', 'Management note'],
            for (final i in r.items)
              [
                i.entry.transactionDate == null ? '-' : DateFormat('d MMM yyyy').format(i.entry.transactionDate!),
                i.entry.title.isEmpty ? i.entry.description : i.entry.title,
                i.categoryName,
                _m(i.entry.amount),
                i.cancelled ? 'Cancelled (not counted)' : '${i.category.label}${i.needsReview ? ' (needs review)' : ''}',
                i.category.hasAvoidable ? _m(i.countedAvoidable) : '-',
                i.assessment?.reason ?? '',
                i.assessment?.managementNote ?? '',
              ],
          ], numeric: {3, 5}, widths: {1: const pw.FlexColumnWidth(2), 6: const pw.FlexColumnWidth(1.6), 7: const pw.FlexColumnWidth(1.8)}),
      ],
    ));
    return doc.save();
  }

  static pw.Widget _section(String t) =>
      pw.Padding(padding: const pw.EdgeInsets.only(top: 10, bottom: 4), child: _text(t, style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold)));

  static pw.Widget _kv(List<(String, String)> items) => pw.Wrap(spacing: 18, runSpacing: 4, children: [
        for (final (k, v) in items)
          pw.RichText(text: pw.TextSpan(children: [
            pw.TextSpan(text: _s('$k: '), style: const pw.TextStyle(color: PdfColors.grey800)),
            pw.TextSpan(text: _s(v), style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          ])),
      ]);

  static pw.Widget _table(List<List<String>> rows, {Set<int> numeric = const {}, Map<int, pw.TableColumnWidth>? widths}) => pw.TableHelper.fromTextArray(
        data: [for (final r in rows) [for (final c in r) _s(c)]],
        headerCount: 1,
        border: pw.TableBorder.all(color: PdfColors.grey500, width: 0.5),
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
        cellStyle: const pw.TextStyle(fontSize: 8),
        cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        cellAlignments: {for (final i in numeric) i: pw.Alignment.centerRight},
        headerAlignments: {for (final i in numeric) i: pw.Alignment.centerRight},
        columnWidths: widths,
      );
}
