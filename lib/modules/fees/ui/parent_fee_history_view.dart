import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../admin/students/models/admin_student_model.dart';
import '../../auth/providers/auth_provider.dart';
import '../../finance/widgets/finance_status_chip.dart';
import '../../parent/data/parent_service.dart';
import '../../parent/data/parent_access.dart' show parentFeesRestrictedMessage;
import '../models/fee_transaction_model.dart';
import '../models/student_fee_assignment_model.dart';
import '../services/fee_service.dart';

/// Parent's dedicated Fees destination — a READ-ONLY history/summary for
/// every linked child, built on FeeService's per-student reads
/// (getAssignmentsForStudent / getPaymentsForStudent) and ParentService's
/// child linkage. There is no collect/assign/edit/void action anywhere on
/// this screen; it exposes strictly less than the Admin Fees module, never
/// more.
///
/// Fees are shown only for a child whose Father or Mother this parent is;
/// for any other relationship (or one the security rules refuse) the card
/// says so instead. Payments come from the parent-safe copies
/// (`parent_payments`), never from the receipt or transaction records
/// themselves (which carry the receipt PDF link and internal remarks). See
/// docs/parent_access_security.md.
class ParentFeeHistoryView extends ConsumerStatefulWidget {
  const ParentFeeHistoryView({super.key, this.feeService, this.parentService});

  final FeeService? feeService;
  final ParentService? parentService;

  @override
  ConsumerState<ParentFeeHistoryView> createState() => _ParentFeeHistoryViewState();
}

class _ChildFeeSummary {
  _ChildFeeSummary({required this.child, required this.assignments, required this.payments, this.restricted = false});

  final AdminStudentModel child;
  final List<StudentFeeAssignmentModel> assignments;
  final List<FeeTransactionModel> payments;

  /// Fees withheld (not this child's Father or Mother).
  final bool restricted;

  double get totalFee => assignments.fold<double>(0, (t, a) => t + a.payableAmount);
  double get paidAmount => assignments.fold<double>(0, (t, a) => t + a.paidAmount);
  double get outstanding => assignments.fold<double>(0, (t, a) => t + a.balanceAmount);
}

class _ParentFeeHistoryViewState extends ConsumerState<ParentFeeHistoryView> {
  late final _feeService = widget.feeService ?? FeeService();
  late final _parentService = widget.parentService ?? ParentService();

  bool _loading = true;
  bool _loadError = false;
  List<_ChildFeeSummary> _summaries = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = ref.read(currentUserProvider);
    if (user == null || user.id.isEmpty) {
      setState(() {
        _loading = false;
        _summaries = const [];
      });
      return;
    }
    setState(() {
      _loading = true;
      _loadError = false;
    });
    try {
      // Linked children resolved from the authenticated parent's own id;
      // each child's fees are then queried by that child's id only (the
      // security rules allow exactly that, and only for a Father or Mother).
      final children = await _parentService.getLinkedChildren(user.id);
      final summaries = <_ChildFeeSummary>[];
      for (final linked in children) {
        final child = linked.student;
        if (linked.canViewFinance == false) {
          summaries.add(_ChildFeeSummary(child: child, assignments: const [], payments: const [], restricted: true));
          continue;
        }
        try {
          // Parent-safe fee copies (amounts exactly as stored; no revision
          // history, admin ids or discount configuration), or before the
          // reconciliation the original records.
          final assignments = linked.fromProjection
              ? await _parentService.projections.getFeeAssignments(child.id)
              : await _feeService.getAssignmentsForStudent(child.id);
          // The parent-safe payment copies (no remarks, collector or PDF
          // link; voided payments removed), or before the reconciliation
          // the child's own receipts through the same filter.
          final projections = _parentService.projections;
          final rows = linked.fromProjection ? await projections.getPayments(child.id) : await projections.getLegacyPayments(child.id);
          final payments = [for (final r in rows) FeeTransactionModel.fromMap(r['receiptId']?.toString() ?? '', r)];
          summaries.add(_ChildFeeSummary(child: child, assignments: assignments, payments: payments));
        } on FirebaseException catch (e) {
          if (e.code != 'permission-denied') rethrow;
          summaries.add(_ChildFeeSummary(child: child, assignments: const [], payments: const [], restricted: true));
        }
      }
      if (!mounted) return;
      setState(() {
        _summaries = summaries;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadError = true;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Couldn't load fee history.", style: TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 8),
              TextButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    if (_summaries.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.family_restroom_outlined, size: 40, color: AppColors.textSecondary),
              SizedBox(height: 12),
              Text(
                'No children linked to your account yet.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _summaries.length,
        separatorBuilder: (_, _) => const SizedBox(height: 16),
        itemBuilder: (context, index) => _ChildFeeCard(summary: _summaries[index]),
      ),
    );
  }
}

class _ChildFeeCard extends StatelessWidget {
  const _ChildFeeCard({required this.summary});

  final _ChildFeeSummary summary;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              summary.child.name,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 12),
            if (summary.restricted)
              const Text(
                parentFeesRestrictedMessage,
                key: Key('parent-fees-restricted'),
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              )
            else ...[
              Row(
                children: [
                  _AmountColumn(label: 'Total Fee', amount: summary.totalFee),
                  _AmountColumn(label: 'Paid', amount: summary.paidAmount),
                  _AmountColumn(label: 'Outstanding', amount: summary.outstanding, emphasize: summary.outstanding > 0),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Payment History',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 8),
              if (summary.payments.isEmpty)
                const Text('No payments recorded yet.', style: TextStyle(color: AppColors.textSecondary, fontSize: 13))
              else
                for (final payment in summary.payments) ...[_PaymentRow(payment: payment), const SizedBox(height: 8)],
            ],
          ],
        ),
      ),
    );
  }
}

class _AmountColumn extends StatelessWidget {
  const _AmountColumn({required this.label, required this.amount, this.emphasize = false});

  final String label;
  final double amount;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
          const SizedBox(height: 2),
          Text(
            '₹${amount.toStringAsFixed(0)}',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: emphasize ? Colors.redAccent : AppColors.textPrimary),
          ),
        ],
      ),
    );
  }
}

class _PaymentRow extends StatelessWidget {
  const _PaymentRow({required this.payment});

  final FeeTransactionModel payment;

  @override
  Widget build(BuildContext context) {
    final date = payment.paymentDate;
    final dateText = date == null ? '-' : '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  payment.feeStructureName.isNotEmpty ? payment.feeStructureName : 'Payment',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text('$dateText • ${payment.paymentMode.isNotEmpty ? payment.paymentMode : '-'}', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FinanceStatusChip(label: '₹${payment.amount.toStringAsFixed(0)}', color: AppColors.secondary),
        ],
      ),
    );
  }
}
