import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../../auth/models/app_user.dart';
import '../../../../public_website/content/blocks/block_limits.dart';
import '../../../../public_website/content/blocks/block_registry.dart';
import '../../../../public_website/content/blocks/section_presets.dart';
import '../../../../public_website/content/blocks/website_block.dart';
import '../../../../public_website/content/website_content_models.dart';
import '../../../../public_website/content/website_design.dart';
import '../../../../public_website/content/website_page_style.dart';
import '../../../../public_website/public_strings.dart';
import '../../../../public_website/public_website_theme.dart';
import '../../../../public_website/widgets/blocks/website_blocks_view.dart';
import '../website_content_screen.dart';
import '../../data/website_content_admin_service.dart' show WebsiteContentException;
import '../../data/website_templates_service.dart';
import '../../data/website_editor_settings.dart';
import 'block_list_ops.dart';
import 'website_block_editor.dart';
import 'website_template_library.dart';
import '../../data/website_albums_service.dart';

/// The page builder: a page built with blocks, edited on a live canvas.
///
/// - **Structure** (left): add sections (ready-made layouts) and blocks;
///   every block, with the blocks inside sections and columns; select,
///   move, duplicate, hide/show and delete them; problems and hidden
///   blocks are marked; then the page's [checks].
/// - **Canvas** (centre): the page as visitors see it — the site's real
///   header and footer ([siteHeader], [siteFooter]) around the page, drawn
///   by the public renderer one block at a time ([WebsiteBlocksView], at
///   the page's full width so sections run edge to edge) with the site
///   [design], at a desktop's width or a phone's. Click a section, or a
///   block inside it, to select it; `+` points add a section or a block
///   there. Blocks visitors wouldn't see (hidden, with problems,
///   unsupported, without a published image) are shown as placeholders,
///   inside sections too. Clicking the header or footer explains that they
///   are shared by every page ([siteChromeInfo]).
/// - **Properties** (right): the selected block's form
///   ([WebsiteBlockForm], with its design options); with nothing
///   selected, [pageSettings].
///
/// All three panels from 1200 px; from 840 px the side panels can be
/// shown and hidden; narrower, one panel at a time (Page, Structure, Edit).
///
/// Edits are reported through [onChanged]; nothing is saved here. Blocks
/// are addressed by position ([BlockPath]): every action selects the block
/// it acted on, and the selection is cleared when the editor is refilled
/// ([generation]). Unsupported blocks are locked: they can be moved or
/// (after a warning) deleted, never edited.
class WebsiteVisualEditor extends StatefulWidget {
  const WebsiteVisualEditor({
    super.key,
    required this.blocks,
    required this.onChanged,
    required this.library,
    required this.media,
    required this.language,
    required this.generation,
    required this.mobilePreview,
    this.tabletPreview = false,
    required this.pageSettings,
    required this.checks,
    required this.banner,
    this.previewView,
    this.pageHeader,
    this.design = SiteDesign.defaults,
    this.pageStyle = const PageStyle(),
    this.siteHeader,
    this.siteFooter,
    this.siteChromeInfo,
    this.templates,
    this.user,
    this.albums,
    this.editorSettings,
  });

  /// The school's albums, for galleries' image source (null: they couldn't
  /// be read).
  final List<WebsiteAlbum>? albums;

  /// The school's template library, and who is editing: with both, blocks
  /// and sections can be saved as templates and templates inserted.
  final WebsiteTemplatesService? templates;
  final AppUser? user;

  /// The school's editor settings: the page's block limit follows them
  /// while the editor is open (a change applies at once). Null: the
  /// default limit ([BlockLimits.defaults]).
  final WebsiteEditorSettingsService? editorSettings;

  /// The page's blocks.
  final List<WebsiteBlock> blocks;
  final ValueChanged<List<WebsiteBlock>> onChanged;

  /// Heads the page on the canvas (an additional page's title,
  /// introduction and banner); clicking it shows the page settings.
  final Widget? pageHeader;

  /// The site design the canvas and the colour settings use (the draft).
  final SiteDesign design;

  /// The page's own look (its background), as being edited: shown behind
  /// the page on the canvas, between the site header and footer.
  final PageStyle pageStyle;

  /// The site's real header and footer (with the draft layout), shown on
  /// the canvas and selectable.
  final Widget? siteHeader;
  final Widget? siteFooter;

  /// What the properties show for the selected header or footer
  /// (`header` or `footer`).
  final Widget Function(String part)? siteChromeInfo;

  /// The whole media library, for choosing images.
  final List<WebsiteMedia> library;

  /// The published images: what visitors (and the canvas) see.
  final Map<String, WebsiteMedia> media;
  final PublicLanguage language;
  final int generation;

  /// The canvas at a phone's width (390 px), or a tablet's (820 px,
  /// when not [mobilePreview]).
  final bool mobilePreview;
  final bool tabletPreview;

  /// The tablet frame's width: the public site's tablet layout.
  static const tabletCanvasWidth = 820.0;
  final Widget pageSettings;
  final Widget checks;

  /// Shown above the canvas (which version is being edited).
  final Widget banner;

  /// When set, shown in place of the editing canvas, with no panels (the
  /// page as visitors see it, or the live version).
  final Widget? previewView;

  @override
  State<WebsiteVisualEditor> createState() => _WebsiteVisualEditorState();
}

enum _Panel { page, structure, edit }

/// The narrowest width the Desktop canvas lays the page out at: a desktop
/// browser's, above the public pages' desktop breakpoint (1100 px).
const desktopCanvasWidth = 1200.0;

/// Below this width the editor shows one panel at a time (a phone).
const narrowEditorWidth = 840.0;

class _WebsiteVisualEditorState extends State<WebsiteVisualEditor> {
  BlockPath? _selected;

  /// The site header or footer is selected (`header`, `footer`).
  String? _chrome;

  /// The panel shown on narrow screens.
  _Panel _panel = _Panel.page;

  /// Side panels on medium screens.
  bool _showStructure = false;
  bool _showProperties = true;
  bool _narrow = false;

  List<WebsiteBlock> get _blocks => widget.blocks;

  /// The page's limits: the school's setting, or the default.
  BlockLimits _limits = BlockLimits.defaults;

  /// Why the default applies although a setting was looked for (it
  /// couldn't be read, or what is saved isn't usable); null otherwise.
  String? _limitsNote;
  StreamSubscription<WebsiteEditorSettings>? _settings;

  void _listenToSettings() {
    _settings?.cancel();
    _settings = widget.editorSettings?.watch().listen(
      (s) {
        if (!mounted) return;
        setState(() {
          _limits = s.limits;
          _limitsNote = s.storedValueInvalid
              ? 'The saved block limit isn’t a valid number, so the default of ${BlockLimits.defaultPageMaxBlocks} applies. An administrator can correct it in Website → Pages → Editor settings.'
              : null;
        });
      },
      onError: (Object _) {
        if (!mounted) return;
        setState(() {
          _limits = BlockLimits.defaults;
          _limitsNote = 'The block limit setting couldn’t be read, so the default of ${BlockLimits.defaultPageMaxBlocks} applies.';
        });
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _listenToSettings();
  }

  @override
  void dispose() {
    _settings?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(WebsiteVisualEditor old) {
    super.didUpdateWidget(old);
    if (old.editorSettings != widget.editorSettings) _listenToSettings();
    if (old.generation != widget.generation) {
      _selected = null;
      _chrome = null;
    } else if (_selected != null && BlockListOps.at(_blocks, _selected!) == null) {
      _selected = null;
    }
  }

  WebsiteBlock? get _selectedBlock => _selected == null ? null : BlockListOps.at(_blocks, _selected!);

  /// Selects [path] (null: page settings); [edit] also brings the
  /// properties into view.
  void _select(BlockPath? path, {bool edit = false}) {
    setState(() {
      _selected = path;
      _chrome = null;
      if (edit && path != null) {
        if (_narrow) _panel = _Panel.edit;
        _showProperties = true;
      }
    });
  }

  void _apply(List<WebsiteBlock> next, BlockPath? select, {bool edit = false}) {
    _select(select, edit: edit);
    widget.onChanged(next);
  }

  void _add(BlockDefinition definition, {BlockPath? at}) {
    final to = at ?? (_selected == null ? BlockPath(_blocks.length) : BlockPath(_selected!.index + 1));
    final block = BlockRegistry.create(definition);
    if (!BlockListOps.canInsert(_blocks, block, limits: _limits)) return _noRoom();
    _apply(BlockListOps.insert(_blocks, to, block), to, edit: true);
  }

  /// Why nothing was added: the page's block limit.
  bool get _templatesOn => widget.templates != null && widget.user != null;

  /// The screen size being previewed.
  String get _screen => widget.mobilePreview ? 'mobile' : (widget.tabletPreview ? 'tablet' : 'desktop');

  static const _screenNames = {'desktop': 'Desktop', 'tablet': 'Tablet', 'mobile': 'Phone'};

  /// "3 columns · Tablet: 2 per row" for a section or columns block.
  String? _columnsSummary(WebsiteBlock block) {
    if (block is! StructuredBlock || !containerTypes.contains(block.type)) return null;
    final count = block.columns('columns').length;
    if (count <= 1) return '1 column';
    return '$count columns · ${_screenNames[_screen]}: ${ColumnsPerRow.on(block, _screen)} per row';
  }

  /// Gives the container at [path] (a section, columns block or row)
  /// [count] columns, asking first when that removes columns holding
  /// blocks.
  Future<void> _setColumnCount(BlockPath path, int count) async {
    final block = BlockListOps.at(_blocks, path);
    if (block is! StructuredBlock || block.columns('columns').length == count) return;
    final changed = await changeColumnLayout(context, block, ColumnOps.layoutFor(block, count));
    if (changed != null && mounted) _apply(BlockListOps.replace(_blocks, path, changed), path);
  }

  /// The canvas toolbar's Columns control for the container at [path].
  Widget? _columnsControl(BlockPath path, WebsiteBlock block) {
    if (block is! StructuredBlock || !containerTypes.contains(block.type)) return null;
    final (fewest, most) = ColumnOps.range(block);
    final count = block.columns('columns').length;
    return PopupMenuButton<int>(
      key: Key('website-canvas-${block.id}-columns'),
      tooltip: 'Columns: ${_columnsSummary(block)}',
      onSelected: (n) => _setColumnCount(path, n),
      itemBuilder: (context) => [
        for (var n = fewest; n <= most; n++)
          PopupMenuItem(key: Key('website-canvas-${block.id}-columns-$n'), value: n, child: Text('$n column${n == 1 ? '' : 's'}${n == count ? ' (now)' : ''}')),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.view_column_outlined, size: 18),
          const SizedBox(width: 2),
          Text('$count', key: Key('website-canvas-${block.id}-columns-count'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }

  /// Saves the block or section at [path] as a template (asking for its
  /// name, description and thumbnail).
  Future<void> _saveTemplate(BlockPath path) async {
    final block = BlockListOps.at(_blocks, path);
    if (block == null || !_templatesOn) return;
    final saved = await showSaveTemplateDialog(context, service: widget.templates!, user: widget.user!, block: block, library: widget.library);
    if (saved != null && mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text('Saved “${saved.name}” to the template library.')));
  }

  /// Opens the template library and inserts an independent copy (new ids
  /// throughout) of the template chosen: [kinds] on the page, after the
  /// selected block or at the end; or, with [container] and [column], a
  /// block template at the end of that column (of a section, columns block
  /// or row).
  Future<void> _browseTemplates({Set<WebsiteTemplateKind> kinds = const {WebsiteTemplateKind.section, WebsiteTemplateKind.block}, BlockPath? container, int? column}) async {
    if (!_templatesOn) return;
    final inColumn = container != null && column != null;
    final chosen = await showTemplateLibrary(
      context,
      service: widget.templates!,
      user: widget.user!,
      library: widget.library,
      media: widget.media,
      design: widget.design,
      kinds: inColumn ? const {WebsiteTemplateKind.block} : kinds,
      allowContainers: !inColumn,
      title: inColumn ? 'Block templates for column ${column + 1}' : (kinds.length == 1 ? '${kinds.single.label} templates' : 'Templates'),
    );
    if (chosen == null || !mounted) return;
    final WebsiteBlock copy;
    try {
      copy = WebsiteTemplatesService.instantiate(chosen);
    } on WebsiteContentException catch (e) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }
    if (inColumn) {
      if (!BlockListOps.canInsertInColumn(_blocks, container, column, copy, limits: _limits)) return _noRoom();
      final (next, to) = BlockListOps.insertInColumn(_blocks, container, column, copy);
      _apply(next, to, edit: true);
    } else {
      // A Columns / Row goes only inside a section's column.
      if (copy.type == rowType) return;
      if (!BlockListOps.canInsert(_blocks, copy, limits: _limits)) return _noRoom();
      final to = _selected == null ? BlockPath(_blocks.length) : BlockPath(_selected!.index + 1);
      _apply(BlockListOps.insert(_blocks, to, copy), to, edit: true);
    }
  }

  void _noRoom() => ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(_limitMessage)));

  String get _limitMessage =>
      'This page has room for ${_limits.maxBlocks} blocks (each section, columns block and block inside them counts). '
      'Remove or combine blocks, or move content to another page, to add more. An administrator can change the limit in Website → Pages → Editor settings.';

  /// Why a column's Add is disabled: the page is full, or (only when one
  /// is set) the column's own limit.
  String _columnFullReason() {
    if (!BlockListOps.pageHasRoom(_blocks, limits: _limits)) return 'This page has reached its limit of ${_limits.maxBlocks} blocks';
    if (_limits.hasColumnLimit) return 'This column holds its maximum of ${_limits.maxColumnBlocks} blocks';
    return 'No more blocks can be added here';
  }

  void _selectChrome(String part) => setState(() {
        _selected = null;
        _chrome = part;
        if (_narrow) _panel = _Panel.edit;
        _showProperties = true;
      });

  /// Adds a new section made from [preset] at [at] (after the selected
  /// block, or at the end).
  void _addSection(SectionPreset preset, {BlockPath? at}) {
    final to = at ?? (_selected == null ? BlockPath(_blocks.length) : BlockPath(_selected!.index + 1));
    final section = preset.create();
    // Never a section that couldn't hold a block.
    if (!BlockListOps.canInsert(_blocks, section, limits: _limits)) return _noRoom();
    _apply(BlockListOps.insert(_blocks, to, section), to, edit: true);
  }

  /// Adds a new block of [definition] at the end of column [column] of
  /// the container at [container]. A Columns / Row (only offered in a
  /// section's column) first asks how many inner columns it has.
  Future<void> _addToColumn(BlockPath container, int column, BlockDefinition definition) async {
    final WebsiteBlock block;
    if (definition.type == rowType) {
      final count = await chooseRowColumns(context);
      if (count == null || !mounted) return;
      block = ColumnOps.newRow(count);
    } else {
      block = BlockRegistry.create(definition);
    }
    if (!BlockListOps.canInsertInColumn(_blocks, container, column, block, limits: _limits)) return _noRoom();
    final (next, to) = BlockListOps.insertInColumn(_blocks, container, column, block);
    _apply(next, to, edit: true);
  }

  /// Whether a new block of [definition] fits in column [column] of the
  /// container at [container] (a Columns / Row also needs room for a block
  /// inside it).
  bool _fitsInColumn(BlockPath container, int column, BlockDefinition definition) => BlockListOps.canInsertInColumn(
        _blocks,
        container,
        column,
        definition.type == rowType ? ColumnOps.newRow(1) : BlockRegistry.create(definition),
        limits: _limits,
      );

  void _move(BlockPath path, int delta) {
    final (next, moved) = BlockListOps.move(_blocks, path, delta);
    _apply(next, moved);
  }

  /// Moves the block at [path] to the end of another column of its section.
  void _moveToColumn(BlockPath path, int column) {
    final (next, moved) = BlockListOps.moveToColumn(_blocks, path, column, limits: _limits);
    _apply(next, moved);
  }

  void _duplicate(BlockPath path) {
    final (next, copy) = BlockListOps.duplicate(_blocks, path);
    _apply(next, copy);
  }

  void _toggleHidden(BlockPath path) => _apply(BlockListOps.toggleHidden(_blocks, path), path);

  Future<void> _delete(BlockPath path) async {
    final unsupported = BlockListOps.at(_blocks, path) is UnsupportedBlock;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(unsupported ? 'Delete this unsupported block?' : 'Delete this block?'),
        content: Text(unsupported
            ? 'This block was made with a newer version of the website editor. This version can’t show or edit it, and deleting it removes its content for good once you save.'
            : 'The block and everything in it are removed from the page when you save. Nothing changes on the website until you save and publish.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(key: const Key('website-block-delete-confirm'), onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed == true && mounted) _apply(BlockListOps.remove(_blocks, path), null);
  }

  /// On a School gallery: it can't choose photographs, so it points to a
  /// Photo gallery and adds one right after it (the School gallery stays).
  Widget _photoGalleryHint(BlockPath path) {
    final next = path.isNested ? BlockPath.inside(path.parent!, path.column!, path.position + 1) : BlockPath(path.index + 1);
    final room = path.isNested ? BlockListOps.columnAtHasRoom(_blocks, path.parent!, path.column!, limits: _limits) : BlockListOps.pageHasRoom(_blocks, limits: _limits);
    return Container(
      key: const Key('website-inspector-gallery-feed-hint'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: const Color(0xFFF3EADB), borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'This block shows every published gallery photograph automatically, with filters. '
            'To choose specific photographs, their order, captions, links and images per row, use a Photo gallery block.',
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 6),
          TextButton.icon(
            key: const Key('website-inspector-add-photo-gallery'),
            onPressed: room ? () => _apply(BlockListOps.insert(_blocks, next, BlockRegistry.create(BlockRegistry.gallery)), next, edit: true) : null,
            icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
            label: Text(room ? 'Add a Photo gallery below' : 'No room for another block here'),
          ),
        ],
      ),
    );
  }

  /// Selects the first block that has a problem.
  void _selectFirstProblem() {
    for (final (path, block) in BlockListOps.walk(_blocks)) {
      if (BlockRegistry.blockProblems(block).isNotEmpty) {
        _select(path, edit: true);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      _narrow = width < narrowEditorWidth;
      if (widget.previewView != null) return _canvasArea(widget.previewView!);
      if (width >= 1200) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: 290, child: _structure()),
            const VerticalDivider(width: 1),
            Expanded(child: _canvasArea(_canvas())),
            const VerticalDivider(width: 1),
            SizedBox(width: 360, child: _properties()),
          ],
        );
      }
      if (!_narrow) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Material(
              color: Colors.white,
              child: Row(
                children: [
                  TextButton.icon(
                    key: const Key('website-editor-toggle-structure'),
                    onPressed: () => setState(() => _showStructure = !_showStructure),
                    icon: Icon(_showStructure ? Icons.chevron_left : Icons.account_tree_outlined),
                    label: Text(_showStructure ? 'Hide structure' : 'Structure'),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    key: const Key('website-editor-toggle-properties'),
                    onPressed: () => setState(() => _showProperties = !_showProperties),
                    icon: Icon(_showProperties ? Icons.chevron_right : Icons.tune),
                    label: Text(_showProperties ? 'Hide properties' : 'Properties'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_showStructure) ...[SizedBox(width: 270, child: _structure()), const VerticalDivider(width: 1)],
                  Expanded(child: _canvasArea(_canvas())),
                  if (_showProperties) ...[const VerticalDivider(width: 1), SizedBox(width: 320, child: _properties())],
                ],
              ),
            ),
          ],
        );
      }
      final selected = _selectedBlock;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: SegmentedButton<_Panel>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: _Panel.page, icon: Icon(Icons.web_outlined), label: Text('Page', key: Key('website-editor-tab-page'))),
                  ButtonSegment(value: _Panel.structure, icon: Icon(Icons.account_tree_outlined), label: Text('Structure', key: Key('website-editor-tab-structure'))),
                  ButtonSegment(value: _Panel.edit, icon: Icon(Icons.tune), label: Text('Edit', key: Key('website-editor-tab-edit'))),
                ],
                selected: {_panel},
                onSelectionChanged: (s) => setState(() => _panel = s.first),
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: switch (_panel) {
              _Panel.page => _canvasArea(_canvas()),
              _Panel.structure => _structure(),
              _Panel.edit => _properties(),
            },
          ),
          if (_panel == _Panel.page && selected != null)
            Material(
              elevation: 4,
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(
                  children: [
                    Icon(blockIcon(selected), size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text('${_label(selected)} selected', overflow: TextOverflow.ellipsis)),
                    FilledButton.tonal(key: const Key('website-editor-edit-selected'), onPressed: () => setState(() => _panel = _Panel.edit), child: const Text('Edit')),
                  ],
                ),
              ),
            ),
        ],
      );
    });
  }

  static String _label(WebsiteBlock block) => block is StructuredBlock ? block.definition.label : 'Unsupported block';

  /// Where the block at [path] is, outermost first: "In section
  /// “Programmes”, column 2 › row, inner column 1".
  String _location(BlockPath path) {
    final steps = <String>[];
    for (BlockPath? p = path; p != null && p.isNested; p = p.parent) {
      final parent = BlockListOps.at(_blocks, p.parent!);
      final name = parent is StructuredBlock && (parent.type == 'section' || parent.type == rowType) ? parent.text('name').en.trim() : '';
      final kind = parent?.type == rowType ? 'row' : (parent is StructuredBlock ? parent.definition.label.toLowerCase() : 'block');
      steps.insert(0, '${name.isEmpty ? kind : '$kind “$name”'}, ${parent?.type == rowType ? 'inner column' : 'column'} ${p.column! + 1}');
    }
    return 'In ${steps.join(' › ')}';
  }

  // ------------------------------------------------------------ canvas

  /// The canvas's frame: [banner] above a page at the canvas's width, or a
  /// phone's, so the public renderer lays the page out for that width.
  Widget _canvasArea(Widget page) {
    final content = WebsiteDesignScope(design: widget.design, child: page);
    return ColoredBox(
      color: const Color(0xFFE9ECEF),
      child: SingleChildScrollView(
        key: const Key('website-editor-canvas-scroll'),
        padding: EdgeInsets.all(_narrow ? 8 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            widget.banner,
            const SizedBox(height: 12),
            Center(
              child: Container(
                key: const Key('website-custom-preview'),
                padding: EdgeInsets.symmetric(vertical: widget.siteHeader == null ? 24 : 0),
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(color: PublicColors.background, borderRadius: BorderRadius.circular(12), border: Border.all(color: PublicColors.line)),
                child: widget.mobilePreview
                    ? LayoutBuilder(builder: (context, c) {
                        // A phone's width, scaled down when the canvas is
                        // narrower, so the page is laid out at the width
                        // it is told it has (never squeezed below it).
                        final page = SizedBox(
                          key: const Key('website-custom-preview-mobile-frame'),
                          width: 390,
                          child: MediaQuery(data: MediaQuery.of(context).copyWith(size: const Size(390, 844)), child: content),
                        );
                        return c.maxWidth >= 390 ? page : FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.topCenter, child: page);
                      })
                    : widget.tabletPreview
                    ? LayoutBuilder(builder: (context, c) {
                        const width = WebsiteVisualEditor.tabletCanvasWidth;
                        final page = SizedBox(
                          key: const Key('website-custom-preview-tablet-frame'),
                          width: width,
                          child: MediaQuery(data: MediaQuery.of(context).copyWith(size: const Size(width, 1180)), child: content),
                        );
                        return c.maxWidth >= width ? page : FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.topCenter, child: page);
                      })
                    : LayoutBuilder(builder: (context, c) {
                        // Laid out at least as wide as a desktop browser, so
                        // the public renderer uses its desktop layout, then
                        // scaled down to fit the canvas.
                        final width = math.max(c.maxWidth, desktopCanvasWidth);
                        final page = SizedBox(
                          key: const Key('website-custom-preview-desktop-frame'),
                          width: width,
                          child: MediaQuery(data: MediaQuery.of(context).copyWith(size: Size(width, MediaQuery.sizeOf(context).height)), child: content),
                        );
                        return width == c.maxWidth ? page : FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.topCenter, child: page);
                      }),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The path of [container] (a section, columns block or a row inside
  /// one of the top-level block [index]'s columns), found by identity:
  /// the canvas draws the page's own block objects.
  BlockPath _containerPath(int index, StructuredBlock container) {
    final top = _blocks[index];
    if (identical(top, container)) return BlockPath(index);
    for (final (c, column) in BlockListOps.columnsOf(top).indexed) {
      for (final (j, child) in column.blocks.indexed) {
        if (identical(child, container)) return BlockPath.nested(index, c, j);
      }
    }
    return BlockPath(index);
  }

  /// How the canvas draws the blocks inside top-level block [index]'s
  /// columns (and inside the Columns / Row blocks there): each selectable,
  /// with a placeholder when visitors wouldn't see it, then an "Add"
  /// button per column. A row's own blocks are selectable inside it.
  WebsiteBlocksEditing _editing(int index) => WebsiteBlocksEditing(
        frame: (context, parent, column, position, child, rendered) {
          final path = BlockPath.inside(_containerPath(index, parent), column, position);
          final row = child is StructuredBlock && child.type == rowType && rendered != null;
          return _CanvasBlock(
            block: child,
            content: rendered ?? _CanvasPlaceholder(block: child, media: widget.media),
            absorb: !row,
            position: position,
            count: BlockListOps.columnsOf(parent)[column].blocks.length,
            selected: _selected == path,
            childSelected: row && _selected != null && _selected != path && _selected!.isWithin(path),
            canDuplicate: BlockListOps.canDuplicate(_blocks, path, limits: _limits),
            onSelect: () => _select(path),
            onMove: (d) => _move(path, d),
            onDuplicate: () => _duplicate(path),
            onToggleHidden: () => _toggleHidden(path),
            onDelete: () => _delete(path),
            onSaveTemplate: _templatesOn && child.type != rowType ? () => _saveTemplate(path) : null,
            columnsControl: row ? _columnsControl(path, child) : null,
          );
        },
        columnEnd: (context, parent, column) {
          final container = _containerPath(index, parent);
          final col = BlockListOps.columnsOf(parent)[column];
          final inRow = parent.type == rowType;
          return Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: _AddMenu(
                menuKey: 'website-canvas-column-${col.id}-add',
                label: col.blocks.isEmpty ? (inRow ? 'Add a block to this inner column' : 'Add a block to this column') : 'Add block',
                enabled: BlockListOps.columnAtHasRoom(_blocks, container, column, limits: _limits),
                disabledTooltip: _columnFullReason(),
                types: BlockRegistry.nestableIn(parent.type),
                fits: (d) => _fitsInColumn(container, column, d),
                onSelected: (d) => _addToColumn(container, column, d),
                onBrowseTemplates: _templatesOn ? () => _browseTemplates(container: container, column: column) : null,
              ),
            ),
          );
        },
      );

  Widget _canvas() {
    final blocks = _blocks;
    final canAdd = BlockListOps.pageHasRoom(blocks, limits: _limits);
    return Builder(builder: (context) {
      final mobile = PublicLayout.of(MediaQuery.sizeOf(context).width).isMobile;
      Widget block(int i, WebsiteBlock block) {
        final container = block is StructuredBlock && containerTypes.contains(block.type) && WebsiteBlocksView.isShown(block);
        final visible = container || WebsiteBlocksView.rendersVisibly(block, widget.media, widget.language);
        return _CanvasBlock(
          block: block,
          content: visible
              ? WebsiteBlocksView(
                  blocks: [block],
                  media: widget.media,
                  language: widget.language,
                  interactive: false,
                  spaced: false,
                  fullBleed: true,
                  editing: container ? _editing(i) : null,
                )
              : PublicContentWidth(maxWidth: 960, child: _CanvasPlaceholder(block: block, media: widget.media)),
          // Blocks inside a section or columns handle their own clicks.
          absorb: !container,
          position: i,
          count: blocks.length,
          selected: _selected == BlockPath(i),
          childSelected: _selected != null && _selected!.isNested && _selected!.index == i,
          canDuplicate: BlockListOps.canDuplicate(blocks, BlockPath(i), limits: _limits),
          onSelect: () => _select(BlockPath(i)),
          onMove: (d) => _move(BlockPath(i), d),
          onDuplicate: () => _duplicate(BlockPath(i)),
          onToggleHidden: () => _toggleHidden(BlockPath(i)),
          onDelete: () => _delete(BlockPath(i)),
          onSaveTemplate: _templatesOn ? () => _saveTemplate(BlockPath(i)) : null,
          columnsControl: _columnsControl(BlockPath(i), block),
        );
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.siteHeader case final header?) _ChromeFrame(part: 'header', selected: _chrome == 'header', onTap: () => _selectChrome('header'), child: header),
          // The page itself, in its own background (the header and footer
          // keep theirs).
          PageBackground(
            style: widget.pageStyle,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // The page's title, introduction and banner image, as visitors see
                // them; clicking there shows the page settings.
                if (widget.pageHeader case final pageHeader?)
                  GestureDetector(
                    key: const Key('website-canvas-page-header'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _select(null),
                    child: Padding(padding: EdgeInsets.only(top: widget.siteHeader == null ? 0 : (mobile ? 32 : 56)), child: pageHeader),
                  ),
                if (blocks.isEmpty)
                  PublicContentWidth(
                    maxWidth: 960,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: WebsiteBlocksEmptyState(addKey: 'website-blocks-add', canAdd: canAdd, onAdd: _add, sections: SectionPreset.all, onAddSection: _addSection),
                    ),
                  ),
                for (final (i, b) in blocks.indexed) ...[
                  _InsertPoint(
                    index: i,
                    height: WebsiteBlocksView.spaceAbove(b, mobile: mobile, screen: WebsiteBlocksView.screenOf(MediaQuery.sizeOf(context).width)),
                    canAdd: canAdd,
                    fitsBlock: (d) => BlockListOps.canAdd(blocks, d, limits: _limits),
                    fitsSection: (p) => BlockListOps.canInsert(blocks, p.create(), limits: _limits),
                    onAdd: (d) => _add(d, at: BlockPath(i)),
                    onAddSection: (p) => _addSection(p, at: BlockPath(i)),
                  ),
                  block(i, b),
                ],
                if (blocks.isNotEmpty)
                  _InsertPoint(
                    index: blocks.length,
                    height: 48,
                    canAdd: canAdd,
                    fitsBlock: (d) => BlockListOps.canAdd(blocks, d, limits: _limits),
                    fitsSection: (p) => BlockListOps.canInsert(blocks, p.create(), limits: _limits),
                    onAdd: (d) => _add(d, at: BlockPath(blocks.length)),
                    onAddSection: (p) => _addSection(p, at: BlockPath(blocks.length)),
                  ),
              ],
            ),
          ),
          if (widget.siteFooter case final footer?) _ChromeFrame(part: 'footer', selected: _chrome == 'footer', onTap: () => _selectChrome('footer'), child: footer),
        ],
      );
    });
  }

  // ------------------------------------------------------------ structure

  Widget _structure() {
    final blocks = _blocks;
    final canAdd = BlockListOps.pageHasRoom(blocks, limits: _limits);
    final count = BlockRegistry.flatten(blocks).length;
    final hasProblems = BlockListOps.walk(blocks).any((e) => BlockRegistry.blockProblems(e.$2).isNotEmpty);
    final rows = <Widget>[];
    // A block's row, then (for a section, columns block or row) each of its
    // columns with its Add and its blocks, indented one step further.
    void add(BlockPath path, WebsiteBlock block, String number, int count) {
      rows.add(_row(path, block, number, count));
      for (final (c, column) in BlockListOps.columnsOf(block).indexed) {
        final inRow = block.type == rowType;
        rows.add(Padding(
          key: Key('website-structure-column-${column.id}'),
          padding: EdgeInsets.fromLTRB(20.0 * (path.depth + 1), 2, 0, 4),
          child: Row(
            children: [
              Expanded(
                child: Text('${inRow ? 'Inner column' : 'Column'} ${c + 1}${column.blocks.isEmpty ? ' (empty)' : ''}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
              ),
              _AddMenu(
                menuKey: 'website-column-${column.id}-add',
                label: 'Add',
                enabled: BlockListOps.columnAtHasRoom(blocks, path, c, limits: _limits),
                disabledTooltip: _columnFullReason(),
                types: BlockRegistry.nestableIn(block.type),
                fits: (d) => _fitsInColumn(path, c, d),
                onSelected: (d) => _addToColumn(path, c, d),
                onBrowseTemplates: _templatesOn ? () => _browseTemplates(container: path, column: c) : null,
              ),
            ],
          ),
        ));
        for (final (j, child) in column.blocks.indexed) {
          add(BlockPath.inside(path, c, j), child, '$number.${c + 1}.${j + 1}', column.blocks.length);
        }
      }
    }

    for (final (i, block) in blocks.indexed) {
      add(BlockPath(i), block, '${i + 1}', blocks.length);
    }
    return ColoredBox(
      color: Colors.white,
      child: ListView(
        key: const Key('website-editor-structure'),
        padding: const EdgeInsets.all(12),
        children: [
          const Text('Structure', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          Wrap(
            spacing: 4,
            children: [
              _SectionMenu(
                menuKey: 'website-sections-add',
                label: 'Add section',
                enabled: canAdd,
                fits: (p) => BlockListOps.canInsert(blocks, p.create(), limits: _limits),
                onSelected: _addSection,
                onBrowseTemplates: _templatesOn ? () => _browseTemplates(kinds: const {WebsiteTemplateKind.section}) : null,
              ),
              _AddMenu(
                menuKey: 'website-blocks-add',
                label: 'Add block',
                enabled: canAdd,
                disabledTooltip: 'This page has reached its limit of ${_limits.maxBlocks} blocks',
                types: BlockRegistry.topLevel,
                fits: (d) => BlockListOps.canAdd(blocks, d, limits: _limits),
                onSelected: _add,
                onBrowseTemplates: _templatesOn ? () => _browseTemplates(kinds: const {WebsiteTemplateKind.block}) : null,
              ),
            ],
          ),
          Text(
            '$count of ${_limits.maxBlocks} blocks used (sections and the blocks inside them each count). Select a block to edit it; new blocks go after the selected one.',
            key: const Key('website-custom-uses-blocks'),
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          if (_limitsNote case final note?)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(note, key: const Key('website-blocks-limit-setting-note'), style: const TextStyle(color: Color(0xFFB3261E), fontSize: 12)),
            ),
          if (count >= _limits.maxBlocks - 2)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                count > _limits.maxBlocks
                    ? 'This page has $count blocks, more than the limit of ${_limits.maxBlocks}: its blocks can still be edited, moved, deleted, saved and published, '
                        'but no more can be added until it has fewer than ${_limits.maxBlocks}.'
                    : count == _limits.maxBlocks
                        ? _limitMessage
                        : 'Nearly full: a new section needs room for itself and a block inside it.',
                key: const Key('website-custom-blocks-limit'),
                style: const TextStyle(color: Color(0xFF8A6A33), fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          const SizedBox(height: 8),
          if (blocks.isEmpty) const Text('No blocks yet. Add one here or on the page.', style: TextStyle(color: AppColors.textSecondary)),
          ...rows,
          if (hasProblems)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('website-editor-first-problem'),
                onPressed: _selectFirstProblem,
                icon: const Icon(Icons.error_outline, color: Color(0xFFB3261E)),
                label: const Text('Show the first block to fix'),
              ),
            ),
          widget.checks,
        ],
      ),
    );
  }

  Widget _row(BlockPath path, WebsiteBlock block, String number, int count) {
    final structured = block is StructuredBlock ? block : null;
    return _StructureRow(
      block: block,
      number: number,
      depth: path.depth,
      selected: _selected == path,
      first: path.position == 0,
      last: path.position == count - 1,
      canDuplicate: BlockListOps.canDuplicate(_blocks, path, limits: _limits),
      onSelect: () => _select(path),
      onEdit: structured == null ? null : () => _select(path, edit: true),
      onMove: (d) => _move(path, d),
      columns: path.isNested ? BlockListOps.columnsOf(BlockListOps.at(_blocks, path.parent!)!).length : 0,
      column: path.column,
      canMoveToColumn: (c) => BlockListOps.canMoveToColumn(_blocks, path, c, limits: _limits),
      onMoveToColumn: (c) => _moveToColumn(path, c),
      onDuplicate: () => _duplicate(path),
      onToggleHidden: () => _toggleHidden(path),
      onDelete: () => _delete(path),
      // A Columns / Row lives only in a section's column: saved with its
      // section, not on its own.
      onSaveTemplate: _templatesOn && structured != null && structured.type != rowType ? () => _saveTemplate(path) : null,
      columnsSummary: _columnsSummary(block),
    );
  }

  // ------------------------------------------------------------ properties

  Widget _properties() {
    final path = _selected;
    final block = _selectedBlock;
    final children = <Widget>[];
    if (_chrome case final part?) {
      children.addAll([
        Row(
          children: [
            Icon(part == 'header' ? Icons.web_asset : Icons.call_to_action_outlined, color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(child: Text(part == 'header' ? 'Site header' : 'Site footer', key: const Key('website-inspector-title'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
            TextButton(key: const Key('website-inspector-close'), onPressed: () => _select(null), child: const Text('Page settings')),
          ],
        ),
        Container(
          key: Key('website-inspector-site-$part'),
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: const Color(0xFFF3EADB), borderRadius: BorderRadius.circular(8)),
          child: Text(
            'The ${part == 'header' ? 'header' : 'footer'} is shared by every page of the website: a change there applies to all of them. '
            'It is edited, previewed and published in Site layout & design.',
            style: const TextStyle(fontSize: 13),
          ),
        ),
        ?widget.siteChromeInfo?.call(part),
      ]);
    } else if (path == null || block == null) {
      children.addAll([
        const Text('Page settings', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const Padding(
          padding: EdgeInsets.only(top: 2, bottom: 8),
          child: Text('Select a block on the page or in the structure to edit it.', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        ),
        widget.pageSettings,
      ]);
    } else {
      final problems = BlockRegistry.blockProblems(block);
      children.addAll([
        Row(
          children: [
            Icon(blockIcon(block), color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(child: Text(_label(block), key: const Key('website-inspector-title'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
            TextButton(key: const Key('website-inspector-close'), onPressed: () => _select(null), child: const Text('Page settings')),
          ],
        ),
        if (path.isNested) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('website-inspector-parent'),
              onPressed: () => _select(path.parent!, edit: true),
              icon: const Icon(Icons.arrow_back, size: 18),
              label: Text('${_label(BlockListOps.at(_blocks, path.parent!)!)} block'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(_location(path), key: const Key('website-inspector-location'), style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ),
        ],
        if (block is StructuredBlock && block.hidden)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('Hidden: kept in the page, but not shown to visitors.', style: TextStyle(fontSize: 12, color: Color(0xFF6E6E73))),
          ),
        if (problems.isNotEmpty)
          Container(
            key: const Key('website-inspector-problems'),
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: const Color(0xFFFCEEEE), borderRadius: BorderRadius.circular(8)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('To fix before saving:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                for (final p in problems) Text('• ${p[0].toUpperCase()}${p.substring(1)}.', style: const TextStyle(fontSize: 12, color: Color(0xFFB3261E))),
              ],
            ),
          ),
        if (block is StructuredBlock && block.type == BlockRegistry.galleryFeed.type) _photoGalleryHint(path),
        const SizedBox(height: 4),
        if (block is StructuredBlock)
          WebsiteBlockForm(
            block: block,
            library: widget.library,
            albums: widget.albums,
            generation: widget.generation,
            onChanged: (b) => widget.onChanged(BlockListOps.replace(_blocks, path, b)),
            onSelectNested: containerTypes.contains(block.type) && path.depth < 2 ? (c, j) => _select(BlockPath.inside(path, c, j), edit: true) : null,
            onAddToColumn: containerTypes.contains(block.type) && path.depth < 2 ? (c, d) => _addToColumn(path, c, d) : null,
            screen: _screen,
            design: widget.design,
          )
        else
          const Text(
            'This block was made with a newer version of the website editor. It is kept unchanged and not shown to visitors. You can move or delete it in the structure.',
            key: Key('website-inspector-locked'),
            style: TextStyle(fontSize: 13),
          ),
      ]);
    }
    return ColoredBox(
      color: Colors.white,
      child: ListView(key: const Key('website-editor-properties'), padding: const EdgeInsets.all(16), children: children),
    );
  }
}

/// The "Add" menu of every block type in [types].
class _AddMenu extends StatelessWidget {
  const _AddMenu({required this.menuKey, required this.label, required this.enabled, required this.disabledTooltip, required this.types, required this.onSelected, this.fits, this.onBrowseTemplates});

  /// Opens the template library (an item at the top, `<menuKey>-templates`).
  final VoidCallback? onBrowseTemplates;

  /// Whether a type fits on the page (one that doesn't is disabled, with the reason).
  final bool Function(BlockDefinition)? fits;

  final String menuKey;
  final String label;
  final bool enabled;
  final String disabledTooltip;
  final List<BlockDefinition> types;
  final ValueChanged<BlockDefinition> onSelected;

  @override
  Widget build(BuildContext context) {
    final color = enabled ? AppColors.primary : AppColors.textSecondary;
    return PopupMenuButton<BlockDefinition>(
      key: Key(menuKey),
      enabled: enabled,
      tooltip: enabled ? 'Add a block' : disabledTooltip,
      onSelected: onSelected,
      itemBuilder: (context) => [
        if (onBrowseTemplates != null) ...[
          _browseItem('$menuKey-templates', 'Browse block templates…', 'Insert a block saved by your school', onBrowseTemplates!),
          const PopupMenuDivider(),
        ],
        for (final d in types)
          PopupMenuItem(
            key: Key('$menuKey-${d.type}'),
            value: d,
            enabled: fits?.call(d) ?? true,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(blockIcon(StructuredBlock(definition: d, id: '')), size: 20),
              title: Text(d.label),
              subtitle: Text((fits?.call(d) ?? true) ? d.description : 'No room on this page: it needs space for a block inside it'),
            ),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        // Shortened rather than overflowing in a narrow column.
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.add, color: color, size: 20),
          const SizedBox(width: 4),
          Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: color, fontWeight: FontWeight.w600))),
        ]),
      ),
    );
  }
}

/// A menu item that opens the template library (after the menu closes).
PopupMenuItem<T> _browseItem<T>(String key, String title, String subtitle, VoidCallback onBrowse) => PopupMenuItem<T>(
      key: Key(key),
      onTap: () => Future(onBrowse),
      child: ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.collections_bookmark_outlined, size: 20),
        title: Text(title),
        subtitle: Text(subtitle),
      ),
    );

/// "Add section": the ready-made section layouts ([SectionPreset]).
class _SectionMenu extends StatelessWidget {
  const _SectionMenu({required this.menuKey, required this.label, required this.enabled, required this.onSelected, this.fits, this.onBrowseTemplates});

  /// Opens the template library (an item at the top, `<menuKey>-templates`).
  final VoidCallback? onBrowseTemplates;

  /// Whether a section fits on the page with its blocks and room for one
  /// more (one that doesn't is disabled, with the reason).
  final bool Function(SectionPreset)? fits;

  final String menuKey;
  final String label;
  final bool enabled;
  final ValueChanged<SectionPreset> onSelected;

  @override
  Widget build(BuildContext context) {
    final color = enabled ? AppColors.primary : AppColors.textSecondary;
    return PopupMenuButton<SectionPreset>(
      key: Key(menuKey),
      enabled: enabled,
      tooltip: enabled ? 'Add a section' : 'This page has reached its block limit',
      onSelected: onSelected,
      itemBuilder: (context) => [
        if (onBrowseTemplates != null) ...[
          _browseItem('$menuKey-templates', 'Browse section templates…', 'Insert a section saved by your school', onBrowseTemplates!),
          const PopupMenuDivider(),
        ],
        for (final p in SectionPreset.all)
          PopupMenuItem(
            key: Key('$menuKey-${p.id}'),
            value: p,
            enabled: fits?.call(p) ?? true,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.view_agenda_outlined, size: 20),
              title: Text(p.label),
              subtitle: Text((fits?.call(p) ?? true) ? p.description : 'No room on this page for this section and a block in it'),
            ),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.view_agenda_outlined, color: color, size: 20),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}

/// A `+` between sections and blocks on the canvas: adds a section (from
/// a ready-made layout) or a block at [index]. As tall as the space
/// visitors see above the block that follows.
class _InsertPoint extends StatelessWidget {
  const _InsertPoint({required this.index, required this.height, required this.canAdd, required this.onAdd, required this.onAddSection, this.fitsBlock, this.fitsSection});

  /// Whether each choice fits on the page (one that doesn't is shown
  /// disabled, with the reason).
  final bool Function(BlockDefinition)? fitsBlock;
  final bool Function(SectionPreset)? fitsSection;

  final int index;
  final double height;
  final bool canAdd;
  final ValueChanged<BlockDefinition> onAdd;
  final ValueChanged<SectionPreset> onAddSection;

  @override
  Widget build(BuildContext context) {
    final line = Expanded(child: Divider(color: AppColors.primary.withValues(alpha: 0.18), thickness: 1));
    final k = 'website-canvas-insert-$index';
    return SizedBox(
      height: math.max(height, 36),
      child: Row(
        children: [
          line,
          PopupMenuButton<Object>(
            key: Key(k),
            enabled: canAdd,
            tooltip: canAdd ? 'Add a section or block here' : 'This page has reached its block limit',
            onSelected: (choice) => choice is SectionPreset ? onAddSection(choice) : onAdd(choice as BlockDefinition),
            itemBuilder: (context) => [
              const PopupMenuItem<Object>(enabled: false, height: 32, child: Text('ADD A SECTION', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1))),
              for (final p in SectionPreset.all)
                if (fitsSection?.call(p) ?? true)
                  PopupMenuItem<Object>(key: Key('$k-section-${p.id}'), value: p, child: Text(p.label))
                else
                  PopupMenuItem<Object>(key: Key('$k-section-${p.id}'), enabled: false, child: Text('${p.label} (no room on this page)')),
              const PopupMenuDivider(),
              const PopupMenuItem<Object>(enabled: false, height: 32, child: Text('ADD A BLOCK', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1))),
              for (final d in BlockRegistry.topLevel)
                PopupMenuItem<Object>(
                  key: Key('$k-${d.type}'),
                  value: d,
                  enabled: fitsBlock?.call(d) ?? true,
                  child: Tooltip(message: d.description, child: Text((fitsBlock?.call(d) ?? true) ? d.label : '${d.label} (no room on this page)')),
                ),
            ],
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.primary.withValues(alpha: canAdd ? 0.6 : 0.2)),
              ),
              child: Icon(Icons.add, size: 18, color: AppColors.primary.withValues(alpha: canAdd ? 1 : 0.3)),
            ),
          ),
          line,
        ],
      ),
    );
  }
}

/// The site's real header or footer on the canvas: shown as visitors see
/// it (nothing inside reacts) and selectable, marked as shared by every
/// page.
class _ChromeFrame extends StatelessWidget {
  const _ChromeFrame({required this.part, required this.selected, required this.onTap, required this.child});

  final String part;
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      selected: selected,
      label: 'Site $part, shared by every page',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: Key('website-canvas-site-$part'),
          onTap: onTap,
          hoverColor: AppColors.primary.withValues(alpha: 0.04),
          child: Container(
            decoration: BoxDecoration(border: Border.all(color: selected ? AppColors.primary : Colors.transparent, width: 2)),
            child: Stack(
              children: [
                AbsorbPointer(child: child),
                if (selected)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(8)),
                      child: Text('Site $part · every page', style: const TextStyle(fontSize: 12, color: Colors.white)),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A block on the canvas (top-level, or inside a section or columns): its
/// public rendering or a placeholder ([content]), selectable by click, tap
/// or keyboard (Enter selects; Delete deletes after confirming; Alt+↑/↓
/// moves), with an outline and a toolbar when selected. While a block
/// inside it is selected ([childSelected]) it keeps an outline but not its
/// toolbar or keys, which act on the whole block.
class _CanvasBlock extends StatelessWidget {
  const _CanvasBlock({
    required this.block,
    required this.content,
    required this.absorb,
    required this.position,
    required this.count,
    required this.selected,
    required this.childSelected,
    required this.canDuplicate,
    required this.onSelect,
    required this.onMove,
    required this.onDuplicate,
    required this.onToggleHidden,
    required this.onDelete,
    this.onSaveTemplate,
    this.columnsControl,
  });

  final WebsiteBlock block;
  final Widget content;

  /// Saves it as a template (null: templates aren't available here).
  final VoidCallback? onSaveTemplate;

  /// A section's or columns block's Columns control, in its toolbar.
  final Widget? columnsControl;

  /// Clicks inside only select the block (false for containers, whose
  /// blocks are selectable themselves).
  final bool absorb;

  /// Its place in its list, and the list's length.
  final int position;
  final int count;
  final bool selected;
  final bool childSelected;
  final bool canDuplicate;
  final VoidCallback onSelect;
  final ValueChanged<int> onMove;
  final VoidCallback onDuplicate;
  final VoidCallback onToggleHidden;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final structured = block is StructuredBlock ? block as StructuredBlock : null;
    final label = structured?.definition.label ?? 'Unsupported block';
    final problems = structured == null ? const <String>[] : BlockRegistry.blockProblems(structured);
    final id = block.id;
    final outline = selected || childSelected
        ? AppColors.primary
        : problems.isNotEmpty
            ? const Color(0xFFB3261E).withValues(alpha: 0.5)
            : Colors.transparent;
    return CallbackShortcuts(
      // Keys act on the whole block only while it is the selection.
      bindings: childSelected
          ? const {}
          : {
              const SingleActivator(LogicalKeyboardKey.delete): onDelete,
              const SingleActivator(LogicalKeyboardKey.backspace): onDelete,
              const SingleActivator(LogicalKeyboardKey.arrowUp, alt: true): () => onMove(-1),
              const SingleActivator(LogicalKeyboardKey.arrowDown, alt: true): () => onMove(1),
            },
      child: Semantics(
        container: true,
        selected: selected,
        label: '$label block ${position + 1} of $count',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: Key('website-canvas-block-$id'),
            onTap: onSelect,
            borderRadius: BorderRadius.circular(10),
            hoverColor: AppColors.primary.withValues(alpha: 0.04),
            focusColor: AppColors.primary.withValues(alpha: 0.08),
            // The outline is drawn over the block, taking no space: the canvas
            // lays blocks out exactly as the website does, and selecting one
            // moves nothing.
            child: Container(
              foregroundDecoration: BoxDecoration(border: Border.all(color: outline, width: selected ? 2 : 1), borderRadius: BorderRadius.circular(10)),
              child: Stack(
                children: [
                  if (absorb) AbsorbPointer(child: content) else content,
                  if (childSelected)
                    Positioned(
                      top: 0,
                      right: 0,
                      child: Container(
                        key: Key('website-canvas-child-selected-$id'),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(8)),
                        child: Text('Editing a block in this ${label.toLowerCase()}', style: const TextStyle(fontSize: 12, color: Colors.white)),
                      ),
                    ),
                  if (selected)
                    Positioned(
                      top: 0,
                      right: 0,
                      child: Material(
                        key: Key('website-canvas-toolbar-$id'),
                        elevation: 3,
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                            ?columnsControl,
                            _ToolButton(key: Key('website-canvas-$id-up'), tooltip: 'Move up', icon: Icons.arrow_upward, onPressed: position == 0 ? null : () => onMove(-1)),
                            _ToolButton(key: Key('website-canvas-$id-down'), tooltip: 'Move down', icon: Icons.arrow_downward, onPressed: position == count - 1 ? null : () => onMove(1)),
                            if (structured != null) ...[
                              _ToolButton(key: Key('website-canvas-$id-duplicate'), tooltip: 'Duplicate', icon: Icons.copy_outlined, onPressed: canDuplicate ? onDuplicate : null),
                              if (onSaveTemplate != null)
                                _ToolButton(key: Key('website-canvas-$id-save-template'), tooltip: 'Save as template', icon: Icons.bookmark_add_outlined, onPressed: onSaveTemplate),
                              _ToolButton(
                                key: Key('website-canvas-$id-visibility'),
                                tooltip: structured.hidden ? 'Show' : 'Hide',
                                icon: structured.hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                onPressed: onToggleHidden,
                              ),
                            ],
                            _ToolButton(key: Key('website-canvas-$id-delete'), tooltip: 'Delete', icon: Icons.delete_outline, onPressed: onDelete),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({super.key, required this.tooltip, required this.icon, required this.onPressed});

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) =>
      IconButton(tooltip: tooltip, onPressed: onPressed, icon: Icon(icon, size: 18), visualDensity: VisualDensity.compact, constraints: const BoxConstraints(minWidth: 36, minHeight: 36));
}

/// What the canvas shows for a block visitors wouldn't see, and why.
class _CanvasPlaceholder extends StatelessWidget {
  const _CanvasPlaceholder({required this.block, required this.media});

  final WebsiteBlock block;
  final Map<String, WebsiteMedia> media;

  (IconData, String, String, bool) _describe() {
    final b = block;
    if (b is! StructuredBlock) {
      return (Icons.lock_outline, 'Unsupported block${b.type.isEmpty ? '' : ' (“${b.type}”)'}', 'Made with a newer version of the editor. Kept unchanged and not shown to visitors.', false);
    }
    final label = b.definition.label;
    if (b.hidden) return (Icons.visibility_off_outlined, 'Hidden: $label', '${blockSummary(b)}\nKept in the page, but not shown to visitors.', false);
    final problems = BlockRegistry.blockProblems(b);
    if (problems.isNotEmpty) {
      final first = problems.first;
      return (Icons.error_outline, '$label: to fix', '${first[0].toUpperCase()}${first.substring(1)}${problems.length > 1 ? ' (and ${problems.length - 1} more)' : ''}. Not shown to visitors until fixed.', true);
    }
    return switch (b.type) {
      // (An image block without an image has a problem, above.)
      'image' => (Icons.image_outlined, 'Image', 'This image isn’t published yet, so visitors don’t see it. Publish it in the Media library.', false),
      'gallery' => (Icons.grid_view_outlined, label, 'No published images yet. Add images in its properties.', false),
      'columns' || 'section' || 'row' => (Icons.view_column_outlined, label, 'Nothing to show yet. Add blocks to it.', false),
      _ => (blockIcon(b), label, 'Nothing to show visitors yet.', false),
    };
  }

  @override
  Widget build(BuildContext context) {
    final (icon, title, detail, error) = _describe();
    final color = error ? const Color(0xFFB3261E) : const Color(0xFF6E6E73);
    return LayoutBuilder(builder: (context, constraints) {
      // In a very narrow column (e.g. four inner columns of a row in a
      // quarter of a section): its icon only, named in a tooltip.
      if (constraints.maxWidth < 140) {
        return Tooltip(
          message: '$title. $detail',
          child: Container(
            key: Key('website-canvas-placeholder-${block.id}'),
            padding: const EdgeInsets.symmetric(vertical: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: error ? const Color(0xFFFCEEEE) : const Color(0xFFF2F2F4),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withValues(alpha: 0.4)),
            ),
            child: Icon(icon, color: color, size: constraints.maxWidth < 28 ? constraints.maxWidth * 0.8 : 24),
          ),
        );
      }
      return _full(icon, title, detail, error, color);
    });
  }

  Widget _full(IconData icon, String title, String detail, bool error, Color color) {
    return Container(
      key: Key('website-canvas-placeholder-${block.id}'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: error ? const Color(0xFFFCEEEE) : const Color(0xFFF2F2F4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: color)),
                const SizedBox(height: 4),
                Text(detail, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One block in the structure: its type, number, state and summary, and
/// its actions. Click to select; the edit button also opens its
/// properties.
class _StructureRow extends StatelessWidget {
  const _StructureRow({
    required this.block,
    required this.number,
    required this.depth,
    required this.selected,
    required this.first,
    required this.last,
    required this.canDuplicate,
    required this.onSelect,
    required this.onEdit,
    required this.onMove,
    this.columns = 0,
    this.column,
    this.canMoveToColumn,
    this.onMoveToColumn,
    required this.onDuplicate,
    required this.onToggleHidden,
    required this.onDelete,
    this.onSaveTemplate,
    this.columnsSummary,
  });

  /// Saves it as a template (null: not offered).
  final VoidCallback? onSaveTemplate;

  /// A section's or columns block's columns ("3 columns · Tablet: 2 per
  /// row"), shown on its row; null for other blocks.
  final String? columnsSummary;

  final WebsiteBlock block;
  final String number;

  /// How many containers it is inside (indented one step for each).
  final int depth;
  bool get nested => depth > 0;
  final bool selected;
  final bool first;
  final bool last;
  final bool canDuplicate;
  final VoidCallback onSelect;
  final VoidCallback? onEdit;
  final ValueChanged<int> onMove;

  /// Inside a column: how many columns its section has, which one it is
  /// in, and moving it to another.
  final int columns;
  final int? column;
  final bool Function(int column)? canMoveToColumn;
  final ValueChanged<int>? onMoveToColumn;
  final VoidCallback onDuplicate;
  final VoidCallback onToggleHidden;
  final VoidCallback onDelete;

  /// Duplicate, Hide/Show, Move to column…, Save as template and Delete,
  /// each with its name (keys `website-block-<id>-<action>`).
  Widget _moreMenu(String id, String label, StructuredBlock? structured) {
    final moves = nested && columns > 1 && onMoveToColumn != null;
    PopupMenuItem<String> item(String value, IconData icon, String text, {bool enabled = true, Color? color}) => PopupMenuItem<String>(
          key: Key('website-block-$id-$value'),
          value: value,
          enabled: enabled,
          child: Row(children: [Icon(icon, size: 18, color: enabled ? color : null), const SizedBox(width: 12), Flexible(child: Text(text, style: TextStyle(color: enabled ? color : null)))]),
        );
    return PopupMenuButton<String>(
      key: Key('website-block-$id-more'),
      tooltip: 'More actions for $number. $label',
      icon: const Icon(Icons.more_vert, size: 20),
      onSelected: (v) {
        if (v.startsWith('to-column-')) return onMoveToColumn?.call(int.parse(v.substring('to-column-'.length)));
        switch (v) {
          case 'duplicate':
            onDuplicate();
          case 'visibility':
            onToggleHidden();
          case 'save-template':
            onSaveTemplate?.call();
          case 'columns':
            onEdit?.call();
          case 'delete':
            onDelete();
        }
      },
      itemBuilder: (context) => [
        if (structured != null) ...[
          item('duplicate', Icons.copy_outlined, 'Duplicate', enabled: canDuplicate),
          item('visibility', structured.hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined, structured.hidden ? 'Show to visitors' : 'Hide from visitors'),
        ],
        if (moves)
          for (var c = 0; c < columns; c++)
            if (c != column)
              item('to-column-$c', Icons.view_column_outlined, (canMoveToColumn?.call(c) ?? true) ? 'Move to column ${c + 1}' : 'Column ${c + 1} is full',
                  enabled: canMoveToColumn?.call(c) ?? true),
        if (columnsSummary != null && onEdit != null) item('columns', Icons.view_column_outlined, 'Columns and layout…'),
        if (onSaveTemplate != null && structured != null) item('save-template', Icons.bookmark_add_outlined, 'Save as template'),
        const PopupMenuDivider(),
        item('delete', Icons.delete_outline, 'Delete…', color: const Color(0xFFB3261E)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final b = block;
    final id = b.id;
    final structured = b is StructuredBlock ? b : null;
    final problems = structured == null ? const <String>[] : BlockRegistry.blockProblems(structured);
    final name = structured?.type == 'section' || structured?.type == rowType ? structured!.text('name').en.trim() : '';
    final label = name.isNotEmpty
        ? '${structured!.type == rowType ? 'Row' : 'Section'} · $name'
        : structured?.definition.label ?? 'Unsupported block${b.type.isEmpty ? '' : ' (“${b.type}”)'}';
    Widget action(String suffix, String tooltip, IconData icon, VoidCallback? onPressed) =>
        _ToolButton(key: Key('website-block-$id-$suffix'), tooltip: tooltip, icon: icon, onPressed: onPressed);
    return Padding(
      padding: EdgeInsets.only(left: 20.0 * depth, bottom: 6),
      child: Card(
        key: Key('website-block-$id'),
        margin: EdgeInsets.zero,
        elevation: 0,
        color: selected ? AppColors.primary.withValues(alpha: 0.08) : AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: selected ? AppColors.primary : Colors.grey.shade300, width: selected ? 1.5 : 1),
        ),
        child: InkWell(
          key: Key('website-block-$id-select'),
          borderRadius: BorderRadius.circular(10),
          onTap: onSelect,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 4, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(blockIcon(b), size: 18, color: AppColors.textSecondary),
                    const SizedBox(width: 8),
                    Expanded(child: Text('$number. $label', overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
                  ],
                ),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (structured == null) WebsiteStatusChip(key: Key('website-block-$id-locked'), label: 'Locked', color: const Color(0xFF6E6E73)),
                    if (structured?.hidden == true) WebsiteStatusChip(key: Key('website-block-$id-hidden'), label: 'Hidden', color: const Color(0xFF6E6E73)),
                    if (problems.isNotEmpty) WebsiteStatusChip(key: Key('website-block-$id-problems'), label: '${problems.length} to fix', color: const Color(0xFFB3261E)),
                    if (columnsSummary != null) WebsiteStatusChip(key: Key('website-block-$id-columns-chip'), label: columnsSummary!, color: AppColors.primary),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 2, right: 6),
                  child: Text(blockSummary(b), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                ),
                // Four controls at most, so the row never wraps (and a tap
                // on it never lands on a button that moved under it):
                // Edit, Move up, Move down, and the other actions in a
                // menu, each named there.
                Row(
                  children: [
                    if (onEdit != null) ...[action('edit', 'Edit properties', Icons.edit_outlined, onEdit), const SizedBox(width: 4)],
                    action('up', 'Move up', Icons.arrow_upward, first ? null : () => onMove(-1)),
                    const SizedBox(width: 4),
                    action('down', 'Move down', Icons.arrow_downward, last ? null : () => onMove(1)),
                    const Spacer(),
                    _moreMenu(id, label, structured),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
