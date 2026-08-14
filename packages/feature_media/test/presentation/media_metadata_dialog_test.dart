import 'package:feature_media/src/presentation/media_metadata_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<MediaMetadataDialogResult?> _showDialog(
  WidgetTester tester, {
  String initialTitle = '',
}) async {
  MediaMetadataDialogResult? captured;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                captured = await showDialog<MediaMetadataDialogResult>(
                  context: context,
                  builder: (_) =>
                      MediaMetadataDialog(initialTitle: initialTitle),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  return captured;
}

void main() {
  testWidgets('shows a validation error when submitted with no title', (
    tester,
  ) async {
    await _showDialog(tester);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('A title is required.'), findsOneWidget);
  });

  testWidgets('shows a validation error when submitted with no alt text', (
    tester,
  ) async {
    await _showDialog(tester, initialTitle: 'Logo');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Accessible alt text is required.'), findsOneWidget);
  });

  testWidgets(
    'returns the entered values once title and alt text are filled in',
    (tester) async {
      MediaMetadataDialogResult? captured;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    captured = await showDialog<MediaMetadataDialogResult>(
                      context: context,
                      builder: (_) => const MediaMetadataDialog(),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).at(0), 'Logo');
      await tester.enterText(find.byType(TextField).at(1), 'The school logo');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(captured?.title, 'Logo');
      expect(captured?.altText, 'The school logo');
    },
  );
}
