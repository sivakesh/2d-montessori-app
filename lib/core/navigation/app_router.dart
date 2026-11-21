import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../admin/screens/admin_session_logs_screen.dart';
import '../../modules/admin/ui/admin_dashboard_screen.dart';
import '../../modules/admin/ui/admin_profile_form.dart';
import '../../modules/auth/ui/auth_gate.dart';
import '../../modules/auth/ui/login_screen.dart';
import '../../modules/auth/ui/otp_screen.dart';
import '../../modules/auth/ui/role_based_home.dart';
import '../../modules/public_website/public_routes.dart';
import '../../modules/public_website/ui/public_announcement_page.dart';
import '../../modules/public_website/ui/public_custom_page.dart';
import '../../modules/public_website/ui/public_event_page.dart';
import '../../modules/public_website/ui/public_gallery_page.dart';
import '../../modules/public_website/ui/public_home_page.dart';
import '../../modules/public_website/ui/public_section_page.dart';

// The app's navigation, on Flutter's Router: the browser's Back and Forward
// follow the public website's pages, and the management app works exactly as
// before.
//
// * Public website: every page navigation (PublicRoutes.open) is a new
//   location, reported to the browser as a new history entry; Back and
//   Forward bring the browser's entry back as the current location. A
//   section of the same page only scrolls and updates the address (no new
//   entry).
// * Management (`/app`, `/login`, `/otp`, `/dashboard`, `/admin_*`): one
//   location holding the management shell, a Navigator with the app's
//   existing route table ([ManagementRoutes]). Every existing push, pop,
//   pushReplacementNamed, pushNamedAndRemoveUntil and dialog works as before
//   inside it; its named routes update the address without new entries (as
//   before), and the browser's Back pops it (respecting PopScope) the way the
//   app's back did before. Not changed in this stage.

/// The management app's routes, exactly as `main.dart` declared them (moved
/// here unchanged).
class ManagementRoutes {
  ManagementRoutes._();

  /// `/app` is the existing AuthGate (login when signed out, the role's
  /// dashboard when signed in).
  static final Map<String, WidgetBuilder> named = {
    PublicRoutes.management: (context) => const AuthGate(),
    '/login': (context) => const LoginScreen(),
    '/dashboard': (context) => const DashboardRoute(),
    '/admin_dashboard': (context) => const AdminDashboardScreen(),
    '/admin_session_logs': (context) => const AdminSessionLogsScreen(),
    '/admin_profile_form': (context) => const AdminProfileForm(),
  };

  static const otp = '/otp';

  /// Whether [path] is a management route.
  static bool isManagement(String path) => named.containsKey(path) || path == otp;

  /// The route for [settings] in the management app, as before: a named
  /// route, or `/otp` with its phone argument. Null for any other name.
  static Route<dynamic>? generate(RouteSettings settings) {
    final name = settings.name ?? '';
    if (name == otp) {
      final arguments = settings.arguments as Map<String, dynamic>;
      // Without route settings, as before (its name is not shown as the
      // address).
      return MaterialPageRoute(builder: (_) => OtpScreen(phoneNumber: arguments['phone'] as String));
    }
    final builder = named[name];
    return builder == null ? null : MaterialPageRoute(settings: settings, builder: builder);
  }
}

/// Where the app is: a public website page (with an optional section) or a
/// management route. [name] is the route name pages and links use;
/// [reported] the address shown for it (what was opened, so a URL is never
/// rewritten); [entry] the browser history entry it belongs to.
@immutable
class AppLocation {
  const AppLocation._({required this.path, required this.name, required this.reported, this.anchor, this.management = false, this.entry, this.arguments});

  /// [uri] as a location: management routes; the public pages (home, the
  /// built-in pages, `/pages/<slug>`, `/events/<id>`, `/announcements/<id>`)
  /// with an optional `#section`; anything else is Home (as before), keeping
  /// the address that was opened.
  factory AppLocation.fromUri(Uri uri, {String? entry, Object? arguments}) {
    var path = uri.path.isEmpty ? PublicRoutes.home : uri.path;
    final reported = uri.hasFragment && uri.fragment.isNotEmpty ? '$path#${uri.fragment}' : path;
    if (ManagementRoutes.isManagement(path)) {
      return AppLocation._(path: path, name: path, reported: path, management: true, entry: entry, arguments: arguments);
    }
    final anchor = PublicRoutes.anchorOf(reported);
    final canonical = publicPath(path);
    if (canonical == null) {
      return AppLocation._(path: PublicRoutes.home, name: PublicRoutes.home, reported: reported, entry: entry);
    }
    path = canonical;
    return AppLocation._(path: path, name: anchor == null ? path : '$path#$anchor', reported: reported, anchor: anchor, entry: entry);
  }

  /// A location from a route name (`/teacher-training#enquire`).
  factory AppLocation.parse(String route, {String? entry, Object? arguments}) => AppLocation.fromUri(Uri.parse(route.isEmpty ? '/' : route), entry: entry, arguments: arguments);

  /// The public page [path] names, as its route ([PublicRoutes]), or null
  /// when it isn't one: `/`, the built-in pages, `/pages/<slug>` (lower
  /// case; any other address under `/pages/` is the page itself, which shows
  /// "page not found"), `/events/<id>`, `/announcements/<id>`.
  static String? publicPath(String path) {
    if (path == PublicRoutes.home || PublicRoutes.sections.contains(path)) return path;
    if (path.startsWith(PublicRoutes.customPagePrefix)) {
      final slug = PublicRoutes.slugFromRoute(path) ?? '';
      return slug.isEmpty ? path : PublicRoutes.customPage(slug);
    }
    if (path.startsWith(PublicRoutes.eventPrefix)) {
      final id = PublicRoutes.eventIdFromRoute(path) ?? '';
      return id.isEmpty ? path : PublicRoutes.event(id);
    }
    if (path.startsWith(PublicRoutes.announcementPrefix)) {
      final id = PublicRoutes.announcementIdFromRoute(path) ?? '';
      return id.isEmpty ? path : PublicRoutes.announcement(id);
    }
    return null;
  }

  final String path;
  final String name;
  final String reported;
  final String? anchor;
  final bool management;
  final String? entry;

  /// The management route's arguments (`/otp`'s phone), when pushed.
  final Object? arguments;

  AppLocation withEntry(String entry) => AppLocation._(path: path, name: name, reported: reported, anchor: anchor, management: management, entry: entry, arguments: arguments);

  /// This page at section [anchor] (the address shows it).
  AppLocation withAnchor(String anchor) => AppLocation._(path: path, name: '$path#$anchor', reported: '$path#$anchor', anchor: anchor, entry: entry);

  /// This management location now showing route [route] (its address).
  AppLocation showing(String route) => AppLocation._(path: route, name: route, reported: route, management: true, entry: entry);

  @override
  String toString() => 'AppLocation($name${entry == null ? '' : ' @$entry'})';
}

/// The page shown for public [location] (as `main.dart` built them).
Widget publicPageFor(AppLocation location) {
  final path = location.path;
  if (path == PublicRoutes.home) return const PublicHomePage();
  if (path == PublicRoutes.gallery) return const PublicGalleryPage();
  if (PublicRoutes.sections.contains(path)) return PublicSectionPage(route: path);
  if (path.startsWith(PublicRoutes.customPagePrefix)) return PublicCustomPage(slug: PublicRoutes.slugFromRoute(path) ?? '');
  if (path.startsWith(PublicRoutes.eventPrefix)) return PublicEventPage(sourceId: PublicRoutes.eventIdFromRoute(path) ?? '');
  if (path.startsWith(PublicRoutes.announcementPrefix)) return PublicAnnouncementPage(sourceId: PublicRoutes.announcementIdFromRoute(path) ?? '');
  return const PublicHomePage();
}

/// Browser addresses ⇄ [AppLocation]s. Each history entry carries the id of
/// the app's entry it belongs to (`appEntry`), so Back and Forward know
/// which one the browser returned to.
class AppRouteParser extends RouteInformationParser<AppLocation> {
  const AppRouteParser();

  static const stateKey = 'appEntry';

  @override
  Future<AppLocation> parseRouteInformation(RouteInformation routeInformation) {
    final state = routeInformation.state;
    final entry = state is Map ? state[stateKey] : null;
    return SynchronousFuture(AppLocation.fromUri(routeInformation.uri, entry: entry is String ? entry : null));
  }

  @override
  RouteInformation restoreRouteInformation(AppLocation configuration) =>
      RouteInformation(uri: Uri.parse(configuration.reported), state: {stateKey: configuration.entry});
}

/// The app's navigation state: the browser history entries this session has
/// seen ([_entries], in order) and the current one ([_position]). The
/// Navigator shows the current entry's page over the previous one (so an
/// in-app back has somewhere to go); management screens, dialogs and other
/// imperative routes are pushed on top as before.
class AppRouterDelegate extends RouterDelegate<AppLocation> with ChangeNotifier {
  AppRouterDelegate();

  /// The delegate of the app's Router above [context], or null (a screen
  /// shown outside the app's Router, e.g. in a test).
  static AppRouterDelegate? maybeOf(BuildContext context) {
    final delegate = Router.maybeOf(context)?.routerDelegate;
    return delegate is AppRouterDelegate ? delegate : null;
  }

  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>(debugLabel: 'app');

  final _session = Random().nextInt(1 << 30).toRadixString(36);
  int _counter = 0;
  String _newEntry() => '$_session-${_counter++}';

  List<_Entry> _entries = [];
  int _position = 0;

  /// The root Navigator's topmost route (a dialog, or a screen pushed
  /// imperatively, is not a page).
  Route<dynamic>? _rootTop;
  late final _rootObserver = _TopObserver((top) => _rootTop = top);

  /// The current location.
  AppLocation get current => _entries[_position].location;

  @override
  AppLocation? get currentConfiguration => _entries.isEmpty ? null : current;

  /// The address the app was opened (or refreshed) at. Any page but Home
  /// has Home beneath it in the app, as before, so the app's own back (and
  /// the system back button) returns Home; the browser's Back follows the
  /// browser's history.
  @override
  Future<void> setInitialRoutePath(AppLocation configuration) {
    final opened = _Entry(configuration.withEntry(configuration.entry ?? _newEntry()));
    final home = configuration.path == PublicRoutes.home && !configuration.management;
    _entries = [if (!home) _Entry(AppLocation.parse(PublicRoutes.home).withEntry(_newEntry())), opened];
    _position = _entries.length - 1;
    return SynchronousFuture(null);
  }

  /// The browser moved to [configuration]'s entry (Back, Forward, or an
  /// address typed in).
  @override
  Future<void> setNewRoutePath(AppLocation configuration) {
    final known = configuration.entry == null ? -1 : _entries.indexWhere((e) => e.id == configuration.entry);
    // Back to an earlier entry (or one from before a refresh): the screens
    // and dialogs on top of the current page are closed first, one at a
    // time and through their PopScope, as the app's back did before; the
    // address then returns to the current location.
    final back = known >= 0 ? known < _position : configuration.entry != null;
    if (back && _closeTopmost()) return SynchronousFuture(null);
    if (known >= 0) {
      _position = known;
      _entries[known] = _Entry(configuration.withEntry(_entries[known].id), shell: _entries[known].shell);
    } else if (configuration.entry == null) {
      // A new address (typed, or opened from outside the app).
      _entries = [..._entries.take(_position + 1), _Entry(configuration.withEntry(_newEntry()))];
      _position = _entries.length - 1;
    } else {
      // An entry from before a refresh: the session starts again there.
      _entries = [_Entry(configuration)];
      _position = 0;
    }
    return SynchronousFuture(null);
  }

  /// Closes the topmost imperative route — a dialog or a screen pushed on
  /// the app's Navigator, else a screen of the management app — through
  /// its PopScope; false when there is none (the page itself is current).
  bool _closeTopmost() {
    final root = navigatorKey.currentState;
    if (root == null) return false;
    final top = _rootTop;
    if (top != null && top.settings is! Page && top.isCurrent) {
      root.maybePop();
      return true;
    }
    final shell = _entries[_position].shell.currentState;
    if (shell != null && shell.canPop()) {
      shell.maybePop();
      return true;
    }
    return false;
  }

  /// Opens [route] as a new page and history entry (a link). The same
  /// address as now does nothing, unless [fresh] (a new page all the same,
  /// e.g. Home again after logging out).
  void go(String route, {Object? arguments, bool fresh = false}) {
    final location = AppLocation.parse(route, arguments: arguments);
    if (!fresh && location.reported == current.reported && location.name == current.name) return;
    _entries = [..._entries.take(_position + 1), _Entry(location.withEntry(_newEntry()))];
    _position = _entries.length - 1;
    notifyListeners();
  }

  /// The current page now shows section [anchor]: the address changes,
  /// without a new history entry when reported under Router.neglect.
  void showSection(String anchor) {
    final entry = _entries[_position];
    if (entry.location.management || entry.location.anchor == anchor) return;
    _entries[_position] = _Entry(entry.location.withAnchor(anchor), shell: entry.shell);
    notifyListeners();
  }

  /// The management app on entry [id] now shows named route [route]: its
  /// address follows (replacing the entry, as before).
  void _managementShows(String id, String route) {
    final index = _entries.indexWhere((e) => e.id == id);
    if (index < 0 || _entries[index].location.path == route) return;
    final entry = _entries[index];
    _entries[index] = _Entry(entry.location.showing(route), shell: entry.shell);
    final context = navigatorKey.currentContext;
    if (context == null || index != _position) return;
    Router.neglect(context, notifyListeners);
  }

  /// The system back button (Android) and in-app back: a dialog or screen on
  /// top first, then the previous page; false at the first page (the app
  /// closes there, as before).
  @override
  Future<bool> popRoute() async {
    final root = navigatorKey.currentState;
    if (root == null) return false;
    final top = _rootTop;
    if (top != null && top.settings is! Page) return root.maybePop();
    final shell = _entries[_position].shell.currentState;
    if (shell != null && shell.canPop()) return shell.maybePop();
    if (_position > 0) return root.maybePop();
    return false;
  }

  /// A page removed by the Navigator itself (an in-app pop): the previous
  /// entry is current again (reported as a new browser entry: the app can't
  /// move the browser back on its own).
  void _removed(Page<Object?> page) {
    final id = (page.key as ValueKey<String>?)?.value;
    final shown = [if (_position > 0) _entries[_position - 1].id, _entries[_position].id];
    if (id == null || !shown.contains(id) || _entries.length < 2) return;
    final index = _entries.indexWhere((e) => e.id == id);
    if (index == _position) {
      _entries = _entries.take(_position).toList();
      _position--;
    } else {
      _entries.removeAt(index);
      _position--;
    }
    notifyListeners();
  }

  Page<void> _pageFor(_Entry entry) => MaterialPage<void>(
        key: ValueKey(entry.id),
        name: entry.location.name,
        arguments: entry.location.arguments,
        child: entry.location.management
            ? ManagementShell(
                navigatorKey: entry.shell,
                initialRoute: entry.location.path,
                initialArguments: entry.location.arguments,
                onShowing: (route) => _managementShows(entry.id, route),
              )
            : publicPageFor(entry.location),
      );

  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: navigatorKey,
      pages: [
        if (_position > 0) _pageFor(_entries[_position - 1]),
        _pageFor(_entries[_position]),
      ],
      onDidRemovePage: _removed,
      // Named routes pushed on the app's Navigator (as before).
      onGenerateRoute: AppRoutes.generate,
      observers: [_rootObserver],
    );
  }
}

class _Entry {
  _Entry(this.location, {GlobalKey<NavigatorState>? shell}) : shell = shell ?? GlobalKey<NavigatorState>(debugLabel: 'management');

  final AppLocation location;
  String get id => location.entry!;

  /// The management shell's Navigator (when this entry is one).
  final GlobalKey<NavigatorState> shell;
}

/// Reports the topmost route of a Navigator.
class _TopObserver extends NavigatorObserver {
  _TopObserver(this.onTop);

  final ValueChanged<Route<dynamic>?> onTop;

  @override
  void didChangeTop(Route<dynamic> topRoute, Route<dynamic>? previousTopRoute) => onTop(topRoute);
}

/// Named routes pushed imperatively on the app's Navigator: a management
/// route opens in a management shell (`/otp` with its arguments); a public
/// page opens as before. Null for an unknown name (as before).
class AppRoutes {
  AppRoutes._();

  static Route<dynamic>? generate(RouteSettings settings) {
    final name = settings.name ?? '';
    final location = AppLocation.parse(name, arguments: settings.arguments);
    if (location.management) {
      return MaterialPageRoute(
        settings: settings,
        builder: (_) => ManagementShell(initialRoute: location.path, initialArguments: settings.arguments),
      );
    }
    if (AppLocation.publicPath(Uri.parse(name).path) == null) return null;
    return MaterialPageRoute(settings: RouteSettings(name: location.name, arguments: settings.arguments), builder: (_) => publicPageFor(location));
  }
}

/// The management app: a Navigator with its existing routes
/// ([ManagementRoutes]) starting at [initialRoute], so its screens push,
/// replace and pop exactly as they did on the app's Navigator. Its named
/// routes are reported ([onShowing]) so the address follows them, as before.
/// A public page pushed by name inside it opens there, as before.
class ManagementShell extends StatefulWidget {
  const ManagementShell({super.key, this.navigatorKey, required this.initialRoute, this.initialArguments, this.onShowing});

  /// The management Navigator's key (the app's back closes its screens).
  final GlobalKey<NavigatorState>? navigatorKey;
  final String initialRoute;
  final Object? initialArguments;
  final ValueChanged<String>? onShowing;

  @override
  State<ManagementShell> createState() => _ManagementShellState();
}

class _ManagementShellState extends State<ManagementShell> {
  late final _observer = _TopObserver((top) {
    final name = top?.settings.name;
    if (name == null || !ManagementRoutes.isManagement(name)) return;
    // After this frame: the address is reported once the screen is shown.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onShowing?.call(name);
    });
  });

  static Route<dynamic>? _generate(RouteSettings settings) => ManagementRoutes.generate(settings) ?? AppRoutes.generate(settings);

  @override
  Widget build(BuildContext context) => Navigator(
        key: widget.navigatorKey,
        initialRoute: widget.initialRoute,
        // The first screen only (not `/` beneath it): the public website is
        // the app's own page underneath. `/otp` opened without its phone
        // (an address typed in, or a refresh) starts at `/app`.
        onGenerateInitialRoutes: (navigator, name) {
          final otpWithoutPhone = name == ManagementRoutes.otp && widget.initialArguments is! Map;
          final route = _generate(RouteSettings(name: otpWithoutPhone ? PublicRoutes.management : name, arguments: widget.initialArguments));
          return [route ?? _generate(const RouteSettings(name: PublicRoutes.management))!];
        },
        onGenerateRoute: _generate,
        observers: [_observer],
      );
}

/// The app's Router configuration ([MontessoriApp]).
RouterConfig<AppLocation> createAppRouterConfig() {
  final initial = WidgetsBinding.instance.platformDispatcher.defaultRouteName;
  return RouterConfig<AppLocation>(
    routeInformationProvider: PlatformRouteInformationProvider(initialRouteInformation: RouteInformation(uri: Uri.parse(initial))),
    routeInformationParser: const AppRouteParser(),
    routerDelegate: AppRouterDelegate(),
    backButtonDispatcher: RootBackButtonDispatcher(),
  );
}
