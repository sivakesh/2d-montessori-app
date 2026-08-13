import 'package:feature_pages/feature_pages.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'renders a heading with Semantics(header: true) — preserves heading hierarchy',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PageSectionRenderer(
              section: RichTextSection(
                id: 's1',
                sortOrder: 0,
                heading: 'Our story',
                body: 'Body text.',
              ),
            ),
          ),
        ),
      );

      final headingFinder = find.ancestor(
        of: find.text('Our story'),
        matching: find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.header == true,
        ),
      );
      expect(headingFinder, findsOneWidget);
      expect(find.text('Body text.'), findsOneWidget);
    },
  );

  testWidgets('exposes an image section\'s alt text as the Semantics label', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PageSectionRenderer(
            section: ImageSection(
              id: 's1',
              sortOrder: 0,
              image: MediaReference(
                url: '',
                altText: 'A classroom of children',
              ),
            ),
          ),
        ),
      ),
    );

    final semantics = tester.widget<Semantics>(
      find.byWidgetPredicate(
        (w) =>
            w is Semantics && w.properties.label == 'A classroom of children',
      ),
    );
    expect(semantics.properties.image, isTrue);
  });

  testWidgets('a hidden section renders nothing', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PageSectionRenderer(
            section: RichTextSection(
              id: 's1',
              sortOrder: 0,
              isVisible: false,
              body: 'Should not render',
            ),
          ),
        ),
      ),
    );

    expect(find.text('Should not render'), findsNothing);
  });
}
