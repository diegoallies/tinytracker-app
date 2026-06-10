/// Renders a real Family Report PDF against the live smoke-test baby and
/// ships the bytes back to the driver (base64 in reportData), so the design
/// can be reviewed as actual rendered pages.
///
///   flutter drive --driver=test_driver/integration_test.dart \
///     --target=integration_test/family_report_render_test.dart -d emulator-5554
library;

import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tinytrack_app/models/baby.dart';
import 'package:tinytrack_app/services/family_report_service.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('render weekly + monthly family report PDFs', (tester) async {
    await dotenv.load(fileName: '.env');
    await Supabase.initialize(
      url: dotenv.env['SUPABASE_URL']!,
      anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
    );
    final client = Supabase.instance.client;
    await client.auth.signInWithPassword(
      email: 'smoketest@tinytrack.dev',
      password: 'TinyTrack-Smoke-2026!',
    );

    final babyRow = await client
        .from('babies')
        .select('*')
        .eq('id', '872f59f9-dec5-4739-ab2a-8a05622bc43b')
        .single();
    final baby = Baby.fromJson(babyRow);

    final now = DateTime.now();
    final weekStart = DateTime(now.year, now.month, now.day - (now.weekday - 1));
    final weekly = await FamilyReportService.build(
      baby: baby,
      periodStart: weekStart,
      periodEnd: DateTime(weekStart.year, weekStart.month, weekStart.day + 7),
      isMonthly: false,
    );
    expect(weekly.length, greaterThan(5000),
        reason: 'weekly PDF should have substance');

    final monthStart = DateTime(now.year, now.month, 1);
    final monthly = await FamilyReportService.build(
      baby: baby,
      periodStart: monthStart,
      periodEnd: DateTime(now.year, now.month + 1, 1),
      isMonthly: true,
    );
    expect(monthly.length, greaterThan(5000));

    binding.reportData = {
      'weekly_pdf': base64Encode(weekly),
      'monthly_pdf': base64Encode(monthly),
    };
  });
}
