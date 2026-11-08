import 'package:flutter/material.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../../auth/models/app_user.dart';
import '../../../../public_website/content/blocks/block_registry.dart';
import '../../../../public_website/content/blocks/website_block.dart';
import '../../../../public_website/content/website_content_models.dart';
import '../../../../public_website/content/website_design.dart';
import '../../../../public_website/public_strings.dart';
import '../../../../public_website/widgets/blocks/website_blocks_view.dart';
import '../../../../public_website/widgets/public_website_image.dart';
import '../../data/website_content_admin_service.dart';
import '../../data/website_templates_service.dart';
import '../website_content_editors.dart' show showWebsiteImagePicker;
import '../website_content_screen.dart' show WebsiteMediaThumb;

/// The screen widths a template preview offers (the editor's own).
const _previewWidths = {'desktop': 1280.0, 'tablet': 820.0, 'mobile': 390.0};
const _previewLabels = {'desktop': 'Desktop', 'tablet': 'Tablet', 'mobile': 'Phone'};

/// [block] drawn by the website's own renderer at [width] px, scaled to
/// the space given and cut off below [height] (a picture: nothing in it
/// responds to clicks).
class WebsiteTemplatePreview extends StatelessWidget {
  const WebsiteTemplatePreview({super.key, required this.block, required this.media, required this.design, this.width = 1280, this.height = 720});

  final WebsiteBlock block;
  final Map<String, WebsiteMedia> media;
  final SiteDesign design;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) => ClipRect(
        child: FittedBox(
          fit: BoxFit.fitWidth,
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: width,
            height: height,
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: MediaQuery(
                  data: MediaQuery.of(context).copyWith(size: Size(width, height)),
                  child: SingleChildScrollView(
                    physics: const NeverScrollableScrollPhysics(),
                    child: WebsiteDesignScope(
                      design: design,
                      child: WebsiteBlocksView(blocks: [block], media: media, language: PublicLanguage.english, interactive: false, spaced: false, fullBleed: true),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

String _summary(WebsiteBlock block) {
  final inside = BlockRegistry.flatten([block]).length - 1;
  if (block is StructuredBlock && containerTypes.contains(block.type)) {
    final cols = block.columns('columns').length;
    return '$cols column${cols == 1 ? '' : 's'}, $inside block${inside == 1 ? '' : 's'} inside';
  }
  return block is StructuredBlock ? block.definition.label : 'Block';
}

/// A thumbnail chooser: the media library image, Choose / Change and
/// Remove (keys `<key>-choose`, `<key>-remove`, `<key>-status`).
class _ThumbnailField extends StatelessWidget {
  const _ThumbnailField({required this.fieldKey, required this.library, required this.mediaId, required this.onChanged});

  final String fieldKey;
  final List<WebsiteMedia> library;
  final String? mediaId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final media = library.where((m) => m.id == mediaId).firstOrNull;
    return Row(
      children: [
        WebsiteMediaThumb(media: media, size: 48),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                mediaId == null ? 'Thumbnail (optional): none, the library shows a preview of the template.' : 'Thumbnail: ${media?.alt.en.trim().isNotEmpty == true ? media!.alt.en : mediaId}',
                key: Key('$fieldKey-status'),
                style: const TextStyle(fontSize: 12.5),
              ),
              Wrap(
                spacing: 4,
                children: [
                  TextButton(
                    key: Key('$fieldKey-choose'),
                    onPressed: () async {
                      final chosen = await showWebsiteImagePicker(context, library, selected: mediaId);
                      if (chosen != null) onChanged(chosen);
                    },
                    child: Text(mediaId == null ? 'Choose' : 'Change'),
                  ),
                  if (mediaId != null) TextButton(key: Key('$fieldKey-remove'), onPressed: () => onChanged(null), child: const Text('Remove')),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Asks for a name, description and optional thumbnail, then saves [block]
/// (a section or any block) as a new template of the school. Returns the
/// template saved, or null when cancelled.
Future<WebsiteTemplate?> showSaveTemplateDialog(
  BuildContext context, {
  required WebsiteTemplatesService service,
  required AppUser user,
  required WebsiteBlock block,
  required List<WebsiteMedia> library,
}) {
  final problem = WebsiteTemplatesService.blockProblem(block);
  if (problem != null) {
    return showDialog<WebsiteTemplate>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('website-template-save-dialog'),
        title: const Text('Can’t save as a template'),
        content: Text(problem, key: const Key('website-template-save-error')),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );
  }
  return showDialog<WebsiteTemplate>(context: context, builder: (context) => _SaveTemplateDialog(service: service, user: user, block: block, library: library));
}

class _SaveTemplateDialog extends StatefulWidget {
  const _SaveTemplateDialog({required this.service, required this.user, required this.block, required this.library});

  final WebsiteTemplatesService service;
  final AppUser user;
  final WebsiteBlock block;
  final List<WebsiteMedia> library;

  @override
  State<_SaveTemplateDialog> createState() => _SaveTemplateDialogState();
}

class _SaveTemplateDialogState extends State<_SaveTemplateDialog> {
  late final TextEditingController _name;
  final _description = TextEditingController();
  String? _thumbnail;
  String? _error;
  bool _busy = false;

  bool get _section => widget.block.type == 'section';

  @override
  void initState() {
    super.initState();
    final b = widget.block;
    final named = b is StructuredBlock && b.type == 'section' ? b.text('name').en.trim() : '';
    _name = TextEditingController(text: named.isNotEmpty ? named : (b is StructuredBlock ? b.definition.label : ''));
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final problem = WebsiteTemplatesService.nameProblem(_name.text);
    if (problem != null) return setState(() => _error = problem);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final saved = await widget.service.save(
        requesterRole: widget.user.role,
        actor: widget.user,
        block: widget.block,
        name: _name.text,
        description: _description.text,
        thumbnailMediaId: _thumbnail,
      );
      if (mounted) Navigator.pop(context, saved);
    } on WebsiteContentException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'The template couldn’t be saved. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        key: const Key('website-template-save-dialog'),
        title: Text(_section ? 'Save section as a template' : 'Save block as a template'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'A copy of this ${_section ? 'section' : 'block'} (${_summary(widget.block)}) goes into the school’s template library, with its settings and images. Changing this page later doesn’t change the template.',
                  style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('website-template-save-name'),
                  controller: _name,
                  maxLength: WebsiteTemplate.maxName,
                  decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 8),
                TextField(
                  key: const Key('website-template-save-description'),
                  controller: _description,
                  maxLength: WebsiteTemplate.maxDescription,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'Description (optional)', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 8),
                _ThumbnailField(fieldKey: 'website-template-save-thumbnail', library: widget.library, mediaId: _thumbnail, onChanged: (id) => setState(() => _thumbnail = id)),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_error!, key: const Key('website-template-save-error'), style: const TextStyle(color: Color(0xFFB3261E))),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(key: const Key('website-template-save-cancel'), onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(key: const Key('website-template-save-confirm'), onPressed: _busy ? null : _save, child: const Text('Save template')),
        ],
      );
}

/// The school's template library: search, filter (sections, blocks),
/// a visual preview of each (its thumbnail, else the template drawn by
/// the website's renderer), a larger preview per screen size, and
/// rename, description, thumbnail and delete. Returns the template chosen
/// to insert, or null.
///
/// [kinds]: the kinds that can be inserted here; [allowContainers]: false
/// inside a column (sections and columns blocks can't go there).
Future<WebsiteTemplate?> showTemplateLibrary(
  BuildContext context, {
  required WebsiteTemplatesService service,
  required AppUser user,
  required List<WebsiteMedia> library,
  required Map<String, WebsiteMedia> media,
  SiteDesign design = SiteDesign.defaults,
  Set<WebsiteTemplateKind> kinds = const {WebsiteTemplateKind.section, WebsiteTemplateKind.block},
  bool allowContainers = true,
  String title = 'Templates',
}) =>
    showDialog<WebsiteTemplate>(
      context: context,
      builder: (context) => _TemplateLibrary(
        service: service,
        user: user,
        library: library,
        media: media,
        design: design,
        kinds: kinds,
        allowContainers: allowContainers,
        title: title,
      ),
    );

class _TemplateLibrary extends StatefulWidget {
  const _TemplateLibrary({
    required this.service,
    required this.user,
    required this.library,
    required this.media,
    required this.design,
    required this.kinds,
    required this.allowContainers,
    required this.title,
  });

  final WebsiteTemplatesService service;
  final AppUser user;
  final List<WebsiteMedia> library;
  final Map<String, WebsiteMedia> media;
  final SiteDesign design;
  final Set<WebsiteTemplateKind> kinds;
  final bool allowContainers;
  final String title;

  @override
  State<_TemplateLibrary> createState() => _TemplateLibraryState();
}

class _TemplateLibraryState extends State<_TemplateLibrary> {
  List<WebsiteTemplate>? _templates;
  String? _loadError;
  String _query = '';
  WebsiteTemplateKind? _filter;

  @override
  void initState() {
    super.initState();
    _filter = widget.kinds.length == 1 ? widget.kinds.single : null;
    _load();
  }

  Future<void> _load() async {
    try {
      final templates = await widget.service.list(requesterRole: widget.user.role);
      if (mounted) setState(() => _templates = templates);
    } catch (_) {
      if (mounted) setState(() => _loadError = 'The templates couldn’t be loaded. Check your connection and try again.');
    }
  }

  /// Why [t] can't be inserted here, or null.
  String? _whyNot(WebsiteTemplate t) {
    if (t.insertProblem case final p?) return p;
    if (!widget.kinds.contains(t.kind)) return t.kind == WebsiteTemplateKind.section ? 'Sections go on the page, not inside a column.' : 'Choose a section template here.';
    if (!widget.allowContainers && t.isContainer) return 'Blocks with their own columns can’t go inside a column.';
    return null;
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } on WebsiteContentException catch (e) {
      if (mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('That didn’t work. Check your connection and try again.')));
    }
    await _load();
  }

  Future<void> _editDetails(WebsiteTemplate t) async {
    final details = await showDialog<(String, String)>(context: context, builder: (context) => _DetailsDialog(template: t));
    if (details != null) {
      await _run(() => widget.service.updateDetails(requesterRole: widget.user.role, actor: widget.user, templateId: t.id, name: details.$1, description: details.$2));
    }
  }

  Future<void> _thumbnail(WebsiteTemplate t, {bool remove = false}) async {
    final chosen = remove ? null : await showWebsiteImagePicker(context, widget.library, selected: t.thumbnailMediaId);
    if (!remove && chosen == null) return;
    await _run(() => widget.service.setThumbnail(requesterRole: widget.user.role, actor: widget.user, templateId: t.id, mediaId: chosen));
  }

  Future<void> _delete(WebsiteTemplate t) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete “${t.name}”?'),
        content: const Text('It is removed from the template library. Pages where it was inserted keep their own copies, unchanged.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(key: const Key('website-template-delete-confirm'), onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed == true) await _run(() => widget.service.delete(requesterRole: widget.user.role, templateId: t.id));
  }

  Future<void> _preview(WebsiteTemplate t) async {
    final insert = await showDialog<bool>(context: context, builder: (context) => _TemplatePreviewDialog(template: t, media: widget.media, design: widget.design, whyNot: _whyNot(t)));
    if (insert == true && mounted) Navigator.pop(context, t);
  }

  Widget _card(WebsiteTemplate t) {
    final k = 'website-template-${t.id}';
    final whyNot = _whyNot(t);
    final thumb = t.thumbnailMediaId == null ? null : widget.media[t.thumbnailMediaId] ?? widget.library.where((m) => m.id == t.thumbnailMediaId).firstOrNull;
    return Card(
      key: Key(k),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade300)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            key: Key('$k-preview'),
            onTap: () => _preview(t),
            child: SizedBox(
              height: 130,
              child: ColoredBox(
                color: const Color(0xFFF6F4EF),
                child: thumb != null && thumb.url.isNotEmpty
                    ? PublicWebsiteImage(media: thumb, aspectRatio: 16 / 9, borderRadius: 0, semanticLabel: 'Thumbnail of ${t.name}')
                    : t.insertProblem == null
                        ? WebsiteTemplatePreview(block: t.block, media: widget.media, design: widget.design)
                        : const Center(child: Icon(Icons.extension_off_outlined, color: AppColors.textSecondary)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.name, key: Key('$k-name'), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text('${t.kind.label} · ${_summary(t.block)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      if (t.description.isNotEmpty) Text(t.description, key: Key('$k-description'), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5)),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  key: Key('$k-menu'),
                  tooltip: 'Manage this template',
                  onSelected: (v) => switch (v) {
                    'details' => _editDetails(t),
                    'thumbnail' => _thumbnail(t),
                    'remove-thumbnail' => _thumbnail(t, remove: true),
                    _ => _delete(t),
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(key: Key('$k-details'), value: 'details', child: const Text('Rename or describe')),
                    PopupMenuItem(key: Key('$k-thumbnail'), value: 'thumbnail', child: Text(t.thumbnailMediaId == null ? 'Choose thumbnail' : 'Replace thumbnail')),
                    if (t.thumbnailMediaId != null) PopupMenuItem(key: Key('$k-remove-thumbnail'), value: 'remove-thumbnail', child: const Text('Remove thumbnail')),
                    PopupMenuItem(key: Key('$k-delete'), value: 'delete', child: const Text('Delete')),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            // Side by side when they fit, else one above the other.
            child: OverflowBar(
              alignment: MainAxisAlignment.spaceBetween,
              overflowAlignment: OverflowBarAlignment.end,
              overflowSpacing: 4,
              children: [
                TextButton(key: Key('$k-open-preview'), onPressed: () => _preview(t), child: const Text('Preview')),
                Tooltip(
                  message: whyNot ?? '',
                  child: FilledButton(key: Key('$k-insert'), onPressed: whyNot == null ? () => Navigator.pop(context, t) : null, child: const Text('Insert')),
                ),
              ],
            ),
          ),
          if (whyNot != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Text(whyNot, key: Key('$k-why-not'), style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final all = _templates;
    final shown = [
      for (final t in all ?? const <WebsiteTemplate>[])
        if ((_filter == null || t.kind == _filter) && t.matches(_query)) t,
    ];
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      key: const Key('website-templates'),
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 980, maxHeight: size.height * 0.9),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: Text(widget.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
                  IconButton(key: const Key('website-templates-close'), tooltip: 'Close', onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                ],
              ),
              const Text('Sections and blocks saved by your school. Inserting adds an independent copy to this page.', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 280),
                    child: TextField(
                      key: const Key('website-templates-search'),
                      onChanged: (v) => setState(() => _query = v),
                      decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search templates', isDense: true, border: OutlineInputBorder()),
                    ),
                  ),
                  if (widget.kinds.length > 1)
                    for (final (kind, label) in [(null, 'All'), (WebsiteTemplateKind.section, 'Sections'), (WebsiteTemplateKind.block, 'Blocks')])
                      ChoiceChip(
                        key: Key('website-templates-filter-${kind?.id ?? 'all'}'),
                        label: Text(label),
                        selected: _filter == kind,
                        onSelected: (_) => setState(() => _filter = kind),
                      ),
                ],
              ),
              const SizedBox(height: 12),
              Flexible(
                child: all == null
                    ? Center(
                        child: _loadError == null
                            ? const Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())
                            : Text(_loadError!, key: const Key('website-templates-error')),
                      )
                    : shown.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              all.isEmpty
                                  ? 'No templates yet. Use “Save as template” on a section or block to add one.'
                                  : 'No templates match “$_query”.',
                              key: const Key('website-templates-empty'),
                              textAlign: TextAlign.center,
                            ),
                          )
                        // Cards of one width, each as tall as its content.
                        : LayoutBuilder(
                            builder: (context, constraints) {
                              final perRow = (constraints.maxWidth / 300).ceil().clamp(1, 4);
                              final width = ((constraints.maxWidth - 12 * (perRow - 1)) / perRow).floorToDouble();
                              return SingleChildScrollView(
                                key: const Key('website-templates-grid'),
                                child: Wrap(
                                  spacing: 12,
                                  runSpacing: 12,
                                  children: [for (final t in shown) SizedBox(width: width, child: _card(t))],
                                ),
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A template's name and description, to change (pops both, or null).
class _DetailsDialog extends StatefulWidget {
  const _DetailsDialog({required this.template});

  final WebsiteTemplate template;

  @override
  State<_DetailsDialog> createState() => _DetailsDialogState();
}

class _DetailsDialogState extends State<_DetailsDialog> {
  late final _name = TextEditingController(text: widget.template.name);
  late final _description = TextEditingController(text: widget.template.description);

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final problem = WebsiteTemplatesService.nameProblem(_name.text);
    return AlertDialog(
      key: const Key('website-template-details-dialog'),
      title: const Text('Template details'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('website-template-details-name'),
              controller: _name,
              maxLength: WebsiteTemplate.maxName,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(labelText: 'Name', border: const OutlineInputBorder(), errorText: problem),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('website-template-details-description'),
              controller: _description,
              maxLength: WebsiteTemplate.maxDescription,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Description (optional)', border: OutlineInputBorder()),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          key: const Key('website-template-details-save'),
          onPressed: problem == null ? () => Navigator.pop(context, (_name.text, _description.text)) : null,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// A template drawn larger, on a desktop, tablet or phone width, with
/// Insert (pops true) when it can be inserted here.
class _TemplatePreviewDialog extends StatefulWidget {
  const _TemplatePreviewDialog({required this.template, required this.media, required this.design, required this.whyNot});

  final WebsiteTemplate template;
  final Map<String, WebsiteMedia> media;
  final SiteDesign design;
  final String? whyNot;

  @override
  State<_TemplatePreviewDialog> createState() => _TemplatePreviewDialogState();
}

class _TemplatePreviewDialogState extends State<_TemplatePreviewDialog> {
  String _screen = 'desktop';

  @override
  Widget build(BuildContext context) {
    final t = widget.template;
    final width = _previewWidths[_screen]!;
    return Dialog(
      key: const Key('website-template-preview'),
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(t.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              if (t.description.isNotEmpty) Text(t.description, style: const TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: [for (final s in _previewWidths.keys) ButtonSegment(value: s, label: Text(_previewLabels[s]!, key: Key('website-template-preview-$s')))],
                  selected: {_screen},
                  onSelectionChanged: (s) => setState(() => _screen = s.single),
                ),
              ),
              const SizedBox(height: 10),
              Flexible(
                child: Container(
                  key: Key('website-template-preview-frame-$_screen'),
                  decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
                  constraints: const BoxConstraints(maxHeight: 520),
                  child: t.insertProblem == null
                      ? Center(
                          child: ConstrainedBox(
                            // A phone or tablet as narrow as it would be beside a desktop.
                            constraints: BoxConstraints(maxWidth: _screen == 'desktop' ? double.infinity : (_screen == 'tablet' ? 560 : 300)),
                            child: WebsiteTemplatePreview(block: t.block, media: widget.media, design: widget.design, width: width, height: _screen == 'mobile' ? 1400 : 900),
                          ),
                        )
                      : Padding(padding: const EdgeInsets.all(24), child: Text(t.insertProblem!)),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  if (widget.whyNot != null) Expanded(child: Text(widget.whyNot!, key: const Key('website-template-preview-why-not'), style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary))) else const Spacer(),
                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Close')),
                  const SizedBox(width: 8),
                  FilledButton(key: const Key('website-template-preview-insert'), onPressed: widget.whyNot == null ? () => Navigator.pop(context, true) : null, child: const Text('Insert')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
