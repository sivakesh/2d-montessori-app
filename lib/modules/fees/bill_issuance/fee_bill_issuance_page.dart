import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../admin/ui/admin_layout.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/fee_month.dart';
import '../services/fee_receipt_regeneration.dart' show ReceiptPdfSaver, shareReceiptPdf;
import '../ui/dialogs/fee_receipt_regenerate_dialog.dart' show SchoolLogoLoader, SchoolProfileLoader, loadSchoolLogo, loadSchoolProfile;
import 'fee_bill_details_dialog.dart';
import 'fee_bill_issue_dialog.dart';
import 'fee_bill_models.dart';
import 'fee_bill_service.dart';

/// Fees → Fee Bill Issuance: supplementary month-wise bill documents issued
/// against payments already collected in Fees (docs/fee_bill_issuance.md).
/// Lists the issued bills with their own totals, kept apart from, and never
/// counted in, fee collections, balances or Finance.
///
/// Keys: `fee-bills-` + `back`, `issue`, `search`, `status-filter`,
/// `total-issued`, `total-gross`, `total-adjustment`, `total-net`,
/// `total-cancelled`, `row-<billNo>`, `empty`, `more`.
class FeeBillIssuancePage extends ConsumerStatefulWidget {
  const FeeBillIssuancePage({
    super.key,
    this.service,
    this.loadSchool = loadSchoolProfile,
    this.loadLogo = loadSchoolLogo,
    this.savePdf = shareReceiptPdf,
    this.clock = DateTime.now,
  });

  final FeeBillService? service;
  final SchoolProfileLoader loadSchool;
  final SchoolLogoLoader loadLogo;
  final ReceiptPdfSaver savePdf;
  final DateTime Function() clock;

  static const title = 'Fee Bill Issuance';
  static const explanation = 'Supplementary bill documents issued against payments already collected in Fees. '
      'Issuing, adjusting or cancelling a bill never creates or changes a payment, receipt, fee balance or Finance record.';

  @override
  ConsumerState<FeeBillIssuancePage> createState() => _FeeBillIssuancePageState();
}

enum _StatusFilter { all, issued, cancelled }

class _FeeBillIssuancePageState extends ConsumerState<FeeBillIssuancePage> {
  late final FeeBillService _service = widget.service ?? FeeBillService();
  late Stream<List<FeeIssuedBill>> _bills = _service.watchBills();
  final _search = TextEditingController();
  _StatusFilter _status = _StatusFilter.all;
  int _shown = 25;

  static final _date = DateFormat('d MMM yyyy');

  String get _role => ref.watch(currentUserProvider)?.role ?? '';
  bool get _isAdmin => _role.toLowerCase() == 'admin';

  @override
  void initState() {
    super.initState();
    // Parents' copies of bills issued before they were kept automatically
    // (or whose refresh failed) are written now; nothing changes when they
    // are already current. Administrators only; never blocks the page.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final result = await _service.backfillDerivedCopies(requesterRole: ref.read(currentUserProvider)?.role ?? '');
      if (mounted && result != null) setState(() => _parentCopies = result);
    });
  }

  /// What updating the parents' bill copies did on opening (administrators;
  /// null until it has run).
  FeeBillsBackfillResult? _parentCopies;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _openIssue() async {
    final issued = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => FeeBillIssueDialog(
        service: _service,
        role: _role,
        loadSchool: widget.loadSchool,
        loadLogo: widget.loadLogo,
        savePdf: widget.savePdf,
        clock: widget.clock,
      ),
    );
    if (issued == true && mounted) setState(() => _bills = _service.watchBills());
  }

  Future<void> _openBill(FeeIssuedBill b) async {
    await showDialog<void>(
      context: context,
      builder: (_) => FeeBillDetailsDialog(bill: b, service: _service, role: _role, loadLogo: widget.loadLogo, savePdf: widget.savePdf, clock: widget.clock),
    );
    if (mounted) setState(() => _bills = _service.watchBills());
  }

  bool _matches(FeeIssuedBill b) {
    if (_status == _StatusFilter.issued && b.isCancelled) return false;
    if (_status == _StatusFilter.cancelled && !b.isCancelled) return false;
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return true;
    return [b.billNo, b.payment.studentName, b.payment.admissionNo, b.payment.receiptNo, FeeMonth.label(b.line.billingMonth), b.line.description]
        .any((f) => f.toLowerCase().contains(q));
  }

  Widget _card(String label, String value, Key key) => SizedBox(
        width: 190,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
              const SizedBox(height: 4),
              Text(value, key: key, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      );

  Widget _row(FeeIssuedBill b) => Card(
        key: Key('fee-bills-row-${b.billNo}'),
        margin: const EdgeInsets.symmetric(vertical: 4),
        child: ListTile(
          onTap: () => _openBill(b),
          leading: Icon(Icons.request_quote_outlined, color: b.isCancelled ? Colors.grey : null),
          title: Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text('Bill Reference ${b.billNo}', style: const TextStyle(fontWeight: FontWeight.w700)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: b.isCancelled ? Colors.grey.shade200 : Colors.green.shade50, borderRadius: BorderRadius.circular(20)),
              child: Text(b.status.label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: b.isCancelled ? Colors.grey.shade800 : Colors.green.shade800)),
            ),
          ]),
          subtitle: Text(
            '${b.payment.studentName}${b.payment.admissionNo.isEmpty ? '' : ' • ${b.payment.admissionNo}'} • ${FeeMonth.label(b.line.billingMonth)}\n'
            'Receipt Reference ${b.payment.receiptNo} • Gross ${billMoney(b.line.grossPaise)} • Adjustment ${billMoney(b.line.adjustmentPaise)} • '
            'Net ${billMoney(b.line.netPaise)} • Issued ${b.issuedAt == null ? '-' : _date.format(b.issuedAt!)}',
          ),
          isThreeLine: true,
          trailing: const Icon(Icons.chevron_right),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return AdminLayout(
      selectedIndex: 6, // Fees
      title: FeeBillIssuancePage.title,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextButton.icon(
            key: const Key('fee-bills-back'),
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back),
            label: const Text('Back to Fees'),
          ),
          Text('Fees › ${FeeBillIssuancePage.title}', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text(FeeBillIssuancePage.title, style: Theme.of(context).textTheme.headlineSmall),
            if (_isAdmin)
              FilledButton.icon(key: const Key('fee-bills-issue'), onPressed: _openIssue, icon: const Icon(Icons.add), label: const Text('Issue Bills')),
          ]),
          const SizedBox(height: 6),
          const Text(FeeBillIssuancePage.explanation, style: TextStyle(fontSize: 13)),
          if (!_isAdmin) const Padding(padding: EdgeInsets.only(top: 4), child: Text('Only an administrator can issue or cancel bills.', style: TextStyle(fontSize: 12))),
          if (_parentCopies case final r?)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                r.failed > 0 || r.error.isNotEmpty
                    ? 'Parent copies of bills could not all be updated (${r.failed} failed): ${r.error}. See Settings → Parent access.'
                    : 'Parent copies of bills are up to date (${r.found} bill${r.found == 1 ? '' : 's'}${r.written > 0 ? ', ${r.written} copied now' : ''}).',
                key: const Key('fee-bills-parent-copies'),
                style: TextStyle(fontSize: 12, color: r.failed > 0 || r.error.isNotEmpty ? Colors.orange.shade900 : Colors.green.shade800),
              ),
            ),
          const SizedBox(height: 12),
          StreamBuilder<List<FeeIssuedBill>>(
            stream: _bills,
            builder: (context, snap) {
              if (snap.hasError) return Text('The bills could not be loaded: ${snap.error}');
              if (!snap.hasData) return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
              final all = snap.data!;
              final t = FeeBillTotals.of(all);
              final shown = all.where(_matches).toList();
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('Bill issuance report (bill documents only, not fee collections)', style: Theme.of(context).textTheme.titleSmall),
                Wrap(children: [
                  _card('Active bills', '${t.issued}', const Key('fee-bills-total-issued')),
                  _card('Gross billed', billMoney(t.grossPaise), const Key('fee-bills-total-gross')),
                  _card('Bill-only adjustments', billMoney(t.adjustmentPaise), const Key('fee-bills-total-adjustment')),
                  _card('Net billed', billMoney(t.netPaise), const Key('fee-bills-total-net')),
                  _card('Cancelled bills', '${t.cancelled}', const Key('fee-bills-total-cancelled')),
                ]),
                const Text(
                  'Totals cover active bills only. Actual payments are in Fees → Collections and Receipts; these figures are never added to them or to Finance.',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 12),
                Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  SizedBox(
                    width: 360,
                    child: TextField(
                      key: const Key('fee-bills-search'),
                      controller: _search,
                      decoration: const InputDecoration(labelText: 'Search Bill Reference, student, admission no., receipt or month', prefixIcon: Icon(Icons.search), isDense: true),
                      onChanged: (_) => setState(() => _shown = 25),
                    ),
                  ),
                  SegmentedButton<_StatusFilter>(
                    key: const Key('fee-bills-status-filter'),
                    segments: const [
                      ButtonSegment(value: _StatusFilter.all, label: Text('All')),
                      ButtonSegment(value: _StatusFilter.issued, label: Text('Issued')),
                      ButtonSegment(value: _StatusFilter.cancelled, label: Text('Cancelled')),
                    ],
                    selected: {_status},
                    onSelectionChanged: (s) => setState(() {
                      _status = s.first;
                      _shown = 25;
                    }),
                  ),
                ]),
                const SizedBox(height: 8),
                if (shown.isEmpty) Text(all.isEmpty ? 'No bills have been issued yet.' : 'No bills match.', key: const Key('fee-bills-empty')),
                for (final b in shown.take(_shown)) _row(b),
                if (shown.length > _shown)
                  TextButton(key: const Key('fee-bills-more'), onPressed: () => setState(() => _shown += 25), child: Text('Show more (${_shown.clamp(0, shown.length)} of ${shown.length} shown)')),
              ]);
            },
          ),
        ]),
      ),
    );
  }
}
