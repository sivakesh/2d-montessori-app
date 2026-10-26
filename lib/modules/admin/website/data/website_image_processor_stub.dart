import 'dart:typed_data';
import 'dart:ui' as ui;

import 'website_image_processor.dart';

/// Non-web fallback: measures the image and keeps its bytes unchanged.
class PlatformWebsiteImageProcessor implements WebsiteImageProcessor {
  @override
  Future<ProcessedWebsiteImage> process(Uint8List bytes, {required String contentType}) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    final width = descriptor.width;
    final height = descriptor.height;
    descriptor.dispose();
    buffer.dispose();
    return ProcessedWebsiteImage(
      width: width,
      height: height,
      display: bytes,
      displayContentType: contentType,
      thumb: bytes,
      thumbContentType: contentType,
    );
  }
}
