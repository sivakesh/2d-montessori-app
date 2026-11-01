import 'dart:typed_data';

import 'website_image_processor_stub.dart'
    if (dart.library.js_interop) 'website_image_processor_web.dart' as platform;

/// The files stored for one uploaded website image.
class ProcessedWebsiteImage {
  const ProcessedWebsiteImage({
    required this.width,
    required this.height,
    required this.display,
    required this.displayContentType,
    required this.thumb,
    required this.thumbContentType,
  });

  /// Pixel size of [display].
  final int width;
  final int height;

  /// The image shown on pages and in the lightbox.
  final Uint8List display;
  final String displayContentType;

  /// The small image for gallery tiles.
  final Uint8List thumb;
  final String thumbContentType;
}

/// Prepares an uploaded image for the website: reads its size and makes a
/// display copy (long edge at most `WebsiteImageSizes.display`) and a
/// thumbnail (`WebsiteImageSizes.thumb`), so visitors never download the
/// camera original. In the browser this re-encodes as JPEG via a canvas,
/// which also drops the photo's embedded metadata (EXIF, including any GPS
/// location); elsewhere the original bytes are kept for both.
abstract class WebsiteImageProcessor {
  factory WebsiteImageProcessor() = platform.PlatformWebsiteImageProcessor;

  Future<ProcessedWebsiteImage> process(Uint8List bytes, {required String contentType});
}
