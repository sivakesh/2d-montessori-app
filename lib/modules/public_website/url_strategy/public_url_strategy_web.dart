import 'package:flutter_web_plugins/url_strategy.dart';

import '../public_routes.dart';

/// Flutter's path URL strategy (`https://<site>/pages/about`), which also
/// opens old hash links (`https://<site>/#/pages/about`) at their page:
/// when the path is the site root and the fragment is a route, that route
/// is used. Flutter then replaces the address with the clean path.
class PublicPathUrlStrategy extends PathUrlStrategy {
  PublicPathUrlStrategy(PlatformLocation super.platformLocation) : _location = platformLocation;

  final PlatformLocation _location;

  @override
  String getPath() {
    final path = super.getPath();
    return PublicRoutes.legacyHashRoute(path.split('?').first, _orEmpty(_location.hash)) ?? path;
  }

  // The browser's hash is nullable on the web (and typed non-null in the
  // SDK's non-web stub this file is analysed against).
  static String _orEmpty(String? value) => value ?? '';
}

/// Must run before `runApp`.
void configurePublicUrlStrategy() => setUrlStrategy(PublicPathUrlStrategy(BrowserPlatformLocation()));
