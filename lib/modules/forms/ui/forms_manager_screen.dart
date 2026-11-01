import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../admin/settings/data/public_submission_settings_service.dart';
import '../../admin/settings/models/school_settings_model.dart';
import '../../admin/settings/ui/access_restricted_view.dart';
import '../../admin/settings/ui/public_submissions_settings_screen.dart';
import '../../admin/website/ui/website_content_screen.dart';
import '../../auth/models/app_user.dart';
import '../../auth/providers/auth_provider.dart';
import '../../public_website/public_strings.dart';
import '../data/csv_download.dart';
import '../data/form_submissions_inbox_service.dart';
import '../data/website_forms_service.dart';
import '../models/public_submission_settings.dart';
import '../models/website_form.dart';
import '../public/public_forms_repository.dart';
import '../../public_website/content/website_content_models.dart';
import 'form_builder_screen.dart';
import 'public_website_form.dart';

/// Settings → Website forms: the Forms Library (create from a template,
/// edit, duplicate, preview, activate, deactivate) and the private
/// Submissions Inbox. Admin only: anyone else sees the locked view, and
/// every service call re-checks the role and the school.
class FormsManagerScreen extends ConsumerWidget {
  const FormsManagerScreen({super.key, this.forms, this.inbox, this.initialTab = 0, this.publicSubmissions});

  final WebsiteFormsService? forms;
  final FormSubmissionsInboxService? inbox;

  /// Whether visitors can send forms (Settings → Public form submissions).
  final PublicSubmissionSettingsService? publicSubmissions;

  /// 0: Forms library, 1: Submissions.
  final int initialTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (user == null || user.role.toLowerCase() != 'admin') {
      return Scaffold(backgroundColor: Colors.grey[50], appBar: AppBar(title: const Text('Website forms')), body: const AccessRestrictedView());
    }
    return DefaultTabController(
      length: 2,
      initialIndex: initialTab.clamp(0, 1),
      child: Scaffold(
        backgroundColor: Colors.grey[50],
        appBar: AppBar(
          title: const Text('Website forms'),
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [Tab(key: Key('forms-tab-library'), text: 'Forms library'), Tab(key: Key('forms-tab-inbox'), text: 'Submissions')],
          ),
        ),
        body: TabBarView(children: [
          _LibraryTab(service: forms ?? WebsiteFormsService(), user: user, publicSubmissions: publicSubmissions),
          _InboxTab(service: inbox ?? FormSubmissionsInboxService(), forms: forms ?? WebsiteFormsService(), user: user),
        ]),
      ),
    );
  }
}

void _snack(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: error ? Colors.red.shade700 : null));
}

String _errorText(Object e) => e is FormsException || e is FormsUnauthorizedException ? e.toString() : 'Something went wrong. Please try again.';

String _when(DateTime? d) {
  if (d == null) return '—';
  final l = d.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(l.day)}/${two(l.month)}/${l.year} ${two(l.hour)}:${two(l.minute)}';
}

/// Shows [form] (a draft or the active version) as visitors would see it,
/// at a desktop's, tablet's or phone's width; nothing is sent. [media]:
/// the images visitors may see (by id).
Future<void> showFormPreview(BuildContext context, PublicWebsiteForm form, {Map<String, WebsiteMedia> media = const {}, FormPreviewDevice device = FormPreviewDevice.desktop}) {
  var current = device;
  return showDialog<void>(
    context: context,
    // A plain Dialog: an AlertDialog measures its content's intrinsic
    // size, which the form's responsive layout can't report.
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final screen = MediaQuery.sizeOf(context);
        final width = current.width.clamp(200.0, (screen.width - 112).clamp(200.0, double.infinity));
        return Dialog(
          key: const Key('forms-preview-dialog'),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: screen.height - 96, maxWidth: width + 48),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(form.title.en.isEmpty ? 'Preview' : 'Preview: ${form.title.en}', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SegmentedButton<FormPreviewDevice>(
                      showSelectedIcon: false,
                      segments: [for (final d in FormPreviewDevice.values) ButtonSegment(value: d, icon: Icon(d.icon, size: 18), label: Text(d.label, key: Key('forms-preview-device-${d.name}')))],
                      selected: {current},
                      onSelectionChanged: (s) => setState(() => current = s.first),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Center(
                        child: SizedBox(
                          key: Key('forms-preview-frame-${current.name}'),
                          width: width,
                          child: MediaQuery(
                            data: MediaQuery.of(context).copyWith(size: Size(width, screen.height)),
                            child: PublicWebsiteFormView(form: form, language: PublicLanguage.english, interactive: false, media: media),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(key: const Key('forms-preview-close'), onPressed: () => Navigator.pop(context), child: const Text('Close')),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

/// Asks before making a form public; true to go ahead.
Future<bool> confirmActivateForm(BuildContext context, {required bool replacing}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(replacing ? 'Activate these changes?' : 'Activate this form?'),
        content: Text(replacing
            ? 'Visitors will see this version straight away on every page with this form, instead of the active one. Earlier responses keep their own version.'
            : 'Visitors will see this form on every page that includes it, and can send responses.'),
        actions: [
          TextButton(key: const Key('forms-activate-cancel'), onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(key: const Key('forms-activate-confirm'), onPressed: () => Navigator.pop(context, true), child: const Text('Activate')),
        ],
      ),
    ) ==
    true;

class _LibraryTab extends ConsumerStatefulWidget {
  const _LibraryTab({required this.service, required this.user, this.publicSubmissions});

  final WebsiteFormsService service;
  final AppUser user;
  final PublicSubmissionSettingsService? publicSubmissions;

  @override
  ConsumerState<_LibraryTab> createState() => _LibraryTabState();
}

class _LibraryTabState extends ConsumerState<_LibraryTab> {
  List<ManagedForm>? _forms;
  List<WebsiteMedia> _library = const [];
  Object? _error;
  String _search = '';
  WebsiteFormStatus? _status;
  bool _busy = false;

  String get _role => widget.user.role.toLowerCase();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final forms = await widget.service.listForms(requesterRole: _role);
      final library = await widget.service.mediaLibrary(requesterRole: _role);
      if (mounted) setState(() => (_forms = forms, _library = library, _error = null));
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    try {
      await action();
      ref.invalidate(publicWebsiteFormProvider);
      ref.invalidate(activeWebsiteFormsProvider);
      if (mounted) _snack(context, done);
    } catch (e) {
      if (mounted) _snack(context, _errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
      await _load();
    }
  }

  Future<void> _open(String formId) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => FormBuilderScreen(service: widget.service, user: widget.user, formId: formId)));
    await _load();
  }

  Future<void> _create() async {
    final template = await showDialog<FormTemplate>(
      context: context,
      builder: (context) => SimpleDialog(
        key: const Key('forms-template-dialog'),
        title: const Text('Start from a template'),
        children: [
          for (final t in FormTemplate.all)
            SimpleDialogOption(
              key: Key('forms-template-${t.id}'),
              onPressed: () => Navigator.pop(context, t),
              child: ListTile(contentPadding: EdgeInsets.zero, title: Text(t.name), subtitle: Text(t.description)),
            ),
        ],
      ),
    );
    if (template == null || !mounted) return;
    WebsiteForm? created;
    await _run(() async => created = await widget.service.createFromTemplate(requesterRole: _role, actor: widget.user, templateId: template.id), 'Draft created. It isn’t on the website until you activate it.');
    if (created != null && mounted) await _open(created!.id);
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null && _forms == null) {
      return Center(
        key: const Key('forms-load-error'),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('The forms couldn’t be loaded. ${_errorText(_error!)}', textAlign: TextAlign.center),
          TextButton(onPressed: _load, child: const Text('Try again')),
        ]),
      );
    }
    final forms = _forms;
    if (forms == null) return const Center(child: CircularProgressIndicator());
    final words = _search.trim().toLowerCase();
    final shown = [
      for (final f in forms)
        if ((_status == null || f.form.status == _status) && (words.isEmpty || f.form.title.en.toLowerCase().contains(words))) f,
    ];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Forms visitors can fill in on the website. A form is shown only on pages with a Form block, and only once it is active. '
          'Saving changes never changes what visitors see until you activate them.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 12),
        _PublicSubmissionsLine(service: widget.publicSubmissions ?? PublicSubmissionSettingsService(), user: widget.user),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 260,
              child: TextField(
                key: const Key('forms-search'),
                decoration: const InputDecoration(isDense: true, prefixIcon: Icon(Icons.search), hintText: 'Search by title', border: OutlineInputBorder()),
                onChanged: (v) => setState(() => _search = v),
              ),
            ),
            DropdownButton<WebsiteFormStatus?>(
              key: const Key('forms-status-filter'),
              value: _status,
              items: [
                const DropdownMenuItem(value: null, child: Text('All statuses')),
                for (final s in WebsiteFormStatus.values) DropdownMenuItem(value: s, child: Text(s.label)),
              ],
              onChanged: (s) => setState(() => _status = s),
            ),
            FilledButton.icon(key: const Key('forms-new'), onPressed: _busy ? null : _create, icon: const Icon(Icons.add), label: const Text('New form')),
          ],
        ),
        const SizedBox(height: 12),
        if (shown.isEmpty)
          Padding(
            key: const Key('forms-empty'),
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Text(forms.isEmpty ? 'No forms yet. Start one from a template.' : 'No form matches.', textAlign: TextAlign.center),
          ),
        for (final entry in shown) _card(entry),
      ],
    );
  }

  Widget _card(ManagedForm entry) {
    final form = entry.form;
    final live = entry.live;
    final changed = form.status == WebsiteFormStatus.active && live != null && !form.toPublic(live.version).sameSchemaAs(live);
    final statusColor = switch (form.status) {
      WebsiteFormStatus.active => const Color(0xFF2E7D5B),
      WebsiteFormStatus.inactive => const Color(0xFF8A6A33),
      WebsiteFormStatus.draft => const Color(0xFF6E6E73),
    };
    return Card(
      key: Key('forms-card-${form.id}'),
      color: AppColors.card,
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(form.title.en.isEmpty ? 'Untitled form' : form.title.en, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                WebsiteStatusChip(key: Key('forms-status-${form.id}'), label: form.status.label, color: statusColor),
                if (live != null) WebsiteStatusChip(label: 'Visitors see version ${live.version}', color: const Color(0xFF2E7D5B)),
                if (changed) WebsiteStatusChip(key: Key('forms-changed-${form.id}'), label: 'Changes not active', color: const Color(0xFF8A6A33)),
                if (_coverWarning(form, live) case final warning?) WebsiteStatusChip(key: Key('forms-cover-warning-${form.id}'), label: warning, color: const Color(0xFFB3261E)),
                Text('${form.fields.length} field${form.fields.length == 1 ? '' : 's'} · updated ${_when(form.updatedAt)}', style: const TextStyle(fontSize: 12)),
              ],
            ),
            if (form.internalDescription.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(form.internalDescription, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
            ],
            Wrap(
              spacing: 4,
              children: [
                TextButton.icon(key: Key('forms-edit-${form.id}'), onPressed: _busy ? null : () => _open(form.id), icon: const Icon(Icons.edit_outlined, size: 18), label: const Text('Edit')),
                TextButton.icon(
                  key: Key('forms-preview-${form.id}'),
                  onPressed: () => showFormPreview(context, form.toPublic(form.version), media: {for (final m in _library) if (WebsiteFormsService.imageProblem(m) == null) m.id: m}),
                  icon: const Icon(Icons.visibility_outlined, size: 18),
                  label: const Text('Preview'),
                ),
                TextButton.icon(
                  key: Key('forms-duplicate-${form.id}'),
                  onPressed: _busy ? null : () => _run(() => widget.service.duplicate(requesterRole: _role, actor: widget.user, formId: form.id), 'Duplicated as a draft.'),
                  icon: const Icon(Icons.copy_outlined, size: 18),
                  label: const Text('Duplicate'),
                ),
                if (form.status != WebsiteFormStatus.active || changed)
                  TextButton.icon(
                    key: Key('forms-activate-${form.id}'),
                    onPressed: _busy
                        ? null
                        : () async {
                            if (!await confirmActivateForm(context, replacing: live != null)) return;
                            await _run(() => widget.service.activate(requesterRole: _role, actor: widget.user, formId: form.id), 'Active: visitors can see and submit it.');
                          },
                    icon: const Icon(Icons.public, size: 18),
                    label: Text(changed ? 'Activate changes' : 'Activate'),
                  ),
                if (form.status == WebsiteFormStatus.active)
                  TextButton.icon(
                    key: Key('forms-deactivate-${form.id}'),
                    onPressed: _busy
                        ? null
                        : () => _run(() => widget.service.deactivate(requesterRole: _role, actor: widget.user, formId: form.id), 'Deactivated. Its responses are kept.'),
                    icon: const Icon(Icons.public_off, size: 18),
                    label: const Text('Deactivate'),
                    style: TextButton.styleFrom(foregroundColor: const Color(0xFFB3261E)),
                  ),
                TextButton.icon(
                  key: Key('forms-delete-${form.id}'),
                  onPressed: _busy ? null : () => _delete(form),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Delete'),
                  style: TextButton.styleFrom(foregroundColor: const Color(0xFFB3261E)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// A warning when the cover image is missing or can't be shown: the
  /// active version's (visitors then see the form without it) first.
  String? _coverWarning(WebsiteForm form, PublicWebsiteForm? live) {
    WebsiteMedia? find(String? id) => _library.where((m) => m.id == id).firstOrNull;
    if (live?.coverMediaId case final id? when WebsiteFormsService.imageProblem(find(id)) != null) return 'Cover image not shown to visitors';
    if (form.coverMediaId == null) return 'No cover image';
    if (WebsiteFormsService.imageProblem(find(form.coverMediaId)) != null) return 'Cover image unavailable';
    return null;
  }

  /// Deletes [form] once the admin types its title. Pages showing it are
  /// listed first; its submissions are kept.
  Future<void> _delete(WebsiteForm form) async {
    Set<String> pages;
    try {
      pages = await widget.service.formReferences(requesterRole: _role, formId: form.id);
    } catch (e) {
      if (mounted) _snack(context, _errorText(e), error: true);
      return;
    }
    if (!mounted) return;
    final phrase = WebsiteFormsService.deleteConfirmation(form);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _DeleteFormDialog(phrase: phrase, pages: pages, active: form.status == WebsiteFormStatus.active),
    );
    if (confirmed != true || !mounted) return;
    await _run(
      () => widget.service.deleteForm(requesterRole: _role, actor: widget.user, formId: form.id, confirmTitle: phrase),
      'Deleted “$phrase”. Its submissions are kept in Submissions.',
    );
  }
}

class _DeleteFormDialog extends StatefulWidget {
  const _DeleteFormDialog({required this.phrase, required this.pages, required this.active});

  final String phrase;
  final Set<String> pages;
  final bool active;

  @override
  State<_DeleteFormDialog> createState() => _DeleteFormDialogState();
}

class _DeleteFormDialogState extends State<_DeleteFormDialog> {
  String _typed = '';

  @override
  Widget build(BuildContext context) => AlertDialog(
        key: const Key('forms-delete-dialog'),
        title: Text('Delete “${widget.phrase}”?'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.active) const Text('It is taken off the website first.'),
              const Text('Its submissions and internal notes are kept, and stay readable and searchable in Submissions. This can’t be undone.'),
              if (widget.pages.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'These pages have a Form block showing it: ${widget.pages.join(', ')}. Visitors will see nothing there; choose another form in those blocks, or remove them.',
                  key: const Key('forms-delete-pages'),
                  style: const TextStyle(color: Color(0xFF8A6A33)),
                ),
              ],
              const SizedBox(height: 12),
              Text('Type “${widget.phrase}” to confirm.'),
              const SizedBox(height: 6),
              TextField(key: const Key('forms-delete-confirm-input'), autofocus: true, decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true), onChanged: (v) => setState(() => _typed = v)),
            ],
          ),
        ),
        actions: [
          TextButton(key: const Key('forms-delete-cancel'), onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            key: const Key('forms-delete-confirm'),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB3261E)),
            onPressed: _typed.trim() == widget.phrase ? () => Navigator.pop(context, true) : null,
            child: const Text('Delete form'),
          ),
        ],
      );
}

// ------------------------------------------------------------ inbox

/// Rows per page of the inbox.
const submissionsPageSize = 20;

enum _Period {
  all('All time', null),
  today('Today', 0),
  week('Last 7 days', 7),
  month('Last 30 days', 30);

  const _Period(this.label, this.days);

  final String label;
  final int? days;
}

class _InboxTab extends StatefulWidget {
  const _InboxTab({required this.service, required this.forms, required this.user});

  final FormSubmissionsInboxService service;
  final WebsiteFormsService forms;
  final AppUser user;

  @override
  State<_InboxTab> createState() => _InboxTabState();
}

class _InboxTabState extends State<_InboxTab> {
  List<FormSubmission>? _all;

  /// Ids of deleted forms (their submissions are kept).
  Set<String> _deleted = const {};
  Object? _error;
  String _search = '';
  String? _formId;
  FormSubmissionStatus? _status;
  _Period _period = _Period.all;
  int _page = 0;

  String get _role => widget.user.role.toLowerCase();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final all = await widget.service.listSubmissions(requesterRole: _role);
      final deleted = await widget.forms.deletedForms(requesterRole: _role);
      if (mounted) setState(() => (_all = all, _deleted = {for (final d in deleted) d.formId}, _error = null));
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  SubmissionsQuery get _query {
    final now = DateTime.now();
    final days = _period.days;
    return SubmissionsQuery(
      search: _search,
      formId: _formId,
      status: _status,
      from: days == null ? null : DateTime(now.year, now.month, now.day).subtract(Duration(days: days)),
    );
  }

  void _export(List<FormSubmission> rows) {
    final csv = FormSubmissionsInboxService.toCsv(rows);
    final ok = downloadCsv('website-form-submissions.csv', csv);
    _snack(context, ok ? 'Exported ${rows.length} submission${rows.length == 1 ? '' : 's'} (without internal notes).' : 'CSV export is available in the web app.', error: !ok);
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null && _all == null) {
      return Center(
        key: const Key('inbox-load-error'),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Submissions couldn’t be loaded. ${_errorText(_error!)}', textAlign: TextAlign.center),
          TextButton(key: const Key('inbox-retry'), onPressed: _load, child: const Text('Try again')),
        ]),
      );
    }
    final all = _all;
    if (all == null) return const Center(child: CircularProgressIndicator());
    final forms = <String, String>{for (final s in all) s.formId: s.formTitle};
    final matching = _query.apply(all);
    final pages = (matching.length / submissionsPageSize).ceil();
    final page = pages == 0 ? 0 : _page.clamp(0, pages - 1);
    final shown = matching.skip(page * submissionsPageSize).take(submissionsPageSize).toList();
    void set(VoidCallback change) => setState(() {
          change();
          _page = 0;
        });
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Responses sent from the website’s forms. Only administrators can see them, their status and internal notes.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 260,
                child: TextField(
                  key: const Key('inbox-search'),
                  decoration: const InputDecoration(isDense: true, prefixIcon: Icon(Icons.search), hintText: 'Search reference or answers', border: OutlineInputBorder()),
                  onChanged: (v) => set(() => _search = v),
                ),
              ),
              DropdownButton<String?>(
                key: const Key('inbox-form-filter'),
                value: _formId,
                items: [
                  const DropdownMenuItem(value: null, child: Text('All forms')),
                  for (final e in forms.entries) DropdownMenuItem(value: e.key, child: Text('${e.value.isEmpty ? e.key : e.value}${_deleted.contains(e.key) ? ' (deleted)' : ''}')),
                ],
                onChanged: (v) => set(() => _formId = v),
              ),
              DropdownButton<FormSubmissionStatus?>(
                key: const Key('inbox-status-filter'),
                value: _status,
                items: [
                  const DropdownMenuItem(value: null, child: Text('All statuses')),
                  for (final s in FormSubmissionStatus.values) DropdownMenuItem(value: s, child: Text(s.label)),
                ],
                onChanged: (v) => set(() => _status = v),
              ),
              DropdownButton<_Period>(
                key: const Key('inbox-period-filter'),
                value: _period,
                items: [for (final p in _Period.values) DropdownMenuItem(value: p, child: Text(p.label))],
                onChanged: (v) => set(() => _period = v ?? _Period.all),
              ),
              OutlinedButton.icon(
                key: const Key('inbox-export'),
                onPressed: matching.isEmpty ? null : () => _export(matching),
                icon: const Icon(Icons.download_outlined, size: 18),
                label: Text('Export CSV (${matching.length})'),
              ),
              IconButton(key: const Key('inbox-refresh'), tooltip: 'Refresh', onPressed: _load, icon: const Icon(Icons.refresh)),
            ],
          ),
          const SizedBox(height: 12),
          if (shown.isEmpty)
            Padding(
              key: const Key('inbox-empty'),
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Text(all.isEmpty ? 'No submissions yet.' : 'No submission matches these filters.', textAlign: TextAlign.center),
            ),
          for (final s in shown)
            Card(
              key: Key('inbox-row-${s.id}'),
              color: AppColors.card,
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text('${s.reference} · ${s.formTitle}', style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                  '${_when(s.createdAt)} · version ${s.formVersion}${s.fields.isEmpty ? '' : ' · ${s.answerText(s.fields.first)}'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Wrap(
                  spacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (_deleted.contains(s.formId)) WebsiteStatusChip(key: Key('inbox-deleted-${s.id}'), label: 'Form deleted', color: const Color(0xFF6E6E73)),
                    WebsiteStatusChip(key: Key('inbox-status-${s.id}'), label: s.status.label, color: _statusColor(s.status)),
                  ],
                ),
                onTap: () async {
                  await Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => SubmissionDetailScreen(service: widget.service, user: widget.user, submissionId: s.id, formDeleted: _deleted.contains(s.formId)),
                  ));
                  await _load();
                },
              ),
            ),
          if (matching.isNotEmpty)
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text('${page * submissionsPageSize + 1}–${page * submissionsPageSize + shown.length} of ${matching.length}', key: const Key('inbox-page-label')),
                IconButton(key: const Key('inbox-prev'), onPressed: page == 0 ? null : () => setState(() => _page = page - 1), icon: const Icon(Icons.chevron_left)),
                IconButton(key: const Key('inbox-next'), onPressed: page >= pages - 1 ? null : () => setState(() => _page = page + 1), icon: const Icon(Icons.chevron_right)),
              ],
            ),
        ],
      ),
    );
  }
}

Color _statusColor(FormSubmissionStatus s) => switch (s) {
      FormSubmissionStatus.newSubmission => AppColors.primary,
      FormSubmissionStatus.contacted || FormSubmissionStatus.inProgress => const Color(0xFF8A6A33),
      FormSubmissionStatus.closed => const Color(0xFF2E7D5B),
      FormSubmissionStatus.spam => const Color(0xFF6E6E73),
    };

/// One submission: its answers (labelled as the form was when it was
/// sent), reference, times, status and internal notes.
class SubmissionDetailScreen extends StatefulWidget {
  const SubmissionDetailScreen({super.key, required this.service, required this.user, required this.submissionId, this.formDeleted = false});

  final FormSubmissionsInboxService service;
  final AppUser user;
  final String submissionId;

  /// Its form has since been deleted (the answers stay readable from their
  /// snapshot).
  final bool formDeleted;

  @override
  State<SubmissionDetailScreen> createState() => _SubmissionDetailScreenState();
}

class _SubmissionDetailScreenState extends State<SubmissionDetailScreen> {
  FormSubmission? _submission;
  List<SubmissionNote> _notes = const [];
  Object? _error;
  bool _busy = false;
  final _note = TextEditingController();

  String get _role => widget.user.role.toLowerCase();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final s = await widget.service.getSubmission(requesterRole: _role, submissionId: widget.submissionId);
      final notes = await widget.service.listNotes(requesterRole: _role, submissionId: widget.submissionId);
      if (mounted) setState(() => (_submission = s, _notes = notes, _error = null));
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) _snack(context, done);
    } catch (e) {
      if (mounted) _snack(context, _errorText(e), error: true);
    } finally {
      await _load();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _submission;
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(title: Text(s?.reference ?? 'Submission')),
      body: _error != null && s == null
          ? Center(key: const Key('submission-error'), child: Text(_errorText(_error!)))
          : s == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  key: const Key('submission-detail'),
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(s.formTitle, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text('Reference ${s.reference} · form version ${s.formVersion}', key: const Key('submission-reference')),
                    if (widget.formDeleted)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: WebsiteStatusChip(key: Key('submission-form-deleted'), label: 'This form has been deleted; the answers are as submitted', color: Color(0xFF6E6E73)),
                      ),
                    Text('Submitted ${_when(s.createdAt)} · last changed ${_when(s.updatedAt)}', style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<FormSubmissionStatus>(
                      key: const Key('submission-status'),
                      initialValue: s.status,
                      decoration: const InputDecoration(labelText: 'Status', border: OutlineInputBorder()),
                      items: [for (final st in FormSubmissionStatus.values) DropdownMenuItem(value: st, child: Text(st.label))],
                      onChanged: _busy
                          ? null
                          : (v) {
                              if (v == null || v == s.status) return;
                              _run(() => widget.service.setStatus(requesterRole: _role, actor: widget.user, submissionId: s.id, status: v), 'Status set to ${v.label}.');
                            },
                    ),
                    const Divider(height: 32),
                    for (final f in s.fields)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(f.label.en, style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                            SelectableText(s.answerText(f).isEmpty ? '—' : s.answerText(f), key: Key('submission-answer-${f.id}')),
                          ],
                        ),
                      ),
                    const Divider(height: 32),
                    const Text('Internal notes (administrators only)', style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    if (_notes.isEmpty) const Text('No notes yet.', style: TextStyle(color: AppColors.textSecondary)),
                    for (final n in _notes)
                      ListTile(
                        key: Key('submission-note-${n.id}'),
                        contentPadding: EdgeInsets.zero,
                        title: Text(n.text),
                        subtitle: Text('${n.authorName} · ${_when(n.createdAt)}'),
                      ),
                    TextField(
                      key: const Key('submission-note-input'),
                      controller: _note,
                      maxLength: FormLimits.maxNote,
                      minLines: 2,
                      maxLines: 6,
                      decoration: const InputDecoration(labelText: 'Add a note', border: OutlineInputBorder()),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton(
                        key: const Key('submission-note-add'),
                        onPressed: _busy
                            ? null
                            : () async {
                                final text = _note.text;
                                await _run(() => widget.service.addNote(requesterRole: _role, actor: widget.user, submissionId: s.id, text: text), 'Note added.');
                                if (mounted && _notes.any((n) => n.text == text.trim())) _note.clear();
                              },
                        child: const Text('Add note'),
                      ),
                    ),
                  ],
                ),
    );
  }
}

/// Whether visitors can send forms now, with a way to change it
/// (Settings → Public form submissions).
class _PublicSubmissionsLine extends ConsumerStatefulWidget {
  const _PublicSubmissionsLine({required this.service, required this.user});

  final PublicSubmissionSettingsService service;
  final AppUser user;

  @override
  ConsumerState<_PublicSubmissionsLine> createState() => _PublicSubmissionsLineState();
}

class _PublicSubmissionsLineState extends ConsumerState<_PublicSubmissionsLine> {
  PublicSubmissionSettings? _saved;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final saved = await widget.service.load(schoolId: kDefaultSchoolId, requesterRole: widget.user.role, requesterSchoolId: kDefaultSchoolId);
      if (mounted) {
        setState(() {
          _saved = saved;
          _failed = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final saved = _saved;
    final text = _failed
        ? 'Public submissions: couldn’t be checked (treated as off).'
        : saved == null
            ? 'Public submissions: checking…'
            : saved.enabled
                ? 'Public submissions are on: visitors can send the active forms.'
                : 'Public submissions are off: visitors see the forms but can’t send them.';
    return Container(
      key: const Key('forms-public-submissions'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade300)),
      child: Row(
        children: [
          Icon(saved?.enabled == true ? Icons.check_circle_outline : Icons.info_outline, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13, color: AppColors.textPrimary))),
          TextButton(
            key: const Key('forms-public-submissions-change'),
            onPressed: () async {
              await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PublicSubmissionsSettingsScreen(service: widget.service)));
              _load();
            },
            child: const Text('Change'),
          ),
        ],
      ),
    );
  }
}
