import 'package:flutter/material.dart';

import '../../../../core/widgets/responsive_dialog_shell.dart';
import '../../models/fee_component_model.dart';
import '../../models/fee_structure_model.dart';
import '../../services/fee_service.dart';

class FeeStructureDialog extends StatefulWidget {
  const FeeStructureDialog({super.key, this.structure});
  final FeeStructureModel? structure;

  @override
  State<FeeStructureDialog> createState() => _FeeStructureDialogState();
}

class _FeeStructureDialogState extends State<FeeStructureDialog> {
  final _service = FeeService();
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _desc = TextEditingController();
  final _year = TextEditingController(text: '2026-2027');
  final List<FeeComponentModel> _components = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final s = widget.structure;
    if (s != null) {
      _name.text = s.name;
      _desc.text = s.description;
      _year.text = s.academicYear;
      _components.addAll(s.components);
    }
  }

  Future<void> _addComponent() async {
    final name = TextEditingController();
    final amount = TextEditingController();
    final term = TextEditingController();
    final dueDay = TextEditingController();
    DateTime? dueDate;
    String frequency = 'monthly';
    bool optional = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => ResponsiveDialogShell.form(
          desktopWidth: 460,
          desktopHeight: 520,
          title: 'Add Component',
          content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: name, decoration: const InputDecoration(labelText: 'Component Name *')),
                  TextField(controller: amount, decoration: const InputDecoration(labelText: 'Amount *'), keyboardType: TextInputType.number),
                  DropdownButtonFormField<String>(
                    initialValue: frequency,
                    decoration: const InputDecoration(labelText: 'Frequency *'),
                    items: const ['monthly', 'term', 'oneTime'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                    onChanged: (v) => setModalState(() => frequency = v ?? frequency),
                  ),
                  if (frequency == 'term')
                    TextField(controller: term, decoration: const InputDecoration(labelText: 'Term Name *')),
                  if (frequency == 'monthly')
                    TextField(controller: dueDay, decoration: const InputDecoration(labelText: 'Due Day of Month (optional)'), keyboardType: TextInputType.number),
                  if (frequency != 'monthly')
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(dueDate == null ? 'Optional Due Date' : dueDate!.toIso8601String().split('T').first),
                      trailing: TextButton(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                            initialDate: dueDate ?? DateTime.now(),
                          );
                          if (picked != null) setModalState(() => dueDate = picked);
                        },
                        child: const Text('Pick'),
                      ),
                    ),
                  SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Optional'), value: optional, onChanged: (v) => setModalState(() => optional = v)),
                ],
              ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (name.text.trim().isEmpty || double.tryParse(amount.text) == null || double.parse(amount.text) <= 0) return;
                if (frequency == 'term' && term.text.trim().isEmpty) return;
                Navigator.pop(context, true);
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      setState(() {
        _components.add(
          FeeComponentModel(
            name: name.text.trim(),
            amount: double.parse(amount.text),
            frequency: frequency,
            termName: frequency == 'term' ? term.text.trim() : null,
            dueDate: frequency == 'monthly' ? null : dueDate,
            dueDayOfMonth: frequency == 'monthly' ? int.tryParse(dueDay.text) : null,
            isOptional: optional,
          ),
        );
      });
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_components.isEmpty) return;
    if (_components.any((c) => c.amount <= 0)) return;
    if (_components.any((c) => c.frequency == 'term' && (c.termName ?? '').trim().isEmpty)) return;
    setState(() => _saving = true);
    final total = _components.fold<double>(0, (total, c) => total + c.amount);
    final data = {
      'name': _name.text.trim(),
      'description': _desc.text.trim(),
      'academicYear': _year.text.trim(),
      'components': _components.map((e) => e.toMap()).toList(),
      'totalAmount': total,
      'isActive': true,
      'createdBy': 'admin',
    };
    late final String structureId;
    if (widget.structure == null) {
      structureId = await _service.createFeeStructure(data);
    } else {
      structureId = widget.structure!.id;
      await _service.updateFeeStructure(structureId, data);
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Fee structure saved')),
    );
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveDialogShell.form(
      desktopWidth: 860,
      desktopHeight: 680,
      title: widget.structure == null ? 'Add Fee Structure' : 'Edit Fee Structure',
      content: Form(
          key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'Fee Structure Name *'), validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null),
                TextFormField(controller: _desc, decoration: const InputDecoration(labelText: 'Description')),
                TextFormField(controller: _year, decoration: const InputDecoration(labelText: 'Academic Year *'), validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null),
                const SizedBox(height: 12),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text('Components'),
                    const Spacer(),
                    TextButton.icon(onPressed: _addComponent, icon: const Icon(Icons.add), label: const Text('Add Component')),
                  ],
                ),
                if (_components.isEmpty)
                  const Text('At least one component required')
                else
                  ..._components.map((c) => Card(
                        child: ListTile(
                          title: Text(c.name),
                          subtitle: Text('${c.frequency} • ${c.amount.toStringAsFixed(0)}${c.frequency == 'term' && (c.termName ?? '').isNotEmpty ? ' • ${c.termName}' : ''}'),
                        ),
                      )),
                const SizedBox(height: 12),
                Text('Total Amount: ${totalAmountText()}'),
              ],
            ),
          ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _saving ? null : _save, child: const Text('Save')),
      ],
    );
  }

  String totalAmountText() => _components.fold<double>(0, (t, c) => t + c.amount).toStringAsFixed(0);
}
