// ignore_for_file: deprecated_member_use
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

void registerRecaptchaContainer() {
  // Ignore duplicate registration if hot reload or rebuild runs again.
  // The browser factory only needs to exist once.
  try {
    ui_web.platformViewRegistry.registerViewFactory(
      'recaptcha-container',
      (int viewId) => html.DivElement()..id = 'recaptcha-container',
    );
  } catch (_) {
    // Factory may already be registered.
  }
}
