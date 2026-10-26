// Startup: the app opens on the public website homepage (no sign-in), which
// carries the school's logo in its header. The management app is at /app
// (see test/public_website_test.dart).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/main.dart';
import 'package:montessori_app/core/widgets/app_logo.dart';
import 'package:montessori_app/modules/public_website/ui/public_home_page.dart';

void main() {
  testWidgets('shows branded logo on launch', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MontessoriApp()),
    );

    expect(find.byType(PublicHomePage), findsOneWidget);
    expect(find.byType(AppLogo), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
  });
}
