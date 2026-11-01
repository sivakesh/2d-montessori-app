import 'package:flutter/material.dart';

import '../../../../core/widgets/responsive_dialog_shell.dart';
import '../../models/finance_category_model.dart';
import '../../services/finance_service.dart';

/// Adds a category, or — with [category] — edits it through
/// FinanceService.updateCategory. When editing a category that Finance
/// records already use, its name and type are locked (see updateCategory)
/// and only Active can change.
class AddCategoryDialog extends StatefulWidget {
  const AddCategoryDialog({super.key, this.category, this.service});

  /// The category to edit; null to add a new one.
  final FinanceCategoryModel? category;

  /// Optional injection seam (tests); defaults to `FinanceService()` as before.
  final FinanceService? service;

  @override
  State<AddCategoryDialog> createState() => _AddCategoryDialogState();
}

class _AddCategoryDialogState extends State<AddCategoryDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  String _type = 'income';
  bool _isActive = true;
  late final _service = widget.service ?? FinanceService();
  bool _saving = false;
  String? _error;

  /// Edit only: which records use the category (locks name and type).
  Future<List<String>>? _references;

  bool get _isEdit => widget.category != null;

  @override
  void initState() {
    super.initState();
    final category = widget.category;
    if (category != null) {
      _name.text = category.name;
      _type = category.type == 'expense' ? 'expense' : 'income';
      _isActive = category.isActive;
      _references = _service.categoryReferences(category);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final category = widget.category;
      if (category != null) {
        await _service.updateCategory(id: category.id, name: _name.text, type: _type, isActive: _isActive);
      } else {
        await _service.createCategory(FinanceCategoryModel(id: '', name: _name.text, type: _type, parentId: null, isSystem: false, isActive: true, createdAt: DateTime.now(), updatedAt: DateTime.now()));
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      // Add keeps its previous behaviour (errors propagate as before).
      if (!_isEdit) rethrow;
      if (mounted) setState(() => _error = e is StateError ? e.message : 'Could not save the category: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _form({required bool locked, String? lockNote}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_isEdit ? 'Edit Category' : 'Add Category', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        if (lockNote != null) ...[
          Text(lockNote, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
          const SizedBox(height: 8),
        ],
        TextFormField(
          controller: _name,
          enabled: !locked,
          decoration: const InputDecoration(labelText: 'Name'),
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _type,
          decoration: const InputDecoration(labelText: 'Type'),
          items: const ['income', 'expense']
              .map((e) => DropdownMenuItem(value: e, child: Text(e)))
              .toList(),
          onChanged: locked ? null : (v) => setState(() => _type = v ?? _type),
        ),
        if (_isEdit) ...[
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Active'),
            subtitle: const Text('Inactive categories are hidden from new entries; existing records keep them.'),
            value: _isActive,
            onChanged: _saving ? null : (v) => setState(() => _isActive = v),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: const TextStyle(fontSize: 12, color: Colors.red)),
        ],
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: _saving ? null : () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveDialogShell(
      desktopWidth: 520,
      desktopHeight: 460,
      mobileCompact: true,
      child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: _references == null
                ? _form(locked: false)
                : FutureBuilder<List<String>>(
                    future: _references,
                    builder: (context, snap) {
                      if (snap.connectionState != ConnectionState.done) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      if (snap.hasError) {
                        // Usage unknown: keep name and type locked rather
                        // than risk changing a category that is in use.
                        return _form(
                          locked: true,
                          lockNote: "Couldn't check where this category is used, so its name and type are locked. "
                              'Close and try again to change them.',
                        );
                      }
                      final refs = snap.data!;
                      return _form(
                        locked: refs.isNotEmpty,
                        lockNote: refs.isEmpty
                            ? null
                            : 'Used by ${refs.join(', ')}: its name and type are locked so existing records stay '
                                'classified as they are. You can still deactivate it.',
                      );
                    },
                  ),
          ),
        ),
    );
  }
}
