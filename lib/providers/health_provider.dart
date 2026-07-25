import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/health_log.dart';
import '../services/analytics_service.dart';
import '../services/supabase_service.dart';
import 'baby_provider.dart';

final healthLogsProvider = FutureProvider.autoDispose<List<HealthLog>>((ref) async {
  final baby = ref.watch(selectedBabyProvider);
  if (baby == null) return [];

  final data = await SupabaseService.client
      .from('health_logs')
      .select()
      .eq('baby_id', baby.id)
      .isFilter('deleted_at', null)
      .order('logged_at', ascending: false)
      .limit(20);

  return data.map<HealthLog>((json) => HealthLog.fromJson(json)).toList();
});

class HealthActions {
  static Future<void> logHealth({
    required String babyId,
    double? temperatureC,
    String? medication,
    String? dosage,
    String? symptoms,
    String? notes,
    DateTime? loggedAt,
    // Watch taps arrive here via WatchBridge; the phone UI leaves the default.
    String source = AnalyticsService.sourcePhone,
  }) async {
    final userId = SupabaseService.userId;
    if (userId == null) return;

    await SupabaseService.client.from('health_logs').insert({
      'baby_id': babyId,
      'user_id': userId,
      'temperature_c': temperatureC,
      'medication': medication?.isNotEmpty == true ? medication : null,
      'dosage': dosage?.isNotEmpty == true ? dosage : null,
      'symptoms': symptoms?.isNotEmpty == true ? symptoms : null,
      'notes': notes?.isNotEmpty == true ? notes : null,
      'logged_at': (loggedAt ?? DateTime.now()).toUtc().toIso8601String(),
    });

    // This table also carries temperature and symptoms, so only count the rows
    // that actually recorded a dose. The drug name and dosage never leave the
    // device — just that a dose happened.
    if (medication?.isNotEmpty == true) {
      AnalyticsService.logMedication(source: source);
    }
  }
}
