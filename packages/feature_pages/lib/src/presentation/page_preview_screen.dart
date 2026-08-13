import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

import '../domain/cms_page.dart';
import 'page_section_renderer.dart';

/// SRS CMS-04: "Secure preview for mobile, tablet and desktop... displays
/// a Draft Preview indicator and is not publicly indexable." This screen
/// only exists inside the authenticated admin app (Firestore Rules never
/// grant public read on `content/{contentId}`), so "secure" and "not
/// publicly indexable" both follow from where this screen lives, not
/// from anything it does itself — there is no separate public preview
/// route or token in this milestone.
class PagePreviewScreen extends StatefulWidget {
  const PagePreviewScreen({super.key, required this.page});

  final CmsPage page;

  @override
  State<PagePreviewScreen> createState() => _PagePreviewScreenState();
}

enum _PreviewWidth { mobile, tablet, desktop }

class _PagePreviewScreenState extends State<PagePreviewScreen> {
  _PreviewWidth _width = _PreviewWidth.desktop;

  double get _widthPx => switch (_width) {
    _PreviewWidth.mobile => 360,
    _PreviewWidth.tablet => 768,
    _PreviewWidth.desktop => 1280,
  };

  @override
  Widget build(BuildContext context) {
    final page = widget.page;
    final sections = [...page.sections]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Draft Preview'),
        actions: [
          SegmentedButton<_PreviewWidth>(
            segments: const [
              ButtonSegment(
                value: _PreviewWidth.mobile,
                icon: Icon(Icons.smartphone),
                label: Text('Mobile'),
              ),
              ButtonSegment(
                value: _PreviewWidth.tablet,
                icon: Icon(Icons.tablet_mac),
                label: Text('Tablet'),
              ),
              ButtonSegment(
                value: _PreviewWidth.desktop,
                icon: Icon(Icons.desktop_windows),
                label: Text('Desktop'),
              ),
            ],
            selected: {_width},
            onSelectionChanged: (s) => setState(() => _width = s.first),
          ),
          const SizedBox(width: 16),
        ],
      ),
      backgroundColor: ColorTokens.surfaceAlt,
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: ColorTokens.accent,
            padding: EdgeInsets.symmetric(vertical: SpacingTokens.xs),
            child: const Center(
              child: Text(
                'DRAFT PREVIEW — not published, not indexable',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: SizedBox(
                width: _widthPx,
                child: Container(
                  color: ColorTokens.surface,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: EdgeInsets.all(SpacingTokens.lg),
                          child: Semantics(
                            header: true,
                            child: Text(
                              page.title,
                              style: TypographyTokens.displayLarge,
                            ),
                          ),
                        ),
                        for (final section in sections)
                          PageSectionRenderer(section: section),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
