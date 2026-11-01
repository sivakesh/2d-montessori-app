import 'package:flutter/material.dart';

/// Named routes of the public website, plus the management app's entry.
class PublicRoutes {
  static const home = '/';
  static const admissions = '/admissions';
  static const teacherTraining = '/teacher-training';
  static const programs = '/programs';
  static const gallery = '/gallery';
  static const contact = '/contact';

  /// The school management app: the existing AuthGate (login when signed
  /// out, the role's dashboard when signed in).
  static const management = '/app';

  /// Top-level public pages, in navigation order.
  static const sections = [home, admissions, teacherTraining, programs, gallery, contact];

  /// Additional pages created in Settings -> Website live under this
  /// prefix, so they can never shadow a built-in or management route.
  static const customPagePrefix = '/pages/';

  static String customPage(String slug) => '$customPagePrefix$slug';

  /// A published event's details: `/events/<id>`, where the id is the
  /// calendar event's (the same for as long as the event is on the
  /// website), so the address can be shared.
  static const eventPrefix = '/events/';

  static String event(String sourceId) => '$eventPrefix$sourceId';

  /// A published announcement's details: `/announcements/<id>`, where the
  /// id is the school notification's, so the address can be shared.
  static const announcementPrefix = '/announcements/';

  static String announcement(String sourceId) => '$announcementPrefix$sourceId';

  /// The announcement id of an `/announcements/<id>` route, or null (see
  /// [eventIdFromRoute]; the case is kept).
  static String? announcementIdFromRoute(String? route) => _idFromRoute(route, announcementPrefix);

  /// The event id of an `/events/<id>` route (query and fragment ignored),
  /// or null for any other route. Unlike page slugs, the case is kept:
  /// event ids are case-sensitive. Its format is checked by the page.
  static String? eventIdFromRoute(String? route) => _idFromRoute(route, eventPrefix);

  static String? _idFromRoute(String? route, String prefix) {
    if (route == null || !route.startsWith(prefix)) return null;
    final rest = route.substring(prefix.length).split(RegExp(r'[?#]')).first;
    final id = rest.endsWith('/') ? rest.substring(0, rest.length - 1) : rest;
    if (id.isEmpty || id.contains('/')) return null;
    return id;
  }

  /// Management-app routes, which website content can never link to.
  static const reservedRoutes = ['/app', '/login', '/otp', '/dashboard'];

  /// Route prefixes that can't be typed as a link: the admin screens, and
  /// additional pages (linked by page id, so a renamed address still works).
  static const reservedPrefixes = ['/admin_', customPagePrefix];

  /// [raw] as the route the app would see: percent-decoding undone
  /// (repeatedly, so `%2561` can't hide an `a`), backslashes read as
  /// slashes, repeated slashes collapsed, `.`/`..` segments resolved,
  /// query, fragment and `;` parameters dropped, lower-cased, without a
  /// trailing slash, always starting with `/`.
  static String normalizeRoute(String raw) {
    var path = raw;
    for (var i = 0; i < 3; i++) {
      try {
        final decoded = Uri.decodeFull(path);
        if (decoded == path) break;
        path = decoded;
      } catch (_) {
        break;
      }
    }
    path = path.split(RegExp(r'[?#;]')).first.replaceAll(r'\', '/').toLowerCase();
    if (!path.startsWith('/')) path = '/$path';
    path = path.replaceAll(RegExp(r'/{2,}'), '/');
    path = Uri(path: path).normalizePath().path;
    if (path.isEmpty) return home;
    return path.length > 1 && path.endsWith('/') ? path.substring(0, path.length - 1) : path;
  }

  /// Whether [route] is a reserved route, however it is written (see
  /// [normalizeRoute]): `/APP`, `//app/`, `/%61pp` and `/x/../app` are all
  /// `/app`.
  static bool isReserved(String route) {
    final path = normalizeRoute(route);
    return reservedRoutes.contains(path) || reservedPrefixes.any((p) => path.startsWith(p) || '$path/' == p);
  }

  /// Whether [route] is a management-app route (`/app`, `/login`, `/otp`,
  /// `/dashboard`, `/admin_*`) — reserved and protected — as opposed to a
  /// reserved-but-public `/pages/` address (which is linked by page id).
  static bool isProtectedAppRoute(String route) {
    final path = normalizeRoute(route);
    return reservedRoutes.contains(path) || path.startsWith('/admin_');
  }

  /// The app routes an absolute [uri] on this website would open: its path
  /// (path URLs) and, when its fragment is a route like `#/app` or
  /// `#!/app`, that too (hash URLs).
  static List<String> routesInUrl(Uri uri) {
    final routes = [normalizeRoute(uri.path)];
    var fragment = uri.fragment;
    try {
      fragment = Uri.decodeFull(fragment);
    } catch (_) {}
    if (fragment.startsWith('!')) fragment = fragment.substring(1);
    if (fragment.startsWith('/') || fragment.startsWith(r'\')) routes.add(normalizeRoute(fragment));
    return routes;
  }

  /// The route a legacy hash URL (`https://site/#/pages/about`) meant, so
  /// old links keep working after the switch to path URLs: the fragment's
  /// route when [path] is the site root and [hash] is a route (`#/...`);
  /// otherwise null (use the path). An ordinary `#anchor` is not a route.
  static String? legacyHashRoute(String path, String hash) {
    if (path != home && path.isNotEmpty) return null;
    if (!hash.startsWith('#/')) return null;
    return hash.substring(1);
  }

  /// The slug of a `/pages/<slug>` route (query and fragment ignored), or
  /// null for any other route. The slug is lower-cased; its format is
  /// checked by the page itself.
  static String? slugFromRoute(String? route) {
    if (route == null || !route.startsWith(customPagePrefix)) return null;
    final rest = route.substring(customPagePrefix.length).split(RegExp(r'[?#]')).first;
    final slug = rest.endsWith('/') ? rest.substring(0, rest.length - 1) : rest;
    if (slug.isEmpty || slug.contains('/')) return null;
    return slug.toLowerCase();
  }

  /// Moves between public pages without growing the back stack: Home pops
  /// back to the first route; any other page replaces everything above it.
  static void open(BuildContext context, String route) {
    final navigator = Navigator.of(context);
    if (ModalRoute.of(context)?.settings.name == route) return;
    if (route == home) {
      // Home is the first route (a deep link like /programs is stacked on
      // top of it); if this page is somehow first, replace it.
      navigator.canPop() ? navigator.popUntil((r) => r.isFirst) : navigator.pushReplacementNamed(home);
      return;
    }
    navigator.pushNamedAndRemoveUntil(route, (r) => r.isFirst);
  }

  /// Opens the management app on top of the public site (back returns here).
  static void openManagement(BuildContext context) => Navigator.of(context).pushNamed(management);
}

/// The hosts this website is served from. A link to any of them is a link
/// to this site, never "external". The running site's own host is always
/// included, so a custom domain added later is covered without a change.
class PublicSiteHosts {
  /// The public domain and the Firebase Hosting domains of the DEV
  /// (`montessori-app-95988`) and production (`twod-montessori-prod`)
  /// projects.
  static const known = [
    '2dmontessori.com',
    'montessori-app-95988.web.app',
    'montessori-app-95988.firebaseapp.com',
    'twod-montessori-prod.web.app',
    'twod-montessori-prod.firebaseapp.com',
  ];

  /// [host] lower-cased and percent-decoded, without trailing dots or a
  /// leading `www.` (so `WWW.2DMontessori.com.` matches).
  static String normalize(String host) {
    var value = host;
    try {
      value = Uri.decodeComponent(value);
    } catch (_) {}
    value = value.toLowerCase().replaceAll(RegExp(r'\.+$'), '');
    return value.startsWith('www.') ? value.substring(4) : value;
  }

  /// [known] plus the host the app is running on (web only).
  static Set<String> current() {
    final base = Uri.base;
    return {
      for (final h in known) normalize(h),
      if ((base.isScheme('http') || base.isScheme('https')) && base.host.isNotEmpty) normalize(base.host),
    };
  }

  /// Whether [uri] points at this website (any port).
  static bool isSiteUrl(Uri uri, {Set<String>? hosts}) => uri.host.isNotEmpty && (hosts ?? current()).contains(normalize(uri.host));
}
