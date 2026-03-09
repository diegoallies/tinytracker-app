import 'package:flutter_riverpod/flutter_riverpod.dart';
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
      .gte('logged_at', AppDateUtils.todayStart.toIso8601String());

  return data.length;
});

final todayDiaperStatsProvider = FutureProvider<Map<String, int>>((ref) async {
  final baby = ref.watch(selectedBabyProvider);
  if (baby == null) return {'wet': 0, 'dirty': 0, 'both': 0};

  final data = await SupabaseService.client
      .from('diapers')
      .select('type')
      .eq('baby_id', baby.id)
      .gte('logged_at', AppDateUtils.todayStart.toIso8601String());

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

class DiaperActions {
  static Future<void> logDiaper({
    required String babyId,
    required String type,
    String? color,
    String? notes,
  }) async {
    final userId = SupabaseService.userId;
    if (userId == null) return;

    await SupabaseService.client.from('diapers').insert({
      'baby_id': babyId,
      'user_id': userId,
      'type': type,
      'color': (type == 'dirty' || type == 'both') ? color : null,
      'notes': notes?.isNotEmpty == true ? notes : null,
      'logged_at': DateTime.now().toIso8601String(),
    });
  }

  static Future<void> deleteDiaper(String diaperId) async {
    await SupabaseService.client
        .from('diapers')
        .delete()
        .eq('id', diaperId);
  }
}
