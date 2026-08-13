import 'package:core_contracts/core_contracts.dart';
import 'package:feature_pages/feature_pages.dart';
import 'package:flutter/material.dart' hide Page;
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_pages_repository.dart';
import '../support/sample_page.dart';

void main() {
  testWidgets('lists pages returned by the repository and opens one on tap', (
    tester,
  ) async {
    final repository = FakePagesRepository();
    addTearDown(repository.dispose);
    repository.nextListResult = Result.ok(
      Page(
        items: [samplePage(pageId: 'p1', title: 'About us')],
        nextCursor: null,
        hasMore: false,
      ),
    );

    CmsPage? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PagesListScreen(
            repository: repository,
            actingRole: UserRole.editor,
            actorId: 'owner-1',
            onOpenPage: (page) => opened = page,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('About us'), findsOneWidget);

    await tester.tap(find.text('About us'));
    await tester.pump();

    expect(opened?.pageId, 'p1');
  });

  testWidgets('shows an empty state when there are no pages', (tester) async {
    final repository = FakePagesRepository();
    addTearDown(repository.dispose);
    repository.nextListResult = const Result.ok(
      Page(items: [], nextCursor: null, hasMore: false),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PagesListScreen(
            repository: repository,
            actingRole: UserRole.editor,
            actorId: 'owner-1',
            onOpenPage: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('No pages yet.'), findsOneWidget);
  });
}
