import 'package:design_system/design_system.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Breakpoints.tokenForWidth', () {
    test('320px resolves to compact', () {
      expect(Breakpoints.tokenForWidth(320), ViewportToken.compact);
    });

    test('600px resolves to medium', () {
      expect(Breakpoints.tokenForWidth(600), ViewportToken.medium);
    });

    test('1024px resolves to expanded', () {
      expect(Breakpoints.tokenForWidth(1024), ViewportToken.expanded);
    });

    test('1440px resolves to wide', () {
      expect(Breakpoints.tokenForWidth(1440), ViewportToken.wide);
    });
  });
}
