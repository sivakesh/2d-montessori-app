import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../admin/ui/admin_fab.dart';
import '../../admin/ui/admin_layout.dart';
import '../models/fee_receipt_model.dart';
import '../models/fee_structure_model.dart';
import '../models/student_fee_assignment_model.dart';
import '../services/fee_service.dart';
import '../widgets/fee_summary_card.dart';
import 'dialogs/fee_assignment_dialog.dart';
import 'dialogs/fee_collection_dialog.dart';
import 'dialogs/fee_receipt_view_dialog.dart';
import 'dialogs/fee_structure_dialog.dart';

class AdminFeesScreen extends StatefulWidget {
  const AdminFeesScreen({super.key});

  @override
  State<AdminFeesScreen> createState() => _AdminFeesScreenState();
}

class _AdminFeesScreenState extends State<AdminFeesScreen> {
  final _service = FeeService();
  int _tab = 0;
  bool _loading = true;
  String? _deletingId;
  Map<String, dynamic> _summary = const {};
  List<FeeStructureModel> _structures = [];
  List<StudentFeeAssignmentModel> _assignments = [];
  List<FeeReceiptModel> _receipts = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final summary = await _service.getDashboardSummary();
    final structures = await _service.getFeeStructures();
    final assignments = await _service.getAssignments();
    final receipts = await _service.getReceipts();
    if (!mounted) return;
    setState(() {
      _summary = summary;
      _structures = structures;
      _assignments = assignments;
      _receipts = receipts;
      _loading = false;
    });
  }

  Future<void> _openStructure({FeeStructureModel? structure}) async {
    await showDialog(context: context, barrierDismissible: false, builder: (_) => FeeStructureDialog(structure: structure));
    await _load();
  }

  Future<void> _openAssignment() async {
    await showDialog(context: context, barrierDismissible: false, builder: (_) => const FeeAssignmentDialog());
    await _load();
  }

  Future<void> _openCollection(StudentFeeAssignmentModel assignment) async {
    await showDialog(context: context, barrierDismissible: false, builder: (_) => FeeCollectionDialog(assignment: assignment));
    await _load();
  }

  Future<void> _openPdf(String url) async {
    if (url.isEmpty) return;
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  Future<bool> _confirmDelete() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete item?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _deleteStructure(FeeStructureModel structure) async {
    if (!await _confirmDelete()) return;
    setState(() => _deletingId = structure.id);
    try {
      await _service.deleteFeeStructure(structure.id);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Structure deleted')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete structure: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _deletingId = null);
    }
  }

  Future<void> _deleteAssignment(StudentFeeAssignmentModel assignment) async {
    if (!await _confirmDelete()) return;
    setState(() => _deletingId = assignment.id);
    try {
      await _service.deleteAssignment(assignment.id);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Assignment deleted')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete assignment: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _deletingId = null);
    }
  }

  Future<void> _deleteReceipt(FeeReceiptModel receipt) async {
    if (!await _confirmDelete()) return;
    setState(() => _deletingId = receipt.id);
    try {
      await _service.deleteReceipt(receipt.id);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Receipt deleted')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete receipt: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _deletingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminLayout(
      selectedIndex: 6,
      title: 'Fees',
      floatingActionButton: AdminFab(
        icon: Icons.add,
        onPressed: () {
          if (_tab == 0) {
            _openStructure();
          } else if (_tab == 1) {
            _openAssignment();
          } else if (_tab == 2 && _assignments.where((a) => a.balanceAmount > 0).isNotEmpty) {
            _openCollection(_assignments.firstWhere((a) => a.balanceAmount > 0));
          }
        },
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : LayoutBuilder(
                builder: (context, constraints) {
                  final cardWidth = constraints.maxWidth >= 1200
                      ? (constraints.maxWidth - 32) / 3
                      : constraints.maxWidth >= 800
                          ? (constraints.maxWidth - 16) / 2
                          : constraints.maxWidth;
              return SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Fees', style: Theme.of(context).textTheme.headlineSmall),
                        const SizedBox(height: 24),
                        Wrap(
                          spacing: 16,
                          runSpacing: 16,
                          children: [
                            FeeSummaryCard(label: 'Total Expected', value: _summary['totalExpected']?.toStringAsFixed(0) ?? '0', icon: Icons.receipt_long),
                            FeeSummaryCard(label: 'Total Collected', value: _summary['totalCollected']?.toStringAsFixed(0) ?? '0', icon: Icons.payments),
                            FeeSummaryCard(label: 'Outstanding', value: _summary['outstanding']?.toStringAsFixed(0) ?? '0', icon: Icons.warning, color: Colors.orange),
                            FeeSummaryCard(label: 'Collection %', value: '${_summary['collectionPercent']?.toStringAsFixed(1) ?? '0'}%', icon: Icons.show_chart),
                            FeeSummaryCard(label: 'Overdue Students', value: '${_summary['overdueStudents'] ?? 0}', icon: Icons.schedule, color: Colors.red),
                            FeeSummaryCard(label: 'Today\'s Collection', value: _summary['todayCollection']?.toStringAsFixed(0) ?? '0', icon: Icons.today),
                          ]
                              .map((card) => SizedBox(width: cardWidth, child: card))
                              .toList(),
                        ),
                        const SizedBox(height: 24),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: const [
                            'Structures',
                            'Assignments',
                            'Collections',
                            'Receipts',
                            'Dues',
                          ].asMap().entries.map((e) {
                            return ChoiceChip(
                              label: Text(e.value),
                              selected: _tab == e.key,
                              onSelected: (_) => setState(() => _tab = e.key),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 16),
                        _buildTab(),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }

  Widget _buildTab() {
    switch (_tab) {
      case 0:
        return _buildStructures();
      case 1:
        return _buildAssignments();
      case 2:
        return _buildCollections();
      case 3:
        return _buildReceipts();
      default:
        return _buildDues();
    }
  }

  Widget _buildStructures() => ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _structures.length,
        itemBuilder: (context, i) {
          final s = _structures[i];
          final frequencySummary = s.components.isEmpty
              ? 'No components'
              : s.components.map((c) => c.frequency).toSet().join(', ');
          return _FeeListCard(
            icon: Icons.receipt_long_outlined,
            title: s.name,
            subtitleLines: ['${s.academicYear} • ${s.components.length} components • $frequencySummary'],
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Edit',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  onPressed: () => _openStructure(structure: s),
                ),
                IconButton(
                  tooltip: 'Delete',
                  visualDensity: VisualDensity.compact,
                  icon: _deletingId == s.id
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                  onPressed: _deletingId == s.id ? null : () => _deleteStructure(s),
                ),
              ],
            ),
          );
        },
      );

  Widget _buildAssignments() => ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _assignments.length,
        itemBuilder: (context, i) {
          final a = _assignments[i];
          return _FeeListCard(
            icon: Icons.assignment_outlined,
            title: a.studentName,
            subtitleLines: [
              '${a.className} • ${a.feeStructureName}',
              'Balance: ${a.balanceAmount.toStringAsFixed(0)}',
            ],
            trailing: IconButton(
              tooltip: 'Delete',
              visualDensity: VisualDensity.compact,
              icon: _deletingId == a.id
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.delete_outline, size: 20, color: Colors.red),
              onPressed: _deletingId == a.id ? null : () => _deleteAssignment(a),
            ),
          );
        },
      );

  Widget _buildCollections() => ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _assignments.where((a) => a.balanceAmount > 0).length,
        itemBuilder: (context, i) {
          final items = _assignments.where((a) => a.balanceAmount > 0).toList();
          final a = items[i];
          return _FeeListCard(
            icon: Icons.payments_outlined,
            title: a.studentName,
            subtitleLines: [
              '${a.admissionNo} • ${a.className}',
              a.feeStructureName,
              'Payable: ${a.payableAmount.toStringAsFixed(0)} • Paid: ${a.paidAmount.toStringAsFixed(0)} • Balance: ${a.balanceAmount.toStringAsFixed(0)}',
            ],
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: () => _openCollection(a),
                  child: const Text('Collect'),
                ),
                IconButton(
                  tooltip: 'Delete',
                  visualDensity: VisualDensity.compact,
                  icon: _deletingId == a.id
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                  onPressed: _deletingId == a.id ? null : () => _deleteAssignment(a),
                ),
              ],
            ),
          );
        },
      );

  Widget _buildReceipts() => ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _receipts.length,
        itemBuilder: (context, i) {
          final r = _receipts[i];
          return _FeeListCard(
            icon: Icons.description_outlined,
            title: r.receiptNo,
            subtitleLines: [
              '${r.studentName} • ${r.admissionNo} • ${r.className}',
              '${r.feeStructureName} • ${r.amount.toStringAsFixed(0)} • ${r.paymentMode}',
            ],
            trailing: PopupMenuButton<String>(
              tooltip: 'Actions',
              icon: const Icon(Icons.more_vert, size: 20),
              onSelected: (value) {
                switch (value) {
                  case 'view':
                    showDialog(context: context, builder: (_) => FeeReceiptViewDialog(receipt: r));
                    break;
                  case 'open_pdf':
                    _openPdf(r.pdfUrl);
                    break;
                  case 'generate_pdf':
                    showDialog(context: context, builder: (_) => FeeReceiptViewDialog(receipt: r));
                    break;
                  case 'delete':
                    _deleteReceipt(r);
                    break;
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'view',
                  child: ListTile(leading: Icon(Icons.visibility_outlined), title: Text('View'), contentPadding: EdgeInsets.zero),
                ),
                PopupMenuItem(
                  value: 'open_pdf',
                  enabled: r.pdfUrl.isNotEmpty,
                  child: const ListTile(leading: Icon(Icons.open_in_new), title: Text('Open PDF'), contentPadding: EdgeInsets.zero),
                ),
                PopupMenuItem(
                  value: 'generate_pdf',
                  enabled: r.pdfUrl.isEmpty,
                  child: const ListTile(leading: Icon(Icons.picture_as_pdf_outlined), title: Text('Generate PDF'), contentPadding: EdgeInsets.zero),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    leading: Icon(Icons.delete_outline, color: Colors.red),
                    title: Text('Delete', style: TextStyle(color: Colors.red)),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          );
        },
      );

  Widget _buildDues() {
    final dues = _assignments.where((a) => a.balanceAmount > 0).toList();
    return ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: dues.length,
        itemBuilder: (context, i) {
          final a = dues[i];
          return _FeeListCard(
            icon: Icons.schedule_outlined,
            title: a.studentName,
            subtitleLines: [
              '${a.admissionNo} • ${a.className}',
              'Due: ${a.balanceAmount.toStringAsFixed(0)}',
            ],
            trailing: IconButton(
              tooltip: 'Delete',
              visualDensity: VisualDensity.compact,
              icon: _deletingId == a.id
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.delete_outline, size: 20, color: Colors.red),
              onPressed: _deletingId == a.id ? null : () => _deleteAssignment(a),
            ),
          );
        },
      );
  }
}

/// Compact list-card shared by the Fees tabs: icon + title/meta (wrapped,
/// ellipsized) + trailing actions — matching the row pattern already used
/// by Students/Classes/Documents/Notifications.
class _FeeListCard extends StatelessWidget {
  const _FeeListCard({
    required this.icon,
    required this.title,
    required this.subtitleLines,
    required this.trailing,
  });

  final IconData icon;
  final String title;
  final List<String> subtitleLines;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textPrimary),
                ),
                for (final line in subtitleLines) ...[
                  const SizedBox(height: 4),
                  Text(
                    line,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          trailing,
        ],
      ),
    );
  }
}
