/// Non-web fallback for [configureUrlStrategy] — see `url_strategy.dart`'s
/// doc comment. A no-op under the Dart VM (`flutter test`), where
/// `dart:ui_web` (which `flutter_web_plugins` itself imports) isn't
/// available at all.
void configureUrlStrategy() {}
