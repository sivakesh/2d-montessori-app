import 'package:admin_web/main.dart';
import 'package:core_contracts/core_contracts.dart';
import 'package:feature_identity/feature_identity.dart';
import 'package:feature_media/feature_media.dart';
import 'package:feature_pages/feature_pages.dart';
import 'package:feature_publishing/feature_publishing.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAuthRepository implements AuthRepository {
  @override
  Stream<AuthState> observeAuthState() =>
      Stream.value(const AuthStateSignedOut());

  @override
  Future<Result<void>> changeOwnPassword(String newPassword) async =>
      const Result.ok(null);

  @override
  Future<Result<void>> completeFirstLogin() async => const Result.ok(null);

  @override
  Future<Result<void>> confirmPasswordReset({
    required String oobCode,
    required String newPassword,
  }) async => const Result.ok(null);

  @override
  Future<Result<void>> refreshOwnClaims() async => const Result.ok(null);

  @override
  Future<Result<void>> sendPasswordResetEmail(String email) async =>
      const Result.ok(null);

  @override
  Future<Result<void>> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async => const Result.ok(null);

  @override
  Future<Result<void>> signOut() async => const Result.ok(null);
}

class _FakeUserAdminRepository implements UserAdminRepository {
  @override
  Future<Result<CreateUserResult>> createUser({
    required String email,
    required String displayName,
    required UserRole role,
  }) async => const Result.failure(ValidationFailure('not used in this test'));

  @override
  Stream<Result<List<UserAccount>>> observeUsers() =>
      Stream.value(const Result.ok([]));

  @override
  Future<Result<ResetPasswordResult>> resetUserPassword(String uid) async =>
      const Result.failure(ValidationFailure('not used in this test'));

  @override
  Future<Result<void>> setUserRole({
    required String uid,
    required UserRole role,
  }) async => const Result.failure(ValidationFailure('not used in this test'));

  @override
  Future<Result<void>> setUserStatus({
    required String uid,
    required AccountStatus status,
  }) async => const Result.failure(ValidationFailure('not used in this test'));
}

class _FakePagesRepository implements PagesRepository {
  @override
  Future<Result<CmsPage>> createPage({
    required String title,
    required String ownerId,
  }) async => const Result.failure(ValidationFailure('not used in this test'));

  @override
  Future<Result<CmsPage>> updateContent({
    required String pageId,
    required PageContentUpdate content,
  }) async => const Result.failure(ValidationFailure('not used in this test'));

  @override
  Future<Result<CmsPage>> get(String pageId) async =>
      const Result.failure(ContentNotFoundFailure());

  @override
  Stream<Result<CmsPage>> observe(String pageId) =>
      Stream.value(const Result.failure(ContentNotFoundFailure()));

  @override
  Future<Result<Page<CmsPage>>> list({
    PagesQuery query = const PagesQuery(),
    PageRequest request = const PageRequest(),
  }) async =>
      const Result.ok(Page(items: [], nextCursor: null, hasMore: false));

  @override
  Future<Result<List<PageRevision>>> listRevisions(String pageId) async =>
      const Result.ok([]);

  @override
  Future<Result<CmsPage>> restoreRevision({
    required String pageId,
    required String revisionId,
    required String actorId,
  }) async => const Result.failure(PageRevisionNotFoundFailure());

  @override
  Future<Result<CmsPage>> transition({
    required String pageId,
    required PublishingAction action,
    required String actorId,
    String? comment,
    DateTime? scheduledAt,
  }) async => const Result.failure(ContentNotFoundFailure());
}

class _FakeMediaRepository implements MediaRepository {
  @override
  Stream<MediaUploadEvent> upload(
    MediaUploadRequest request, {
    required String actorId,
  }) => Stream.value(
    const MediaUploadFinished(
      Result.failure(MediaUploadFailure('not used in this test')),
    ),
  );

  @override
  Future<Result<MediaAsset>> get(String mediaId) async =>
      const Result.failure(MediaNotFoundFailure());

  @override
  Stream<Result<MediaAsset>> observe(String mediaId) =>
      Stream.value(const Result.failure(MediaNotFoundFailure()));

  @override
  Future<Result<Page<MediaAsset>>> list({
    MediaFilter query = const MediaFilter(),
    PageRequest request = const PageRequest(),
  }) async =>
      const Result.ok(Page(items: [], nextCursor: null, hasMore: false));

  @override
  Future<Result<MediaAsset>> updateMetadata({
    required String mediaId,
    required String title,
    required String altText,
    String description = '',
  }) async => const Result.failure(MediaNotFoundFailure());

  @override
  Future<Result<void>> archive(String mediaId) async =>
      const Result.failure(MediaNotFoundFailure());

  @override
  Future<Result<void>> restore(String mediaId) async =>
      const Result.failure(MediaNotFoundFailure());

  @override
  Future<Result<void>> delete(String mediaId) async =>
      const Result.failure(MediaNotFoundFailure());

  @override
  Future<Result<List<MediaUsageReference>>> listUsages(String mediaId) async =>
      const Result.ok([]);
}

void main() {
  testWidgets('AdminWebApp shows the sign-in screen when signed out', (
    WidgetTester tester,
  ) async {
    // No Firebase bootstrap here — main.dart's Firebase.initializeApp()
    // call requires platform channels unavailable under `flutter test`.
    // This pumps AdminWebApp directly with fake repositories instead, the
    // same pattern as apps/public_web/test/widget_test.dart.
    final authRepository = _FakeAuthRepository();
    final controller = AuthController(authRepository);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      AdminWebApp(
        authController: controller,
        authRepository: authRepository,
        userAdminRepository: _FakeUserAdminRepository(),
        pagesRepository: _FakePagesRepository(),
        mediaRepository: _FakeMediaRepository(),
      ),
    );
    await tester.pump();

    expect(find.text('2D Montessori Admin'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
  });
}
