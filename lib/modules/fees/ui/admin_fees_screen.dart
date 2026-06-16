import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

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

  @override
  Widget build(BuildContext context) {
    return AdminLayout(
      selectedIndex: 6,
      title: 'Fees',
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF2E7D32),
        onPressed: () {
          if (_tab == 0) {
            _openStructure();
          } else if (_tab == 1) {
            _openAssignment();
          } else if (_tab == 2 && _assignments.where((a) => a.balanceAmount > 0).isNotEmpty) {
            _openCollection(_assignments.firstWhere((a) => a.balanceAmount > 0));
          }
        },
        child: const Icon(Icons.add, color: Colors.white),
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
          return Card(
            child: ListTile(
              title: Text(s.name),
              subtitle: Text('${s.academicYear} • ${s.components.length} components • $frequencySummary'),
              trailing: Wrap(children: [IconButton(icon: const Icon(Icons.edit), onPressed: () => _openStructure(structure: s))]),
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
          return Card(
            child: ListTile(
              title: Text(a.studentName),
              subtitle: Text('${a.className} • ${a.feeStructureName}\nBalance: ${a.balanceAmount.toStringAsFixed(0)}'),
              trailing: ElevatedButton(onPressed: () => _openCollection(a), child: const Text('Collect')),
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
          return Card(
            child: ListTile(
              title: Text(a.studentName),
              subtitle: Text('${a.admissionNo} • ${a.className}\n${a.feeStructureName}\nPayable: ${a.payableAmount.toStringAsFixed(0)} • Paid: ${a.paidAmount.toStringAsFixed(0)} • Balance: ${a.balanceAmount.toStringAsFixed(0)}'),
              trailing: TextButton(
                onPressed: () => _openCollection(a),
                child: const Text('Collect'),
              ),
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
          return Card(
            child: ListTile(
              title: Text(r.receiptNo),
              subtitle: Text('${r.studentName} • ${r.admissionNo} • ${r.className}\n${r.feeStructureName} • ${r.amount.toStringAsFixed(0)} • ${r.paymentMode}'),
              trailing: Wrap(
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: () => showDialog(context: context, builder: (_) => FeeReceiptViewDialog(receipt: r)),
                    child: const Text('View'),
                  ),
                  TextButton(
                    onPressed: r.pdfUrl.isEmpty ? null : () => _openPdf(r.pdfUrl),
                    child: const Text('Open PDF'),
                  ),
                  TextButton(
                    onPressed: r.pdfUrl.isEmpty ? () => showDialog(context: context, builder: (_) => FeeReceiptViewDialog(receipt: r)) : null,
                    child: const Text('Generate PDF'),
                  ),
                ],
              ),
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
          return Card(
            child: ListTile(
              title: Text(a.studentName),
              subtitle: Text('${a.admissionNo} • ${a.className}\nDue: ${a.balanceAmount.toStringAsFixed(0)}'),
              trailing: TextButton(onPressed: () {}, child: const Text('Send Reminder')),
            ),
          );
        },
      );
  }
}
