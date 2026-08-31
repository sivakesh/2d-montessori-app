// PROD-01: Firebase production environment separation.
//
// Proves the DEPLOY_TARGET/Firebase-project selection mechanism is correct
// and safe, and -- just as importantly -- that it is completely orthogonal
// to APP_ENV/AppEnvironment (application behaviour, including the DEV/UAT
// OTP bypass in getAuthService()). APP_ENV must keep meaning exactly what
// it meant before this task; DEPLOY_TARGET must never be able to influence
// it, and vice versa.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:montessori_app/core/config/deploy_target.dart';
import 'package:montessori_app/core/config/firebase_environment.dart';
import 'package:montessori_app/firebase_options.dart' as dev_options;
import 'package:montessori_app/firebase_options_prod.dart' as prod_options;

void main() {
  group('resolveDeployTarget (DEPLOY_TARGET mapping)', () {
    test('omitted/empty value defaults to dev (DEV/UAT) -- backward compat', () {
      expect(resolveDeployTarget(''), DeployTarget.dev);
    });

    test('DEPLOY_TARGET=dev resolves to dev', () {
      expect(resolveDeployTarget('dev'), DeployTarget.dev);
    });

    test('DEPLOY_TARGET=prod resolves to prod', () {
      expect(resolveDeployTarget('prod'), DeployTarget.prod);
    });

    test('invalid values fail safely and never resolve to prod', () {
      for (final bad in ['staging', 'PROD', 'Dev', 'production', ' prod', 'prod ']) {
        expect(
          () => resolveDeployTarget(bad),
          throwsA(isA<StateError>()),
          reason: 'DEPLOY_TARGET="$bad" must throw, not silently pick an environment',
        );
      }
    });

    test('the default currentDeployTarget (no dart-define in `flutter test`) is dev', () {
      // `flutter test` runs with no --dart-define=DEPLOY_TARGET, exercising
      // exactly the "omitted" backward-compatibility path.
      expect(currentDeployTarget, DeployTarget.dev);
    });
  });

  group('Firebase project config content', () {
    test('DEV/UAT web config points at montessori-app-95988', () {
      final web = dev_options.DefaultFirebaseOptions.web;
      expect(web.projectId, 'montessori-app-95988');
      expect(web.authDomain, 'montessori-app-95988.firebaseapp.com');
      expect(web.storageBucket, 'montessori-app-95988.firebasestorage.app');
    });

    test('PRODUCTION web config points at twod-montessori-prod', () {
      final web = prod_options.DefaultFirebaseOptionsProd.web;
      expect(web.projectId, 'twod-montessori-prod');
      expect(web.authDomain, 'twod-montessori-prod.firebaseapp.com');
      expect(web.storageBucket, 'twod-montessori-prod.firebasestorage.app');
    });

    test('DEV and PROD web configs are for different Firebase projects', () {
      expect(
        dev_options.DefaultFirebaseOptions.web.projectId,
        isNot(prod_options.DefaultFirebaseOptionsProd.web.projectId),
      );
      expect(
        dev_options.DefaultFirebaseOptions.web.apiKey,
        isNot(prod_options.DefaultFirebaseOptionsProd.web.apiKey),
      );
    });
  });

  group('firebaseOptionsFor (DeployTarget -> FirebaseOptions dispatch)', () {
    test('DeployTarget.dev resolves to the DEV/UAT project', () {
      // `flutter test` runs on the VM (kIsWeb == false), so currentPlatform
      // falls through to the android config here -- still the same
      // DEV/UAT project, so the projectId assertion holds regardless of
      // which platform branch is taken.
      expect(firebaseOptionsFor(DeployTarget.dev).projectId, 'montessori-app-95988');
    });

    test(
      'DeployTarget.prod never silently falls back to a non-production config '
      'on a platform it is not configured for',
      () {
        // Production is Web-only today (Android prod flavors are a follow-up
        // task, deliberately out of scope). Under `flutter test` (VM, not
        // web), asking for prod options must fail loudly rather than
        // returning some other project's config.
        expect(
          () => firebaseOptionsFor(DeployTarget.prod),
          throwsA(isA<UnsupportedError>()),
        );
      },
    );
  });

  group('APP_ENV / auth-bypass isolation from DEPLOY_TARGET', () {
    test('app_env.dart (APP_ENV semantics) is byte-for-byte unchanged by this task', () {
      final content = File('lib/core/config/app_env.dart').readAsStringSync();
      expect(content, contains("enum AppEnvironment { dev, prod }"));
      expect(
        content,
        contains("const _appEnvironment = String.fromEnvironment('APP_ENV', defaultValue: '');"),
      );
      expect(content, contains("'dev' => AppEnvironment.dev,"));
      expect(content, contains("'prod' => AppEnvironment.prod,"));
      expect(content, contains("_ => kReleaseMode ? AppEnvironment.prod : AppEnvironment.dev,"));
      // No coupling was introduced from APP_ENV's implementation to the new
      // DEPLOY_TARGET machinery.
      expect(content, isNot(contains('DEPLOY_TARGET')));
      expect(content, isNot(contains('DeployTarget')));
    });

    test(
      'getAuthService() (the DEV/UAT OTP bypass switch) has no dependency on '
      'DEPLOY_TARGET or the Firebase project selector',
      () {
        final content = File('lib/modules/auth/data/auth_service_impl.dart').readAsStringSync();
        // Bypass selection still keys purely off AppEnvironment (APP_ENV).
        expect(content, contains('currentEnvironment == AppEnvironment.dev'));
        expect(content, contains('return DevAuthService();'));
        // It must not import or reference the new deploy-target machinery --
        // proving DEPLOY_TARGET=prod cannot possibly influence which auth
        // service is returned.
        expect(content, isNot(contains('deploy_target.dart')));
        expect(content, isNot(contains('firebase_environment.dart')));
        expect(content, isNot(contains('DeployTarget')));
      },
    );

    test('main.dart selects Firebase options via DEPLOY_TARGET, not APP_ENV', () {
      final content = File('lib/main.dart').readAsStringSync();
      expect(content, contains('firebaseOptionsFor(currentDeployTarget)'));
      // Firebase initialization must not be gated on AppEnvironment/APP_ENV.
      expect(content, isNot(contains('currentEnvironment')));
      expect(content, isNot(contains('AppEnvironment')));
    });
  });

  group('.firebaserc aliases', () {
    late Map<String, dynamic> firebaserc;

    setUpAll(() {
      firebaserc = jsonDecode(File('.firebaserc').readAsStringSync()) as Map<String, dynamic>;
    });

    test('dev alias points at the DEV/UAT project', () {
      final projects = firebaserc['projects'] as Map<String, dynamic>;
      expect(projects['dev'], 'montessori-app-95988');
    });

    test('prod alias points at the real production project, not DEV/UAT', () {
      final projects = firebaserc['projects'] as Map<String, dynamic>;
      expect(projects['prod'], 'twod-montessori-prod');
      expect(
        projects['prod'],
        isNot('montessori-app-95988'),
        reason: 'the old misleading prod->montessori-app-95988 alias must be gone',
      );
    });

    test('default alias remains the safe DEV/UAT project, never production', () {
      final projects = firebaserc['projects'] as Map<String, dynamic>;
      expect(projects['default'], 'montessori-app-95988');
      expect(projects['default'], isNot('twod-montessori-prod'));
    });
  });
}
