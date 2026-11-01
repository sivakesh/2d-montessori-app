import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../public_website/content/website_content_repository.dart';
import '../../../../public_website/content/website_site_layout.dart';
import '../../../../public_website/public_strings.dart';

/// The public site's real header, footer and menu below [child], drawn
/// with [chrome] (the draft layout and design being edited, resolved
/// against the published pages) in [language] — for the editors' canvases
/// and previews. Nothing inside can be focused or followed.
class WebsiteChromeScope extends StatelessWidget {
  const WebsiteChromeScope({super.key, required this.chrome, required this.language, required this.child});

  final PublicSiteChrome chrome;
  final PublicLanguage language;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      // A new scope per language: a changed overrideWith isn't applied to
      // an existing scope (the chrome value is).
      key: ValueKey(language),
      overrides: [
        publicSiteChromeProvider.overrideWithValue(chrome),
        publicLanguageProvider.overrideWith((ref) => language),
      ],
      child: ExcludeFocus(child: child),
    );
  }
}
