import '../../admin/settings/models/academic_year_months.dart';
import 'fee_receipt_model.dart';

/// Fees Dashboard → Monthly Fee Collection: the money actually received in
/// each month of the current academic year (through today), grouped by
/// each receipt's own `paymentDate`, never by its `feeMonth` (what the fee
/// was for), an assignment's dates, or a due date. Every payment method is
/// included.
///
/// [receipts] are the Fees screen's receipts (FeeService.getReceipts),
/// which already leave out voided ones (`isDeleted`), exactly as the
/// Receipts list does. A receipt without a payment date can't be placed in
/// a month and is only counted in [undated]. Read-only.
class FeeMonthlyCollections {
  FeeMonthlyCollections._(this.window, this._byMonth, this.undated);

  factory FeeMonthlyCollections.of(List<FeeReceiptModel> receipts, AcademicYearMonths window) {
    final byMonth = {for (final m in window.months) m: <FeeReceiptModel>[]};
    var undated = 0;
    for (final r in receipts) {
      final d = r.paymentDate;
      if (d == null) {
        undated++;
        continue;
      }
      if (!window.contains(d)) continue;
      byMonth[AcademicYearMonths.key(d)]?.add(r);
    }
    for (final list in byMonth.values) {
      list.sort((a, b) {
        final c = b.paymentDate!.compareTo(a.paymentDate!);
        return c != 0 ? c : a.receiptNo.compareTo(b.receiptNo);
      });
    }
    return FeeMonthlyCollections._(window, byMonth, undated);
  }

  final AcademicYearMonths window;
  final Map<String, List<FeeReceiptModel>> _byMonth;

  /// Receipts with no payment date (not in any month).
  final int undated;

  List<String> get months => window.months;

  /// The payments received in [month], newest first: the drill-down list.
  List<FeeReceiptModel> receiptsIn(String month) => List.unmodifiable(_byMonth[month] ?? const []);

  /// Summed in paise.
  double totalIn(String month) => (_byMonth[month] ?? const []).fold<int>(0, (s, r) => s + (r.amount * 100).round()) / 100;
  int countIn(String month) => (_byMonth[month] ?? const []).length;
  double get total => months.fold<int>(0, (s, m) => s + (totalIn(m) * 100).round()) / 100;
  bool get isEmpty => months.every((m) => countIn(m) == 0);
}
