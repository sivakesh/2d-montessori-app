import 'dart:async';

import 'package:core_contracts/core_contracts.dart';
import 'package:feature_pages/feature_pages.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:public_web/main.dart';

class _FakePublicPagesRepository implements PublicPagesRepository {
  @override
  Future<Result<PublicPageView>> getBySlug(String slug) async =>
      const Result.failure(ValidationFailure('not found in this test'));

  @override
  Future<Result<List<PublicPageView>>> listNavigationPages() async =>
      const Result.ok([]);
}

void main() {
  testWidgets('PublicWebApp renders the home placeholder at the root route', (
    WidgetTester tester,
  ) async {
    // Pumps the widget tree directly (not main()) so this test never
    // touches Firebase — bootstrapFirebase() requires platform channels
    // that aren't available under `flutter test` without additional
    // mocking, which is out of scope for a widget smoke test.
    await tester.pumpWidget(
      PublicWebApp(publicPagesRepository: _FakePublicPagesRepository()),
    );
    await tester.pump();

    expect(find.text('2D Montessori'), findsOneWidget);
  });

  testWidgets('an unknown slug renders the not-found screen, not a crash', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      PublicWebApp(publicPagesRepository: _FakePublicPagesRepository()),
    );
    final navigatorState = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(navigatorState.pushNamed('/does-not-exist'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Page not found'), findsOneWidget);
  });
}
