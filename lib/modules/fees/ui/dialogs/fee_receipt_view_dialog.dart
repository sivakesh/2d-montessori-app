import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/widgets/responsive_dialog_shell.dart';
import '../../models/fee_month.dart';
import '../../models/fee_receipt_model.dart';
import '../../services/fee_receipt_regeneration.dart';
import '../../services/fee_service.dart';
import 'fee_receipt_regenerate_dialog.dart';

class FeeReceiptViewDialog extends StatefulWidget {
  const FeeReceiptViewDialog({
    super.key,
    required this.receipt,
    this.service,
    this.voided = false,
    this.loadSchool = loadSchoolProfile,
    this.loadLogo = loadSchoolLogo,
    this.saveRegeneratedPdf = shareReceiptPdf,
  });
  final FeeReceiptModel receipt;

  /// The service used to refresh the receipt and generate its PDF;
  /// defaults to FeeService(), created only when first needed.
  final FeeService? service;

  /// A voided (cancelled) payment's receipt, opened from Collection
  /// Details: marked as voided, and no new PDF can be generated for it.
  final bool voided;

  /// Regenerate PDF (FeeReceiptRegenerateDialog): the school's profile and
  /// logo, and how the regenerated copy reaches the administrator.
  final SchoolProfileLoader loadSchool;
  final SchoolLogoLoader loadLogo;
  final ReceiptPdfSaver saveRegeneratedPdf;

  @override
  State<FeeReceiptViewDialog> createState() => _FeeReceiptViewDialogState();
}

class _FeeReceiptViewDialogState extends State<FeeReceiptViewDialog> {
  late final _service = widget.service ?? FeeService();
  late FeeReceiptModel _receipt = widget.receipt;
  bool _isGeneratingPdf = false;
  String? _pdfStatusMessage;
  String? _pdfErrorMessage;

  Future<void> _refreshReceipt() async {
    final refreshed = await _service.getReceiptById(widget.receipt.id);
    if (refreshed != null && mounted) {
      setState(() => _receipt = refreshed);
    }
  }

  Future<void> _openPdf() async {
    if (_receipt.pdfUrl.isEmpty) return;
    await launchUrl(Uri.parse(_receipt.pdfUrl), mode: LaunchMode.externalApplication);
  }

  Future<void> _generatePdf() async {
    if (_isGeneratingPdf) return;
    setState(() {
      _isGeneratingPdf = true;
      _pdfStatusMessage = 'Generating receipt PDF...';
      _pdfErrorMessage = null;
    });
    try {
      final success = await _service.generateAndUploadReceiptPdf(_receipt);
      if (!success) {
        throw StateError('Could not generate receipt PDF');
      }
      await _refreshReceipt();
      if (!mounted) return;
      setState(() {
        _isGeneratingPdf = false;
        _pdfStatusMessage = 'Receipt PDF generated successfully';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Receipt PDF generated successfully')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isGeneratingPdf = false;
        _pdfStatusMessage = null;
        _pdfErrorMessage = 'Could not generate receipt PDF. Please try again.';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not generate receipt PDF. Please try again.')),
      );
    }
  }

  /// Regenerate PDF (it already has one): the professional copy with the
  /// options chosen, downloaded separately; this receipt, its stored
  /// PDF and every record are left as they are. Generate PDF (none yet)
  /// stays the default receipt ([_generatePdf]).
  Future<void> _regeneratePdf() async {
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => FeeReceiptRegenerateDialog(
        receipt: _receipt,
        service: _service,
        loadSchool: widget.loadSchool,
        loadLogo: widget.loadLogo,
        savePdf: widget.saveRegeneratedPdf,
      ),
    );
    if (done != true || !mounted) return;
    setState(() {
      _pdfStatusMessage = 'Receipt PDF regenerated';
      _pdfErrorMessage = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Receipt PDF regenerated')));
  }

  @override
  Widget build(BuildContext context) {
    final hasPdf = _receipt.pdfUrl.isNotEmpty;
    Widget row(String label, String value, {bool boldValue = false, Color? valueColor}) {
      return Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade400, width: 0.8),
          color: Colors.white,
        ),
        child: Row(
          children: [
            Expanded(
              flex: 42,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                color: Colors.grey.shade100,
                child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
              ),
            ),
            Expanded(
              flex: 58,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                child: Text(
                  value,
                  style: TextStyle(
                    fontWeight: boldValue ? FontWeight.bold : FontWeight.normal,
                    fontSize: boldValue ? 13 : 12,
                    color: valueColor,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return ResponsiveDialogShell.form(
      desktopWidth: 640,
      desktopHeight: 700,
      title: '2D Montessori Receipt',
      content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Column(
                  children: [
                    Image.asset('assets/logo.png', height: 52, errorBuilder: (_, _, _) => const SizedBox.shrink()),
                    const SizedBox(height: 8),
                    const Text('2D Montessori', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 4),
                    const Text('FEE RECEIPT', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (widget.voided)
                Container(
                  key: const Key('fee-receipt-voided'),
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    border: Border.all(color: Colors.red.shade200),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'VOIDED: this payment was cancelled and does not count towards the fee.',
                    style: TextStyle(color: Colors.red.shade900, fontWeight: FontWeight.w600, fontSize: 12),
                  ),
                ),
              row('Receipt No', _receipt.receiptNo),
              row('Student Name', _receipt.studentName),
              row('Admission No', _receipt.admissionNo),
              row('Class', _receipt.className),
              row('Fee Name', _receipt.feeStructureName),
              if (_receipt.feeMonth.isNotEmpty) row('Fee Month', FeeMonth.label(_receipt.feeMonth)),
              row('Amount Paid', 'Rs. ${_receipt.amount.toStringAsFixed(0)}', boldValue: true),
              row('Payment Mode', _receipt.paymentMode),
              row('Reference No', _receipt.referenceNo),
              row('Payment Date', _receipt.paymentDate?.toIso8601String().split('T').first ?? '-'),
              row('Generated Date', _receipt.pdfGeneratedAt?.toIso8601String().split('T').first ?? '-'),
              const SizedBox(height: 12),
              if (_isGeneratingPdf)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                      SizedBox(width: 12),
                      Expanded(child: Text('Generating receipt PDF...\nPlease wait')),
                    ],
                  ),
                ),
              if (_pdfStatusMessage != null && !_isGeneratingPdf)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(_pdfStatusMessage!, style: const TextStyle(color: Colors.green)),
                ),
              if (_pdfErrorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(_pdfErrorMessage!, style: const TextStyle(color: Colors.red)),
                ),
              Row(
                children: [
                  TextButton(
                    onPressed: (!_isGeneratingPdf && hasPdf) ? _openPdf : null,
                    child: const Text('Open PDF'),
                  ),
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: _isGeneratingPdf || widget.voided ? null : (hasPdf ? _regeneratePdf : _generatePdf),
                    child: Text(_isGeneratingPdf ? 'Generating...' : (hasPdf ? 'Regenerate PDF' : 'Generate PDF')),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                runSpacing: 4,
                children: const [
                  Text('System generated receipt', style: TextStyle(fontSize: 11)),
                  Text('Authorized Signature: ____________________', style: TextStyle(fontSize: 11)),
                ],
              ),
            ],
          ),
    );
  }
}
