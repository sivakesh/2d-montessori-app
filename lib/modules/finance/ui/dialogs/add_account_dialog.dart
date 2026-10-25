import 'package:flutter/material.dart';

import '../../../../core/widgets/responsive_dialog_shell.dart';
import '../../models/finance_account_model.dart';
import '../../services/finance_service.dart';

/// Adds an account, or — with [account] — edits it through
/// FinanceService.updateAccount. While editing, the type and opening balance
/// are locked when Finance records use the account, and Active is locked
/// when the account is required for routing new payments (see
/// FinanceService.accountUsage).
class AddAccountDialog extends StatefulWidget {
  const AddAccountDialog({super.key, this.account, this.service});

  /// The account to edit; null to add a new one.
  final FinanceAccountModel? account;

  /// Optional injection seam (tests); defaults to `FinanceService()` as before.
  final FinanceService? service;

  @override
  State<AddAccountDialog> createState() => _AddAccountDialogState();
}

class _AddAccountDialogState extends State<AddAccountDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _opening = TextEditingController(text: '0');
  String _type = 'cash';
  bool _isActive = true;
  late final _service = widget.service ?? FinanceService();
  bool _saving = false;
  String? _error;

  /// Edit only: what depends on the account (locks fields).
  Future<FinanceAccountUsage>? _usage;

  bool get _isEdit => widget.account != null;

  @override
  void initState() {
    super.initState();
    final account = widget.account;
    if (account != null) {
      _name.text = account.name;
      _type = account.type;
      _opening.text = _exact(account.openingBalance);
      _isActive = account.isActive;
      _usage = _service.accountUsage(account);
    }
  }

  /// Pre-fills without rounding, so an unchanged opening balance saves as is.
  static String _exact(double value) => value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toString();

  @override
  void dispose() {
    _name.dispose();
    _opening.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final opening = double.tryParse(_opening.text) ?? 0;
      final account = widget.account;
      if (account != null) {
        await _service.updateAccount(id: account.id, name: _name.text, type: _type, openingBalance: opening, isActive: _isActive);
      } else {
        await _service.createAccount(FinanceAccountModel(id: '', name: _name.text, type: _type, openingBalance: opening, currentBalance: opening, isActive: true, createdAt: DateTime.now(), updatedAt: DateTime.now()));
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      // Add keeps its previous behaviour (errors propagate as before).
      if (!_isEdit) rethrow;
      if (mounted) setState(() => _error = e is StateError ? e.message : 'Could not save the account: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _form({bool historyLocked = false, String? activeLockedReason, List<String> notes = const []}) {
    final types = [...FinanceService.accountTypes, if (!FinanceService.accountTypes.contains(_type)) _type];
    return Column(
      mainAxisSize: MainAxisSize.min,
      // Add keeps its original (centred) layout.
      crossAxisAlignment: _isEdit ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        Text(_isEdit ? 'Edit Account' : 'Add Account', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        for (final note in notes) ...[
          Text(note, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
          const SizedBox(height: 8),
        ],
        TextFormField(
          controller: _name,
          decoration: const InputDecoration(labelText: 'Name'),
          validator: (v) => (v == null || (_isEdit ? v.trim().isEmpty : v.isEmpty)) ? 'Required' : null,
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _type,
          decoration: const InputDecoration(labelText: 'Type'),
          items: types.map((e) => DropdownMenuItem(value: e, child: Text(e.isEmpty ? '(no type)' : e))).toList(),
          onChanged: historyLocked ? null : (v) => setState(() => _type = v ?? _type),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _opening,
          enabled: !historyLocked,
          decoration: const InputDecoration(labelText: 'Opening Balance'),
          keyboardType: TextInputType.number,
          validator: _isEdit ? (v) => double.tryParse(v?.trim() ?? '')?.isFinite == true ? null : 'Enter a number' : null,
        ),
        if (_isEdit) ...[
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Active'),
            subtitle: Text(
              activeLockedReason ?? 'Inactive accounts receive no new payments; their history and balances stay as they are.',
            ),
            value: _isActive,
            onChanged: _saving || activeLockedReason != null ? null : (v) => setState(() => _isActive = v),
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
      desktopHeight: _isEdit ? 560 : 420,
      child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: _usage == null
                ? _form()
                : FutureBuilder<FinanceAccountUsage>(
                    future: _usage,
                    builder: (context, snap) {
                      if (snap.connectionState != ConnectionState.done) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      final name = widget.account!.name;
                      if (snap.hasError) {
                        // Usage unknown: lock everything that could change
                        // balances or routing; the name can still change.
                        return _form(
                          historyLocked: true,
                          activeLockedReason: "Couldn't check how this account is used, so Active is locked.",
                          notes: const [
                            "Couldn't check how this account is used, so its type and opening balance are locked. "
                                'Close and try again to change them.',
                          ],
                        );
                      }
                      final usage = snap.data!;
                      final notes = [
                        if (usage.references.isNotEmpty)
                          'Used by ${usage.references.join(', ')}: its type and opening balance are locked so past '
                              'balances stay as they are. Existing records keep the account name they were saved with.',
                        if (usage.onlyActiveFor.isNotEmpty)
                          'It is the only active ${usage.onlyActiveFor.join('/')} account, so its type must keep covering '
                              '${usage.onlyActiveFor.join('/')} payments.',
                      ];
                      return _form(
                        historyLocked: usage.references.isNotEmpty,
                        activeLockedReason: widget.account!.isActive ? usage.deactivateBlockedReason(name) : null,
                        notes: notes,
                      );
                    },
                  ),
          ),
        ),
    );
  }
}
