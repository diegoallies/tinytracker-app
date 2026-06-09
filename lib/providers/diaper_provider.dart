import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/diaper.dart';
import '../services/supabase_service.dart';
import '../utils/date_utils.dart';
import 'baby_provider.dart';

final recentDiapersProvider = FutureProvider<List<Diaper>>((ref) async {
  final baby = ref.watch(selectedBabyProvider);
  if (baby == null) return [];

  final data = await SupabaseService.client
      .from('diapers')
      .select('*')
      .eq('baby_id', baby.id)
      .order('logged_at', ascending: false)
      .limit(10);

  return data.map<Diaper>((json) => Diaper.fromJson(json)).toList();
});

final todayDiaperCountProvider = FutureProvider<int>((ref) async {
  final baby = ref.watch(selectedBabyProvider);
  if (baby == null) return 0;

  final data = await SupabaseService.client
      .from('diapers')
      .select('id')
      .eq('baby_id', baby.id)
      .gte('logged_at', AppDateUtils.todayStart.toUtc().toIso8601String());

  return data.length;
});

final todayDiaperStatsProvider = FutureProvider<Map<String, int>>((ref) async {
  final baby = ref.watch(selectedBabyProvider);
  if (baby == null) return {'wet': 0, 'dirty': 0, 'both': 0};

  final data = await SupabaseService.client
      .from('diapers')
      .select('type')
      .eq('baby_id', baby.id)
      .gte('logged_at', AppDateUtils.todayStart.toUtc().toIso8601String());

  int wet = 0, dirty = 0, both = 0;
  for (final d in data) {
    switch (d['type']) {
      case 'wet': wet++;
      case 'dirty': dirty++;
      case 'both': both++;
    }
  }
  return {'wet': wet, 'dirty': dirty, 'both': both};
});

final lastDiaperAtProvider = FutureProvider<DateTime?>((ref) async {
  final baby = ref.watch(selectedBabyProvider);
  if (baby == null) return null;

  final data = await SupabaseService.client
      .from('diapers')
      .select('logged_at')
      .eq('baby_id', baby.id)
      .order('logged_at', ascending: false)
      .limit(1)
      .maybeSingle();

  if (data == null) return null;
  return DateTime.parse(data['logged_at'] as String);
});

class DiaperActions {
  static Future<void> logDiaper({
    required String babyId,
    required String type,
    String? color,
    int? stoolType,
    String? notes,
    DateTime? loggedAt,
  }) async {
    final userId = SupabaseService.userId;
    if (userId == null) return;

    final isDirty = type == 'dirty' || type == 'both';
    final payload = {
      'baby_id': babyId,
      'user_id': userId,
      'type': type,
      'color': isDirty ? color : null,
      'notes': notes?.isNotEmpty == true ? notes : null,
      'logged_at': (loggedAt ?? DateTime.now()).toUtc().toIso8601String(),
    };

    // stool_type lands with the Care Pack migration; if the column doesn't
    // exist yet the insert is retried without it so logging never breaks.
    if (isDirty && stoolType != null) {
      try {
        await SupabaseService.client
            .from('diapers')
            .insert({...payload, 'stool_type': stoolType});
        return;
      } on PostgrestException catch (e) {
        // Only retry when the column genuinely doesn't exist yet — see
        // feeding_provider.dart for the rationale.
        if (e.code != '42703' && e.code != 'PGRST204') rethrow;
        debugPrint('diaper insert with stool_type failed (${e.code}), retrying without');
      }
    }
    await SupabaseService.client.from('diapers').insert(payload);
  }

  static Future<void> deleteDiaper(String diaperId) async {
    await SupabaseService.client
        .from('diapers')
        .delete()
        .eq('id', diaperId);
  }
}
