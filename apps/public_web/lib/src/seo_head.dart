/// Updates the document `<head>` (title, meta description, canonical
/// link, robots directive, Open Graph tags) on every route change — see
/// `seo_head_web.dart`'s doc comment for what this does and does not
/// achieve for SEO/crawlability (SRS SEO-01/NFR-09).
///
/// Conditionally exports the real `package:web`-based implementation
/// only when compiling for a web target (`dart.library.js_interop` is
/// only available under the JS/Wasm compilers, not the Dart VM) —
/// `seo_head_stub.dart`'s no-op is used everywhere else, which is what
/// lets `flutter test` (VM-based) run at all: `package:web`'s own
/// internals (not just this file) fail to compile under the VM, so it
/// must never be imported unconditionally from code a VM-run test
/// exercises.
library;

export 'seo_head_stub.dart' if (dart.library.js_interop) 'seo_head_web.dart';
