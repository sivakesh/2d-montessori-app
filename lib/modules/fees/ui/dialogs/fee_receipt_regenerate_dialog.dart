import 'dart:async';
import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';

import '../../../admin/settings/data/school_settings_service.dart';
import '../../../admin/settings/models/school_settings_model.dart';
import '../../models/fee_receipt_model.dart';
import '../../services/fee_receipt_regeneration.dart';
import '../../services/fee_service.dart';

/// Reads the school's profile (School Settings), or null when none is saved.
typedef SchoolProfileLoader = Future<SchoolSettingsModel?> Function();

/// Reads the school's logo image from its saved URL, or null.
typedef SchoolLogoLoader = Future<Uint8List?> Function(String url);

Future<SchoolSettingsModel?> loadSchoolProfile() => SchoolSettingsService().getSchoolIdentity(schoolId: kDefaultSchoolId);

Future<Uint8List?> loadSchoolLogo(String url) async {
  if (url.isEmpty) return null;
  try {
    return await FirebaseStorage.instance.refFromURL(url).getData(5 * 1024 * 1024).timeout(const Duration(seconds: 15));
  } catch (_) {
    return null;
  }
}

/// Regenerate PDF for an existing receipt (RegeneratedReceipt): review and
/// choose the parent / guardian, class, nature of fee and service period,
/// optionally the GSTIN and "(GST Included)" (both off by default), then a separate copy is
/// downloaded. Nothing is written: the receipt, its stored PDF, the
/// payment, the assignment, the student and parents, School Settings and
/// Finance are all unchanged; what is chosen here is for the copy only.
///
/// Keys: `receipt-regen-` + `parent-<i>` (a linked parent), `parent-relation`,
/// `parent-name`, `class`, `nature`, `period`, `amount`, `amount-words`,
/// `show-gstin`, `gstin`, `amount-includes-gst`, `error`, `note`, `generate`, `cancel`.
class FeeReceiptRegenerateDialog extends StatefulWidget {
  const FeeReceiptRegenerateDialog({
    super.key,
    required this.receipt,
    required this.service,
    this.loadSchool = loadSchoolProfile,
    this.loadLogo = loadSchoolLogo,
    this.savePdf = shareReceiptPdf,
  });

  final FeeReceiptModel receipt;
  final FeeService service;
  final SchoolProfileLoader loadSchool;
  final SchoolLogoLoader loadLogo;
  final ReceiptPdfSaver savePdf;

  @override
  State<FeeReceiptRegenerateDialog> createState() => _FeeReceiptRegenerateDialogState();
}

class _FeeReceiptRegenerateDialogState extends State<FeeReceiptRegenerateDialog> {
  bool _loading = true;
  bool _busy = false;
  List<String> _classes = const [];
  String? _className;
  List<ReceiptParent> _parents = const [];
  String _relation = 'Father';
  final _parentName = TextEditingController();
  final _nature = TextEditingController();
  final _period = TextEditingController();
  bool _showGstin = false;
  bool _amountIncludesGst = false;
  SchoolSettingsModel? _school;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _parentName.dispose();
    _nature.dispose();
    _period.dispose();
    super.dispose();
  }

  /// Everything prefilled comes from saved records, read only.
  Future<void> _load() async {
    final r = widget.receipt;
    final s = widget.service;
    Future<T?> read<T>(Future<T?> Function() f) async {
      try {
        return await f();
      } catch (_) {
        return null;
      }
    }

    final names = await read(s.getClassNames) ?? const <String, String>{};
    final student = (await read(() => s.getStudentById(r.studentId)))?.data();
    final assignment = await read(() => s.getAssignmentById(r.assignmentId));
    final structure = await read(() => s.getFeeStructureById(assignment?.feeStructureId ?? ''));
    final school = await read(widget.loadSchool);
    if (!mounted) return;

    final currentClass = (names[student?['classId']?.toString() ?? ''] ?? '').trim();
    // The existing classes, once each; the receipt's recorded class too if
    // it is no longer among them (so the dropdown always has a choice).
    final options = {
      for (final n in names.values)
        if (n.trim().isNotEmpty) n.trim(),
      if (r.className.trim().isNotEmpty) r.className.trim(),
    }.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final parents = ReceiptParent.fromStudent(student);
    final preferred = ReceiptParent.preferred(parents);
    setState(() {
      _classes = options;
      _className = currentClass.isNotEmpty ? currentClass : (r.className.trim().isEmpty ? null : r.className.trim());
      _parents = parents;
      if (preferred != null) {
        _relation = preferred.relation;
        _parentName.text = preferred.name;
      }
      _nature.text = RegeneratedReceipt.natureOfFeeFrom(structure);
      _period.text = RegeneratedReceipt.servicePeriodFrom(r, assignment);
      _school = school;
      _loading = false;
    });
  }

  ReceiptRegenerationOptions get _options => ReceiptRegenerationOptions(
        className: _className ?? '',
        parentRelation: _relation,
        parentName: _parentName.text,
        natureOfFee: _nature.text,
        servicePeriod: _period.text,
        showGstin: _showGstin,
        gstin: _school?.gstin ?? '',
        amountIncludesGst: _amountIncludesGst,
      );

  Future<void> _generate() async {
    if (_busy) return;
    final error = RegeneratedReceipt.validate(_options);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final doc = RegeneratedReceipt.build(widget.receipt, _options, school: _school);
      final logo = await widget.loadLogo(_school?.logoUrl ?? '');
      await widget.savePdf(await doc.toPdf(logo: logo), RegeneratedReceipt.fileName(widget.receipt));
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not regenerate the receipt PDF. Please try again.';
      });
    }
  }

  Widget _heading(String text) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 6),
        child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: Colors.blueGrey.shade700)),
      );

  Widget _review(String label, String value, {Key? key, bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 150, child: Text(label, style: TextStyle(fontSize: 13, color: Colors.grey.shade700))),
            Expanded(child: Text(value, key: key, style: TextStyle(fontSize: 13, fontWeight: bold ? FontWeight.w700 : FontWeight.w500))),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final r = widget.receipt;
    final validation = _loading ? null : RegeneratedReceipt.validate(_options);
    final gstError = _showGstin && validation != null && validation != RegeneratedReceipt.classMissingMessage ? validation : null;
    final preview = _loading || validation != null ? null : RegeneratedReceipt.build(r, _options, school: _school);
    return AlertDialog(
      title: Text('Regenerate receipt ${r.receiptNo}'),
      content: SizedBox(
        width: 540,
        child: _loading
            ? const SizedBox(height: 80, child: Center(child: CircularProgressIndicator()))
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      key: const Key('receipt-regen-note'),
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
                      child: const Text(
                        'This creates a separate copy for you to download. It does not replace the original receipt or its stored PDF, '
                        'and the receipt number, amount, payment, student, parent and Finance records are not changed. '
                        'What you choose here applies to this copy only.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                    _heading('PARENT / GUARDIAN'),
                    if (_parents.isNotEmpty)
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          for (final (i, p) in _parents.indexed)
                            ChoiceChip(
                              key: Key('receipt-regen-parent-$i'),
                              label: Text('${p.relation}: ${p.name}'),
                              selected: _relation == p.relation && _parentName.text.trim() == p.name,
                              onSelected: _busy
                                  ? null
                                  : (_) => setState(() {
                                        _relation = p.relation;
                                        _parentName.text = p.name;
                                      }),
                            ),
                        ],
                      )
                    else
                      Text('No parent or guardian is linked to this student. Enter a name for this copy if needed.',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 160,
                          child: DropdownButtonFormField<String>(
                            key: const Key('receipt-regen-parent-relation'),
                            initialValue: _relation,
                            isExpanded: true,
                            decoration: const InputDecoration(labelText: 'Relationship'),
                            items: [for (final rel in ReceiptParent.relations) DropdownMenuItem(value: rel, child: Text(rel))],
                            onChanged: _busy ? null : (v) => setState(() => _relation = v ?? 'Father'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            key: const Key('receipt-regen-parent-name'),
                            controller: _parentName,
                            enabled: !_busy,
                            decoration: InputDecoration(
                              labelText: ReceiptParent.labelOf(_relation),
                              helperText: _parentName.text.trim().isEmpty ? 'Left off the receipt when blank.' : null,
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ],
                    ),
                    _heading('STUDENT'),
                    _review('Student Name', r.studentName.trim().isEmpty ? '-' : r.studentName),
                    _review('Admission No', r.admissionNo.trim().isEmpty ? '-' : r.admissionNo),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      key: const Key('receipt-regen-class'),
                      initialValue: _className,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Class shown on the receipt',
                        helperText: 'For this copy only: the student\'s class is not changed.',
                      ),
                      items: [for (final c in _classes) DropdownMenuItem(value: c, child: Text(c, overflow: TextOverflow.ellipsis))],
                      onChanged: _busy ? null : (v) => setState(() => _className = v),
                    ),
                    _heading('PAYMENT'),
                    TextField(
                      key: const Key('receipt-regen-nature'),
                      controller: _nature,
                      enabled: !_busy,
                      decoration: const InputDecoration(labelText: 'Nature of Fee', helperText: 'From the saved fee structure. Left off when blank.'),
                      onChanged: (_) => setState(() {}),
                    ),
                    TextField(
                      key: const Key('receipt-regen-period'),
                      controller: _period,
                      enabled: !_busy,
                      decoration: const InputDecoration(labelText: 'Service Period', helperText: 'From the saved fee month or academic year. Left off when blank.'),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 10),
                    if (preview != null) ...[
                      for (final (label, value) in preview.paymentRows)
                        if (label != 'Nature of Fee' && label != 'Service Period') _review(label, value),
                      _review('Amount Paid', preview.amountLabel, key: const Key('receipt-regen-amount'), bold: true),
                      _review('Amount in Words', preview.amountWords, key: const Key('receipt-regen-amount-words')),
                    ],
                    _heading('TAX REGISTRATION'),
                    CheckboxListTile(
                      key: const Key('receipt-regen-show-gstin'),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _showGstin,
                      onChanged: _busy
                          ? null
                          : (v) => setState(() {
                                _showGstin = v ?? false;
                                _error = null;
                              }),
                      title: const Text('Show GSTIN on receipt'),
                      subtitle: const Text('Prints the school\'s GSTIN in the header. It does not add or calculate GST.'),
                    ),
                    if (_showGstin && gstError == null)
                      Text('GSTIN: ${_school?.gstin ?? ''}', key: const Key('receipt-regen-gstin'), style: const TextStyle(fontSize: 13)),
                    CheckboxListTile(
                      key: const Key('receipt-regen-amount-includes-gst'),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _amountIncludesGst,
                      onChanged: _busy ? null : (v) => setState(() => _amountIncludesGst = v ?? false),
                      title: const Text('Amount includes GST'),
                      subtitle: const Text('Shows "(GST Included)" beside Amount Paid. The amount is not changed and no GST is calculated.'),
                    ),
                    if (gstError != null || _error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(_error ?? gstError!, key: const Key('receipt-regen-error'), style: TextStyle(fontSize: 12, color: Colors.red.shade800)),
                      ),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          key: const Key('receipt-regen-cancel'),
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('receipt-regen-generate'),
          onPressed: _loading || _busy || validation != null ? null : _generate,
          child: Text(_busy ? 'Generating...' : 'Download copy'),
        ),
      ],
    );
  }
}
