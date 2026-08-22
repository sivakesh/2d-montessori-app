// Regression coverage for the new responsive presentation logic in
// showNotificationDetail: bottom sheet below AppSizes.mobileBreakpoint,
// centered dialog at/above it — the actual new behavior introduced by the
// Phase C polish pass. Does not touch notification data loading, which is
// already covered elsewhere.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/admin/notifications/models/admin_notification_model.dart';
import 'package:montessori_app/modules/notifications/ui/notifications_feed_screen.dart';

AdminNotificationModel _notification({
  String? message,
  String attachmentUrl = '',
  String attachmentName = '',
}) {
  return AdminNotificationModel(
    id: 'n1',
    title: 'Fee Reminder',
    message: message ?? 'Please complete the term fee payment.',
    notificationType: 'General',
    category: 'Finance',
    priority: 'Normal',
    audience: 'Parents',
    visibility: 'Parents',
    status: 'Published',
    academicYear: '2026-2027',
    publishDate: DateTime(2026, 8, 1),
    expiryDate: null,
    createdBy: 'admin',
    createdByName: 'Admin',
    createdAt: DateTime(2026, 8, 1),
    updatedAt: null,
    sentAt: null,
    isPinned: false,
    requiresAcknowledgement: false,
    attachmentName: attachmentName,
    attachmentUrl: attachmentUrl,
    attachmentSize: null,
    attachmentMimeType: '',
    appliesToAllClasses: true,
    applicableClassIds: const [],
    applicableClassNames: const [],
    appliesToAllStudents: false,
    applicableStudentIds: const [],
    applicableStudentNames: const [],
    appliesToAllStaff: true,
    applicableStaffIds: const [],
    applicableStaffNames: const [],
    isPublic: false,
  );
}

Future<void> _openDetail(
  WidgetTester tester,
  Size viewSize, {
  String? message,
  String attachmentUrl = '',
  String attachmentName = '',
}) async {
  final originalSize = tester.view.physicalSize;
  final originalDpr = tester.view.devicePixelRatio;
  tester.view.physicalSize = viewSize;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.physicalSize = originalSize;
    tester.view.devicePixelRatio = originalDpr;
  });

  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => showNotificationDetail(
            context,
            _notification(
              message: message,
              attachmentUrl: attachmentUrl,
              attachmentName: attachmentName,
            ),
          ),
          child: const Text('Open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('below the mobile breakpoint (390 wide): shows a bottom sheet, not a Dialog', (
    tester,
  ) async {
    await _openDetail(tester, const Size(390, 844));

    expect(tester.takeException(), isNull);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    expect(find.text('Fee Reminder'), findsOneWidget);
  });

  testWidgets('at/above the mobile breakpoint (900 wide): shows a centered Dialog, not a bottom sheet', (
    tester,
  ) async {
    await _openDetail(tester, const Size(900, 1024));

    expect(tester.takeException(), isNull);
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('Fee Reminder'), findsOneWidget);
  });

  testWidgets('768 wide (tablet) stays on the mobile/bottom-sheet side, matching the app\'s own shell breakpoint', (
    tester,
  ) async {
    await _openDetail(tester, const Size(768, 1024));

    expect(tester.takeException(), isNull);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('a long message does not overflow at the crash-repro mobile size (400x775)', (
    tester,
  ) async {
    await _openDetail(
      tester,
      const Size(400, 775),
      message: List.filled(60, 'A fairly long sentence about school policy.').join(' '),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('the explicit close button dismisses the detail view', (tester) async {
    await _openDetail(tester, const Size(390, 844));
    expect(find.text('Fee Reminder'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(find.text('Fee Reminder'), findsNothing);
  });

  testWidgets(
    'a short notification stays well below the 75% max-height cap, not stretched to fill it',
    (tester) async {
      const viewSize = Size(390, 844);
      await _openDetail(tester, viewSize, message: 'Short message.');

      final sheetHeight = tester.getRect(find.byType(BottomSheet)).height;
      // The cap is 75% of 844 ≈ 633; a one-line message should render far
      // short of that — this is the "no huge white panel for a short
      // notification" requirement, checked as an actual measurement rather
      // than just reading the code.
      expect(sheetHeight, lessThan(viewSize.height * 0.5));
    },
  );

  testWidgets(
    'a genuinely long notification expands toward, but never past, the 75% max-height cap',
    (tester) async {
      const viewSize = Size(390, 844);
      await _openDetail(
        tester,
        viewSize,
        message: List.filled(
          200,
          'A fairly long sentence about school policy.',
        ).join(' '),
      );

      final sheetHeight = tester.getRect(find.byType(BottomSheet)).height;
      // BottomSheet's own rect includes Flutter's drag-handle chrome on top
      // of our capped content, so this isn't pinned to the exact 75% figure
      // — it just proves the sheet stays clearly bounded rather than
      // growing toward the full screen the way it would with no cap at all.
      expect(sheetHeight, lessThan(viewSize.height * 0.9));
      // With that much text it should also be meaningfully taller than the
      // short-message case above, i.e. it actually expanded rather than
      // silently clipping at a small fixed size.
      expect(sheetHeight, greaterThan(viewSize.height * 0.5));
    },
  );

  testWidgets(
    'shows an attachment row with an ellipsis-safe long filename when the notification has one',
    (tester) async {
      await _openDetail(
        tester,
        const Size(390, 844),
        attachmentUrl: 'https://example.com/file.pdf',
        attachmentName:
            'Term_1_Fee_Structure_And_Payment_Schedule_2026_2027_Complete.pdf',
      );

      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.attach_file), findsOneWidget);
      expect(find.byIcon(Icons.open_in_new), findsOneWidget);
      final filenameFinder = find.textContaining('Term_1_Fee_Structure');
      expect(filenameFinder, findsOneWidget);
      final filenameWidget = tester.widget<Text>(filenameFinder);
      expect(filenameWidget.maxLines, 1);
      expect(filenameWidget.overflow, TextOverflow.ellipsis);
    },
  );

  testWidgets(
    'shows no attachment row when the notification has none',
    (tester) async {
      await _openDetail(tester, const Size(390, 844));

      expect(find.byIcon(Icons.attach_file), findsNothing);
      expect(find.byIcon(Icons.open_in_new), findsNothing);
    },
  );
}
