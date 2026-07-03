/// App Store marketing screenshots — light mode, curated screens only.
///
/// Build + run (watch-safe; do NOT plain `flutter drive`, it breaks the
/// embedded watch target — see docs/watch build notes):
///   flutter build ios --config-only --simulator --debug \
///     --target=integration_test/appstore_screenshots_test.dart
///   xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner \
///     -configuration Debug -destination 'id=<SIM_UDID>' \
///     -derivedDataPath build/simdd build
///   flutter drive --driver=test_driver/integration_test.dart \
///     --target=integration_test/appstore_screenshots_test.dart \
///     --use-application-binary=build/simdd/Build/Products/Debug-iphonesimulator/Runner.app \
///     -d <SIM_UDID>
/// PNGs land in build/screenshots/.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tinytrack_app/main.dart' as app;
import 'package:tinytrack_app/widgets/layout/bottom_nav_bar.dart';

const _email = 'smoketest@tinytrack.dev';
const _password = 'TinyTrack-Smoke-2026!';

Future<bool> pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 250));
    if (finder.evaluate().isNotEmpty) return true;
  }
  return false;
}

Future<void> settleABit(WidgetTester tester,
    [Duration duration = const Duration(seconds: 2)]) async {
  final end = DateTime.now().add(duration);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  var surfaceConverted = false;

  Future<void> shot(WidgetTester tester, String name) async {
    if (!surfaceConverted) {
      await binding.convertFlutterSurfaceToImage();
      surfaceConverted = true;
      await tester.pump(const Duration(milliseconds: 100));
    }
    // Extra settle so shimmer skeletons have loaded real content.
    await settleABit(tester, const Duration(seconds: 1));
    await binding.takeScreenshot(name);
  }

  testWidgets('capture App Store screenshots', (tester) async {
    app.main();
    await settleABit(tester, const Duration(seconds: 1));

    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {}

    final loginField = find.widgetWithText(TextField, 'Email');
    expect(await pumpUntilFound(tester, loginField,
            timeout: const Duration(seconds: 15)),
        isTrue,
        reason: 'login screen should appear after splash');

    await tester.enterText(loginField.first, _email);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.enterText(
        find.widgetWithText(TextField, 'Password').first, _password);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.widgetWithText(ElevatedButton, 'Sign In'));

    expect(await pumpUntilFound(tester, find.text('Testy'),
            timeout: const Duration(seconds: 25)),
        isTrue,
        reason: 'dashboard should show the test baby after sign-in');
    // Long settle: let avatars/photos and summaries finish loading.
    await settleABit(tester, const Duration(seconds: 4));

    await shot(tester, '01_dashboard');

    Future<void> tapTab(String label) async {
      final tab = find.descendant(
        of: find.byType(BottomNavBar),
        matching: find.text(label),
      );
      expect(tab, findsOneWidget, reason: 'nav tab $label should exist');
      await tester.tap(tab, warnIfMissed: false);
      await settleABit(tester);
    }

    await tapTab('Feed');
    await shot(tester, '02_feed');

    await tapTab('Sleep');
    await shot(tester, '03_sleep');

    // Feature screens from the More grid.
    Future<void> openFeature(String name) async {
      await tapTab('More');
      await settleABit(tester, const Duration(seconds: 1));
      final card = find.text(name).last;
      await tester.scrollUntilVisible(card, 200,
          scrollable: find.byType(Scrollable).first);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(card, warnIfMissed: false);
      await settleABit(tester, const Duration(seconds: 3));
      expect(tester.takeException(), isNull,
          reason: '$name screen should render');
    }

    Future<void> goBack() async {
      final back = find.byType(BackButton);
      if (back.evaluate().isNotEmpty) {
        await tester.tap(back.first, warnIfMissed: false);
      } else {
        final backIcon = find.byIcon(Icons.arrow_back);
        if (backIcon.evaluate().isNotEmpty) {
          await tester.tap(backIcon.first, warnIfMissed: false);
        }
      }
      await settleABit(tester, const Duration(seconds: 1));
    }

    await openFeature('Trends');
    await shot(tester, '04_trends');
    await goBack();

    await openFeature('Weekly Report');
    await shot(tester, '05_weekly_report');
    await goBack();

    await openFeature('Growth');
    await shot(tester, '06_growth');
    await goBack();

    await openFeature('Daily Journal');
    await shot(tester, '07_journal');
    await goBack();

    expect(tester.takeException(), isNull);
  });
}
