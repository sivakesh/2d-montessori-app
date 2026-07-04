// ignore_for_file: deprecated_member_use
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

void cleanupRecaptchaImpl() {
  try {
    final selectors = [
      '.grecaptcha-badge',
      'iframe[src*="recaptcha"]',
      'iframe[src*="google.com/recaptcha"]',
      'div[style*="z-index: 2000000000"]',
    ];

    for (final selector in selectors) {
      final elements = html.document.querySelectorAll(selector);
      for (final element in elements) {
        if (element is html.HtmlElement) {
          element.style.display = 'none';
          element.style.visibility = 'hidden';
          element.style.opacity = '0';
          element.style.pointerEvents = 'none';
        }

        final parent = element.parent;
        if (parent is html.HtmlElement &&
            (selector.contains('iframe') || selector.contains('grecaptcha'))) {
          parent.style.display = 'none';
          parent.style.visibility = 'hidden';
          parent.style.opacity = '0';
          parent.style.pointerEvents = 'none';
        }
      }
    }

    final recaptchaContainer = html.document.getElementById(
      'recaptcha-container',
    );

    if (recaptchaContainer is html.HtmlElement) {
      recaptchaContainer.style.display = 'none';
      recaptchaContainer.style.visibility = 'hidden';
      recaptchaContainer.children.clear();
    }
  } catch (_) {
    // Ignore cleanup errors.
  }
}
