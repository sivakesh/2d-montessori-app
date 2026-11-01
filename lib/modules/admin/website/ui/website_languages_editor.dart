import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../auth/models/app_user.dart';
import '../../../public_website/content/website_content_repository.dart';
import '../../../public_website/content/website_languages.dart';
import '../../../public_website/public_strings.dart';
import '../../../public_website/widgets/public_scaffold.dart';
import '../data/website_content_admin_service.dart';
import 'website_content_editors.dart';
import 'website_content_screen.dart';

/// Settings -> Website -> Languages: the website's language registry —
/// which languages exist, which the editors offer (enabled), which visitors
/// can choose (public), their order and the fallback language — with a
/// preview of the public language switch, a saved draft and
/// publish/unpublish. English is the source language and always on.
/// Turning a language off never deletes text written in it.
class WebsiteLanguagesEditorScreen extends ConsumerStatefulWidget {
  const WebsiteLanguagesEditorScreen({super.key, required this.service, required this.user});

  final WebsiteContentAdminService service;
  final AppUser user;

  @override
  ConsumerState<WebsiteLanguagesEditorScreen> createState() => _WebsiteLanguagesEditorScreenState();
}

class _WebsiteLanguagesEditorScreenState extends ConsumerState<WebsiteLanguagesEditorScreen> with WebsiteContentActions {
  @override
  WebsiteContentAdminService get service => widget.service;
  @override
  AppUser get user => widget.user;

  SiteLanguageRegistry _registry = SiteLanguageRegistry.defaults;
  SiteLanguageRegistry? _savedDraft;
  SiteLanguageRegistry? _live;
  bool _liveUnreadable = false;
  bool _loading = true;
  bool _loadFailed = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    final ok = await attempt(() async {
      final saved = await service.getLanguageRegistry(requesterRole: role);
      if (!mounted) return;
      setState(() {
        _savedDraft = saved.draft;
        _live = saved.live;
        _liveUnreadable = saved.liveUnreadable;
        _registry = saved.draft ?? saved.live ?? SiteLanguageRegistry.defaults;
      });
    });
    if (mounted) {
      setState(() {
        _loading = false;
        _loadFailed = !ok;
      });
    }
  }

  Future<void> _run(Future<void> Function() action, String success) async {
    setState(() => _busy = true);
    final ok = await attempt(action, success: success);
    if (ok) {
      refreshPublicSite();
      final saved = await service.getLanguageRegistry(requesterRole: role);
      if (mounted) {
        setState(() {
          _savedDraft = saved.draft;
          _live = saved.live;
          _liveUnreadable = saved.liveUnreadable;
        });
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<bool> _confirm({required String title, required String body, required String action, required Key key}) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(key: key, onPressed: () => Navigator.pop(context, true), child: Text(action)),
        ],
      ),
    );
    return confirmed == true && mounted;
  }

  void _update(int index, SiteLanguage language) => setState(() {
        _registry = _registry.copyWith(languages: [..._registry.languages]..[index] = language);
      });

  void _move(int index, int delta) {
    final to = index + delta;
    if (to < 0 || to >= _registry.languages.length) return;
    setState(() {
      final list = [..._registry.languages];
      final item = list.removeAt(index);
      list.insert(to, item);
      _registry = _registry.copyWith(languages: list);
    });
  }

  Future<void> _add() async {
    final added = await showDialog<SiteLanguage>(
      context: context,
      builder: (_) => _AddLanguageDialog(existing: {for (final l in _registry.languages) l.code.toLowerCase()}),
    );
    if (added != null && mounted) setState(() => _registry = _registry.copyWith(languages: [..._registry.languages, added]));
  }

  Future<void> _publish() async {
    if (!await _confirm(
      title: 'Publish these languages?',
      body: 'Visitors’ language switch will offer the enabled, public languages straight away. Text not yet available in a language shows in the fallback language.',
      action: 'Publish',
      key: const Key('website-languages-publish-confirm'),
    )) {
      return;
    }
    await _run(() => service.publishLanguageRegistry(requesterRole: role, actor: user, registry: _registry), 'Published. Visitors now see these languages.');
  }

  Future<void> _unpublish() async {
    if (!await _confirm(
      title: 'Unpublish the languages?',
      body: 'Visitors are offered English and Tamil again. Your draft is kept, and no text in any language is deleted.',
      action: 'Unpublish',
      key: const Key('website-languages-unpublish-confirm'),
    )) {
      return;
    }
    await _run(() => service.unpublishLanguageRegistry(requesterRole: role, actor: user), 'Unpublished. Visitors are offered English and Tamil again.');
  }

  Future<void> _reset() async {
    if (!await _confirm(
      title: 'Start again from the initial languages?',
      body: 'The editor returns to English and Tamil on, the other languages off, English as fallback. Languages you added are removed from the list (their text is not deleted). Nothing changes until you save a draft or publish.',
      action: 'Start again',
      key: const Key('website-languages-reset-confirm'),
    )) {
      return;
    }
    setState(() => _registry = SiteLanguageRegistry.defaults);
    showMessage('Reset in the editor. Save a draft or publish to apply it.');
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _loadFailed) {
      return Scaffold(
        appBar: AppBar(title: const Text('Languages')),
        body: Center(
          child: _loading
              ? const CircularProgressIndicator()
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('The languages could not be loaded.'),
                    const SizedBox(height: 12),
                    OutlinedButton(key: const Key('website-languages-retry'), onPressed: _load, child: const Text('Try again')),
                  ],
                ),
        ),
      );
    }

    final registry = _registry;
    final live = _live;
    final saved = _savedDraft ?? live;
    final unsaved = saved == null ? !registry.sameContentAs(SiteLanguageRegistry.defaults) : !registry.sameContentAs(saved);
    final errors = registry.validationErrors();
    final visible = [for (final l in registry.languages) if (l.isVisible) l];
    final String description;
    if (_savedDraft == null && live == null) {
      description = 'Nothing has been saved yet. These are the initial languages; visitors are offered English and Tamil.';
    } else if (live == null) {
      description = 'You are editing a saved draft that is not published. Visitors are offered English and Tamil.';
    } else if (_savedDraft != null && !_savedDraft!.sameContentAs(live)) {
      description = 'You are editing a saved draft with unpublished changes. Visitors still see the published languages.';
    } else {
      description = 'You are editing the published languages that visitors see.';
    }

    return WebsiteEditorFrame(
      title: 'Languages',
      busy: _busy,
      children: [
        WebsiteEditSourceBanner(
          key: const Key('website-languages-source'),
          text: description,
          chips: [
            live == null
                ? const WebsiteStatusChip(label: 'Not published', color: Color(0xFF6E6E73))
                : const WebsiteStatusChip(label: 'Published', color: Color(0xFF2E7D5B)),
            if (unsaved) const WebsiteStatusChip(key: Key('website-languages-unsaved'), label: 'Unsaved edits', color: Color(0xFFB3261E)),
          ],
        ),
        if (_liveUnreadable)
          Container(
            key: const Key('website-languages-live-unreadable'),
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFFCEEEE), borderRadius: BorderRadius.circular(10)),
            child: const Text(
              'The published languages could not be read, so visitors are offered English and Tamil. Publish these languages to replace them, or unpublish them.',
              style: TextStyle(fontSize: 13),
            ),
          ),
        // While editing is English only, a language made public shows the
        // fallback language's text wherever no translation is stored.
        if (!multilingualEditing)
          Container(
            key: const Key('website-languages-english-only'),
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFF3EADB), borderRadius: BorderRadius.circular(10)),
            child: const Text(
              'Website text is edited in English only for now. If visitors can choose another language, pages without text in that language '
              'show the fallback language’s text instead (English unless you change it below). Text already saved in Tamil is kept and still shown.',
              style: TextStyle(fontSize: 13),
            ),
          ),
        const WebsiteEditorSectionTitle('Languages'),
        const Text(
          'Enabled: offered in the website editors. Public: offered in the visitors’ language switch (enabled languages only). '
          'Turning a language off never deletes text written in it. Text in Hindi, Malayalam, Telugu, Kannada and French '
          'is entered in a later step; until then those languages show the fallback language’s text.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 10),
        for (var i = 0; i < registry.languages.length; i++)
          Builder(builder: (context) {
            final l = registry.languages[i];
            final isSource = l.code == PublicLanguage.sourceCode;
            return Card(
              key: Key('website-languages-entry-${l.code}'),
              color: AppColors.card,
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 4, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(l.nativeName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                        Text('${l.englishName} · ${l.code}', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                        if (isSource) const WebsiteStatusChip(label: 'Source', color: Color(0xFF2E7D5B)),
                        if (l.code == registry.fallbackCode) const WebsiteStatusChip(label: 'Fallback', color: Color(0xFF8A6A33)),
                        if (l.isVisible)
                          WebsiteStatusChip(key: Key('website-languages-visible-${l.code}'), label: 'Shown to visitors', color: const Color(0xFF2E7D5B))
                        else if (l.enabled)
                          const WebsiteStatusChip(label: 'Editors only', color: Color(0xFF6E6E73))
                        else
                          const WebsiteStatusChip(label: 'Off', color: Color(0xFF6E6E73)),
                      ],
                    ),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          const Text('Enabled', style: TextStyle(fontSize: 13)),
                          Switch(
                            key: Key('website-languages-enabled-${l.code}'),
                            value: l.enabled,
                            // Turning a language off also takes it off the public switch.
                            onChanged: isSource ? null : (v) => _update(i, l.copyWith(enabled: v, isPublic: v ? l.isPublic : false)),
                          ),
                        ]),
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          const Text('Public', style: TextStyle(fontSize: 13)),
                          Switch(
                            key: Key('website-languages-public-${l.code}'),
                            value: l.isVisible,
                            onChanged: isSource || !l.enabled ? null : (v) => _update(i, l.copyWith(isPublic: v)),
                          ),
                        ]),
                        IconButton(key: Key('website-languages-up-${l.code}'), tooltip: 'Move up', onPressed: i == 0 ? null : () => _move(i, -1), icon: const Icon(Icons.arrow_upward)),
                        IconButton(
                          key: Key('website-languages-down-${l.code}'),
                          tooltip: 'Move down',
                          onPressed: i == registry.languages.length - 1 ? null : () => _move(i, 1),
                          icon: const Icon(Icons.arrow_downward),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            key: const Key('website-languages-add'),
            onPressed: registry.languages.length >= SiteLanguageRegistry.maxLanguages ? null : _add,
            icon: const Icon(Icons.add),
            label: const Text('Add language'),
          ),
        ),
        const WebsiteEditorSectionTitle('Fallback language'),
        const Text(
          'Shown when text isn’t available in the visitor’s language. English text is always the last resort.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          key: const Key('website-languages-fallback'),
          initialValue: visible.any((l) => l.code == registry.fallbackCode) ? registry.fallbackCode : null,
          decoration: websiteField('Fallback language'),
          items: [
            for (final l in visible) DropdownMenuItem(value: l.code, child: Text('${l.nativeName} (${l.englishName})', key: Key('website-languages-fallback-${l.code}'))),
          ],
          onChanged: (code) {
            if (code != null) setState(() => _registry = _registry.copyWith(fallbackCode: code));
          },
        ),
        const WebsiteEditorSectionTitle('Preview'),
        Text(
          'Editors offer: ${[for (final l in registry.enabled) l.nativeName].join(', ')}',
          key: const Key('website-languages-preview-editors'),
          style: const TextStyle(fontSize: 13),
        ),
        const SizedBox(height: 8),
        Container(
          key: const Key('website-languages-preview'),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(12)),
          child: Row(
            children: [
              const Text('Visitors’ language switch: ', style: TextStyle(fontSize: 13)),
              const SizedBox(width: 8),
              Flexible(
                child: ProviderScope(
                  // A fresh scope per draft: a changed overrideWith isn't
                  // applied to an existing scope.
                  key: ValueKey(registry.toMap().toString()),
                  overrides: [
                    publicLanguagesProvider.overrideWithValue(registry.validationErrors().isEmpty ? registry.publicLanguages : PublicLanguage.builtIn),
                    publicLanguageProvider.overrideWith((ref) => PublicLanguage.english),
                  ],
                  child: const Align(alignment: Alignment.centerLeft, child: PublicLanguageSwitch()),
                ),
              ),
            ],
          ),
        ),
        if (errors.isNotEmpty)
          Container(
            key: const Key('website-languages-errors'),
            margin: const EdgeInsets.only(top: 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFFCEEEE), borderRadius: BorderRadius.circular(10)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Fix before saving:', style: TextStyle(fontWeight: FontWeight.w600)),
                for (final e in errors) Text('• $e', style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            OutlinedButton.icon(
              key: const Key('website-languages-save-draft'),
              onPressed: () => _run(
                () => service.saveLanguageRegistryDraft(requesterRole: role, actor: user, registry: registry),
                live == null ? 'Draft saved. Visitors are still offered English and Tamil.' : 'Draft saved. Visitors still see the published languages.',
              ),
              icon: const Icon(Icons.save_outlined),
              label: const Text('Save draft'),
            ),
            FilledButton.icon(
              key: const Key('website-languages-publish'),
              onPressed: _publish,
              icon: const Icon(Icons.public),
              label: const Text('Publish'),
              style: FilledButton.styleFrom(backgroundColor: AppColors.secondary),
            ),
            if (live != null || _liveUnreadable)
              TextButton.icon(key: const Key('website-languages-unpublish'), onPressed: _unpublish, icon: const Icon(Icons.visibility_off_outlined), label: const Text('Unpublish')),
            TextButton.icon(key: const Key('website-languages-reset'), onPressed: _reset, icon: const Icon(Icons.restart_alt), label: const Text('Start again from initial languages')),
          ],
        ),
      ],
    );
  }
}

class _AddLanguageDialog extends StatefulWidget {
  const _AddLanguageDialog({required this.existing});

  final Set<String> existing;

  @override
  State<_AddLanguageDialog> createState() => _AddLanguageDialogState();
}

class _AddLanguageDialogState extends State<_AddLanguageDialog> {
  final _code = TextEditingController();
  final _nativeName = TextEditingController();
  final _englishName = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    _nativeName.dispose();
    _englishName.dispose();
    super.dispose();
  }

  void _submit() {
    final code = _code.text.trim();
    final codeError = SiteLanguageRegistry.validateCode(code);
    final String? error;
    if (codeError != null) {
      error = codeError;
    } else if (widget.existing.contains(code.toLowerCase())) {
      error = 'This language is already listed.';
    } else if (_nativeName.text.trim().isEmpty) {
      error = 'Enter the language’s own name.';
    } else if (_nativeName.text.trim().length > SiteLanguageRegistry.maxNameLength || _englishName.text.trim().length > SiteLanguageRegistry.maxNameLength) {
      error = 'Names must be ${SiteLanguageRegistry.maxNameLength} characters or fewer.';
    } else {
      error = null;
    }
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    // New languages start off: enable them, and make them public, when ready.
    Navigator.pop(
      context,
      SiteLanguage(code: code, nativeName: _nativeName.text.trim(), englishName: _englishName.text.trim().isEmpty ? code : _englishName.text.trim()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add language'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(key: const Key('website-languages-new-code'), controller: _code, decoration: websiteField('Language code', hint: 'for example bn or pt-BR')),
            const SizedBox(height: 8),
            TextField(key: const Key('website-languages-new-native'), controller: _nativeName, decoration: websiteField('Name in the language itself', hint: 'for example বাংলা')),
            const SizedBox(height: 8),
            TextField(key: const Key('website-languages-new-english'), controller: _englishName, decoration: websiteField('English name', hint: 'for example Bengali')),
            const SizedBox(height: 8),
            const Text('A new language starts off. Enable it, and make it public, when it is ready.', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, key: const Key('website-languages-new-error'), style: const TextStyle(color: Color(0xFFB3261E), fontSize: 13)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(key: const Key('website-languages-new-save'), onPressed: _submit, child: const Text('Add')),
      ],
    );
  }
}
