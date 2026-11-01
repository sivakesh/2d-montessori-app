import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../../forms/models/public_submission_settings.dart';
import '../data/public_submission_settings_service.dart';
import '../models/school_settings_model.dart';
import 'access_restricted_view.dart';

/// Settings → Website → Public form submissions: whether visitors can
/// send the website's forms, and what they're told while they can't.
///
/// The switch always shows what is saved: a change shows as made only
/// after it has been saved, and a failed change leaves (and reloads) the
/// saved state. Admins only, for their own school.

class PublicSubmissionsSettingsScreen extends StatelessWidget {
  const PublicSubmissionsSettingsScreen({super.key, this.service});

  final PublicSubmissionSettingsService? service;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(title: const Text('Public form submissions')),
      body: _Body(service: service),
    );
  }
}

class _Body extends ConsumerStatefulWidget {
  const _Body({this.service});

  final PublicSubmissionSettingsService? service;

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  late final _service = widget.service ?? PublicSubmissionSettingsService();
  final _message = TextEditingController();

  /// What is saved, as last read.
  PublicSubmissionSettings? _saved;
  bool _loading = true;
  bool _loadFailed = false;
  bool _saving = false;

  /// The app serves one school; an admin's school is that one.
  static const _schoolId = kDefaultSchoolId;

  String get _role => (ref.read(currentUserProvider)?.role ?? '').toLowerCase();

  @override
  void initState() {
    super.initState();
    _message.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_role != 'admin') {
      setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      final saved = await _service.load(schoolId: _schoolId, requesterRole: _role, requesterSchoolId: _schoolId);
      if (!mounted) return;
      setState(() => _show(saved));
    } catch (_) {
      if (mounted) setState(() => _loadFailed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _show(PublicSubmissionSettings saved) {
    _saved = saved;
    _message.text = saved.closedMessage;
  }

  void _say(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _toggle(bool enabled) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(enabled ? 'Turn on public submissions?' : 'Turn off public submissions?'),
        content: Text(enabled
            ? 'Visitors will be able to send every active form on the website.'
            : 'Visitors will no longer be able to send forms. Forms stay on the website with your closed message. Earlier submissions are kept.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            key: const Key('public-submissions-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(enabled ? 'Turn on' : 'Turn off'),
          ),
        ],
      ),
    );
    if (ok == true) await _save(enabled: enabled, message: _saved!.closedMessage, done: enabled ? 'Public submissions turned on' : 'Public submissions turned off');
  }

  Future<void> _save({required bool enabled, required String message, required String done}) async {
    final saved = _saved!;
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    setState(() => _saving = true);
    try {
      final now = await _service.update(
        schoolId: _schoolId,
        requesterRole: _role,
        requesterSchoolId: _schoolId,
        actor: user,
        enabled: enabled,
        closedMessage: message,
        expectedRevision: saved.revision,
      );
      if (!mounted) return;
      setState(() => _show(now));
      _say(done);
    } on PublicSubmissionSettingsConflict catch (e) {
      if (!mounted) return;
      setState(() => _show(e.current));
      _say(e.toString());
    } catch (e) {
      if (!mounted) return;
      _say(e is ArgumentError ? '${e.message}' : 'The change couldn’t be saved. The setting is unchanged.');
      // Show what is saved, whatever happened to the change.
      await _load();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = (ref.watch(currentUserProvider)?.role ?? '').toLowerCase() == 'admin';
    if (!isAdmin) return const AccessRestrictedView();
    if (_loading && _saved == null) return const Center(child: CircularProgressIndicator(key: Key('public-submissions-loading')));
    final saved = _saved;
    if (saved == null || _loadFailed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            key: const Key('public-submissions-load-error'),
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('The setting couldn’t be loaded. Public submissions are treated as off.', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: _load, child: const Text('Try again')),
            ],
          ),
        ),
      );
    }
    final (statusText, statusColor, statusIcon) = saved.enabled
        ? ('On: visitors can send forms', Colors.green.shade700, Icons.check_circle_outline)
        : ('Off: visitors can’t send forms', Colors.grey.shade700, Icons.block);
    final message = _message.text.trim();
    final messageError = PublicSubmissionSettings.validateClosedMessage(message);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: AppColors.card,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text('Accept form submissions from the website', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                    ),
                    if (_saving) const Padding(padding: EdgeInsets.only(right: 8), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
                    Switch(key: const Key('public-submissions-switch'), value: saved.enabled, onChanged: _saving ? null : _toggle),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  key: const Key('public-submissions-status'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(statusIcon, size: 18, color: statusColor),
                    const SizedBox(width: 6),
                    Expanded(child: Text(statusText, style: TextStyle(color: statusColor))),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  saved.updatedAt == null && saved.revision == 0
                      ? 'Never changed: off by default.'
                      : 'Last changed${saved.updatedByName?.isNotEmpty == true ? ' by ${saved.updatedByName}' : ''}'
                          '${saved.updatedAt != null ? ' on ${DateFormat('d MMM yyyy, h:mm a').format(saved.updatedAt!)}' : ''}.',
                  key: const Key('public-submissions-updated'),
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Applies to every form on the website. Forms, submissions and their history aren’t changed.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          color: AppColors.card,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Message while closed', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                const SizedBox(height: 8),
                TextField(
                  key: const Key('public-submissions-message'),
                  controller: _message,
                  enabled: !_saving,
                  minLines: 2,
                  maxLines: 4,
                  maxLength: PublicSubmissionSettings.maxClosedMessage,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    hintText: 'Online submissions aren’t open yet. Please contact the school directly.',
                    helperText: 'Shown under each form while submissions are off. Leave blank for the website’s own wording.',
                    helperMaxLines: 2,
                    errorText: messageError,
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    key: const Key('public-submissions-save-message'),
                    onPressed: _saving || messageError != null || message == saved.closedMessage
                        ? null
                        : () => _save(enabled: saved.enabled, message: message, done: 'Message saved'),
                    child: const Text('Save message'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
