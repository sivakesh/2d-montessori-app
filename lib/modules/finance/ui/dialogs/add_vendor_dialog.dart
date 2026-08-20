import 'package:flutter/material.dart';

import '../../../../core/widgets/responsive_dialog_shell.dart';
import '../../models/vendor_model.dart';
import '../../services/finance_service.dart';

class AddVendorDialog extends StatefulWidget {
  const AddVendorDialog({super.key});

  @override
  State<AddVendorDialog> createState() => _AddVendorDialogState();
}

class _AddVendorDialogState extends State<AddVendorDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _address = TextEditingController();
  final _gst = TextEditingController();
  final _serviceType = TextEditingController();
  final _service = FinanceService();
  bool _saving = false;
  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      await _service.createVendor(VendorModel(id: '', name: _name.text, phone: _phone.text, email: _email.text, address: _address.text, gstNo: _gst.text.isEmpty ? null : _gst.text, serviceType: _serviceType.text, isActive: true, createdAt: DateTime.now(), updatedAt: DateTime.now()));
      if (!mounted) return;
      Navigator.pop(context, true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
  @override
  Widget build(BuildContext context) {
    return ResponsiveDialogShell(
      desktopWidth: 640,
      desktopHeight: 560,
      child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Add Vendor', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Name'),
                  validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(controller: _phone, decoration: const InputDecoration(labelText: 'Phone')),
                const SizedBox(height: 12),
                TextFormField(controller: _email, decoration: const InputDecoration(labelText: 'Email')),
                const SizedBox(height: 12),
                TextFormField(controller: _address, decoration: const InputDecoration(labelText: 'Address'), maxLines: 2),
                const SizedBox(height: 12),
                TextFormField(controller: _gst, decoration: const InputDecoration(labelText: 'GST No')),
                const SizedBox(height: 12),
                TextFormField(controller: _serviceType, decoration: const InputDecoration(labelText: 'Service Type')),
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
            ),
          ),
        ),
    );
  }
}
