import 'package:feature_pages/feature_pages.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isValidSlugFormat', () {
    test('accepts lowercase letters, numbers and hyphens', () {
      expect(isValidSlugFormat('about-us'), isTrue);
      expect(isValidSlugFormat('program-2026'), isTrue);
      expect(isValidSlugFormat('a'), isTrue);
    });

    test('rejects uppercase, spaces, and leading/trailing/double hyphens', () {
      expect(isValidSlugFormat('About-Us'), isFalse);
      expect(isValidSlugFormat('about us'), isFalse);
      expect(isValidSlugFormat('-about'), isFalse);
      expect(isValidSlugFormat('about-'), isFalse);
      expect(isValidSlugFormat('about--us'), isFalse);
      expect(isValidSlugFormat(''), isFalse);
    });
  });
}
