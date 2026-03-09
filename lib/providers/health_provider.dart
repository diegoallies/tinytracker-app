import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/health_log.dart';
import '../services/supabase_service.dart';
import 'baby_provider.dart';

final healthLogsProvider = FutureProvider.autoDispose<List<HealthLog>>((ref) async {
  final baby = ref.watch(selectedBabyProvider);
  if (baby == null) return [];

  final data = await SupabaseService.client
      .from('health_logs')
      .select()
      .eq('baby_id', baby.id)
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
      'logged_at': DateTime.now().toIso8601String(),
    });
  }
}
