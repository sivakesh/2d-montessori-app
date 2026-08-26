// SETTINGS-01 coverage for SchoolSettingsService — the School Settings
// data/authorization/logo-storage layer. UI-level coverage (navigation,
// access-restricted rendering, responsive/no-overflow) lives in
// admin_settings_navigation_test.dart.
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/admin/settings/data/school_settings_service.dart';
import 'package:montessori_app/modules/admin/settings/models/school_settings_model.dart';

class _StubFilePicker extends FilePicker {
  _StubFilePicker(this.result);
  final FilePickerResult? result;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async =>
      result;
}

PlatformFile _fakeLogo({String name = 'logo.png'}) {
  final bytes = Uint8List.fromList(List.generate(16, (i) => i));
  return PlatformFile(name: name, size: bytes.length, bytes: bytes);
}

SchoolSettingsService _service(
  FakeFirebaseFirestore firestore, {
  MockFirebaseStorage? storage,
  FilePicker? filePicker,
}) =>
    SchoolSettingsService(
      firestore: firestore,
      storage: storage ?? MockFirebaseStorage(),
      filePicker: filePicker ?? _StubFilePicker(null),
    );

void main() {
  group('SchoolSettingsService — load', () {
    test('1. No settings saved yet returns null (empty/default form)', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);

      final settings = await service.getSettings(schoolId: kDefaultSchoolId, requesterRole: 'admin');

      expect(settings, isNull);
    });

    test('2. Existing settings load with the saved values', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      await service.saveSettings(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        name: '2D Montessori House',
        address: '12 Garden Road',
        phone: '+91 80 1234 5678',
        email: 'info@2dmontessori.example',
        website: 'https://2dmontessori.example',
        description: 'A calm, child-led learning environment.',
        updatedBy: 'admin-1',
        updatedByName: 'Asha',
      );

      final settings = await service.getSettings(schoolId: kDefaultSchoolId, requesterRole: 'admin');

      expect(settings, isNotNull);
      expect(settings!.name, '2D Montessori House');
      expect(settings.address, '12 Garden Road');
      expect(settings.phone, '+91 80 1234 5678');
      expect(settings.email, 'info@2dmontessori.example');
      expect(settings.website, 'https://2dmontessori.example');
      expect(settings.description, 'A calm, child-led learning environment.');
      expect(settings.schoolId, kDefaultSchoolId);
    });
  });

  group('SchoolSettingsService — save (create vs update)', () {
    test('3. First save creates the settings document', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);

      await service.saveSettings(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        name: 'Sunshine Montessori',
        updatedBy: 'admin-1',
        updatedByName: 'Asha',
      );

      final snap = await firestore.collection('school_settings').get();
      expect(snap.docs, hasLength(1));
      expect(snap.docs.single.id, kDefaultSchoolId);
      expect(snap.docs.single.data()['name'], 'Sunshine Montessori');
    });

    test('4. Subsequent save updates the same document, never creates a duplicate', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);

      await service.saveSettings(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        name: 'Sunshine Montessori',
        updatedBy: 'admin-1',
        updatedByName: 'Asha',
      );
      await service.saveSettings(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        name: 'Sunshine Montessori House',
        phone: '080-1234567',
        updatedBy: 'admin-1',
        updatedByName: 'Asha',
      );
      await service.saveSettings(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        name: 'Sunshine Montessori House',
        phone: '080-1234567',
        email: 'hello@sunshine.example',
        updatedBy: 'admin-2',
        updatedByName: 'Ravi',
      );

      final snap = await firestore.collection('school_settings').get();
      expect(snap.docs, hasLength(1), reason: 'repeated saves must update, never duplicate');
      final data = snap.docs.single.data();
      expect(data['name'], 'Sunshine Montessori House');
      expect(data['phone'], '080-1234567');
      expect(data['email'], 'hello@sunshine.example');
      expect(data['updatedBy'], 'admin-2');
    });
  });

  group('SchoolSettingsService — validation', () {
    test('5. Blank school name is rejected and nothing is written', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);

      expect(
        () => service.saveSettings(
          schoolId: kDefaultSchoolId,
          requesterRole: 'admin',
          name: '   ',
          updatedBy: 'admin-1',
          updatedByName: 'Asha',
        ),
        throwsArgumentError,
      );

      final snap = await firestore.collection('school_settings').get();
      expect(snap.docs, isEmpty);
    });

    test('6. Invalid email is rejected; a blank email is fine (optional field)', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);

      expect(
        () => service.saveSettings(
          schoolId: kDefaultSchoolId,
          requesterRole: 'admin',
          name: 'Sunshine Montessori',
          email: 'not-an-email',
          updatedBy: 'admin-1',
          updatedByName: 'Asha',
        ),
        throwsArgumentError,
      );

      // Optional field left blank must not be rejected.
      await service.saveSettings(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        name: 'Sunshine Montessori',
        email: '',
        updatedBy: 'admin-1',
        updatedByName: 'Asha',
      );
      final settings = await service.getSettings(schoolId: kDefaultSchoolId, requesterRole: 'admin');
      expect(settings!.email, '');
    });

    test('invalid website is rejected; a well-formed one is accepted', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);

      expect(
        () => service.saveSettings(
          schoolId: kDefaultSchoolId,
          requesterRole: 'admin',
          name: 'Sunshine Montessori',
          website: 'not a website',
          updatedBy: 'admin-1',
          updatedByName: 'Asha',
        ),
        throwsArgumentError,
      );

      await service.saveSettings(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        name: 'Sunshine Montessori',
        website: 'https://sunshine.example/about',
        updatedBy: 'admin-1',
        updatedByName: 'Asha',
      );
      final settings = await service.getSettings(schoolId: kDefaultSchoolId, requesterRole: 'admin');
      expect(settings!.website, 'https://sunshine.example/about');
    });

    test('normal school phone formats are preserved verbatim, never rejected/reformatted', () async {
      for (final phone in <String>[
        '+91 80 1234 5678',
        '080-12345678',
        '(080) 1234 5678',
        '1800-123-4567',
        '9876543210',
      ]) {
        final firestoreForPhone = FakeFirebaseFirestore();
        final svc = _service(firestoreForPhone);
        await svc.saveSettings(
          schoolId: kDefaultSchoolId,
          requesterRole: 'admin',
          name: 'Sunshine Montessori',
          phone: phone,
          updatedBy: 'admin-1',
          updatedByName: 'Asha',
        );
        final settings = await svc.getSettings(schoolId: kDefaultSchoolId, requesterRole: 'admin');
        expect(settings!.phone, phone, reason: 'phone format "$phone" must be preserved verbatim');
      }
    });
  });

  group('SchoolSettingsService — authorization', () {
    test('7. Admin can load and save settings', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);

      await service.saveSettings(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        name: 'Sunshine Montessori',
        updatedBy: 'admin-1',
        updatedByName: 'Asha',
      );
      final settings = await service.getSettings(schoolId: kDefaultSchoolId, requesterRole: 'admin');
      expect(settings, isNotNull);
    });

    test('8. Staff is denied both reading and saving settings', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);

      expect(
        () => service.getSettings(schoolId: kDefaultSchoolId, requesterRole: 'staff'),
        throwsA(isA<UnauthorizedSchoolSettingsException>()),
      );
      expect(
        () => service.saveSettings(
          schoolId: kDefaultSchoolId,
          requesterRole: 'staff',
          name: 'Hijacked Name',
          updatedBy: 'staff-1',
          updatedByName: 'Malini',
        ),
        throwsA(isA<UnauthorizedSchoolSettingsException>()),
      );

      final snap = await firestore.collection('school_settings').get();
      expect(snap.docs, isEmpty, reason: 'a denied save must never write anything');
    });

    test('9. Parent is denied both reading and saving settings', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);

      expect(
        () => service.getSettings(schoolId: kDefaultSchoolId, requesterRole: 'parent'),
        throwsA(isA<UnauthorizedSchoolSettingsException>()),
      );
      expect(
        () => service.saveSettings(
          schoolId: kDefaultSchoolId,
          requesterRole: 'parent',
          name: 'Hijacked Name',
          updatedBy: 'parent-1',
          updatedByName: 'Kavya',
        ),
        throwsA(isA<UnauthorizedSchoolSettingsException>()),
      );

      final snap = await firestore.collection('school_settings').get();
      expect(snap.docs, isEmpty);
    });
  });

  group('SchoolSettingsService — schoolId isolation', () {
    test('10. Settings for one schoolId are never visible under, or overwritten by, another schoolId', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);

      await service.saveSettings(
        schoolId: 'school-a',
        requesterRole: 'admin',
        name: 'School A',
        updatedBy: 'admin-1',
        updatedByName: 'Asha',
      );

      // Nothing has ever been saved for school-b.
      final bSettings = await service.getSettings(schoolId: 'school-b', requesterRole: 'admin');
      expect(bSettings, isNull);

      await service.saveSettings(
        schoolId: 'school-b',
        requesterRole: 'admin',
        name: 'School B',
        updatedBy: 'admin-1',
        updatedByName: 'Asha',
      );

      final aSettings = await service.getSettings(schoolId: 'school-a', requesterRole: 'admin');
      final bSettingsAfter = await service.getSettings(schoolId: 'school-b', requesterRole: 'admin');

      expect(aSettings!.name, 'School A', reason: 'school-a must be unaffected by school-b being created');
      expect(bSettingsAfter!.name, 'School B');

      final snap = await firestore.collection('school_settings').get();
      expect(snap.docs, hasLength(2));
      expect(snap.docs.map((d) => d.id).toSet(), {'school-a', 'school-b'});
    });
  });

  group('SchoolSettingsService — logo (Storage)', () {
    test('11a. pickLogoFile returns the picked file, or null when cancelled', () async {
      final firestore = FakeFirebaseFirestore();
      final file = _fakeLogo();
      final picked = _service(
        firestore,
        filePicker: _StubFilePicker(FilePickerResult([file])),
      );
      final cancelled = _service(firestore, filePicker: _StubFilePicker(null));

      expect((await picked.pickLogoFile())?.name, 'logo.png');
      expect(await cancelled.pickLogoFile(), isNull);
    });

    test('11b. Uploading a logo stores it in Storage and saveSettings persists the URL', () async {
      final firestore = FakeFirebaseFirestore();
      final storage = MockFirebaseStorage();
      final service = _service(firestore, storage: storage);

      final url = await service.uploadLogo(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        file: _fakeLogo(),
      );
      expect(url, isNotEmpty);

      await service.saveSettings(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        name: 'Sunshine Montessori',
        logoUrl: url,
        updatedBy: 'admin-1',
        updatedByName: 'Asha',
      );

      final settings = await service.getSettings(schoolId: kDefaultSchoolId, requesterRole: 'admin');
      expect(settings!.logoUrl, url);
      // The uploaded bytes are actually retrievable from Storage at that URL.
      final data = await storage.refFromURL(url).getData();
      expect(data, isNotNull);
    });

    test('11c. Replacing a logo deletes the previous Storage object (no orphan)', () async {
      final firestore = FakeFirebaseFirestore();
      final storage = MockFirebaseStorage();
      final service = _service(firestore, storage: storage);

      final firstUrl = await service.uploadLogo(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        file: _fakeLogo(name: 'old_logo.png'),
      );
      final secondUrl = await service.uploadLogo(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        file: _fakeLogo(name: 'new_logo.png'),
        previousLogoUrl: firstUrl,
      );

      expect(secondUrl, isNot(firstUrl));
      // Old object gone (getDownloadURL throws 'object-not-found' once the
      // underlying data no longer exists — MockFirebaseStorage's own
      // signal that a ref no longer resolves to anything)...
      expect(
        () => storage.refFromURL(firstUrl).getDownloadURL(),
        throwsA(isA<FirebaseException>()),
      );
      // ...new object present.
      expect(await storage.refFromURL(secondUrl).getData(), isNotNull);
    });

    test('11d. Removing a logo deletes the Storage object and clears logoUrl on the document', () async {
      final firestore = FakeFirebaseFirestore();
      final storage = MockFirebaseStorage();
      final service = _service(firestore, storage: storage);

      final url = await service.uploadLogo(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        file: _fakeLogo(),
      );
      await service.saveSettings(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        name: 'Sunshine Montessori',
        logoUrl: url,
        updatedBy: 'admin-1',
        updatedByName: 'Asha',
      );

      await service.removeLogo(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        logoUrl: url,
        updatedBy: 'admin-1',
        updatedByName: 'Asha',
      );

      final settings = await service.getSettings(schoolId: kDefaultSchoolId, requesterRole: 'admin');
      expect(settings!.logoUrl, '', reason: 'logoUrl must be cleared on the document');
      expect(
        () => storage.refFromURL(url).getDownloadURL(),
        throwsA(isA<FirebaseException>()),
        reason: 'the Storage object itself must be deleted, not just unlinked',
      );
    });

    test('removing a logo that was never actually uploaded (already-gone object) does not throw', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);

      await expectLater(
        service.removeLogo(
          schoolId: kDefaultSchoolId,
          requesterRole: 'admin',
          logoUrl: 'https://firebasestorage.googleapis.com/v0/b/some-bucket/o/school_settings%2Fghost.png',
          updatedBy: 'admin-1',
          updatedByName: 'Asha',
        ),
        completes,
      );
      final settings = await service.getSettings(schoolId: kDefaultSchoolId, requesterRole: 'admin');
      expect(settings!.logoUrl, '');
    });

    test('Staff/Parent cannot upload or remove the logo', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);

      for (final role in ['staff', 'parent']) {
        expect(
          () => service.uploadLogo(schoolId: kDefaultSchoolId, requesterRole: role, file: _fakeLogo()),
          throwsA(isA<UnauthorizedSchoolSettingsException>()),
        );
        expect(
          () => service.removeLogo(
            schoolId: kDefaultSchoolId,
            requesterRole: role,
            logoUrl: 'https://firebasestorage.googleapis.com/v0/b/some-bucket/o/x.png',
            updatedBy: 'x',
            updatedByName: 'x',
          ),
          throwsA(isA<UnauthorizedSchoolSettingsException>()),
        );
      }
    });
  });
}
