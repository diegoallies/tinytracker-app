import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/milestone.dart';
import '../services/supabase_service.dart';
import '../utils/milestone_data.dart';
import 'baby_provider.dart';

final milestonesProvider = FutureProvider.autoDispose<List<Milestone>>((ref) async {
  final baby = ref.watch(selectedBabyProvider);
  if (baby == null) return [];

  final data = await SupabaseService.client
      .from('milestones')
      .select()
      .eq('baby_id', baby.id)
      .order('expected_age_months', ascending: true);

  if (data.isEmpty) {
    // Seed with default milestones
    await _seedMilestones(baby.id);
    final seeded = await SupabaseService.client
        .from('milestones')
        .select()
        .eq('baby_id', baby.id)
        .order('expected_age_months', ascending: true);
    return seeded.map<Milestone>((json) => Milestone.fromJson(json)).toList();
  }

  return data.map<Milestone>((json) => Milestone.fromJson(json)).toList();
});

Future<void> _seedMilestones(String babyId) async {
  final userId = SupabaseService.userId;
  if (userId == null) return;

  final batch = defaultMilestones.map((m) => {
    'baby_id': babyId,
    'user_id': userId,
    'category': m.category,
    'title': m.title,
    'description': m.description,
    'expected_age_months': m.expectedAgeMonths,
    'achieved': false,
  }).toList();

  await SupabaseService.client.from('milestones').insert(batch);
}

class MilestoneActions {
  static Future<void> toggleAchieved(String milestoneId, bool achieved) async {
    await SupabaseService.client.from('milestones').update({
      'achieved': achieved,
      'achieved_at': achieved ? DateTime.now().toIso8601String() : null,
    }).eq('id', milestoneId);
  }

  static Future<void> updatePhoto(String milestoneId, String photoUrl) async {
    await SupabaseService.client.from('milestones').update({
      'photo_url': photoUrl,
    }).eq('id', milestoneId);
  }

  static Future<void> addCustomMilestone({
    required String babyId,
    required String category,
    required String title,
    String? description,
    required int expectedAgeMonths,
  }) async {
    final userId = SupabaseService.userId;
    if (userId == null) return;

    await SupabaseService.client.from('milestones').insert({
      'baby_id': babyId,
      'user_id': userId,
      'category': category,
      'title': title,
      'description': description,
      'expected_age_months': expectedAgeMonths,
      'achieved': false,
    });
  }
}
