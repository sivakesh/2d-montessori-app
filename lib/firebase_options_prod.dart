// Firebase options for the LIVE PRODUCTION project (twod-montessori-prod).
//
// PROD-01: manually created alongside the FlutterFire-CLI-generated
// `firebase_options.dart` (which remains the DEV/UAT config and was not
// modified). Values below are the actual registered Web app config for
// twod-montessori-prod, fetched read-only via
// `firebase apps:sdkconfig web <appId> --project twod-montessori-prod`.
//
// Android has not been configured for production yet -- that is a separate
// follow-up task (Android product flavors + a prod google-services.json).
// Do not add an `android` case/const here until that exists.
// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;

class DefaultFirebaseOptionsProd {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    throw UnsupportedError(
      'DefaultFirebaseOptionsProd have not been configured for '
      '$defaultTargetPlatform. Production launch is Web-only; Android '
      'production is a follow-up task.',
    );
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyBbYELUWA1hK1ZjXsbpxespvM3mOAyFFwE',
    appId: '1:455124304339:web:0d3b3d520aa2cd5a836f26',
    messagingSenderId: '455124304339',
    projectId: 'twod-montessori-prod',
    authDomain: 'twod-montessori-prod.firebaseapp.com',
    storageBucket: 'twod-montessori-prod.firebasestorage.app',
  );
}
