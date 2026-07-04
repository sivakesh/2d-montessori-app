// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;

void ensureRecaptchaContainer() {
  final existing = html.document.getElementById('recaptcha-container');
  if (existing == null) {
    return;
  }

  if (existing is html.HtmlElement) {
    existing.style
      ..position = 'static'
      ..width = '304px'
      ..height = '78px'
      ..display = 'block'
      ..overflow = 'visible'
      ..opacity = '1'
      ..pointerEvents = 'auto';
  }
}

void cleanupRecaptchaContainer() {
  final existing = html.document.getElementById('recaptcha-container');
  if (existing is html.HtmlElement) {
    existing.children.clear();
    existing.style
      ..width = '304px'
      ..height = '78px'
      ..display = 'block';
  }
}
