import 'package:core_contracts/core_contracts.dart';
import 'package:feature_identity/src/presentation/widgets/role_guarded_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester, UserRole role) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RoleGuardedSection(
          role: role,
          capability: Capability.manageUsersAndRoles,
          builder: (_) => const Text('protected content'),
        ),
      ),
    );
  }

  testWidgets('shows Access Denied for a role without the capability', (
    tester,
  ) async {
    await pump(tester, UserRole.editor);
    expect(find.text('Access denied'), findsOneWidget);
    expect(find.text('protected content'), findsNothing);
  });

  testWidgets('shows the guarded content for a role with the capability', (
    tester,
  ) async {
    await pump(tester, UserRole.superAdmin);
    expect(find.text('protected content'), findsOneWidget);
    expect(find.text('Access denied'), findsNothing);
  });
}
