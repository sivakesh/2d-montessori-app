import 'package:core_contracts/core_contracts.dart';
import 'package:feature_pages/feature_pages.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_pages_repository.dart';
import '../../support/sample_page.dart';

void main() {
  late FakePagesRepository repository;

  setUp(() => repository = FakePagesRepository());
  tearDown(() => repository.dispose());

  test('GetPageUseCase delegates to the repository', () async {
    final page = samplePage();
    repository.nextGetResult = Result.ok(page);
    final result = await GetPageUseCase(repository)(page.pageId);
    expect(result.isOk, isTrue);
    expect(repository.lastGetPageId, page.pageId);
  });

  test('ListPagesUseCase delegates the query and pagination request', () async {
    final pages = [samplePage(pageId: 'p1'), samplePage(pageId: 'p2')];
    repository.nextListResult = Result.ok(
      Page(items: pages, nextCursor: 'p2', hasMore: false),
    );
    final result = await ListPagesUseCase(repository)();
    result.fold(
      (page) => expect(page.items, hasLength(2)),
      (_) => fail('expected success'),
    );
  });

  test('ListPageRevisionsUseCase delegates to the repository', () async {
    repository.nextRevisionsResult = const Result.ok([]);
    final result = await ListPageRevisionsUseCase(repository)('page-1');
    expect(result.isOk, isTrue);
  });
}
