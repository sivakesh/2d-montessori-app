import 'dart:async';

import 'package:feature_publishing/feature_publishing.dart';
import 'package:flutter/material.dart';

import '../domain/call_to_action.dart';
import '../domain/media_reference.dart';
import '../domain/page_content_update.dart';
import '../domain/page_section.dart';
import '../domain/page_type.dart';
import '../domain/seo_metadata.dart';
import 'page_editor_controller.dart';
import 'page_preview_screen.dart';
import 'section_editor_dialog.dart';

/// The Pages editor: content fields, SEO fields, section management
/// (add/reorder/edit/delete/hide from the nine approved types only —
/// there is no "custom HTML" option anywhere in this screen), autosave,
/// validation, preview, revision history and every workflow action —
/// each button only appears when [PublishingStateMachine] has a matching
/// edge from the page's current status *and*
/// `RolePermissionMatrix.hasFull` allows this user to use it, so the
/// available actions are always derived from the single source of truth
/// rather than hand-maintained per screen. No own [Scaffold]/[AppBar],
/// matching `UserManagementScreen`/`PagesListScreen`.
class PageEditorScreen extends StatefulWidget {
  const PageEditorScreen({
    super.key,
    required this.controller,
    required this.onClose,
  });

  final PageEditorController controller;
  final VoidCallback onClose;

  @override
  State<PageEditorScreen> createState() => _PageEditorScreenState();
}

class _PageEditorScreenState extends State<PageEditorScreen> {
  late final _title = TextEditingController(text: widget.controller.page.title);
  late final _slug = TextEditingController(text: widget.controller.page.slug);
  late final _summary = TextEditingController(
    text: widget.controller.page.summary,
  );
  late final _navigationLabel = TextEditingController(
    text: widget.controller.page.navigationLabel ?? '',
  );
  late PageType _pageType = widget.controller.page.pageType;
  late bool _showInNavigation = widget.controller.page.showInNavigation;
  late List<PageSection> _sections = List.of(widget.controller.page.sections);

  late final _featuredImageUrl = TextEditingController(
    text: widget.controller.page.featuredImage?.url ?? '',
  );
  late final _featuredImageAlt = TextEditingController(
    text: widget.controller.page.featuredImage?.altText ?? '',
  );

  late final _seoTitle = TextEditingController(
    text: widget.controller.page.seo.title ?? '',
  );
  late final _seoDescription = TextEditingController(
    text: widget.controller.page.seo.metaDescription ?? '',
  );
  late final _canonicalUrl = TextEditingController(
    text: widget.controller.page.seo.canonicalUrl ?? '',
  );
  late PageIndexingControl _indexing = widget.controller.page.seo.indexing;
  late final _socialTitle = TextEditingController(
    text: widget.controller.page.seo.social.title ?? '',
  );
  late final _socialDescription = TextEditingController(
    text: widget.controller.page.seo.social.description ?? '',
  );
  late final _socialImageUrl = TextEditingController(
    text: widget.controller.page.seo.social.image?.url ?? '',
  );

  Timer? _autosaveTimer;
  List<String> _lastViolations = const [];

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    for (final controller in [
      _title,
      _slug,
      _summary,
      _navigationLabel,
      _featuredImageUrl,
      _featuredImageAlt,
      _seoTitle,
      _seoDescription,
      _canonicalUrl,
      _socialTitle,
      _socialDescription,
      _socialImageUrl,
    ]) {
      controller.addListener(_scheduleAutosave);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _autosaveTimer?.cancel();
    for (final controller in [
      _title,
      _slug,
      _summary,
      _navigationLabel,
      _featuredImageUrl,
      _featuredImageAlt,
      _seoTitle,
      _seoDescription,
      _canonicalUrl,
      _socialTitle,
      _socialDescription,
      _socialImageUrl,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  /// SRS CMS-07: "Editing screens autosave drafts, show saving/last-saved
  /// status." Debounced so we save once typing pauses, not on every
  /// keystroke.
  void _scheduleAutosave() {
    if (!widget.controller.canEditContent) return;
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(const Duration(seconds: 2), _save);
  }

  PageContentUpdate _buildUpdate() => PageContentUpdate(
    title: _title.text,
    slug: _slug.text,
    summary: _summary.text,
    pageType: _pageType,
    sections: _sections,
    featuredImage: _featuredImageUrl.text.trim().isEmpty
        ? null
        : MediaReference(
            url: _featuredImageUrl.text.trim(),
            altText: _featuredImageAlt.text.trim(),
          ),
    seo: SeoMetadata(
      title: _seoTitle.text.trim().isEmpty ? null : _seoTitle.text.trim(),
      metaDescription: _seoDescription.text.trim().isEmpty
          ? null
          : _seoDescription.text.trim(),
      canonicalUrl: _canonicalUrl.text.trim().isEmpty
          ? null
          : _canonicalUrl.text.trim(),
      indexing: _indexing,
      social: SocialShareMetadata(
        title: _socialTitle.text.trim().isEmpty
            ? null
            : _socialTitle.text.trim(),
        description: _socialDescription.text.trim().isEmpty
            ? null
            : _socialDescription.text.trim(),
        image: _socialImageUrl.text.trim().isEmpty
            ? null
            : MediaReference(
                url: _socialImageUrl.text.trim(),
                altText: _socialTitle.text.trim(),
              ),
      ),
    ),
    navigationLabel: _navigationLabel.text.trim().isEmpty
        ? null
        : _navigationLabel.text.trim(),
    showInNavigation: _showInNavigation,
  );

  Future<void> _save() async {
    await widget.controller.saveContent(_buildUpdate());
  }

  Future<void> _addSection(PageSectionType type) async {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final sortOrder = _sections.isEmpty
        ? 0
        : _sections.map((s) => s.sortOrder).reduce((a, b) => a > b ? a : b) + 1;
    final draft = switch (type) {
      PageSectionType.richText => RichTextSection(
        id: id,
        sortOrder: sortOrder,
        body: '',
      ),
      PageSectionType.image => ImageSection(
        id: id,
        sortOrder: sortOrder,
        image: const MediaReference(url: '', altText: ''),
      ),
      PageSectionType.imageText => ImageTextSection(
        id: id,
        sortOrder: sortOrder,
        body: '',
        image: const MediaReference(url: '', altText: ''),
      ),
      PageSectionType.cta => CtaSection(
        id: id,
        sortOrder: sortOrder,
        primaryCta: const CallToAction(
          label: '',
          linkType: CallToActionLinkType.internal,
          target: '',
        ),
      ),
      PageSectionType.highlights => HighlightsSection(
        id: id,
        sortOrder: sortOrder,
        cards: const [],
      ),
      PageSectionType.faq => FaqSection(
        id: id,
        sortOrder: sortOrder,
        items: const [],
      ),
      PageSectionType.gallery => GallerySection(
        id: id,
        sortOrder: sortOrder,
        items: const [],
      ),
      PageSectionType.testimonial => TestimonialSection(
        id: id,
        sortOrder: sortOrder,
        items: const [],
      ),
      PageSectionType.relatedContent => RelatedContentSection(
        id: id,
        sortOrder: sortOrder,
        relatedPageIds: const [],
      ),
    };
    final edited = await SectionEditorDialog.show(context, draft);
    if (edited == null) return;
    setState(() => _sections = [..._sections, edited]);
    _scheduleAutosave();
  }

  Future<void> _editSection(int index) async {
    final edited = await SectionEditorDialog.show(context, _sections[index]);
    if (edited == null) return;
    setState(() => _sections[index] = edited);
    _scheduleAutosave();
  }

  void _removeSection(int index) {
    setState(() => _sections = [..._sections]..removeAt(index));
    _scheduleAutosave();
  }

  void _reorderSections(int oldIndex, int newIndex) {
    setState(() {
      final list = [..._sections];
      if (newIndex > oldIndex) newIndex -= 1;
      final item = list.removeAt(oldIndex);
      list.insert(newIndex, item);
      _sections = [
        for (var i = 0; i < list.length; i++)
          list[i].copyWithBase(sortOrder: i),
      ];
    });
    _scheduleAutosave();
  }

  Future<String?> _promptComment() => showDialog<String>(
    context: context,
    builder: (context) {
      final controller = TextEditingController();
      return AlertDialog(
        title: const Text('Reason for rejection'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Comment (required)'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Reject'),
          ),
        ],
      );
    },
  );

  Future<DateTime?> _promptScheduleDate() async {
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _runAction(PublishingAction action) async {
    final controller = widget.controller;
    bool ok;
    switch (action) {
      case PublishingAction.submitForReview:
        setState(() => _lastViolations = controller.completenessViolations);
        if (_lastViolations.isNotEmpty) return;
        ok = await controller.doSubmitForReview();
      case PublishingAction.approve:
        ok = await controller.doApprove();
      case PublishingAction.reject:
        final comment = await _promptComment();
        if (comment == null || comment.trim().isEmpty) return;
        ok = await controller.doReject(comment.trim());
      case PublishingAction.publish:
        setState(() => _lastViolations = controller.completenessViolations);
        if (_lastViolations.isNotEmpty) return;
        ok = await controller.doPublish();
      case PublishingAction.unpublish:
        ok = await controller.doUnpublish();
      case PublishingAction.schedule:
        setState(() => _lastViolations = controller.completenessViolations);
        if (_lastViolations.isNotEmpty) return;
        final at = await _promptScheduleDate();
        if (at == null) return;
        ok = await controller.doSchedule(at);
      case PublishingAction.unschedule:
        ok = await controller.doUnschedule();
      case PublishingAction.archive:
        ok = await controller.doArchive();
      case PublishingAction.restore:
        ok = await controller.doRestore();
    }
    if (!mounted) return;
    if (ok) setState(() => _lastViolations = const []);
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final page = controller.page;
    final availableActions = PublishingStateMachine.transitions
        .where(
          (rule) =>
              rule.from == page.status &&
              PublishingStateMachine.isAllowed(
                page.status,
                rule.action,
                controller.actingRole,
              ),
        )
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: widget.onClose,
              ),
              Expanded(
                child: Text(
                  page.title.isEmpty ? '(untitled)' : page.title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              Chip(label: Text(page.status.storageValue)),
              const SizedBox(width: 8),
              TextButton.icon(
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('Preview'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => PagePreviewScreen(page: page),
                  ),
                ),
              ),
              TextButton.icon(
                icon: const Icon(Icons.history),
                label: const Text('History'),
                onPressed: () async {
                  await controller.loadRevisions();
                  if (!context.mounted) return;
                  await showDialog<void>(
                    context: context,
                    builder: (_) =>
                        _RevisionHistoryDialog(controller: controller),
                  );
                },
              ),
            ],
          ),
        ),
        if (controller.lastErrorMessage != null)
          MaterialBanner(
            content: Text(controller.lastErrorMessage!),
            actions: [
              TextButton(
                onPressed: () => setState(() {}),
                child: const Text('Dismiss'),
              ),
            ],
          ),
        if (_lastViolations.isNotEmpty)
          Container(
            width: double.infinity,
            color: Theme.of(context).colorScheme.errorContainer,
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('This page is not ready:'),
                for (final v in _lastViolations) Text('• $v'),
              ],
            ),
          ),
        Expanded(
          child: AbsorbPointer(
            absorbing: !controller.canEditContent,
            child: Opacity(
              opacity: controller.canEditContent ? 1 : 0.6,
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!controller.canEditContent)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: Text(
                          'This page can only be edited while it is a draft you own (or you have edit-all-content permission).',
                        ),
                      ),
                    TextField(
                      controller: _title,
                      decoration: const InputDecoration(labelText: 'Title'),
                    ),
                    TextField(
                      controller: _slug,
                      decoration: const InputDecoration(labelText: 'URL slug'),
                    ),
                    TextField(
                      controller: _summary,
                      decoration: const InputDecoration(labelText: 'Summary'),
                      maxLines: 2,
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<PageType>(
                            initialValue: _pageType,
                            decoration: const InputDecoration(
                              labelText: 'Page type',
                            ),
                            items: PageType.values
                                .map(
                                  (t) => DropdownMenuItem(
                                    value: t,
                                    child: Text(t.storageValue),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) {
                              setState(() => _pageType = v ?? _pageType);
                              _scheduleAutosave();
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _navigationLabel,
                            decoration: const InputDecoration(
                              labelText: 'Navigation label (optional)',
                            ),
                          ),
                        ),
                      ],
                    ),
                    CheckboxListTile(
                      title: const Text(
                        'Show in site navigation once published',
                      ),
                      value: _showInNavigation,
                      onChanged: (v) {
                        setState(() => _showInNavigation = v ?? false);
                        _scheduleAutosave();
                      },
                    ),
                    TextField(
                      controller: _featuredImageUrl,
                      decoration: const InputDecoration(
                        labelText: 'Featured image URL (optional)',
                      ),
                    ),
                    TextField(
                      controller: _featuredImageAlt,
                      decoration: const InputDecoration(
                        labelText: 'Featured image alt text',
                      ),
                    ),
                    ExpansionTile(
                      title: const Text('SEO & social sharing'),
                      children: [
                        TextField(
                          controller: _seoTitle,
                          decoration: const InputDecoration(
                            labelText: 'SEO title',
                          ),
                        ),
                        TextField(
                          controller: _seoDescription,
                          decoration: const InputDecoration(
                            labelText: 'Meta description',
                          ),
                          maxLines: 2,
                        ),
                        TextField(
                          controller: _canonicalUrl,
                          decoration: const InputDecoration(
                            labelText: 'Canonical URL (optional)',
                          ),
                        ),
                        DropdownButtonFormField<PageIndexingControl>(
                          initialValue: _indexing,
                          decoration: const InputDecoration(
                            labelText: 'Search indexing',
                          ),
                          items: PageIndexingControl.values
                              .map(
                                (v) => DropdownMenuItem(
                                  value: v,
                                  child: Text(v.storageValue),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            setState(() => _indexing = v ?? _indexing);
                            _scheduleAutosave();
                          },
                        ),
                        TextField(
                          controller: _socialTitle,
                          decoration: const InputDecoration(
                            labelText: 'Social share title (optional)',
                          ),
                        ),
                        TextField(
                          controller: _socialDescription,
                          decoration: const InputDecoration(
                            labelText: 'Social share description (optional)',
                          ),
                        ),
                        TextField(
                          controller: _socialImageUrl,
                          decoration: const InputDecoration(
                            labelText: 'Social share image URL (optional)',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Text(
                          'Sections',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const Spacer(),
                        MenuAnchor(
                          builder: (context, menuController, child) =>
                              TextButton.icon(
                                icon: const Icon(Icons.add),
                                label: const Text('Add section'),
                                onPressed: () => menuController.isOpen
                                    ? menuController.close()
                                    : menuController.open(),
                              ),
                          menuChildren: PageSectionType.values
                              .map(
                                (type) => MenuItemButton(
                                  onPressed: () => _addSection(type),
                                  child: Text(type.storageValue),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ),
                    ReorderableListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _sections.length,
                      onReorder: _reorderSections,
                      itemBuilder: (context, index) {
                        final section = _sections[index];
                        return ListTile(
                          key: ValueKey(section.id),
                          leading: const Icon(Icons.drag_handle),
                          title: Text(section.type.storageValue),
                          subtitle: section.isVisible
                              ? null
                              : const Text('Hidden'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: () => _editSection(index),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => _removeSection(index),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (controller.canEditContent)
                FilledButton.icon(
                  onPressed: controller.isBusy ? null : _save,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Save draft'),
                ),
              if (controller.lastSavedAt != null)
                Text(
                  'Saved ${controller.lastSavedAt!.toLocal().toString().split('.').first}',
                ),
              for (final rule in availableActions)
                OutlinedButton(
                  onPressed: controller.isBusy
                      ? null
                      : () => _runAction(rule.action),
                  child: Text(rule.action.storageValue),
                ),
              if (controller.isBusy)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RevisionHistoryDialog extends StatelessWidget {
  const _RevisionHistoryDialog({required this.controller});

  final PageEditorController controller;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Revision history'),
      content: SizedBox(
        width: 400,
        height: 300,
        child: controller.revisions.isEmpty
            ? const Center(child: Text('No revisions yet.'))
            : ListView.builder(
                itemCount: controller.revisions.length,
                itemBuilder: (context, index) {
                  final revision = controller.revisions[index];
                  return ListTile(
                    title: Text(revision.title),
                    subtitle: Text(
                      '${revision.createdAt.toLocal()} · ${revision.actorId}',
                    ),
                    trailing: controller.canEditContent
                        ? TextButton(
                            onPressed: () async {
                              final ok = await controller.restoreRevision(
                                revision.revisionId,
                              );
                              if (context.mounted && ok) {
                                Navigator.of(context).pop();
                              }
                            },
                            child: const Text('Restore'),
                          )
                        : null,
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
