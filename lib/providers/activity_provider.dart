import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/supabase_service.dart';
import 'baby_provider.dart';
import '../utils/date_utils.dart';

class ActivityItem {
  final String id;
  final String type; // feeding, diaper, sleep
  final String label;
  final DateTime time;

  ActivityItem({
    required this.id,
    required this.type,
    required this.label,
    required this.time,
  });
}

final activityFeedProvider = FutureProvider<List<ActivityItem>>((ref) async {
  final baby = ref.watch(selectedBabyProvider);
  if (baby == null) return [];

  final client = SupabaseService.client;
  final since = DateTime.now().subtract(const Duration(hours: 24)).toUtc().toIso8601String();

  final results = await Future.wait([
    client.from('feedings').select('id, type, logged_at')
        .eq('baby_id', baby.id).isFilter('deleted_at', null)
        .gte('logged_at', since),
    client.from('diapers').select('id, type, logged_at')
        .eq('baby_id', baby.id).isFilter('deleted_at', null)
        .gte('logged_at', since),
    client.from('sleeps').select('id, start_time, end_time, duration_minutes')
        .eq('baby_id', baby.id).isFilter('deleted_at', null)
        .gte('start_time', since),
  ]);

  final items = <ActivityItem>[];

  for (final f in results[0] as List) {
    final type = f['type'] as String;
    String label;
    switch (type) {
      case 'breast_left': label = 'Left breast feeding';
      case 'breast_right': label = 'Right breast feeding';
      case 'bottle': label = 'Bottle feeding';
      case 'solids': label = 'Solids feeding';
      default: label = 'Feeding';
    }
    items.add(ActivityItem(
      id: f['id'],
      type: 'feeding',
      label: label,
      time: parseDbTime(f['logged_at']),
    ));
  }

  for (final d in results[1] as List) {
    final type = d['type'] as String;
    items.add(ActivityItem(
      id: d['id'],
      type: 'diaper',
      label: '${type[0].toUpperCase()}${type.substring(1)} diaper',
      time: parseDbTime(d['logged_at']),
    ));
  }

  for (final s in results[2] as List) {
    final endTime = s['end_time'];
    final dur = s['duration_minutes'] as int?;
    final label = endTime != null
        ? 'Slept ${dur != null ? "${dur ~/ 60}h ${dur % 60}m" : ""}'
        : 'Sleeping...';
    items.add(ActivityItem(
      id: s['id'],
      type: 'sleep',
      label: label,
      time: parseDbTime(s['start_time']),
    ));
  }

  items.sort((a, b) => b.time.compareTo(a.time));
  return items.take(15).toList();
});
