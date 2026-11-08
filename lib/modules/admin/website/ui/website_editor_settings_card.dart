import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../auth/models/app_user.dart';
import '../../../public_website/content/blocks/block_limits.dart';
import '../../settings/models/school_settings_model.dart';
import '../data/website_editor_settings.dart';

/// Website → Pages → Editor settings: the page block limit the visual
/// editor uses, shown as saved now (it follows changes) with Change for
/// administrators. Lowering it changes no page.
class WebsiteEditorSettingsCard extends StatefulWidget {
  const WebsiteEditorSettingsCard({super.key, required this.service, required this.user});

  final WebsiteEditorSettingsService service;
  final AppUser user;

  @override
  State<WebsiteEditorSettingsCard> createState() => _WebsiteEditorSettingsCardState();
}

class _WebsiteEditorSettingsCardState extends State<WebsiteEditorSettingsCard> {
  WebsiteEditorSettings? _settings;
  bool _unreadable = false;
  StreamSubscription<WebsiteEditorSettings>? _sub;

  bool get _isAdmin => widget.user.role.toLowerCase() == 'admin';

  @override
  void initState() {
    super.initState();
    _sub = widget.service.watch().listen(
      (s) {
        if (!mounted) return;
        setState(() {
          _settings = s;
          _unreadable = false;
        });
      },
      onError: (Object _) {
        if (mounted) setState(() => _unreadable = true);
      },
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _change() async {
    final current = _settings;
    if (current == null) return;
    final saved = await showDialog<WebsiteEditorSettings>(
      context: context,
      builder: (_) => _BlockLimitDialog(service: widget.service, user: widget.user, current: current),
    );
    if (saved != null && mounted) {
      setState(() => _settings = saved);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text('Pages can now have up to ${saved.maxBlocksPerPage} blocks.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _settings;
    final String detail;
    if (_unreadable) {
      detail = 'The setting couldn’t be read, so editors use the default of ${BlockLimits.defaultPageMaxBlocks} blocks per page.';
    } else if (s == null) {
      detail = 'Loading…';
    } else if (s.storedValueInvalid) {
      detail = 'The saved value isn’t valid, so the default of ${BlockLimits.defaultPageMaxBlocks} applies. Change it to correct it.';
    } else if (s.isDefault) {
      detail = 'The default. Every section, columns block and block inside them counts.';
    } else {
      final when = s.updatedAt == null ? '' : ' on ${DateFormat('d MMM yyyy').format(s.updatedAt!)}';
      detail = 'Set${s.updatedByName.isEmpty ? '' : ' by ${s.updatedByName}'}$when. Every section, columns block and block inside them counts.';
    }
    return Card(
      key: const Key('website-editor-settings'),
      color: AppColors.card,
      margin: const EdgeInsets.only(bottom: 16),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
        leading: const Icon(Icons.view_agenda_outlined),
        title: Text(
          'Blocks per page: ${s?.maxBlocksPerPage ?? BlockLimits.defaultPageMaxBlocks}',
          key: const Key('website-editor-settings-limit'),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(detail, key: const Key('website-editor-settings-detail'), style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
        trailing: _isAdmin
            ? TextButton(key: const Key('website-editor-settings-change'), onPressed: s == null ? null : _change, child: const Text('Change'))
            : null,
      ),
    );
  }
}

class _BlockLimitDialog extends StatefulWidget {
  const _BlockLimitDialog({required this.service, required this.user, required this.current});

  final WebsiteEditorSettingsService service;
  final AppUser user;
  final WebsiteEditorSettings current;

  @override
  State<_BlockLimitDialog> createState() => _BlockLimitDialogState();
}

class _BlockLimitDialogState extends State<_BlockLimitDialog> {
  late final _controller = TextEditingController(text: '${widget.current.maxBlocksPerPage}');
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final value = int.tryParse(_controller.text.trim());
    final error = WebsiteEditorSettings.validateMaxBlocks(value);
    if (error != null) return setState(() => _error = error);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await widget.service.update(
        requesterRole: widget.user.role,
        requesterSchoolId: kDefaultSchoolId,
        actor: widget.user,
        maxBlocksPerPage: value!,
        expectedRevision: widget.current.revision,
      );
      if (mounted) Navigator.pop(context, saved);
    } on WebsiteEditorSettingsConflict catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _controller.text = '${e.current.maxBlocksPerPage}';
          _error = 'Another administrator changed it to ${e.current.maxBlocksPerPage} meanwhile. Nothing was saved; review it and save again.';
        });
      }
    } on UnauthorizedSchoolSettingsException {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Only an administrator can change this setting.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'It couldn’t be saved. Check your connection and try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('website-editor-settings-dialog'),
      title: const Text('Blocks per page'),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text(
            'How many blocks a page may have in the visual editor. Every section, columns block and block inside them counts once.',
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('website-editor-settings-field'),
            controller: _controller,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: 'Maximum blocks per page',
              helperText: 'From ${BlockLimits.minPageMaxBlocks} to ${BlockLimits.safetyMaxBlocks}. The default is ${BlockLimits.defaultPageMaxBlocks}.',
              errorText: _error,
              errorMaxLines: 3,
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (_) => _saving ? null : _save(),
          ),
          const SizedBox(height: 10),
          const Text(
            'Lowering it changes no page: pages that already have more blocks keep them and can still be edited, rearranged, saved and published; '
            'only adding more is stopped. Raising it applies at once.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ]),
      ),
      actions: [
        TextButton(key: const Key('website-editor-settings-cancel'), onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(key: const Key('website-editor-settings-save'), onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Save')),
      ],
    );
  }
}
