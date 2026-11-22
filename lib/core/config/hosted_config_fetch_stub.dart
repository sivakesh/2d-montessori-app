import 'hosted_firebase_config.dart';

/// Not on the web: there is no Firebase Hosting page to ask.
Future<HostedConfigResponse> fetchHostedConfig(Uri url) =>
    Future.error(UnsupportedError('Hosted Firebase configuration is only available on the web.'));
