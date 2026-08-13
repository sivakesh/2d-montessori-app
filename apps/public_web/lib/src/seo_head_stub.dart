/// Non-web fallback for [SeoHead] — used whenever this code is compiled
/// for a target where `package:web`'s `dart:js_interop` bindings aren't
/// available (the Dart VM, which is what `flutter test` runs on; this
/// app has no other non-web target today). A no-op here is correct: the
/// production app always compiles to web (`flutter build web`), where
/// `seo_head_web.dart` is selected instead — see `seo_head.dart`'s
/// conditional export.
abstract final class SeoHead {
  static void apply({
    required String title,
    String? description,
    String? canonicalUrl,
    required bool indexable,
    String? ogTitle,
    String? ogDescription,
    String? ogImageUrl,
  }) {}
}
