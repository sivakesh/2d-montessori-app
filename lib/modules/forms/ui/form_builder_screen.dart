import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../admin/website/ui/page_builder/website_visual_editor.dart' show narrowEditorWidth;
import '../../admin/website/ui/website_content_editors.dart' show showWebsiteImagePicker, websiteField;
import '../../admin/website/ui/website_content_screen.dart';
import '../../auth/models/app_user.dart';
import '../../public_website/content/website_content_models.dart';
import '../../public_website/public_strings.dart';
import '../../public_website/public_website_theme.dart';
import '../data/website_forms_service.dart';
import '../models/website_form.dart';
import '../public/public_forms_repository.dart';
import 'forms_manager_screen.dart';
import 'public_website_form.dart';

/// The widths the canvas and preview show a form at.
enum FormPreviewDevice {
  desktop('Desktop', Icons.desktop_windows_outlined, 960),
  tablet('Tablet', Icons.tablet_mac_outlined, 768),
  phone('Phone', Icons.smartphone_outlined, 390);

  const FormPreviewDevice(this.label, this.icon, this.width);

  final String label;
  final IconData icon;
  final double width;
}

enum _Panel { canvas, structure, edit }

/// The visual form builder, laid out like the website's page builder
/// (`WebsiteVisualEditor`):
///
/// - **Structure** (left): the form's questions and content in order —
///   select, drag to reorder (or move up and down), duplicate and remove
///   them, and add questions, section headings, text, images and dividers
///   after the selected item.
/// - **Canvas** (centre): the form as visitors see it, drawn by the public
///   renderer ([PublicWebsiteFormView]) at a desktop's, tablet's or phone's
///   width; click any item (or the cover and title) to select it.
/// - **Properties** (right): the selected item's settings, or — with
///   nothing selected — the form's title, description, cover image,
///   success message, internal description and version history.
///
/// All three panels from [narrowEditorWidth]; narrower, one at a time
/// (Form, Structure, Edit). Every item keeps its id when it is moved or
/// edited. Save keeps a draft (visitors see no change); Activate makes
/// the saved form the version visitors see. Leaving with unsaved edits
/// asks first.
class FormBuilderScreen extends ConsumerStatefulWidget {
  const FormBuilderScreen({super.key, required this.service, required this.user, required this.formId});

  final WebsiteFormsService service;
  final AppUser user;
  final String formId;

  @override
  ConsumerState<FormBuilderScreen> createState() => _FormBuilderScreenState();
}

class _FormBuilderScreenState extends ConsumerState<FormBuilderScreen> {
  ManagedForm? _loaded;
  WebsiteForm? _form;
  List<WebsiteMedia> _library = const [];
  List<FormVersionRecord> _versions = const [];
  Object? _error;
  bool _busy = false;
  String? _selectedId;
  FormPreviewDevice _device = FormPreviewDevice.desktop;
  _Panel _panel = _Panel.canvas;

  /// Bumped when the form is reloaded, so text fields show the stored text.
  int _generation = 0;

  String get _role => widget.user.role.toLowerCase();
  bool get _unsaved => _form != null && _loaded != null && !_sameContent(_form!, _loaded!.form);

  static bool _sameContent(WebsiteForm a, WebsiteForm b) => a.toContentMap().toString() == b.toContentMap().toString();

  /// The images visitors may see, by id.
  Map<String, WebsiteMedia> get _eligible => {for (final m in _library) if (WebsiteFormsService.imageProblem(m) == null) m.id: m};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final loaded = await widget.service.getForm(requesterRole: _role, formId: widget.formId);
      final library = await widget.service.mediaLibrary(requesterRole: _role);
      final versions = await widget.service.versionHistory(requesterRole: _role, formId: widget.formId);
      if (!mounted) return;
      setState(() {
        _loaded = loaded;
        _form = loaded?.form;
        _library = library;
        _versions = versions;
        _error = loaded == null ? FormsException('This form no longer exists.') : null;
        if (_selectedId != null && !(loaded?.form.items.any((i) => i.id == _selectedId) ?? false)) _selectedId = null;
        _generation++;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _edit(WebsiteForm Function(WebsiteForm f) change) => setState(() => _form = change(_form!));

  void _editItem(String id, FormItem Function(FormItem i) change) => _edit((f) => f.copyWith(items: [for (final i in f.items) i.id == id ? change(i) : i]));

  void _select(String? id) => setState(() => _selectedId = id);

  int get _insertAt {
    final i = _form!.items.indexWhere((x) => x.id == _selectedId);
    return i < 0 ? _form!.items.length : i + 1;
  }

  void _insert(FormItem item) => setState(() {
        _form = _form!.copyWith(items: [..._form!.items]..insert(_insertAt, item));
        _selectedId = item.id;
      });

  void _move(int from, int to) {
    final items = [..._form!.items];
    if (to < 0 || to >= items.length || from == to) return;
    final item = items.removeAt(from);
    items.insert(to, item);
    _edit((f) => f.copyWith(items: items));
  }

  void _duplicate(int index) => setState(() {
        final copy = _form!.items[index].withFreshIds();
        _form = _form!.copyWith(items: [..._form!.items]..insert(index + 1, copy));
        _selectedId = copy.id;
      });

  void _remove(int index) => setState(() {
        final items = [..._form!.items];
        final removed = items.removeAt(index);
        _form = _form!.copyWith(items: items);
        if (_selectedId == removed.id) _selectedId = null;
      });

  Future<bool> _run(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    try {
      await action();
      ref.invalidate(publicWebsiteFormProvider);
      ref.invalidate(activeWebsiteFormsProvider);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e is FormsException || e is FormsUnauthorizedException ? e.toString() : 'Something went wrong. Please try again.'),
          backgroundColor: Colors.red.shade700,
        ));
      }
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final form = _form!;
    if (await _run(() => widget.service.saveDraft(requesterRole: _role, actor: widget.user, form: form),
        _loaded?.live == null ? 'Saved. It isn’t on the website until you activate it.' : 'Saved. Visitors still see the active version until you activate these changes.')) {
      await _load();
    }
  }

  Future<void> _activate() async {
    final form = _form!;
    if (form.problems(complete: true).isNotEmpty) return;
    if (!await confirmActivateForm(context, replacing: _loaded?.live != null)) return;
    // What is activated is what is stored: save first.
    final ok = await _run(() async {
      await widget.service.saveDraft(requesterRole: _role, actor: widget.user, form: form);
      await widget.service.activate(requesterRole: _role, actor: widget.user, formId: form.id);
    }, 'Active: visitors can see and submit this version.');
    if (ok) await _load();
  }

  Future<bool> _confirmLeave() async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          key: const Key('builder-leave-dialog'),
          title: const Text('Leave without saving?'),
          content: const Text('Your changes to this form haven’t been saved, and will be lost.'),
          actions: [
            TextButton(key: const Key('builder-leave-cancel'), onPressed: () => Navigator.pop(context, false), child: const Text('Keep editing')),
            FilledButton(key: const Key('builder-leave-confirm'), onPressed: () => Navigator.pop(context, true), child: const Text('Leave')),
          ],
        ),
      ) ==
      true;

  @override
  Widget build(BuildContext context) {
    final form = _form;
    return PopScope(
      canPop: !_unsaved,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave() && context.mounted) {
          setState(() => _form = _loaded?.form);
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.grey[50],
        appBar: AppBar(title: Text(form == null || form.title.en.isEmpty ? 'Edit form' : form.title.en)),
        body: _error != null && form == null
            ? Center(key: const Key('builder-error'), child: Text(_error.toString()))
            : form == null
                ? const Center(child: CircularProgressIndicator())
                : _body(form),
      ),
    );
  }

  Widget _body(WebsiteForm form) {
    final live = _loaded?.live;
    final problems = form.problems(complete: true);
    final changedFromLive = live != null && !form.toPublic(live.version).sameSchemaAs(live);
    final toolbar = Material(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            WebsiteStatusChip(key: const Key('builder-status'), label: form.status.label, color: form.status == WebsiteFormStatus.active ? const Color(0xFF2E7D5B) : const Color(0xFF6E6E73)),
            if (live != null) WebsiteStatusChip(label: 'Visitors see version ${live.version}', color: const Color(0xFF2E7D5B)),
            if (changedFromLive) const WebsiteStatusChip(key: Key('builder-changed'), label: 'Changes not active', color: Color(0xFF8A6A33)),
            if (_unsaved) const WebsiteStatusChip(key: Key('builder-unsaved'), label: 'Unsaved edits', color: Color(0xFFB3261E)),
            if (problems.isNotEmpty) WebsiteStatusChip(key: const Key('builder-fix-count'), label: '${problems.length} to fix', color: const Color(0xFFB3261E)),
            OutlinedButton.icon(key: const Key('builder-save'), onPressed: _busy || !_unsaved ? null : _save, icon: const Icon(Icons.save_outlined), label: const Text('Save draft')),
            OutlinedButton.icon(
              key: const Key('builder-preview'),
              onPressed: () => showFormPreview(context, form.toPublic(form.version), media: _eligible, device: _device),
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('Preview'),
            ),
            FilledButton.icon(
              key: const Key('builder-activate'),
              onPressed: _busy || problems.isNotEmpty || (form.status == WebsiteFormStatus.active && !changedFromLive && !_unsaved) ? null : _activate,
              icon: const Icon(Icons.public),
              label: Text(live == null ? 'Activate' : 'Activate changes'),
            ),
            if (form.status == WebsiteFormStatus.active)
              TextButton.icon(
                key: const Key('builder-deactivate'),
                onPressed: _busy
                    ? null
                    : () async {
                        if (await _run(() => widget.service.deactivate(requesterRole: _role, actor: widget.user, formId: form.id), 'Deactivated. Its responses are kept.')) await _load();
                      },
                icon: const Icon(Icons.public_off),
                label: const Text('Deactivate'),
                style: TextButton.styleFrom(foregroundColor: const Color(0xFFB3261E)),
              ),
          ],
        ),
      ),
    );
    return LayoutBuilder(builder: (context, constraints) {
      final narrow = constraints.maxWidth < narrowEditorWidth;
      if (!narrow) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            toolbar,
            const Divider(height: 1),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(width: 280, child: _structure(form)),
                  const VerticalDivider(width: 1),
                  Expanded(child: _canvas(form, problems)),
                  const VerticalDivider(width: 1),
                  SizedBox(width: 340, child: _properties(form)),
                ],
              ),
            ),
          ],
        );
      }
      final selected = form.items.where((i) => i.id == _selectedId).firstOrNull;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          toolbar,
          Material(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: SegmentedButton<_Panel>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: _Panel.canvas, icon: Icon(Icons.web_outlined), label: Text('Form', key: Key('builder-tab-canvas'))),
                  ButtonSegment(value: _Panel.structure, icon: Icon(Icons.account_tree_outlined), label: Text('Structure', key: Key('builder-tab-structure'))),
                  ButtonSegment(value: _Panel.edit, icon: Icon(Icons.tune), label: Text('Edit', key: Key('builder-tab-edit'))),
                ],
                selected: {_panel},
                onSelectionChanged: (s) => setState(() => _panel = s.first),
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: switch (_panel) {
              _Panel.canvas => _canvas(form, problems),
              _Panel.structure => _structure(form),
              _Panel.edit => _properties(form),
            },
          ),
          if (_panel == _Panel.canvas)
            Material(
              elevation: 4,
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(
                  children: [
                    Expanded(child: Text(selected == null ? 'Form settings selected' : '${selected.displayLabel} selected', overflow: TextOverflow.ellipsis)),
                    FilledButton.tonal(key: const Key('builder-edit-selected'), onPressed: () => setState(() => _panel = _Panel.edit), child: const Text('Edit')),
                  ],
                ),
              ),
            ),
        ],
      );
    });
  }

  // ------------------------------------------------------------ structure

  Widget _addMenu() => PopupMenuButton<FormItem Function()>(
        key: const Key('builder-add-field'),
        tooltip: 'Add a question or content',
        enabled: !_busy,
        onSelected: (build) {
          final item = build();
          final form = _form!;
          if (item is WebsiteFormField && form.fields.length >= FormLimits.maxFields) return _snack('A form can have at most ${FormLimits.maxFields} fields.');
          if (item is FormContentBlock && form.items.whereType<FormContentBlock>().length >= FormLimits.maxContentBlocks) {
            return _snack('A form can have at most ${FormLimits.maxContentBlocks} headings, texts, images and dividers.');
          }
          _insert(item);
        },
        itemBuilder: (_) => [
          const PopupMenuItem(enabled: false, height: 28, child: Text('Questions', style: TextStyle(fontWeight: FontWeight.w700))),
          for (final t in FormFieldType.values)
            PopupMenuItem(
              key: Key('builder-add-${t.id}'),
              value: () => WebsiteFormField.create(t, '', options: t.hasOptions ? const ['Option 1', 'Option 2'] : const []),
              child: Text(t.label),
            ),
          const PopupMenuDivider(),
          const PopupMenuItem(enabled: false, height: 28, child: Text('Content', style: TextStyle(fontWeight: FontWeight.w700))),
          for (final t in FormBlockType.values) PopupMenuItem(key: Key('builder-add-content-${t.id}'), value: () => FormContentBlock.create(t), child: Text(t.label)),
        ],
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          child: Text('+ Add', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
        ),
      );

  void _snack(String message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  static IconData _icon(FormItem item) => switch (item) {
        WebsiteFormField(:final type) => switch (type) {
            FormFieldType.email => Icons.alternate_email,
            FormFieldType.phone => Icons.phone_outlined,
            FormFieldType.dropdown => Icons.arrow_drop_down_circle_outlined,
            FormFieldType.radio => Icons.radio_button_checked,
            FormFieldType.checkbox => Icons.check_box_outlined,
            FormFieldType.longText => Icons.notes,
            FormFieldType.date => Icons.calendar_today_outlined,
            FormFieldType.number => Icons.pin_outlined,
            FormFieldType.attachment => Icons.attach_file,
            _ => Icons.short_text,
          },
        FormContentBlock(:final type) => switch (type) {
            FormBlockType.heading => Icons.title,
            FormBlockType.image => Icons.image_outlined,
            FormBlockType.divider => Icons.horizontal_rule,
            _ => Icons.subject,
          },
      };

  Widget _structure(WebsiteForm form) {
    final items = form.items;
    return Column(
      key: const Key('builder-structure'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          key: const Key('form-structure-settings'),
          dense: true,
          selected: _selectedId == null,
          leading: const Icon(Icons.description_outlined),
          title: const Text('Form settings', style: TextStyle(fontWeight: FontWeight.w600)),
          subtitle: const Text('Title, description, cover image'),
          onTap: () => _select(null),
        ),
        const Divider(height: 1),
        Expanded(
          child: items.isEmpty
              ? const Padding(
                  key: Key('builder-empty'),
                  padding: EdgeInsets.all(16),
                  child: Text('No questions yet. Add one below.', style: TextStyle(color: AppColors.textSecondary)),
                )
              : ReorderableListView.builder(
                  key: const Key('builder-structure-list'),
                  buildDefaultDragHandles: false,
                  itemCount: items.length,
                  onReorder: (from, to) => _move(from, to > from ? to - 1 : to),
                  itemBuilder: (context, i) {
                    final item = items[i];
                    final problems = item.problems(complete: true);
                    final k = 'form-structure-${item.id}';
                    return Material(
                      key: ValueKey(item.id),
                      color: _selectedId == item.id ? AppColors.primary.withValues(alpha: 0.08) : Colors.transparent,
                      child: InkWell(
                        key: Key(k),
                        onTap: () => _select(item.id),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(4, 2, 4, 2),
                          child: Row(
                            children: [
                              ReorderableDragStartListener(index: i, child: const Padding(padding: EdgeInsets.all(6), child: Icon(Icons.drag_indicator, size: 18))),
                              Icon(_icon(item), size: 18),
                              const SizedBox(width: 6),
                              Expanded(child: Text(item.displayLabel, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
                              if (problems.isNotEmpty) Tooltip(message: problems.first, child: Icon(Icons.error_outline, key: Key('$k-problem'), size: 16, color: const Color(0xFFB3261E))),
                              PopupMenuButton<String>(
                                key: Key('$k-menu'),
                                tooltip: 'Actions',
                                padding: EdgeInsets.zero,
                                onSelected: (a) => switch (a) {
                                  'up' => _move(i, i - 1),
                                  'down' => _move(i, i + 1),
                                  'duplicate' => _duplicate(i),
                                  _ => _remove(i),
                                },
                                itemBuilder: (_) => [
                                  PopupMenuItem(key: Key('$k-up'), value: 'up', enabled: i > 0, child: const Text('Move up')),
                                  PopupMenuItem(key: Key('$k-down'), value: 'down', enabled: i < items.length - 1, child: const Text('Move down')),
                                  PopupMenuItem(key: Key('$k-duplicate'), value: 'duplicate', child: const Text('Duplicate')),
                                  PopupMenuItem(key: Key('$k-remove'), value: 'remove', child: const Text('Remove')),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
        const Divider(height: 1),
        Align(alignment: Alignment.centerLeft, child: _addMenu()),
      ],
    );
  }

  // ------------------------------------------------------------ canvas

  Widget _canvas(WebsiteForm form, List<String> problems) {
    return ColoredBox(
      color: const Color(0xFFE9ECEF),
      child: SingleChildScrollView(
        key: const Key('builder'),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                const Text('The form as visitors see it. Click any part to edit it.', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                SegmentedButton<FormPreviewDevice>(
                  showSelectedIcon: false,
                  segments: [
                    for (final d in FormPreviewDevice.values) ButtonSegment(value: d, icon: Icon(d.icon, size: 18), tooltip: d.label, label: Text(d.label, key: Key('builder-device-${d.name}'))),
                  ],
                  selected: {_device},
                  onSelectionChanged: (s) => setState(() => _device = s.first),
                ),
              ],
            ),
            if (problems.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                key: const Key('builder-problems'),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: const Color(0xFFFFF4E0), borderRadius: BorderRadius.circular(10)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('To fix before activating (${problems.length})', style: const TextStyle(fontWeight: FontWeight.w700)),
                    for (final p in problems.take(6)) Text('• $p', style: const TextStyle(fontSize: 13)),
                    if (problems.length > 6) Text('…and ${problems.length - 6} more.', style: const TextStyle(fontSize: 13)),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            LayoutBuilder(builder: (context, c) {
              // Laid out at the device's own width (so the renderer uses
              // that layout), then scaled down to fit, as the page builder
              // does.
              final width = _device.width;
              final frame = Center(
                child: Container(
                  key: const Key('form-builder-canvas'),
                  width: width,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: PublicColors.background, borderRadius: BorderRadius.circular(12), border: Border.all(color: PublicColors.line)),
                  child: MediaQuery(
                    data: MediaQuery.of(context).copyWith(size: Size(width, MediaQuery.sizeOf(context).height)),
                    child: PublicWebsiteFormView(
                      key: ValueKey('canvas-$_generation'),
                      form: form.toPublic(form.version),
                      language: PublicLanguage.english,
                      interactive: false,
                      media: _eligible,
                      selectedId: _selectedId,
                      onSelect: _select,
                    ),
                  ),
                ),
              );
              return c.maxWidth >= width ? frame : FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.topCenter, child: SizedBox(width: width, child: frame));
            }),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------ properties

  Widget _properties(WebsiteForm form) {
    final selected = form.items.where((i) => i.id == _selectedId).firstOrNull;
    return ListView(
      key: const Key('builder-properties'),
      padding: const EdgeInsets.all(16),
      children: switch (selected) {
        null => _formSettings(form),
        final WebsiteFormField f => _fieldSettings(f),
        final FormContentBlock b => _contentSettings(b),
      },
    );
  }

  Widget _text(String key, String label, String initial, ValueChanged<String> onChanged, {int? maxLength, bool multiline = false, String? helper}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextFormField(
          key: Key('$key-$_generation'),
          initialValue: initial,
          maxLength: maxLength,
          minLines: multiline ? 2 : 1,
          maxLines: multiline ? 6 : 1,
          decoration: websiteField(label, helper: helper).copyWith(isDense: true),
          onChanged: onChanged,
        ),
      );

  Widget _heading(String text) => Padding(padding: const EdgeInsets.only(top: 4, bottom: 8), child: Text(text, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)));

  /// An image chooser: its thumbnail, whether visitors may see it, and
  /// Choose / Remove.
  Widget _imagePicker(String key, String what, String? mediaId, ValueChanged<String?> onChanged, {bool required = false}) {
    final media = _library.where((m) => m.id == mediaId).firstOrNull;
    final problem = mediaId == null || mediaId.isEmpty ? null : WebsiteFormsService.imageProblem(media, what: what);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WebsiteMediaThumb(media: media, size: 56),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  mediaId == null || mediaId.isEmpty
                      ? (required ? 'No $what chosen. Required before activating.' : 'No image chosen.')
                      : problem ?? 'Visitors see this image (${media!.alt.en}).',
                  key: Key('$key-status'),
                  style: TextStyle(fontSize: 12.5, color: problem != null || (required && (mediaId ?? '').isEmpty) ? const Color(0xFFB3261E) : null),
                ),
                Wrap(
                  spacing: 4,
                  children: [
                    TextButton(
                      key: Key('$key-choose'),
                      onPressed: () async {
                        final chosen = await showWebsiteImagePicker(context, _library, selected: mediaId);
                        if (chosen != null) onChanged(chosen);
                      },
                      child: Text(mediaId == null || mediaId.isEmpty ? 'Choose' : 'Change'),
                    ),
                    if (mediaId != null && mediaId.isNotEmpty) TextButton(key: Key('$key-remove'), onPressed: () => onChanged(null), child: const Text('Remove')),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _formSettings(WebsiteForm form) => [
        _heading('Form settings'),
        _text('builder-title-en', 'Title', form.title.en, (v) => _edit((f) => f.copyWith(title: f.title.withText('en', v))), maxLength: FormLimits.maxTitle),
        _text('builder-public-description-en', 'Description', form.description.en, (v) => _edit((f) => f.copyWith(description: f.description.withText('en', v))),
            maxLength: FormLimits.maxDescription, multiline: true, helper: 'Shown to visitors under the title. Required before activating.'),
        const Text('Cover image', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        _imagePicker('builder-cover', 'cover image', form.coverMediaId, (id) => _edit((f) => f.copyWith(coverMediaId: () => id)), required: true),
        _text('builder-success-en', 'Success message', form.successMessage.en, (v) => _edit((f) => f.copyWith(successMessage: f.successMessage.withText('en', v))),
            maxLength: FormLimits.maxSuccessMessage, multiline: true, helper: 'Shown after a visitor sends the form, with their reference.'),
        _text('builder-description', 'Internal description (administrators only)', form.internalDescription, (v) => _edit((f) => f.copyWith(internalDescription: v)),
            maxLength: FormLimits.maxDescription, multiline: true, helper: 'Never shown on the website.'),
        const Divider(height: 24),
        _heading('Version history'),
        if (_versions.isEmpty) const Text('Never activated.', key: Key('builder-versions-empty'), style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        for (final v in _versions)
          ListTile(
            key: Key('builder-version-${v.version}'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(radius: 14, child: Text('${v.version}', style: const TextStyle(fontSize: 12))),
            title: Text(v.title),
            subtitle: Text('${v.fieldCount} questions · activated ${_when(v.activatedAt)}${v.activatedByName.isEmpty ? '' : ' by ${v.activatedByName}'}'),
          ),
      ];

  static String _when(DateTime? d) {
    if (d == null) return '—';
    final l = d.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(l.day)}/${two(l.month)}/${l.year} ${two(l.hour)}:${two(l.minute)}';
  }

  /// A whole number setting ('' = none).
  Widget _number(String key, String label, num? value, ValueChanged<num?> onChanged, {bool decimal = false}) => _text(
        key,
        label,
        value?.toString() ?? '',
        (v) => onChanged(v.trim().isEmpty ? null : (decimal ? num.tryParse(v.trim()) : int.tryParse(v.trim()))),
      );

  List<Widget> _fieldSettings(WebsiteFormField field) {
    final type = field.type;
    final k = 'builder-field-${field.id}';
    void edit(WebsiteFormField Function(WebsiteFormField f) change) => _editItem(field.id, (i) => change(i as WebsiteFormField));
    final labelMax = type == FormFieldType.checkbox ? FormLimits.maxConsentLabel : FormLimits.maxLabel;
    final problems = field.problems(complete: true);
    return [
      _heading(type?.label ?? 'Unsupported field'),
      if (problems.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(problems.join('\n'), key: Key('$k-problems'), style: const TextStyle(fontSize: 12.5, color: Color(0xFFB3261E))),
        ),
      _text('$k-label-en', type == FormFieldType.checkbox ? 'Consent or checkbox text' : 'Label', field.label.en,
          (v) => edit((x) => x.copyWith(label: x.label.withText('en', v))), maxLength: labelMax, multiline: type == FormFieldType.checkbox),
      if (type != null && type.isText && type != FormFieldType.date)
        _text('$k-placeholder-en', 'Placeholder (optional)', field.placeholder.en, (v) => edit((x) => x.copyWith(placeholder: x.placeholder.withText('en', v))),
            maxLength: FormLimits.maxPlaceholder),
      _text('$k-help-en', 'Help text (optional)', field.helpText.en, (v) => edit((x) => x.copyWith(helpText: x.helpText.withText('en', v))), maxLength: FormLimits.maxHelpText),
      if (type != FormFieldType.attachment)
        _text('$k-error-en', 'Error message (optional)', field.errorMessage.en, (v) => edit((x) => x.copyWith(errorMessage: x.errorMessage.withText('en', v))),
            maxLength: FormLimits.maxErrorMessage, helper: 'Shown instead of the standard message when the answer isn’t accepted.'),
      if (type != FormFieldType.attachment)
        SwitchListTile(
          key: Key('$k-required'),
          contentPadding: EdgeInsets.zero,
          title: Text(type == FormFieldType.checkbox ? 'Must be ticked' : 'Required'),
          value: field.required,
          onChanged: (v) => edit((x) => x.copyWith(required: v)),
        ),
      if (type == FormFieldType.shortText || type == FormFieldType.longText) ...[
        _number('$k-min-length', 'Fewest characters (optional)', field.minLength, (v) => edit((x) => x.copyWith(minLength: () => v?.toInt()))),
        _number('$k-max-length', 'Most characters (optional, up to ${type == FormFieldType.longText ? FormLimits.maxLongText : FormLimits.maxShortText})', field.maxLength,
            (v) => edit((x) => x.copyWith(maxLength: () => v?.toInt()))),
      ],
      if (type == FormFieldType.number) ...[
        _number('$k-min', 'Smallest value (optional)', field.min, (v) => edit((x) => x.copyWith(min: () => v)), decimal: true),
        _number('$k-max', 'Largest value (optional)', field.max, (v) => edit((x) => x.copyWith(max: () => v)), decimal: true),
      ],
      if (type == FormFieldType.date) ...[
        _text('$k-min-date', 'Earliest date (optional, YYYY-MM-DD)', field.minDate ?? '', (v) => edit((x) => x.copyWith(minDate: () => v.trim().isEmpty ? null : v.trim()))),
        _text('$k-max-date', 'Latest date (optional, YYYY-MM-DD)', field.maxDate ?? '', (v) => edit((x) => x.copyWith(maxDate: () => v.trim().isEmpty ? null : v.trim()))),
      ],
      if (type?.hasOptions ?? false) ..._optionsEditor(field, edit),
      if (type == FormFieldType.attachment) ..._attachmentSettings(field, edit),
    ];
  }

  List<Widget> _optionsEditor(WebsiteFormField field, void Function(WebsiteFormField Function(WebsiteFormField f)) edit) {
    final k = 'builder-field-${field.id}';
    return [
      const Text('Options', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      for (final (j, o) in field.options.indexed)
        Row(
          key: Key('$k-option-${o.id}'),
          children: [
            Expanded(
              child: _text('$k-option-${o.id}-en', 'Option ${j + 1}', o.label.en,
                  (v) => edit((x) => x.copyWith(options: [for (final y in x.options) y.id == o.id ? y.copyWith(label: y.label.withText('en', v)) : y])),
                  maxLength: FormLimits.maxOptionLabel),
            ),
            IconButton(
              key: Key('$k-remove-option-$j'),
              tooltip: 'Remove option',
              onPressed: () => edit((x) => x.copyWith(options: [for (final y in x.options) if (y.id != o.id) y])),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      if (field.options.length < FormLimits.maxOptions)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            key: Key('$k-add-option'),
            onPressed: () => edit((x) => x.copyWith(options: [...x.options, FormFieldOption(id: FormIds.option(), label: const LocalizedText())])),
            child: const Text('+ Add option'),
          ),
        ),
    ];
  }

  List<Widget> _attachmentSettings(WebsiteFormField field, void Function(WebsiteFormField Function(WebsiteFormField f)) edit) {
    final k = 'builder-field-${field.id}';
    return [
      Container(
        key: Key('$k-uploads-disabled'),
        padding: const EdgeInsets.all(10),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(color: const Color(0xFFFFF4E0), borderRadius: BorderRadius.circular(8)),
        child: const Text(
          'Visitors can’t upload documents yet: this field is shown disabled, and isn’t required, until secure uploads are set up.',
          style: TextStyle(fontSize: 12.5),
        ),
      ),
      const Text('Allowed file types', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      Wrap(
        spacing: 6,
        children: [
          for (final t in FormAttachments.types.keys)
            FilterChip(
              key: Key('$k-type-$t'),
              label: Text(t.toUpperCase()),
              selected: field.allowedFileTypes.contains(t),
              onSelected: (on) => edit((x) => x.copyWith(allowedFileTypes: [for (final y in FormAttachments.types.keys) if (y == t ? on : x.allowedFileTypes.contains(y)) y])),
            ),
        ],
      ),
      const SizedBox(height: 8),
      DropdownButtonFormField<int>(
        key: Key('$k-max-size'),
        initialValue: field.maxFileSizeMb.clamp(1, FormAttachments.maxSizeMb),
        decoration: websiteField('Largest file').copyWith(isDense: true),
        items: [for (var mb = 1; mb <= FormAttachments.maxSizeMb; mb++) DropdownMenuItem(value: mb, child: Text('$mb MB'))],
        onChanged: (v) => edit((x) => x.copyWith(maxFileSizeMb: v)),
      ),
      const SizedBox(height: 10),
      DropdownButtonFormField<int>(
        key: Key('$k-max-files'),
        initialValue: field.maxFiles.clamp(1, FormAttachments.maxFiles),
        decoration: websiteField('Most files').copyWith(isDense: true),
        items: [for (var n = 1; n <= FormAttachments.maxFiles; n++) DropdownMenuItem(value: n, child: Text('$n'))],
        onChanged: (v) => edit((x) => x.copyWith(maxFiles: v)),
      ),
      const SizedBox(height: 8),
      Text('Accepted MIME types: ${FormAttachments.mimeTypesFor(field.allowedFileTypes).join(', ')}', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
    ];
  }

  List<Widget> _contentSettings(FormContentBlock block) {
    final k = 'builder-content-${block.id}';
    void edit(FormContentBlock Function(FormContentBlock b) change) => _editItem(block.id, (i) => change(i as FormContentBlock));
    final problems = block.problems(complete: true);
    return [
      _heading(block.type?.label ?? 'Unsupported content'),
      if (problems.isNotEmpty)
        Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(problems.join('\n'), key: Key('$k-problems'), style: const TextStyle(fontSize: 12.5, color: Color(0xFFB3261E)))),
      if (block.type == FormBlockType.heading) ...[
        _text('$k-title-en', 'Heading', block.title.en, (v) => edit((b) => b.copyWith(title: b.title.withText('en', v))), maxLength: FormLimits.maxTitle),
      ],
      if (block.type == FormBlockType.image)
        _imagePicker('$k-image', 'image', block.mediaId.isEmpty ? null : block.mediaId, (id) => edit((b) => b.copyWith(mediaId: id ?? '')), required: true),
      if (block.type != FormBlockType.divider && block.type != null) ...[
        _text('$k-body-en', switch (block.type) { FormBlockType.heading => 'Description (optional)', FormBlockType.image => 'Caption (optional)', _ => 'Text' },
            block.body.en, (v) => edit((b) => b.copyWith(body: b.body.withText('en', v))), maxLength: FormLimits.maxContentText, multiline: true),
      ],
      if (block.type == FormBlockType.divider) const Text('A line between parts of the form.', style: TextStyle(color: AppColors.textSecondary)),
    ];
  }
}
