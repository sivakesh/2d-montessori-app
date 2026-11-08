import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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

  /// The day the opening balance applies from (FinanceAccountModel
  /// .openingBalanceDate); required for a new or changed non-zero one.
  DateTime? _openingDate;
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
      _openingDate = account.openingBalanceDate;
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
    final opening = double.tryParse(_opening.text) ?? 0;
    final account = widget.account;
    final changed = account == null || opening != account.openingBalance;
    if (changed && (opening * 100).round() != 0 && _openingDate == null) {
      setState(() {
        _saving = false;
        _error = FinanceService.openingDateRequiredMessage;
      });
      return;
    }
    try {
      if (account != null) {
        await _service.updateAccount(id: account.id, name: _name.text, type: _type, openingBalance: opening, isActive: _isActive, openingBalanceDate: _openingDate);
      } else {
        await _service.createAccount(FinanceAccountModel(id: '', name: _name.text, type: _type, openingBalance: opening, currentBalance: opening, isActive: true, createdAt: DateTime.now(), updatedAt: DateTime.now(), openingBalanceDate: _openingDate));
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

  /// The opening balance's date: shown always, editable even when the
  /// amount is locked (it only places the balance in history).
  Widget _openingDateField() {
    final account = widget.account;
    final amount = double.tryParse(_opening.text.trim()) ?? 0;
    final nonZero = (amount * 100).round() != 0;
    final legacyUndated = account != null && account.hasUndatedOpeningBalance && _openingDate == null;
    return Column(
      key: const Key('account-opening-date'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Opening balance date${nonZero ? '' : ' (optional)'}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
              Text(
                _openingDate == null ? 'Not set' : DateFormat('dd MMM yyyy').format(_openingDate!),
                key: const Key('account-opening-date-value'),
                style: const TextStyle(fontSize: 15),
              ),
            ]),
          ),
          TextButton.icon(
            key: const Key('account-opening-date-pick'),
            onPressed: _saving
                ? null
                : () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _openingDate ?? DateTime.now(),
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                      helpText: 'Opening balance date',
                    );
                    if (picked != null) {
                      setState(() {
                        _openingDate = DateTime(picked.year, picked.month, picked.day);
                        _error = null;
                      });
                    }
                  },
            icon: const Icon(Icons.event_outlined, size: 18),
            label: Text(_openingDate == null ? 'Choose date' : 'Change'),
          ),
        ]),
        Text(
          'The day this opening balance applies from. Historical month-end balances include it from that day; current balances always include it.',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
        ),
        if (legacyUndated) ...[
          const SizedBox(height: 6),
          Text(
            'Opening date not set: historical month-end balances count this ₹${account.openingBalance.toStringAsFixed(0)} from the beginning. '
            'Choose the date it applies from to place it correctly. The amount is not changed.',
            key: const Key('account-opening-date-missing'),
            style: const TextStyle(fontSize: 12, color: Color(0xFFB26A00)),
          ),
        ],
      ],
    );
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
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        _openingDateField(),
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
      desktopHeight: _isEdit ? 680 : 540,
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
