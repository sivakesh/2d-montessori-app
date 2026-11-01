// The map itself: an iframe on the web, a placeholder elsewhere (tests).
export 'public_map_frame_stub.dart'
    if (dart.library.html) 'public_map_frame_web.dart';
