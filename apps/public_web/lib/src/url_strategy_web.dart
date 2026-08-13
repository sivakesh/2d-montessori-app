import 'package:flutter_web_plugins/flutter_web_plugins.dart';

/// Real `/slug` URLs instead of Flutter's default `#/slug` hash routes —
/// see `main.dart`'s call site for why this matters for SEO.
void configureUrlStrategy() => usePathUrlStrategy();
