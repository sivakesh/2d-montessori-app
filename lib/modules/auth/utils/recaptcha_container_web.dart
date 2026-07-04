// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;

void ensureRecaptchaContainer() {
  var existing = html.document.getElementById('recaptcha-container');

  if (existing == null) {
    existing = html.DivElement()..id = 'recaptcha-container';
    html.document.body?.append(existing);
  }

  if (existing is html.HtmlElement) {
    existing.style
      ..position = 'fixed'
      ..right = '0'
      ..bottom = '0'
      ..width = '1px'
      ..height = '1px'
      ..overflow = 'hidden'
      ..opacity = '0'
      ..pointerEvents = 'none'
      ..zIndex = '-1';
  }
}

void cleanupRecaptchaContainer() {
  final existing = html.document.getElementById('recaptcha-container');
  if (existing is html.HtmlElement) {
    existing.children.clear();
  }
}
