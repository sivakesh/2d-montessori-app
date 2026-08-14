import 'package:feature_media/feature_media.dart' show MediaRepository;
import 'package:flutter/material.dart';

import '../domain/call_to_action.dart';
import '../domain/media_reference.dart';
import '../domain/page_section.dart';
import 'media_reference_picker_field.dart';

/// Edits one [PageSection] in place. Every field maps 1:1 to a typed
/// section property — there is no free-text/HTML field anywhere in this
/// dialog, which is what makes "no unrestricted drag-and-drop/free-form
/// builder" true at the editing surface, not just in storage.
class SectionEditorDialog extends StatefulWidget {
  const SectionEditorDialog({
    super.key,
    required this.section,
    required this.mediaRepository,
  });

  final PageSection section;
  final MediaRepository mediaRepository;

  static Future<PageSection?> show(
    BuildContext context,
    PageSection section, {
    required MediaRepository mediaRepository,
  }) => showDialog<PageSection>(
    context: context,
    builder: (_) =>
        SectionEditorDialog(section: section, mediaRepository: mediaRepository),
  );

  @override
  State<SectionEditorDialog> createState() => _SectionEditorDialogState();
}

class _SectionEditorDialogState extends State<SectionEditorDialog> {
  late PageSection _section = widget.section;

  void _update(PageSection Function() build) =>
      setState(() => _section = build());

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Edit ${_section.type.storageValue} section'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(child: _fieldsFor(_section)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_section),
          child: const Text('Done'),
        ),
      ],
    );
  }

  Widget _fieldsFor(PageSection section) {
    return switch (section) {
      final RichTextSection s => _richText(s),
      final ImageSection s => _image(s),
      final ImageTextSection s => _imageText(s),
      final CtaSection s => _cta(s),
      final HighlightsSection s => _highlights(s),
      final FaqSection s => _faq(s),
      final GallerySection s => _gallery(s),
      final TestimonialSection s => _testimonial(s),
      final RelatedContentSection s => _relatedContent(s),
    };
  }

  Widget _richText(RichTextSection s) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextFormField(
        initialValue: s.heading,
        decoration: const InputDecoration(labelText: 'Heading (optional)'),
        onChanged: (v) => _update(
          () => RichTextSection(
            id: s.id,
            sortOrder: s.sortOrder,
            isVisible: s.isVisible,
            heading: v,
            body: s.body,
          ),
        ),
      ),
      const SizedBox(height: 8),
      TextFormField(
        initialValue: s.body,
        maxLines: 6,
        decoration: const InputDecoration(
          labelText: 'Body text (paragraphs only, no formatting)',
        ),
        onChanged: (v) => _update(
          () => RichTextSection(
            id: s.id,
            sortOrder: s.sortOrder,
            isVisible: s.isVisible,
            heading: s.heading,
            body: v,
          ),
        ),
      ),
    ],
  );

  Widget _image(ImageSection s) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      MediaReferencePickerField(
        label: 'Image',
        value: s.image,
        mediaRepository: widget.mediaRepository,
        onChanged: (image) => _update(
          () => ImageSection(
            id: s.id,
            sortOrder: s.sortOrder,
            isVisible: s.isVisible,
            image: image ?? s.image,
          ),
        ),
      ),
    ],
  );

  Widget _imageText(ImageTextSection s) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextFormField(
        initialValue: s.heading,
        decoration: const InputDecoration(labelText: 'Heading (optional)'),
        onChanged: (v) => _update(
          () => ImageTextSection(
            id: s.id,
            sortOrder: s.sortOrder,
            isVisible: s.isVisible,
            heading: v,
            body: s.body,
            image: s.image,
            imageSide: s.imageSide,
          ),
        ),
      ),
      TextFormField(
        initialValue: s.body,
        maxLines: 4,
        decoration: const InputDecoration(labelText: 'Body text'),
        onChanged: (v) => _update(
          () => ImageTextSection(
            id: s.id,
            sortOrder: s.sortOrder,
            isVisible: s.isVisible,
            heading: s.heading,
            body: v,
            image: s.image,
            imageSide: s.imageSide,
          ),
        ),
      ),
      MediaReferencePickerField(
        label: 'Image',
        value: s.image,
        mediaRepository: widget.mediaRepository,
        onChanged: (image) => _update(
          () => ImageTextSection(
            id: s.id,
            sortOrder: s.sortOrder,
            isVisible: s.isVisible,
            heading: s.heading,
            body: s.body,
            image: image ?? s.image,
            imageSide: s.imageSide,
          ),
        ),
      ),
      DropdownButtonFormField<ImageSide>(
        initialValue: s.imageSide,
        decoration: const InputDecoration(labelText: 'Image side'),
        items: ImageSide.values
            .map((v) => DropdownMenuItem(value: v, child: Text(v.name)))
            .toList(),
        onChanged: (v) => _update(
          () => ImageTextSection(
            id: s.id,
            sortOrder: s.sortOrder,
            isVisible: s.isVisible,
            heading: s.heading,
            body: s.body,
            image: s.image,
            imageSide: v ?? s.imageSide,
          ),
        ),
      ),
    ],
  );

  Widget _cta(CtaSection s) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextFormField(
        initialValue: s.heading,
        decoration: const InputDecoration(labelText: 'Heading (optional)'),
        onChanged: (v) => _update(
          () => CtaSection(
            id: s.id,
            sortOrder: s.sortOrder,
            isVisible: s.isVisible,
            heading: v,
            body: s.body,
            primaryCta: s.primaryCta,
            secondaryCta: s.secondaryCta,
          ),
        ),
      ),
      TextFormField(
        initialValue: s.body,
        decoration: const InputDecoration(labelText: 'Body (optional)'),
        onChanged: (v) => _update(
          () => CtaSection(
            id: s.id,
            sortOrder: s.sortOrder,
            isVisible: s.isVisible,
            heading: s.heading,
            body: v,
            primaryCta: s.primaryCta,
            secondaryCta: s.secondaryCta,
          ),
        ),
      ),
      const Divider(),
      const Align(
        alignment: Alignment.centerLeft,
        child: Text('Primary action'),
      ),
      TextFormField(
        initialValue: s.primaryCta.label,
        decoration: const InputDecoration(labelText: 'Label'),
        onChanged: (v) => _update(
          () => CtaSection(
            id: s.id,
            sortOrder: s.sortOrder,
            isVisible: s.isVisible,
            heading: s.heading,
            body: s.body,
            primaryCta: CallToAction(
              label: v,
              linkType: s.primaryCta.linkType,
              target: s.primaryCta.target,
              openInNewTab: s.primaryCta.openInNewTab,
            ),
            secondaryCta: s.secondaryCta,
          ),
        ),
      ),
      TextFormField(
        initialValue: s.primaryCta.target,
        decoration: const InputDecoration(
          labelText: 'Destination (route, URL, tel:, mailto:)',
        ),
        onChanged: (v) => _update(
          () => CtaSection(
            id: s.id,
            sortOrder: s.sortOrder,
            isVisible: s.isVisible,
            heading: s.heading,
            body: s.body,
            primaryCta: CallToAction(
              label: s.primaryCta.label,
              linkType: s.primaryCta.linkType,
              target: v,
              openInNewTab: s.primaryCta.openInNewTab,
            ),
            secondaryCta: s.secondaryCta,
          ),
        ),
      ),
    ],
  );

  Widget _highlights(HighlightsSection s) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextFormField(
        initialValue: s.heading,
        decoration: const InputDecoration(labelText: 'Heading (optional)'),
        onChanged: (v) => _update(
          () => HighlightsSection(
            id: s.id,
            sortOrder: s.sortOrder,
            isVisible: s.isVisible,
            heading: v,
            introduction: s.introduction,
            cards: s.cards,
          ),
        ),
      ),
      const SizedBox(height: 8),
      for (var i = 0; i < s.cards.length; i++)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                TextFormField(
                  initialValue: s.cards[i].title,
                  decoration: const InputDecoration(labelText: 'Card title'),
                  onChanged: (v) => _update(() {
                    final cards = [...s.cards];
                    cards[i] = HighlightCard(
                      title: v,
                      body: cards[i].body,
                      image: cards[i].image,
                    );
                    return HighlightsSection(
                      id: s.id,
                      sortOrder: s.sortOrder,
                      isVisible: s.isVisible,
                      heading: s.heading,
                      introduction: s.introduction,
                      cards: cards,
                    );
                  }),
                ),
                TextFormField(
                  initialValue: s.cards[i].body,
                  decoration: const InputDecoration(labelText: 'Card body'),
                  onChanged: (v) => _update(() {
                    final cards = [...s.cards];
                    cards[i] = HighlightCard(
                      title: cards[i].title,
                      body: v,
                      image: cards[i].image,
                    );
                    return HighlightsSection(
                      id: s.id,
                      sortOrder: s.sortOrder,
                      isVisible: s.isVisible,
                      heading: s.heading,
                      introduction: s.introduction,
                      cards: cards,
                    );
                  }),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _update(() {
                      final cards = [...s.cards]..removeAt(i);
                      return HighlightsSection(
                        id: s.id,
                        sortOrder: s.sortOrder,
                        isVisible: s.isVisible,
                        heading: s.heading,
                        introduction: s.introduction,
                        cards: cards,
                      );
                    }),
                  ),
                ),
              ],
            ),
          ),
        ),
      TextButton.icon(
        icon: const Icon(Icons.add),
        label: const Text('Add card'),
        onPressed: () => _update(
          () => HighlightsSection(
            id: s.id,
            sortOrder: s.sortOrder,
            isVisible: s.isVisible,
            heading: s.heading,
            introduction: s.introduction,
            cards: [
              ...s.cards,
              const HighlightCard(title: '', body: ''),
            ],
          ),
        ),
      ),
    ],
  );

  Widget _faq(FaqSection s) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextFormField(
        initialValue: s.heading,
        decoration: const InputDecoration(labelText: 'Heading (optional)'),
        onChanged: (v) => _update(
          () => FaqSection(
            id: s.id,
            sortOrder: s.sortOrder,
            isVisible: s.isVisible,
            heading: v,
            items: s.items,
          ),
        ),
      ),
      for (var i = 0; i < s.items.length; i++)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                TextFormField(
                  initialValue: s.items[i].question,
                  decoration: const InputDecoration(labelText: 'Question'),
                  onChanged: (v) => _update(() {
                    final items = [...s.items];
                    items[i] = FaqItem(question: v, answer: items[i].answer);
                    return FaqSection(
                      id: s.id,
                      sortOrder: s.sortOrder,
                      isVisible: s.isVisible,
                      heading: s.heading,
                      items: items,
                    );
                  }),
                ),
                TextFormField(
                  initialValue: s.items[i].answer,
                  decoration: const InputDecoration(labelText: 'Answer'),
                  onChanged: (v) => _update(() {
                    final items = [...s.items];
                    items[i] = FaqItem(question: items[i].question, answer: v);
                    return FaqSection(
                      id: s.id,
                      sortOrder: s.sortOrder,
                      isVisible: s.isVisible,
                      heading: s.heading,
                      items: items,
                    );
                  }),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _update(() {
                      final items = [...s.items]..removeAt(i);
                      return FaqSection(
                        id: s.id,
                        sortOrder: s.sortOrder,
                        isVisible: s.isVisible,
                        heading: s.heading,
                        items: items,
                      );
                    }),
                  ),
                ),
              ],
            ),
          ),
        ),
      TextButton.icon(
        icon: const Icon(Icons.add),
        label: const Text('Add question'),
        onPressed: () => _update(
          () => FaqSection(
            id: s.id,
            sortOrder: s.sortOrder,
            isVisible: s.isVisible,
            heading: s.heading,
            items: [
              ...s.items,
              const FaqItem(question: '', answer: ''),
            ],
          ),
        ),
      ),
    ],
  );

  Widget _gallery(GallerySection s) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextFormField(
        initialValue: s.heading,
        decoration: const InputDecoration(labelText: 'Heading (optional)'),
        onChanged: (v) => _update(
          () => GallerySection(
            id: s.id,
            sortOrder: s.sortOrder,
            isVisible: s.isVisible,
            heading: v,
            items: s.items,
          ),
        ),
      ),
      for (var i = 0; i < s.items.length; i++)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                MediaReferencePickerField(
                  label: 'Image',
                  value: s.items[i],
                  mediaRepository: widget.mediaRepository,
                  onChanged: (image) => _update(() {
                    final items = [...s.items];
                    items[i] = image ?? items[i];
                    return GallerySection(
                      id: s.id,
                      sortOrder: s.sortOrder,
                      isVisible: s.isVisible,
                      heading: s.heading,
                      items: items,
                    );
                  }),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _update(() {
                      final items = [...s.items]..removeAt(i);
                      return GallerySection(
                        id: s.id,
                        sortOrder: s.sortOrder,
                        isVisible: s.isVisible,
                        heading: s.heading,
                        items: items,
                      );
                    }),
                  ),
                ),
              ],
            ),
          ),
        ),
      TextButton.icon(
        icon: const Icon(Icons.add),
        label: const Text('Add image'),
        onPressed: () => _update(
          () => GallerySection(
            id: s.id,
            sortOrder: s.sortOrder,
            isVisible: s.isVisible,
            heading: s.heading,
            items: [
              ...s.items,
              const MediaReference(url: '', altText: ''),
            ],
          ),
        ),
      ),
    ],
  );

  Widget _testimonial(TestimonialSection s) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextFormField(
        initialValue: s.heading,
        decoration: const InputDecoration(labelText: 'Heading (optional)'),
        onChanged: (v) => _update(
          () => TestimonialSection(
            id: s.id,
            sortOrder: s.sortOrder,
            isVisible: s.isVisible,
            heading: v,
            items: s.items,
          ),
        ),
      ),
      for (var i = 0; i < s.items.length; i++)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                TextFormField(
                  initialValue: s.items[i].quote,
                  decoration: const InputDecoration(labelText: 'Quote'),
                  onChanged: (v) => _update(() {
                    final items = [...s.items];
                    items[i] = TestimonialEntry(
                      quote: v,
                      attributionName: items[i].attributionName,
                      relationship: items[i].relationship,
                    );
                    return TestimonialSection(
                      id: s.id,
                      sortOrder: s.sortOrder,
                      isVisible: s.isVisible,
                      heading: s.heading,
                      items: items,
                    );
                  }),
                ),
                TextFormField(
                  initialValue: s.items[i].attributionName,
                  decoration: const InputDecoration(
                    labelText: 'Attribution (leave blank to anonymise)',
                  ),
                  onChanged: (v) => _update(() {
                    final items = [...s.items];
                    items[i] = TestimonialEntry(
                      quote: items[i].quote,
                      attributionName: v,
                      relationship: items[i].relationship,
                    );
                    return TestimonialSection(
                      id: s.id,
                      sortOrder: s.sortOrder,
                      isVisible: s.isVisible,
                      heading: s.heading,
                      items: items,
                    );
                  }),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _update(() {
                      final items = [...s.items]..removeAt(i);
                      return TestimonialSection(
                        id: s.id,
                        sortOrder: s.sortOrder,
                        isVisible: s.isVisible,
                        heading: s.heading,
                        items: items,
                      );
                    }),
                  ),
                ),
              ],
            ),
          ),
        ),
      TextButton.icon(
        icon: const Icon(Icons.add),
        label: const Text('Add testimonial'),
        onPressed: () => _update(
          () => TestimonialSection(
            id: s.id,
            sortOrder: s.sortOrder,
            isVisible: s.isVisible,
            heading: s.heading,
            items: [
              ...s.items,
              const TestimonialEntry(quote: ''),
            ],
          ),
        ),
      ),
    ],
  );

  Widget _relatedContent(RelatedContentSection s) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextFormField(
        initialValue: s.heading,
        decoration: const InputDecoration(labelText: 'Heading (optional)'),
        onChanged: (v) => _update(
          () => RelatedContentSection(
            id: s.id,
            sortOrder: s.sortOrder,
            isVisible: s.isVisible,
            heading: v,
            relatedPageIds: s.relatedPageIds,
          ),
        ),
      ),
      TextFormField(
        initialValue: s.relatedPageIds.join(', '),
        decoration: const InputDecoration(
          labelText: 'Related page IDs (comma-separated)',
          helperText:
              'Manually selected — unpublished/archived pages are skipped automatically when rendered.',
        ),
        onChanged: (v) => _update(
          () => RelatedContentSection(
            id: s.id,
            sortOrder: s.sortOrder,
            isVisible: s.isVisible,
            heading: s.heading,
            relatedPageIds: v
                .split(',')
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toList(),
          ),
        ),
      ),
    ],
  );
}
