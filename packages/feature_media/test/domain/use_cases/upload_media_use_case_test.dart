import 'dart:typed_data';

import 'package:core_contracts/core_contracts.dart';
import 'package:feature_media/feature_media.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_media_repository.dart';

MediaUploadRequest _validRequest({
  String mimeType = 'image/png',
  Uint8List? bytes,
  String title = 'Logo',
  String altText = 'The school logo',
}) => MediaUploadRequest(
  bytes: bytes ?? Uint8List(1024),
  fileName: 'logo.png',
  mimeType: mimeType,
  title: title,
  altText: altText,
);

void main() {
  late FakeMediaRepository repository;
  late UploadMediaUseCase useCase;

  setUp(() {
    repository = FakeMediaRepository();
    useCase = UploadMediaUseCase(repository);
  });

  Future<MediaUploadEvent> lastEvent(Stream<MediaUploadEvent> stream) async {
    final events = await stream.toList();
    return events.last;
  }

  test(
    'an Editor (limited access) passes validation and reaches the repository',
    () async {
      // SRS §3: every real UserRole has at least "limited" (own uploads)
      // media access, so a valid request from an Editor should fall
      // through validation and reach the repository rather than being
      // rejected on capability grounds.
      repository.uploadResponse = Stream.value(
        const MediaUploadTransferComplete('m1'),
      );
      await useCase(
        request: _validRequest(),
        actingRole: UserRole.editor,
        actorId: 'u1',
      ).toList();
      expect(repository.lastUploadRequest, isNotNull);
    },
  );

  test('rejects a blank title without calling the repository', () async {
    final event = await lastEvent(
      useCase(
        request: _validRequest(title: ''),
        actingRole: UserRole.editor,
        actorId: 'u1',
      ),
    );
    final finished = event as MediaUploadFinished;
    expect(
      finished.result.fold((_) => null, (f) => f),
      isA<ValidationFailure>(),
    );
    expect(repository.lastUploadRequest, isNull);
  });

  test('rejects blank alt text without calling the repository', () async {
    final event = await lastEvent(
      useCase(
        request: _validRequest(altText: ''),
        actingRole: UserRole.editor,
        actorId: 'u1',
      ),
    );
    final finished = event as MediaUploadFinished;
    expect(
      finished.result.fold((_) => null, (f) => f),
      isA<ValidationFailure>(),
    );
    expect(repository.lastUploadRequest, isNull);
  });

  test(
    'rejects an unapproved MIME type without calling the repository',
    () async {
      final event = await lastEvent(
        useCase(
          request: _validRequest(mimeType: 'application/x-msdownload'),
          actingRole: UserRole.editor,
          actorId: 'u1',
        ),
      );
      final finished = event as MediaUploadFinished;
      expect(
        finished.result.fold((_) => null, (f) => f),
        isA<UnapprovedMediaTypeFailure>(),
      );
      expect(repository.lastUploadRequest, isNull);
    },
  );

  test(
    'rejects an oversized file (over its type’s limit) without calling the repository',
    () async {
      final event = await lastEvent(
        useCase(
          request: _validRequest(bytes: Uint8List(11 * 1024 * 1024)),
          actingRole: UserRole.editor,
          actorId: 'u1',
        ),
      );
      final finished = event as MediaUploadFinished;
      expect(
        finished.result.fold((_) => null, (f) => f),
        isA<MediaTooLargeFailure>(),
      );
      expect(repository.lastUploadRequest, isNull);
    },
  );

  test(
    'delegates to the repository with the caller’s actorId when everything is valid',
    () async {
      await useCase(
        request: _validRequest(),
        actingRole: UserRole.publisher,
        actorId: 'publisher-1',
      ).toList();
      expect(repository.lastUploadRequest, isNotNull);
      expect(repository.lastUploadActorId, 'publisher-1');
    },
  );
}
