// Hosted Firebase configuration (DEPLOY_TARGET=hosted): a web build served
// by Firebase Hosting reads the serving project's options from
// /__/firebase/init.json on its own origin, checks them strictly and against
// EXPECTED_PROJECT_ID, and otherwise shows an error with Retry — never the
// compiled DEV or production options. '', dev and prod are unchanged
// (test/prod01_deploy_target_test.dart).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:montessori_app/core/config/deploy_target.dart';
import 'package:montessori_app/core/config/firebase_environment.dart';
import 'package:montessori_app/core/config/hosted_config_error_app.dart';
import 'package:montessori_app/core/config/hosted_config_fetch.dart';
import 'package:montessori_app/core/config/hosted_firebase_config.dart';
import 'package:montessori_app/core/config/hosted_firebase_startup.dart';

const _project = 'school-app-12345';

/// The shape Firebase Hosting serves (verified on DEV in Stage 1), with
/// made-up values.
Map<String, Object?> _config({Map<String, Object?> overrides = const {}, List<String> without = const []}) => {
      'apiKey': 'test-api-key',
      'appId': '1:123456789012:web:abcdef0123456789',
      'authDomain': '$_project.firebaseapp.com',
      'databaseURL': '',
      'messagingSenderId': '123456789012',
      'projectId': _project,
      'storageBucket': '$_project.firebasestorage.app',
      ...overrides,
    }..removeWhere((k, _) => without.contains(k));

HostedConfigResponse _ok(Object? body, {String type = 'application/json'}) =>
    HostedConfigResponse(status: 200, contentType: type, body: body is String ? body : jsonEncode(body));

TypeMatcher<HostedConfigException> _problem(HostedConfigProblem p) => isA<HostedConfigException>().having((e) => e.problem, 'problem', p);

FirebaseOptions _parse(HostedConfigResponse r, {String expected = _project}) => parseHostedFirebaseConfig(r, expectedProjectId: expected);

void main() {
  group('DEPLOY_TARGET=hosted', () {
    test('resolves to hosted on the web only', () {
      expect(resolveDeployTarget('hosted', isWeb: true), DeployTarget.hosted);
      expect(() => resolveDeployTarget('hosted', isWeb: false), throwsStateError, reason: 'a native build never enters hosted mode');
      expect(() => resolveDeployTarget('hosted'), throwsStateError, reason: 'flutter test is not the web');
    });

    test("'', dev and prod are unchanged on every platform; other spellings still refused", () {
      for (final web in [true, false]) {
        expect(resolveDeployTarget('', isWeb: web), DeployTarget.dev);
        expect(resolveDeployTarget('dev', isWeb: web), DeployTarget.dev);
        expect(resolveDeployTarget('prod', isWeb: web), DeployTarget.prod);
        for (final bad in ['Hosted', 'HOSTED', ' hosted', 'hosted ', 'host']) {
          expect(() => resolveDeployTarget(bad, isWeb: web), throwsStateError);
        }
      }
      expect(currentDeployTarget, DeployTarget.dev, reason: 'no dart-define in flutter test');
    });

    test('has no compiled options: no fallback to DEV or production', () {
      expect(() => firebaseOptionsFor(DeployTarget.hosted), throwsStateError);
    });

    test('the hosted startup code never reaches the compiled options', () {
      for (final f in ['hosted_firebase_startup.dart', 'hosted_firebase_config.dart', 'hosted_config_fetch.dart', 'hosted_config_fetch_web.dart', 'hosted_config_fetch_stub.dart', 'hosted_config_error_app.dart']) {
        final source = File('lib/core/config/$f').readAsStringSync();
        for (final forbidden in ['firebase_options', 'firebaseOptionsFor', 'DefaultFirebaseOptions', 'firebase_environment']) {
          expect(source, isNot(contains(forbidden)), reason: '$f must not use $forbidden');
        }
      }
      final main = File('lib/main.dart').readAsStringSync();
      final hostedBranch = main.substring(main.indexOf('if (currentDeployTarget == DeployTarget.hosted)'), main.indexOf('} else {'));
      expect(hostedBranch, contains('initializeHostedFirebase()'));
      expect(hostedBranch, isNot(contains('firebaseOptionsFor')));
    });
  });

  group('parseHostedFirebaseConfig', () {
    test('a valid configuration: every option, an empty databaseURL as absent', () {
      final options = _parse(_ok(_config()));
      expect(options.projectId, _project);
      expect(options.apiKey, 'test-api-key');
      expect(options.appId, '1:123456789012:web:abcdef0123456789');
      expect(options.messagingSenderId, '123456789012');
      expect(options.authDomain, '$_project.firebaseapp.com');
      expect(options.storageBucket, '$_project.firebasestorage.app');
      expect(options.databaseURL, isNull, reason: 'Hosting serves "" when there is no database');
      expect(options.measurementId, isNull);
      expect(_parse(_ok(_config()), expected: _project), options);
    });

    test('a JSON content type with a charset is accepted; a non-empty databaseURL is kept', () {
      final options = _parse(_ok(_config(overrides: {'databaseURL': 'https://x.firebaseio.com'}), type: 'Application/JSON; charset=utf-8'));
      expect(options.databaseURL, 'https://x.firebaseio.com');
    });

    test('the app page returned with HTTP 200 (a misrouted path) is refused', () {
      const html = '<!DOCTYPE html><html><head></head><body></body></html>';
      expect(() => _parse(_ok(html, type: 'text/html; charset=utf-8')), throwsA(_problem(HostedConfigProblem.invalidResponse)));
      expect(() => _parse(_ok(html)), throwsA(_problem(HostedConfigProblem.invalidResponse)), reason: 'HTML labelled as JSON is still not JSON');
      expect(() => _parse(_ok(_config(), type: '')), throwsA(_problem(HostedConfigProblem.invalidResponse)));
    });

    test('a response other than HTTP 200 is unavailable', () {
      for (final status in [301, 304, 403, 404, 500, 503]) {
        expect(() => _parse(HostedConfigResponse(status: status, contentType: 'application/json', body: jsonEncode(_config()))), throwsA(_problem(HostedConfigProblem.unavailable)));
      }
    });

    test('invalid JSON, a non-object, or a field that is not text is refused', () {
      for (final body in ['{', '', 'null', '[]', '"text"', '{"apiKey": "a",}']) {
        expect(() => _parse(_ok(body)), throwsA(_problem(HostedConfigProblem.invalidResponse)), reason: body);
      }
      expect(() => _parse(_ok(_config(overrides: {'projectId': 42}))), throwsA(_problem(HostedConfigProblem.invalidResponse)));
      expect(() => _parse(_ok(_config(overrides: {'databaseURL': false}))), throwsA(_problem(HostedConfigProblem.invalidResponse)));
    });

    test('every required field must be present and non-empty (authDomain and storageBucket included)', () {
      for (final key in ['apiKey', 'appId', 'messagingSenderId', 'projectId', 'authDomain', 'storageBucket']) {
        expect(() => _parse(_ok(_config(without: [key]))), throwsA(_problem(HostedConfigProblem.invalidResponse)), reason: 'missing $key');
        expect(() => _parse(_ok(_config(overrides: {key: '  '}))), throwsA(_problem(HostedConfigProblem.invalidResponse)), reason: 'blank $key');
      }
    });

    test('an invalid project id, or host fields that are not host names, are refused', () {
      for (final id in ['Upper-Case1', 'ab', '1starts-with-digit', 'ends-with-', 'has_underscore', 'a' * 31]) {
        expect(() => _parse(_ok(_config(overrides: {'projectId': id})), expected: id), throwsA(_problem(HostedConfigProblem.invalidResponse)), reason: id);
      }
      expect(() => _parse(_ok(_config(overrides: {'authDomain': 'https://evil.example/'}))), throwsA(_problem(HostedConfigProblem.invalidResponse)));
      expect(() => _parse(_ok(_config(overrides: {'storageBucket': 'no dots'}))), throwsA(_problem(HostedConfigProblem.invalidResponse)));
    });

    test('a valid configuration for another project is a mismatch', () {
      expect(
        () => _parse(_ok(_config()), expected: 'another-school-1'),
        throwsA(_problem(HostedConfigProblem.projectMismatch).having((e) => e.detail, 'detail', allOf(contains('another-school-1'), contains(_project)))),
      );
    });

    test('error details never contain the API key', () {
      final errors = <HostedConfigException>[];
      for (final r in [_ok(_config(), type: 'text/html'), _ok(_config(without: ['appId'])), _ok(_config(overrides: {'projectId': 'Bad'}))]) {
        try {
          _parse(r, expected: _project);
        } on HostedConfigException catch (e) {
          errors.add(e);
        }
      }
      try {
        _parse(_ok(_config()), expected: 'another-school-1');
      } on HostedConfigException catch (e) {
        errors.add(e);
      }
      expect(errors, hasLength(4));
      for (final e in errors) {
        expect(e.detail, isNot(contains('test-api-key')));
      }
    });
  });

  group('loadHostedFirebaseOptions', () {
    final page = Uri.parse('https://$_project.web.app/app/dashboard?x=1#top');

    test('fetches /__/firebase/init.json on the page\'s own origin', () async {
      final urls = <Uri>[];
      final options = await loadHostedFirebaseOptions(page: page, expectedProjectId: _project, fetch: (url) async {
        urls.add(url);
        return _ok(_config());
      });
      expect(urls, [Uri.parse('https://$_project.web.app/__/firebase/init.json')]);
      expect(options.projectId, _project);
      final custom = <Uri>[];
      await loadHostedFirebaseOptions(page: Uri.parse('https://www.school.example:8443/pages/about'), expectedProjectId: _project, fetch: (url) async {
        custom.add(url);
        return _ok(_config());
      });
      expect(custom.single.toString(), 'https://www.school.example:8443/__/firebase/init.json');
    });

    test('a missing or invalid EXPECTED_PROJECT_ID stops before any request', () async {
      var calls = 0;
      for (final expected in ['', 'Not Valid']) {
        await expectLater(
          loadHostedFirebaseOptions(page: page, expectedProjectId: expected, fetch: (_) async {
            calls++;
            return _ok(_config());
          }),
          throwsA(_problem(HostedConfigProblem.buildMisconfigured)),
        );
      }
      expect(calls, 0);
    });

    test('a network failure is unavailable', () async {
      await expectLater(
        loadHostedFirebaseOptions(page: page, expectedProjectId: _project, fetch: (_) => Future.error(const SocketException('offline'))),
        throwsA(_problem(HostedConfigProblem.unavailable)),
      );
    });

    test('a request that does not answer in time is unavailable', () async {
      await expectLater(
        loadHostedFirebaseOptions(page: page, expectedProjectId: _project, timeout: const Duration(milliseconds: 20), fetch: (_) => Completer<HostedConfigResponse>().future),
        throwsA(_problem(HostedConfigProblem.unavailable).having((e) => e.detail, 'detail', contains('timed out'))),
      );
    });

    test('a page not served over HTTP (e.g. a file) has nothing to ask', () async {
      await expectLater(
        loadHostedFirebaseOptions(page: Uri.parse('file:///index.html'), expectedProjectId: _project, fetch: (_) async => _ok(_config())),
        throwsA(_problem(HostedConfigProblem.unavailable)),
      );
    });

    test('off the web the request always fails (the non-web stub)', () async {
      await expectLater(fetchHostedConfig(Uri.parse('https://$_project.web.app/__/firebase/init.json')), throwsUnsupportedError);
      await expectLater(
        loadHostedFirebaseOptions(page: page, expectedProjectId: _project, fetch: fetchHostedConfig),
        throwsA(_problem(HostedConfigProblem.unavailable)),
      );
    });
  });

  group('HostedFirebaseStartup', () {
    final valid = FirebaseOptions(apiKey: 'k', appId: 'a', messagingSenderId: '1', projectId: _project);

    test('valid configuration: initialized once, no error shown', () async {
      final initialized = <FirebaseOptions>[];
      var errors = 0;
      await HostedFirebaseStartup(
        load: () async => valid,
        initialize: (o) async => initialized.add(o),
        isInitialized: () => initialized.isNotEmpty,
        showError: (_) async => errors++,
      ).run();
      expect(initialized, [valid]);
      expect(errors, 0);
    });

    test('an error is shown and the whole attempt runs again on Retry, never with other options', () async {
      final shown = <HostedConfigProblem>[];
      final initialized = <FirebaseOptions>[];
      var loads = 0;
      await HostedFirebaseStartup(
        load: () async {
          loads++;
          if (loads == 1) throw const HostedConfigException(HostedConfigProblem.unavailable, 'offline');
          if (loads == 2) throw const HostedConfigException(HostedConfigProblem.projectMismatch, 'wrong project');
          return valid;
        },
        initialize: (o) async => initialized.add(o),
        isInitialized: () => initialized.isNotEmpty,
        showError: (e) async => shown.add(e.problem),
      ).run();
      expect(shown, [HostedConfigProblem.unavailable, HostedConfigProblem.projectMismatch]);
      expect(loads, 3);
      expect(initialized, [valid], reason: 'only the hosted options, only once');
    });

    test('waits for Retry before trying again', () async {
      final retry = Completer<void>();
      var loads = 0;
      var done = false;
      final run = HostedFirebaseStartup(
        load: () async {
          loads++;
          if (loads == 1) throw const HostedConfigException(HostedConfigProblem.unavailable, 'offline');
          return valid;
        },
        initialize: (_) async {},
        isInitialized: () => false,
        showError: (_) => retry.future,
      ).run().then((_) => done = true);
      await Future<void>.delayed(Duration.zero);
      expect(loads, 1);
      expect(done, isFalse, reason: 'stopped: Firebase not initialized, the app not started');
      retry.complete();
      await run;
      expect(loads, 2);
    });

    test('an app created by a failed attempt is not initialized again (no duplicate app)', () async {
      var appExists = false;
      var initializeCalls = 0;
      var errors = 0;
      await HostedFirebaseStartup(
        load: () async => valid,
        initialize: (_) async {
          initializeCalls++;
          appExists = true;
          throw StateError('failed after the app was created');
        },
        isInitialized: () => appExists,
        showError: (_) async => errors++,
      ).run();
      expect(initializeCalls, 1);
      expect(errors, 1);
    });

    test('already initialized: nothing is loaded or initialized', () async {
      var loads = 0;
      await HostedFirebaseStartup(
        load: () async {
          loads++;
          return valid;
        },
        initialize: (_) async => fail('must not initialize twice'),
        isInitialized: () => true,
        showError: (_) async => fail('no error'),
      ).run();
      expect(loads, 0);
    });

    test('the build define is read from EXPECTED_PROJECT_ID (empty in flutter test)', () {
      expect(expectedProjectIdFromBuild, isEmpty);
    });
  });

  group('HostedConfigErrorApp', () {
    testWidgets('says what happened and retries once per error shown', (tester) async {
      var retries = 0;
      await tester.pumpWidget(HostedConfigErrorApp(
        error: const HostedConfigException(HostedConfigProblem.unavailable, 'The configuration request timed out.'),
        onRetry: () => retries++,
      ));
      expect(find.text("The app can't start right now"), findsOneWidget);
      expect(find.text(HostedConfigErrorApp.messageFor(HostedConfigProblem.unavailable)), findsOneWidget);
      expect(find.text('The configuration request timed out.'), findsOneWidget);
      await tester.tap(find.byKey(HostedConfigErrorApp.retryKey));
      await tester.pump();
      await tester.tap(find.byKey(HostedConfigErrorApp.retryKey));
      await tester.pump();
      expect(retries, 1);
      expect(find.text('Retrying…'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('every problem has its own message; fits a phone without overflow', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final messages = {for (final p in HostedConfigProblem.values) HostedConfigErrorApp.messageFor(p)};
      expect(messages, hasLength(HostedConfigProblem.values.length));
      for (final p in HostedConfigProblem.values) {
        await tester.pumpWidget(HostedConfigErrorApp(error: HostedConfigException(p, 'detail'), onRetry: () {}));
        expect(find.text(HostedConfigErrorApp.messageFor(p)), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      expect(find.byType(FilledButton), findsOneWidget);
    });
  });
}
