/// End-to-end smoke test against the LIVE backend using the dedicated
/// smoketest@tinytrack.dev account (isolated baby "Testy", seeded data).
///
/// Run on a device/emulator:
///   flutter test integration_test/smoke_test.dart -d emulator-5554
///
/// Walks: cold start → login → dashboard → every bottom tab → every
/// More-grid feature screen, asserting each renders without exceptions.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tinytrack_app/main.dart' as app;

const _email = 'smoketest@tinytrack.dev';
const _password = 'TinyTrack-Smoke-2026!';

/// Pumps frames until [finder] matches or [timeout] passes. pumpAndSettle is
/// unusable here — the splash pulse and shimmer skeletons animate forever.
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
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('full app walk: login → all screens render', (tester) async {
    app.main();
    await settleABit(tester, const Duration(seconds: 1));

    // Make the run deterministic: start signed out.
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {}

    // Splash → login (splash animation takes ~3s).
    final loginField = find.widgetWithText(TextField, 'Email');
    expect(await pumpUntilFound(tester, loginField,
            timeout: const Duration(seconds: 15)),
        isTrue,
        reason: 'login screen should appear after splash');

    // Sign in with the smoke-test account.
    await tester.enterText(loginField.first, _email);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.enterText(
        find.widgetWithText(TextField, 'Password').first, _password);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.widgetWithText(ElevatedButton, 'Sign In'));

    // Dashboard for the seeded baby.
    expect(await pumpUntilFound(tester, find.text('Testy'),
            timeout: const Duration(seconds: 25)),
        isTrue,
        reason: 'dashboard should show the test baby after sign-in');
    await settleABit(tester);

    // Flip to DARK MODE so the whole walk verifies dark-mode rendering.
    final nightToggle = find.byIcon(Icons.nightlight_round);
    if (nightToggle.evaluate().isNotEmpty) {
      await tester.tap(nightToggle.first, warnIfMissed: false);
      await settleABit(tester, const Duration(seconds: 1));
      expect(tester.takeException(), isNull,
          reason: 'dark mode toggle should not throw');
    }

    // Bottom tabs (custom nav bar labels: Home/Feed/Diaper/Sleep/More).
    Future<void> tapTab(String label) async {
      await tester.tap(find.text(label).last, warnIfMissed: false);
      await settleABit(tester);
    }

    for (final tab in ['Feed', 'Diaper', 'Sleep', 'More']) {
      await tapTab(tab);
      expect(tester.takeException(), isNull, reason: '$tab tab should render');
    }

    // Every feature screen reachable from the More grid.
    const features = [
      'Reflux', 'Daily Journal', 'Weekly Report', 'Monthly Review',
      'Care Guide', 'Immunisations', 'Settings', 'Trends', 'Summary',
      'Growth', 'Milestones', 'Health', 'Tummy Time', 'Photos', 'Export',
      'Baby',
    ];
    for (final feature in features) {
      // Back on the More tab each iteration.
      await tapTab('More');
      await settleABit(tester, const Duration(seconds: 1));

      final card = find.text(feature).last;
      await tester.scrollUntilVisible(card, 200,
          scrollable: find.byType(Scrollable).first);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(card, warnIfMissed: false);
      await settleABit(tester, const Duration(seconds: 3));
      expect(tester.takeException(), isNull,
          reason: '$feature screen should render without exceptions');

      // Leave detail screens (slide routes have a back affordance).
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

    // ----- Write journeys: real inserts against the live test baby -----

    // 1. Log a diaper (defaults to 'wet', just save).
    await tapTab('Diaper');
    final saveDiaper = find.text('Save Diaper');
    await tester.scrollUntilVisible(saveDiaper, 200,
        scrollable: find.byType(Scrollable).first);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(saveDiaper, warnIfMissed: false);
    expect(
        await pumpUntilFound(tester, find.text('Diaper logged successfully')),
        isTrue,
        reason: 'diaper save should succeed against the live backend');

    // 2. Log a reflux event (severity 2 + flag, from the Care Pack).
    await tapTab('More');
    await settleABit(tester, const Duration(seconds: 1));
    await tester.tap(find.text('Reflux').last, warnIfMissed: false);
    await settleABit(tester, const Duration(seconds: 2));
    await tester.tap(find.text('2').first, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 300));
    final logReflux = find.text('Log Reflux');
    await tester.scrollUntilVisible(logReflux, 200,
        scrollable: find.byType(Scrollable).first);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(logReflux, warnIfMissed: false);
    await settleABit(tester, const Duration(seconds: 3));
    expect(tester.takeException(), isNull,
        reason: 'reflux log should not throw');

    // 3. Save today's journal (tap a mood, save).
    final backToMore = find.byType(BackButton);
    if (backToMore.evaluate().isNotEmpty) {
      await tester.tap(backToMore.first, warnIfMissed: false);
      await settleABit(tester, const Duration(seconds: 1));
    }
    await tapTab('More');
    await settleABit(tester, const Duration(seconds: 1));
    await tester.tap(find.text('Daily Journal').last, warnIfMissed: false);
    await settleABit(tester, const Duration(seconds: 2));
    await tester.tap(find.text('😊').first, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 300));
    final saveJournal = find.text('Save Journal');
    await tester.scrollUntilVisible(saveJournal, 300,
        scrollable: find.byType(Scrollable).first);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(saveJournal, warnIfMissed: false);
    await settleABit(tester, const Duration(seconds: 3));
    expect(tester.takeException(), isNull,
        reason: 'journal save should not throw');

    // Land back on the dashboard to finish.
    await tapTab('Home');
    expect(tester.takeException(), isNull);
  });
}
