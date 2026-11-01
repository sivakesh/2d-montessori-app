import 'dart:js_interop';

/// Browser download: a Blob behind a temporary link (no data leaves the
/// browser).
bool downloadCsv(String fileName, String csv) {
  // A byte order mark, so spreadsheets read the text as UTF-8 (Tamil).
  final blob = _Blob(['﻿$csv'.toJS].toJS, {'type': 'text/csv;charset=utf-8'}.jsify()! as JSObject);
  final url = _Url.createObjectURL(blob);
  final link = _document.createElement('a') as _Anchor;
  link.href = url;
  link.download = fileName;
  link.click();
  _Url.revokeObjectURL(url);
  return true;
}

@JS('document')
external _Document get _document;

extension type _Document._(JSObject _) implements JSObject {
  external JSObject createElement(String tagName);
}

extension type _Anchor._(JSObject _) implements JSObject {
  external set href(String value);
  external set download(String value);
  external void click();
}

@JS('Blob')
extension type _Blob._(JSObject _) implements JSObject {
  external factory _Blob(JSArray<JSAny> parts, JSObject options);
}

@JS('URL')
extension type _Url._(JSObject _) implements JSObject {
  external static String createObjectURL(_Blob blob);
  external static void revokeObjectURL(String url);
}
