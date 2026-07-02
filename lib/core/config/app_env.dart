import 'package:flutter/foundation.dart';

enum AppEnvironment { dev, prod }

const _appEnvironment = String.fromEnvironment('APP_ENV', defaultValue: '');

final currentEnvironment = switch (_appEnvironment) {
  'dev' => AppEnvironment.dev,
  'prod' => AppEnvironment.prod,
  _ => kReleaseMode ? AppEnvironment.prod : AppEnvironment.dev,
};
