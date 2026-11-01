import 'dart:async';
import 'dart:js_interop';
import 'dart:math' as math;
import 'dart:typed_data';

import '../../../public_website/content/website_content_models.dart';
import 'website_image_processor.dart';

/// Browser implementation: decodes the image with an <img> element and
/// draws scaled copies onto a canvas, exported as JPEG.
class PlatformWebsiteImageProcessor implements WebsiteImageProcessor {
  static const _quality = 0.85;

  @override
  Future<ProcessedWebsiteImage> process(Uint8List bytes, {required String contentType}) async {
    final blob = _Blob([bytes.toJS].toJS, {'type': contentType}.jsify()! as JSObject);
    final url = _Url.createObjectURL(blob);
    try {
      final image = _document.createElement('img') as _ImageElement;
      image.src = url;
      await image.decode().toDart;
      final width = image.naturalWidth;
      final height = image.naturalHeight;
      if (width <= 0 || height <= 0) throw StateError('The image could not be read.');
      final display = await _encode(image, width, height, WebsiteImageSizes.display);
      final thumb = await _encode(image, width, height, WebsiteImageSizes.thumb);
      return ProcessedWebsiteImage(
        width: display.width,
        height: display.height,
        display: display.bytes,
        displayContentType: 'image/jpeg',
        thumb: thumb.bytes,
        thumbContentType: 'image/jpeg',
      );
    } finally {
      _Url.revokeObjectURL(url);
    }
  }

  Future<({int width, int height, Uint8List bytes})> _encode(_ImageElement image, int width, int height, int maxEdge) async {
    final scale = math.min(1.0, maxEdge / math.max(width, height));
    final w = math.max(1, (width * scale).round());
    final h = math.max(1, (height * scale).round());
    final canvas = _document.createElement('canvas') as _CanvasElement
      ..width = w
      ..height = h;
    final context = canvas.getContext('2d');
    // JPEG has no transparency: paint the site's warm white underneath.
    context.fillStyle = '#FBF8F2';
    context.fillRect(0, 0, w, h);
    context.imageSmoothingQuality = 'high';
    context.drawImage(image, 0, 0, w, h);
    final completer = Completer<_Blob?>();
    canvas.toBlob(((_Blob? blob) => completer.complete(blob)).toJS, 'image/jpeg', _quality);
    final blob = await completer.future;
    if (blob == null) throw StateError('The image could not be resized.');
    final buffer = await blob.arrayBuffer().toDart;
    return (width: w, height: h, bytes: buffer.toDart.asUint8List());
  }
}

@JS('document')
external _Document get _document;

extension type _Document._(JSObject _) implements JSObject {
  external JSObject createElement(String tagName);
}

extension type _ImageElement._(JSObject _) implements JSObject {
  external set src(String value);
  external int get naturalWidth;
  external int get naturalHeight;
  external JSPromise<JSAny?> decode();
}

extension type _CanvasElement._(JSObject _) implements JSObject {
  external set width(int value);
  external set height(int value);
  external _Context2D getContext(String contextId);
  external void toBlob(JSFunction callback, String type, num quality);
}

extension type _Context2D._(JSObject _) implements JSObject {
  external set fillStyle(String value);
  external set imageSmoothingQuality(String value);
  external void fillRect(num x, num y, num width, num height);
  external void drawImage(JSObject image, num dx, num dy, num dWidth, num dHeight);
}

@JS('Blob')
extension type _Blob._(JSObject _) implements JSObject {
  external factory _Blob(JSArray<JSAny> parts, JSObject options);
  external JSPromise<JSArrayBuffer> arrayBuffer();
}

@JS('URL')
extension type _Url._(JSObject _) implements JSObject {
  external static String createObjectURL(_Blob blob);
  external static void revokeObjectURL(String url);
}
