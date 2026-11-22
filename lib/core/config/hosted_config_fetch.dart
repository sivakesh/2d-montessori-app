// The same-origin request for a hosted build's Firebase configuration: the
// browser's fetch on the web (dart:js_interop, no extra package); elsewhere
// it always fails, so a non-web build can never be configured this way.
export 'hosted_config_fetch_stub.dart' if (dart.library.js_interop) 'hosted_config_fetch_web.dart';
