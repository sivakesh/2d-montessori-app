import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

/// Firebase options for a hosted web build ([DeployTarget.hosted]): the
/// configuration Firebase Hosting serves for the project that hosts the
/// page, at this reserved path on the page's own origin.
///
/// Everything here is checked strictly, and every problem is a
/// [HostedConfigException]: a hosted build never falls back to compiled
/// options.
const hostedFirebaseConfigPath = '/__/firebase/init.json';

/// What the configuration request returned.
class HostedConfigResponse {
  const HostedConfigResponse({required this.status, required this.contentType, required this.body});

  final int status;

  /// The `Content-Type` header ('' when there is none).
  final String contentType;

  final String body;
}

/// Fetches [url] (same origin). Throws on a network failure.
typedef HostedConfigFetch = Future<HostedConfigResponse> Function(Uri url);

/// Why a hosted build can't start.
enum HostedConfigProblem {
  /// The build itself is wrong (no valid `EXPECTED_PROJECT_ID`).
  buildMisconfigured,

  /// The configuration couldn't be fetched (network, timeout, not HTTP 200).
  unavailable,

  /// It was fetched but isn't a valid Firebase web configuration.
  invalidResponse,

  /// It is valid but for a different project than this build expects.
  projectMismatch,
}

class HostedConfigException implements Exception {
  const HostedConfigException(this.problem, this.detail);

  final HostedConfigProblem problem;

  /// What exactly went wrong (no secrets: never the API key).
  final String detail;

  @override
  String toString() => 'HostedConfigException(${problem.name}): $detail';
}

/// A Google Cloud / Firebase project id: 6–30 characters, lowercase
/// letters, digits and hyphens, starting with a letter and not ending with
/// a hyphen.
final _projectIdPattern = RegExp(r'^[a-z][a-z0-9-]{4,28}[a-z0-9]$');

bool isValidFirebaseProjectId(String value) => _projectIdPattern.hasMatch(value);

final _hostPattern = RegExp(r'^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$');

/// The options in [response], checked: HTTP 200, a JSON content type, a
/// JSON object whose known fields are strings, every required field
/// present, a valid project id equal to [expectedProjectId], and host-like
/// `authDomain` and `storageBucket`. An empty `databaseURL` is absent.
FirebaseOptions parseHostedFirebaseConfig(HostedConfigResponse response, {required String expectedProjectId}) {
  if (response.status != 200) {
    throw HostedConfigException(HostedConfigProblem.unavailable, 'The configuration request returned HTTP ${response.status}.');
  }
  final mediaType = response.contentType.split(';').first.trim().toLowerCase();
  if (mediaType != 'application/json') {
    throw HostedConfigException(
      HostedConfigProblem.invalidResponse,
      'The configuration response is "${mediaType.isEmpty ? 'untyped' : mediaType}", not JSON (is this build served by Firebase Hosting?).',
    );
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(response.body);
  } on FormatException {
    throw const HostedConfigException(HostedConfigProblem.invalidResponse, 'The configuration response is not valid JSON.');
  }
  if (decoded is! Map<String, dynamic>) {
    throw const HostedConfigException(HostedConfigProblem.invalidResponse, 'The configuration response is not a JSON object.');
  }
  final Map<String, dynamic> config = decoded;

  String? field(String key) {
    final value = config[key];
    if (value == null) return null;
    if (value is! String) {
      throw HostedConfigException(HostedConfigProblem.invalidResponse, 'The configuration field "$key" is not text.');
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String required(String key) =>
      field(key) ?? (throw HostedConfigException(HostedConfigProblem.invalidResponse, 'The configuration has no "$key".'));

  final apiKey = required('apiKey');
  final appId = required('appId');
  final messagingSenderId = required('messagingSenderId');
  final projectId = required('projectId');
  final authDomain = required('authDomain');
  final storageBucket = required('storageBucket');
  final databaseUrl = field('databaseURL');
  final measurementId = field('measurementId');

  if (!isValidFirebaseProjectId(projectId)) {
    throw HostedConfigException(HostedConfigProblem.invalidResponse, 'The configuration project id "$projectId" is not a valid project id.');
  }
  for (final (key, value) in [('authDomain', authDomain), ('storageBucket', storageBucket)]) {
    if (!_hostPattern.hasMatch(value)) {
      throw HostedConfigException(HostedConfigProblem.invalidResponse, 'The configuration field "$key" is not a host name.');
    }
  }
  if (projectId != expectedProjectId) {
    throw HostedConfigException(
      HostedConfigProblem.projectMismatch,
      'This build expects project "$expectedProjectId" but is served by "$projectId".',
    );
  }
  return FirebaseOptions(
    apiKey: apiKey,
    appId: appId,
    messagingSenderId: messagingSenderId,
    projectId: projectId,
    authDomain: authDomain,
    storageBucket: storageBucket,
    databaseURL: databaseUrl,
    measurementId: measurementId,
  );
}

/// The hosting project's options for the page at [page]: fetched with
/// [fetch] from [hostedFirebaseConfigPath] on the page's own origin (within
/// [timeout]) and checked by [parseHostedFirebaseConfig].
///
/// [expectedProjectId] (the build's `EXPECTED_PROJECT_ID`) must be a valid
/// project id, or nothing is fetched.
Future<FirebaseOptions> loadHostedFirebaseOptions({
  required Uri page,
  required String expectedProjectId,
  required HostedConfigFetch fetch,
  Duration timeout = const Duration(seconds: 10),
}) async {
  if (!isValidFirebaseProjectId(expectedProjectId)) {
    throw HostedConfigException(
      HostedConfigProblem.buildMisconfigured,
      expectedProjectId.isEmpty
          ? 'This build has no EXPECTED_PROJECT_ID.'
          : 'This build\'s EXPECTED_PROJECT_ID "$expectedProjectId" is not a valid project id.',
    );
  }
  if (!page.isScheme('https') && !page.isScheme('http')) {
    throw const HostedConfigException(HostedConfigProblem.unavailable, 'The page is not served over HTTP, so there is no Firebase Hosting configuration.');
  }
  final url = page.resolve(hostedFirebaseConfigPath);
  final HostedConfigResponse response;
  try {
    response = await fetch(url).timeout(timeout);
  } on TimeoutException {
    throw const HostedConfigException(HostedConfigProblem.unavailable, 'The configuration request timed out.');
  } catch (_) {
    throw const HostedConfigException(HostedConfigProblem.unavailable, 'The configuration request failed (network error).');
  }
  return parseHostedFirebaseConfig(response, expectedProjectId: expectedProjectId);
}
