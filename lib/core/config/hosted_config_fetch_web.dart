import 'dart:js_interop';

import 'hosted_firebase_config.dart';

@JS('fetch')
external JSPromise<_FetchResponse> _fetch(String url, _FetchInit init);

extension type _FetchInit._(JSObject _) implements JSObject {
  external factory _FetchInit({String method, String credentials, String cache, String redirect});
}

extension type _FetchResponse._(JSObject _) implements JSObject {
  external int get status;
  external _FetchHeaders get headers;
  external JSPromise<JSString> text();
}

extension type _FetchHeaders._(JSObject _) implements JSObject {
  external String? get(String name);
}

/// GET [url] with the browser's fetch: same-origin credentials, revalidated
/// with the server each time (`no-cache`, so a changed configuration is
/// seen at once), and no redirects followed.
Future<HostedConfigResponse> fetchHostedConfig(Uri url) async {
  final response = await _fetch(
    url.toString(),
    _FetchInit(method: 'GET', credentials: 'same-origin', cache: 'no-cache', redirect: 'error'),
  ).toDart;
  final body = (await response.text().toDart).toDart;
  return HostedConfigResponse(status: response.status, contentType: response.headers.get('content-type') ?? '', body: body);
}
