// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

void cleanupRecaptchaImpl() {
  try {
    final container = html.document.getElementById('recaptcha-container');
    if (container != null) {
      container.style.display = 'none';
      container.children.clear();
    }

    final iframes = html.document.querySelectorAll('iframe');
    for (final frame in iframes) {
      final src = frame.getAttribute('src') ?? '';
      if (src.contains('recaptcha')) {
        final parent = frame.parent;
        if (parent is html.HtmlElement) {
          parent.style.display = 'none';
        }
      }
    }
  } catch (_) {
    // Ignore cleanup errors.
  }
}
