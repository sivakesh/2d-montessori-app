// ignore_for_file: avoid_web_libraries_in_flutter
// ignore_for_file: deprecated_member_use
import 'dart:html' as html;
import 'dart:ui_web' as ui;

void registerRecaptchaView() {
  ui.platformViewRegistry.registerViewFactory(
    'recaptcha-container',
    (int viewId) {
      final element = html.DivElement()
        ..id = 'recaptcha-container'
        ..style.width = '304px'
        ..style.height = '78px'
        ..style.display = 'block';

      return element;
    },
  );
}
