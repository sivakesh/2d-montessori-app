import 'package:core_contracts/core_contracts.dart' as core;
import 'package:feature_media/feature_media.dart';
import 'package:feature_pages/feature_pages.dart';
import 'package:feature_pages/src/presentation/media_reference_picker_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pages-integration coverage for SRS "Replace raw image-URL entry in
/// Pages with Media Library selection" — proves picking an asset from
/// `feature_media`'s library produces a correctly-shaped `MediaReference`
/// (url from the asset's largest variant, altText/storagePath carried
/// over from the asset itself), without needing to stand up the full
/// `PageEditorScreen`.
class _FakeMediaRepository implements MediaRepository {
  MediaAsset? assetToReturn;

  @override
  Stream<MediaUploadEvent> upload(
    MediaUploadRequest request, {
    required String actorId,
  }) => const Stream.empty();

  @override
  Future<core.Result<MediaAsset>> get(String mediaId) async =>
      const core.Result.failure(MediaNotFoundFailure());

  @override
  Stream<core.Result<MediaAsset>> observe(String mediaId) =>
      Stream.value(const core.Result.failure(MediaNotFoundFailure()));

  @override
  Future<core.Result<core.Page<MediaAsset>>> list({
    MediaFilter query = const MediaFilter(),
    core.PageRequest request = const core.PageRequest(),
  }) async => core.Result.ok(
    core.Page(
      items: assetToReturn == null ? const [] : [assetToReturn!],
      nextCursor: null,
      hasMore: false,
    ),
  );

  @override
  Future<core.Result<MediaAsset>> updateMetadata({
    required String mediaId,
    required String title,
    required String altText,
    String description = '',
  }) async => const core.Result.failure(MediaNotFoundFailure());

  @override
  Future<core.Result<void>> archive(String mediaId) async =>
      const core.Result.failure(MediaNotFoundFailure());

  @override
  Future<core.Result<void>> restore(String mediaId) async =>
      const core.Result.failure(MediaNotFoundFailure());

  @override
  Future<core.Result<void>> delete(String mediaId) async =>
      const core.Result.failure(MediaNotFoundFailure());

  @override
  Future<core.Result<List<MediaUsageReference>>> listUsages(
    String mediaId,
  ) async => const core.Result.ok([]);
}

MediaAsset _readyAsset() => const MediaAsset(
  mediaId: 'm1',
  fileName: 'logo.png',
  title: 'Logo',
  altText: 'The school logo',
  status: MediaStatus.ready,
  archived: false,
  storagePath: 'private/media/m1/original.png',
  uploadedBy: 'u1',
  variants: {
    'w640': MediaVariant(
      storagePath: 'public/media/m1/w640.webp',
      url: 'https://storage.example/m1/w640.webp',
      format: 'webp',
      width: 640,
    ),
  },
);

void main() {
  testWidgets('shows "No image selected" when value is null', (tester) async {
    final repository = _FakeMediaRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaReferencePickerField(
            label: 'Featured image',
            value: null,
            mediaRepository: repository,
            onChanged: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('No image selected'), findsOneWidget);
    expect(find.text('Choose'), findsOneWidget);
  });

  testWidgets(
    'picking an asset from the library produces a MediaReference from its largest variant',
    (tester) async {
      final repository = _FakeMediaRepository()..assetToReturn = _readyAsset();
      MediaReference? picked;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaReferencePickerField(
              label: 'Featured image',
              value: null,
              mediaRepository: repository,
              onChanged: (v) => picked = v,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Choose'));
      await tester.pumpAndSettle();

      // The picker dialog is open, showing the one ready asset.
      expect(find.text('Logo'), findsOneWidget);

      await tester.tap(find.text('Logo'));
      await tester.pumpAndSettle();

      expect(picked, isNotNull);
      expect(picked!.url, 'https://storage.example/m1/w640.webp');
      expect(picked!.altText, 'The school logo');
      expect(picked!.storagePath, 'private/media/m1/original.png');
    },
  );

  testWidgets('shows a "Remove" button once a value is set', (tester) async {
    final repository = _FakeMediaRepository();
    MediaReference? current = const MediaReference(
      url: 'https://storage.example/m1/w640.webp',
      altText: 'The school logo',
      storagePath: 'private/media/m1/original.png',
    );

    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) => MaterialApp(
          home: Scaffold(
            body: MediaReferencePickerField(
              label: 'Featured image',
              value: current,
              mediaRepository: repository,
              onChanged: (v) => setState(() => current = v),
            ),
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.close), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();

    expect(current, isNull);
  });
}
