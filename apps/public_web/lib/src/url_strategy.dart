/// Configures the browser URL strategy — see `main.dart`'s call site.
///
/// Conditionally exported the same way `seo_head.dart` is: this app's
/// only real target is web, but `flutter_web_plugins` itself imports
/// `dart:ui_web`, which does not exist under the Dart VM `flutter test`
/// runs on. Importing `flutter_web_plugins` unconditionally from
/// `main.dart` would make every widget test that imports `main.dart`
/// fail to even compile, not just fail an assertion — the stub avoids
/// that the same way `seo_head_stub.dart` does for `package:web`.
library;

export 'url_strategy_stub.dart'
    if (dart.library.js_interop) 'url_strategy_web.dart';
