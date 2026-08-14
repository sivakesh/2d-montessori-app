import 'dart:typed_data';

import 'package:core_contracts/core_contracts.dart';
import 'package:feature_media/feature_media.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_media_repository.dart';

/// A fake `FilePicker.platform` implementation — the standard
/// `PlatformInterface` testing pattern (`FilePicker.platform` has a
/// public setter for exactly this reason). Lets these tests prove the
/// screen's Upload button is genuinely wired to a real call, without
/// depending on a real browser file dialog (which does not exist under
/// `flutter test`) or on the *deployed* web platform implementation's
/// registration, which is a separate, real-project-only concern these
/// tests cannot exercise — see docs/architecture/decisions.md's "Media
/// Upload button" entry for how that half was verified instead.
class FakeFilePicker extends FilePicker {
  int callCount = 0;
  bool? lastWithData;
  FilePickerResult? Function()? resultBuilder;
  Object? errorToThrow;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    void Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    callCount++;
    lastWithData = withData;
    if (errorToThrow != null) throw errorToThrow!;
    return resultBuilder?.call();
  }
}

PlatformFile _platformFile({String name = 'logo.png', int size = 4}) =>
    PlatformFile(name: name, size: size, bytes: Uint8List(size));

Widget _wrap(MediaLibraryController controller) => MaterialApp(
  home: Scaffold(body: MediaLibraryScreen(controller: controller)),
);

void main() {
  late FakeMediaRepository repository;
  late MediaLibraryController controller;
  late FakeFilePicker fakePicker;

  setUp(() {
    repository = FakeMediaRepository();
    controller = MediaLibraryController(
      repository: repository,
      actingRole: UserRole.publisher,
      actorId: 'publisher-1',
    );
    fakePicker = FakeFilePicker();
    // `FilePicker.platform` (a `late` field with no default) is never
    // auto-initialized under plain `flutter test` — nothing runs the
    // real app's plugin-registration step here, so there is no "real"
    // platform value to save and restore between tests, only ever this
    // fake one.
    FilePicker.platform = fakePicker;
  });

  tearDown(() => controller.dispose());

  testWidgets(
    'tapping Upload calls FilePicker.platform.pickFiles synchronously from the click, requesting bytes',
    (tester) async {
      fakePicker.resultBuilder = () => null; // cancel immediately
      await tester.pumpWidget(_wrap(controller));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Upload'));
      await tester.pump();

      expect(fakePicker.callCount, 1);
      expect(fakePicker.lastWithData, isTrue);
    },
  );

  testWidgets(
    'a successful selection opens the metadata dialog pre-filled with the file name',
    (tester) async {
      fakePicker.resultBuilder = () =>
          FilePickerResult([_platformFile(name: 'school-photo.png')]);
      await tester.pumpWidget(_wrap(controller));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Upload'));
      await tester.pumpAndSettle();

      expect(find.text('Media details'), findsOneWidget);
      expect(
        find.widgetWithText(TextField, 'school-photo.png'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'cancellation (a null result) closes cleanly with no dialog and no error banner',
    (tester) async {
      fakePicker.resultBuilder = () => null;
      await tester.pumpWidget(_wrap(controller));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Upload'));
      await tester.pumpAndSettle();

      expect(find.text('Media details'), findsNothing);
      expect(find.byType(MaterialBanner), findsNothing);
    },
  );

  testWidgets(
    'an exception from the picker itself produces a visible, accessible error banner — never a silent no-op',
    (tester) async {
      fakePicker.errorToThrow = StateError('web implementation not registered');
      await tester.pumpWidget(_wrap(controller));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Upload'));
      await tester.pumpAndSettle();

      expect(find.byType(MaterialBanner), findsOneWidget);
      expect(
        find.textContaining('Could not open the file picker'),
        findsOneWidget,
      );
      expect(find.text('Media details'), findsNothing);
    },
  );

  testWidgets(
    'a picked file with no readable bytes also produces a visible error, not a silent no-op',
    (tester) async {
      fakePicker.resultBuilder = () => FilePickerResult([
        PlatformFile(name: 'empty.png', size: 0),
      ]); // bytes: null
      await tester.pumpWidget(_wrap(controller));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Upload'));
      await tester.pumpAndSettle();

      expect(find.byType(MaterialBanner), findsOneWidget);
      expect(find.textContaining('could not be read'), findsOneWidget);
    },
  );

  testWidgets('the error banner can be dismissed', (tester) async {
    fakePicker.errorToThrow = Exception('boom');
    await tester.pumpWidget(_wrap(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Upload'));
    await tester.pumpAndSettle();
    expect(find.byType(MaterialBanner), findsOneWidget);

    await tester.tap(find.text('Dismiss'));
    await tester.pumpAndSettle();
    expect(find.byType(MaterialBanner), findsNothing);
  });
}
