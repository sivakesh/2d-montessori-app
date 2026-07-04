import 'recaptcha_cleanup_stub.dart'
    if (dart.library.html) 'recaptcha_cleanup_web.dart';

void cleanupRecaptcha() => cleanupRecaptchaImpl();
