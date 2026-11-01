// Path URLs on the web (`/pages/about` instead of `/#/pages/about`); a
// no-op on other platforms.
export 'public_url_strategy_stub.dart' if (dart.library.js_interop) 'public_url_strategy_web.dart';
