import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../content/blocks/website_block.dart';
import '../content/built_in_pages.dart';
import '../content/website_content_models.dart';
import '../content/website_content_repository.dart';
import '../public_strings.dart';
import '../widgets/blocks/website_blocks_view.dart';
import '../widgets/public_scaffold.dart';

/// A built-in page published as blocks: its blocks at the page's full
/// width, with published images only, under the site's header and footer.
class PublicBuiltInBlocksPage extends ConsumerWidget {
  const PublicBuiltInBlocksPage({super.key, required this.page, required this.blocks});

  final BuiltInPage page;
  final List<WebsiteBlock> blocks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(publicLanguageProvider);
    final media = ref.watch(publishedWebsiteMediaProvider).valueOrNull ?? const <WebsiteMedia>[];
    return PublicScaffold(
      currentRoute: page.route,
      body: WebsiteBlocksView(
        key: Key('public-built-in-blocks-${page.id}'),
        blocks: blocks,
        media: {for (final m in media) m.id: m},
        language: language,
        fullBleed: true,
      ),
    );
  }
}
