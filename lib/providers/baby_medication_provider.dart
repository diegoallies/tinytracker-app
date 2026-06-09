import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/baby_medication.dart';
import '../services/supabase_service.dart';
import 'baby_provider.dart';

final babyMedicationsProvider =
    FutureProvider.autoDispose<List<BabyMedication>>((ref) async {
  final baby = ref.watch(selectedBabyProvider);
  if (baby == null) return [];

  final data = await SupabaseService.client
      .from('baby_medications')
      .select()
      .eq('baby_id', baby.id)
      .order('name', ascending: true);

  return data
      .map<BabyMedication>(
          (json) => BabyMedication.fromJson(json))
      .toList();
});

class BabyMedicationActions {
  static Future<BabyMedication?> add({
    required String babyId,
    required String name,
    String? defaultDosage,
  }) async {
    final userId = SupabaseService.userId;
    if (userId == null) return null;

    final data = await SupabaseService.client
        .from('baby_medications')
        .insert({
          'baby_id': babyId,
          'name': name,
          'default_dosage':
              (defaultDosage?.trim().isNotEmpty ?? false) ? defaultDosage : null,
          'created_by': userId,
        })
        .select()
        .single();

    return BabyMedication.fromJson(data);
  }

  static Future<void> delete(String id) async {
    await SupabaseService.client
        .from('baby_medications')
        .delete()
        .eq('id', id);
  }
}
