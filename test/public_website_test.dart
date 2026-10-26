// Public website foundation (lib/modules/public_website):
// - `/` is the public homepage and renders without Firebase or sign-in, at
//   mobile, tablet and desktop widths, without layout overflow.
// - Header/drawer/footer navigation reaches Home, Admissions, Teacher
//   Training, Programs and Contact; the Families and Educators pathways open
//   Admissions and Teacher Training; moving between pages keeps a short back
//   stack (back returns Home).
// - The EN/தமிழ் switch changes the site's text and carries across pages.
// - Login opens `/app`: the existing AuthGate, which shows the
//   existing LoginScreen when signed out; back returns to the site.
// - Existing named routes and /otp (with its phone argument) still work.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/main.dart';
import 'package:montessori_app/modules/auth/providers/auth_state_provider.dart';
import 'package:montessori_app/modules/auth/ui/auth_gate.dart';
import 'package:montessori_app/modules/auth/ui/login_screen.dart';
import 'package:montessori_app/modules/auth/ui/otp_screen.dart';
import 'package:montessori_app/modules/public_website/public_routes.dart';
import 'package:montessori_app/modules/public_website/ui/public_home_page.dart';
import 'package:montessori_app/modules/public_website/ui/public_section_page.dart';

const _desktop = Size(1400, 1000);
const _tablet = Size(900, 1000);
const _mobile = Size(375, 800);

void main() {
  Future<void> pumpApp(WidgetTester tester, {Size size = _desktop}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
      // Signed out, without Firebase: only AuthGate (at /app) reads this.
      overrides: [authStateProvider.overrideWith((ref) => Stream.value(null))],
      child: const MontessoriApp(),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  String? sectionTitle(WidgetTester tester) {
    final title = find.byKey(const Key('public-section-title'));
    return title.evaluate().isEmpty ? null : tester.widget<Text>(title).data;
  }

  NavigatorState navigator(WidgetTester tester) => tester.state<NavigatorState>(find.byType(Navigator).first);

  group('homepage', () {
    for (final (name, size) in [('desktop', _desktop), ('tablet', _tablet), ('mobile', _mobile), ('narrow 320px', const Size(320, 700))]) {
      testWidgets('loads without signing in ($name), no overflow', (tester) async {
        await pumpApp(tester, size: size);
        expect(tester.takeException(), isNull);
        expect(find.byType(PublicHomePage), findsOneWidget);
        expect(find.byType(LoginScreen), findsNothing);
        expect(find.byType(AuthGate), findsNothing);
        expect(find.text('A calm, thoughtful place to learn and grow'), findsOneWidget);
        expect(find.byKey(const Key('public-pathway-families')), findsOneWidget);
        expect(find.byKey(const Key('public-pathway-educators')), findsOneWidget);
        expect(find.byKey(const Key('public-footer')), findsOneWidget);
        final desktop = size.width >= 1100;
        expect(find.byKey(const Key('public-nav-/admissions')), desktop ? findsOneWidget : findsNothing);
        expect(find.byKey(const Key('public-menu-button')), desktop ? findsNothing : findsOneWidget);
        await tester.drag(find.byType(SingleChildScrollView).first, const Offset(0, -2000));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('navigation', () {
    testWidgets('header links reach every section; Home returns; back stack stays short', (tester) async {
      await pumpApp(tester);
      for (final (route, label) in [
        (PublicRoutes.admissions, 'Admissions'),
        (PublicRoutes.teacherTraining, 'Teacher Training'),
        (PublicRoutes.programs, 'Programs'),
        (PublicRoutes.contact, 'Contact'),
      ]) {
        await tapAndSettle(tester, find.byKey(Key('public-nav-$route')));
        expect(sectionTitle(tester), label);
        expect(find.byType(PublicSectionPage), findsOneWidget, reason: 'one page at a time');
        expect(find.text('This page is being prepared'), findsOneWidget);
      }
      // Only Home is underneath, so back returns there.
      navigator(tester).pop();
      await tester.pumpAndSettle();
      expect(find.byType(PublicHomePage), findsOneWidget);
      expect(navigator(tester).canPop(), isFalse);

      await tapAndSettle(tester, find.byKey(const Key('public-nav-/programs')));
      await tapAndSettle(tester, find.byKey(const Key('public-nav-/')));
      expect(find.byType(PublicHomePage), findsOneWidget);
      expect(navigator(tester).canPop(), isFalse);
    });

    testWidgets('Families and Educators pathways open Admissions and Teacher Training', (tester) async {
      await pumpApp(tester);
      await tapAndSettle(tester, find.byKey(const Key('public-pathway-families')));
      expect(sectionTitle(tester), 'Admissions');
      await tapAndSettle(tester, find.byKey(const Key('public-back-home')));
      expect(find.byType(PublicHomePage), findsOneWidget);
      await tapAndSettle(tester, find.byKey(const Key('public-pathway-educators')));
      expect(sectionTitle(tester), 'Teacher Training');
    });

    testWidgets('footer links navigate', (tester) async {
      await pumpApp(tester);
      await tapAndSettle(tester, find.byKey(const Key('public-footer-/contact')));
      expect(sectionTitle(tester), 'Contact');
      await tapAndSettle(tester, find.byKey(const Key('public-footer-/')));
      expect(find.byType(PublicHomePage), findsOneWidget);
    });

    testWidgets('mobile: the menu drawer lists every section and navigates', (tester) async {
      await pumpApp(tester, size: _mobile);
      await tapAndSettle(tester, find.byKey(const Key('public-menu-button')));
      expect(find.byKey(const Key('public-menu')), findsOneWidget);
      for (final route in PublicRoutes.sections) {
        expect(find.byKey(Key('public-menu-$route')), findsOneWidget);
      }
      expect(find.byKey(const Key('public-management-login')), findsOneWidget);
      await tapAndSettle(tester, find.byKey(const Key('public-menu-/teacher-training')));
      expect(sectionTitle(tester), 'Teacher Training');
      expect(find.byKey(const Key('public-menu')), findsNothing, reason: 'drawer closed');
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('language switch: Tamil text across pages, back to English', (tester) async {
    await pumpApp(tester);
    await tapAndSettle(tester, find.text('தமிழ்'));
    expect(find.text('கற்கவும் வளரவும் அமைதியான, அக்கறையுள்ள இடம்'), findsOneWidget);
    expect(find.text('குடும்பங்களுக்கு'), findsOneWidget);
    expect(find.text('Admissions'), findsNothing);
    // Longer Tamil labels may not fit inline; the header then offers the
    // menu instead (see the overflow test below). Use whichever is shown.
    if (find.byKey(const Key('public-nav-/admissions')).evaluate().isNotEmpty) {
      await tapAndSettle(tester, find.byKey(const Key('public-nav-/admissions')));
    } else {
      await tapAndSettle(tester, find.byKey(const Key('public-menu-button')));
      await tapAndSettle(tester, find.byKey(const Key('public-menu-/admissions')));
    }
    expect(sectionTitle(tester), 'சேர்க்கை');
    expect(find.text('உள்நுழைவு'), findsWidgets); // Login: utility bar and footer
    await tapAndSettle(tester, find.text('EN'));
    expect(sectionTitle(tester), 'Admissions');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Tamil and large text never overflow: the header falls back to the menu when links do not fit', (tester) async {
    for (final size in [_desktop, _tablet, _mobile, const Size(320, 700)]) {
      await pumpApp(tester, size: size);
      await tapAndSettle(tester, find.text('தமிழ்'));
      expect(tester.takeException(), isNull, reason: 'Tamil at ${size.width}');
      await tapAndSettle(tester, find.text('EN')); // reset the shared language for the next size
    }

    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpApp(tester, size: _desktop);
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('public-menu-button')), findsOneWidget, reason: 'links no longer fit inline');
    await tapAndSettle(tester, find.byKey(const Key('public-menu-button')));
    await tapAndSettle(tester, find.byKey(const Key('public-menu-/contact')));
    expect(sectionTitle(tester), 'Contact');
    expect(tester.takeException(), isNull);
  });

  group('language switch layout', () {
    Finder label(String text) => find.descendant(of: find.byKey(const Key('public-language-switch')), matching: find.text(text));

    /// Both labels on one line, sharing one height and centre line; both
    /// segments equally tall; each label centred with balanced padding.
    void expectSwitchAligned(WidgetTester tester) {
      final en = tester.getRect(label('EN'));
      final ta = tester.getRect(label('தமிழ்'));
      expect(ta.height, closeTo(en.height, 0.01), reason: 'தமிழ் is a single line, like EN');
      expect(ta.center.dy, closeTo(en.center.dy, 0.5), reason: 'vertically aligned');
      final enSegment = tester.getRect(find.byKey(const Key('public-language-english')));
      final taSegment = tester.getRect(find.byKey(const Key('public-language-tamil')));
      expect(taSegment.height, closeTo(enSegment.height, 0.01));
      expect(taSegment.top, closeTo(enSegment.top, 0.01));
      for (final (segment, text) in [(enSegment, en), (taSegment, ta)]) {
        expect(text.left - segment.left, closeTo(segment.right - text.right, 0.5), reason: 'balanced horizontal padding');
        expect(text.left, greaterThan(segment.left), reason: 'label fully inside its segment');
        expect(text.right, lessThan(segment.right));
        expect(text.center.dy, closeTo(segment.center.dy, 0.5), reason: 'centred in its segment');
      }
    }

    for (final (name, size, scale) in [
      ('desktop', _desktop, 1.0),
      ('tablet', _tablet, 1.0),
      ('mobile', _mobile, 1.0),
      ('320px', const Size(320, 700), 1.0),
      ('desktop, 2x text', _desktop, 2.0),
      ('320px, 2x text', const Size(320, 700), 2.0),
    ]) {
      testWidgets('$name: EN and தமிழ் on one line, aligned, with Tamil unselected and selected', (tester) async {
        if (scale != 1.0) {
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        }
        await pumpApp(tester, size: size);
        expect(tester.takeException(), isNull);
        expectSwitchAligned(tester);
        final switchRect = tester.getRect(find.byKey(const Key('public-language-switch')));
        expect(switchRect.left, greaterThanOrEqualTo(0));
        expect(switchRect.right, lessThanOrEqualTo(size.width));

        await tapAndSettle(tester, label('தமிழ்'));
        expect(tester.takeException(), isNull);
        expect(find.text('உள்நுழைவு'), findsWidgets, reason: 'Tamil selected');
        expectSwitchAligned(tester);

        await tapAndSettle(tester, label('EN'));
        expectSwitchAligned(tester);
        expect(find.text('Login'), findsWidgets, reason: 'back to English');
      });
    }

    testWidgets('selected segment keeps the filled forest style; the other is outlined text', (tester) async {
      await pumpApp(tester);
      Material segment(String language) => tester.widget<Material>(find.byKey(Key('public-language-$language')));
      Color? textColor(String text) => tester.widget<Text>(label(text)).style?.color;
      expect(segment('english').color, const Color(0xFF1F4D3A));
      expect(segment('tamil').color, Colors.transparent);
      expect(textColor('EN'), Colors.white);
      expect(textColor('தமிழ்'), const Color(0xFF1F4D3A));
      await tapAndSettle(tester, label('தமிழ்'));
      expect(segment('tamil').color, const Color(0xFF1F4D3A));
      expect(segment('english').color, Colors.transparent);
      expect(textColor('தமிழ்'), Colors.white);
    });
  });

  group('Login label', () {
    testWidgets('header, mobile menu and footer say "Login" (no "Management Login"); Tamil too', (tester) async {
      await pumpApp(tester);
      expect(find.descendant(of: find.byKey(const Key('public-utility-bar')), matching: find.text('Login')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('public-footer')), matching: find.text('Login')), findsOneWidget);
      expect(find.text('Management Login'), findsNothing);
      await tapAndSettle(tester, find.text('தமிழ்'));
      expect(find.descendant(of: find.byKey(const Key('public-utility-bar')), matching: find.text('உள்நுழைவு')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('public-footer')), matching: find.text('உள்நுழைவு')), findsOneWidget);
      expect(find.text('நிர்வாக உள்நுழைவு'), findsNothing);
      await tapAndSettle(tester, find.text('EN')); // the language persists across the re-pump below

      await pumpApp(tester, size: _mobile);
      await tapAndSettle(tester, find.byKey(const Key('public-menu-button')));
      expect(find.descendant(of: find.byKey(const Key('public-menu')), matching: find.text('Login')), findsOneWidget);
      expect(find.text('Management Login'), findsNothing);
    });

    testWidgets('header Login still opens /app: the existing AuthGate and LoginScreen', (tester) async {
      await pumpApp(tester);
      await tapAndSettle(tester, find.descendant(of: find.byKey(const Key('public-utility-bar')), matching: find.text('Login')));
      expect(find.byType(AuthGate), findsOneWidget);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(ModalRoute.of(tester.element(find.byType(AuthGate)))!.settings.name, PublicRoutes.management);
    });
  });

  group('management entry', () {
    testWidgets('Login opens /app: the existing AuthGate and LoginScreen; back returns to the site', (tester) async {
      await pumpApp(tester);
      await tapAndSettle(tester, find.byKey(const Key('public-management-login')));
      expect(find.byType(AuthGate), findsOneWidget);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(ModalRoute.of(tester.element(find.byType(AuthGate)))!.settings.name, PublicRoutes.management);

      navigator(tester).pop();
      await tester.pumpAndSettle();
      expect(find.byType(PublicHomePage), findsOneWidget);
    });

    testWidgets('the footer and mobile menu use the same management entry', (tester) async {
      await pumpApp(tester, size: _mobile);
      await tapAndSettle(tester, find.byKey(const Key('public-footer-management-login')));
      expect(find.byType(AuthGate), findsOneWidget);
      navigator(tester).pop();
      await tester.pumpAndSettle();

      await tapAndSettle(tester, find.byKey(const Key('public-menu-button')));
      await tapAndSettle(tester, find.byKey(const Key('public-management-login')));
      expect(find.byType(AuthGate), findsOneWidget);
      expect(find.byType(LoginScreen), findsOneWidget);
    });

    testWidgets('/app is AuthGate itself (role routing unchanged), not a bypass', (tester) async {
      await pumpApp(tester);
      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      final page = app.routes![PublicRoutes.management]!(tester.element(find.byType(PublicHomePage)));
      expect(page, isA<AuthGate>());
      expect(app.home, isA<PublicHomePage>());
    });
  });

  group('existing routes', () {
    testWidgets('all existing named routes are still registered', (tester) async {
      await pumpApp(tester);
      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.routes!.keys, containsAll(['/login', '/dashboard', '/admin_dashboard', '/admin_session_logs', '/admin_profile_form']));
      expect(app.onGenerateRoute, isNotNull);
    });

    testWidgets('/login opens the existing LoginScreen', (tester) async {
      await pumpApp(tester);
      navigator(tester).pushNamed('/login');
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
    });

    testWidgets('/otp still receives its phone argument', (tester) async {
      await pumpApp(tester);
      navigator(tester).pushNamed('/otp', arguments: {'phone': '9876543210'});
      await tester.pumpAndSettle();
      expect(tester.widget<OtpScreen>(find.byType(OtpScreen)).phoneNumber, '9876543210');
    });
  });
}
