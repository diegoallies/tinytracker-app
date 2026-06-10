import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
      .isFilter('deleted_at', null)
      .order('name', ascending: true);

  return data
      .map<BabyMedication>(
          (json) => BabyMedication.fromJson(json))
      .toList();
});

/// Today's administered medication doses for the selected baby, grouped by
/// lowercased medication name. One health_logs query per screen open — the
/// status chips for every catalog med are computed from this single map.
final medicationDosesTodayProvider =
    FutureProvider.autoDispose<Map<String, List<DateTime>>>((ref) async {
  final baby = ref.watch(selectedBabyProvider);
  if (baby == null) return {};

  final now = DateTime.now();
  final since = DateTime(now.year, now.month, now.day);

  final data = await SupabaseService.client
      .from('health_logs')
      .select('medication, logged_at')
      .eq('baby_id', baby.id)
      .not('medication', 'is', null)
      .isFilter('deleted_at', null)
      .gte('logged_at', since.toUtc().toIso8601String())
      .order('logged_at', ascending: false);

  final byName = <String, List<DateTime>>{};
  for (final row in data) {
    final name = (row['medication'] as String?)?.trim().toLowerCase();
    if (name == null || name.isEmpty) continue;
    byName
        .putIfAbsent(name, () => [])
        .add(DateTime.parse(row['logged_at'] as String).toLocal());
  }
  return byName;
});

/// One administered dose row from health_logs. Carries the row id so a
/// mis-tap can be deleted from the med detail sheet.
class MedDoseLog {
  final String id;
  final DateTime at;
  final String? dosage;

  const MedDoseLog({required this.id, required this.at, this.dosage});
}

/// Today's administered doses of one medication (newest first), with row
/// ids. Only queried while a med's detail sheet is open.
final medDoseLogsTodayProvider = FutureProvider.autoDispose
    .family<List<MedDoseLog>, String>((ref, medName) async {
  final baby = ref.watch(selectedBabyProvider);
  if (baby == null) return [];

  final now = DateTime.now();
  final since = DateTime(now.year, now.month, now.day);

  final data = await SupabaseService.client
      .from('health_logs')
      .select('id, dosage, logged_at')
      .eq('baby_id', baby.id)
      .ilike('medication', _likeEscape(medName.trim()))
      .isFilter('deleted_at', null)
      .gte('logged_at', since.toUtc().toIso8601String())
      .order('logged_at', ascending: false);

  return data
      .map<MedDoseLog>((row) => MedDoseLog(
            id: row['id'] as String,
            at: DateTime.parse(row['logged_at'] as String).toLocal(),
            dosage: row['dosage'] as String?,
          ))
      .toList();
});


/// Escapes LIKE wildcards so a med name containing % or _ matches literally.
String _likeEscape(String s) =>
    s.replaceAll(r'\\', r'\\\\').replaceAll('%', r'\\%').replaceAll('_', r'\\_');

class BabyMedicationActions {
  static Future<BabyMedication?> add({
    required String babyId,
    required String name,
    String? defaultDosage,
    int? frequencyPerDay,
    bool asNeeded = false,
    double? minIntervalHours,
    String? instructions,
  }) async {
    final userId = SupabaseService.userId;
    if (userId == null) return null;

    try {
      final data = await SupabaseService.client
          .from('baby_medications')
          .insert({
            'baby_id': babyId,
            'name': name,
            'default_dosage':
                (defaultDosage?.trim().isNotEmpty ?? false) ? defaultDosage : null,
            'created_by': userId,
            // Only send schedule columns when set, so the insert still works
            // against an older schema that lacks them.
            'frequency_per_day': ?frequencyPerDay,
            'min_interval_hours': ?minIntervalHours,
            if (asNeeded) 'as_needed': true,
            if (instructions?.trim().isNotEmpty ?? false)
              'instructions': instructions!.trim(),
          })
          .select()
          .single();

      return BabyMedication.fromJson(data);
    } on PostgrestException catch (e) {
      // Unique violation on (baby_id, lower(name)): a soft-deleted med with
      // this name still occupies the key. PostgREST upsert can't target an
      // expression index, so resurrect the existing row with the new values.
      if (e.code != '23505') rethrow;
      final data = await SupabaseService.client
          .from('baby_medications')
          .update({
            'name': name,
            'default_dosage':
                (defaultDosage?.trim().isNotEmpty ?? false) ? defaultDosage : null,
            'frequency_per_day': frequencyPerDay,
            'min_interval_hours': minIntervalHours,
            'as_needed': asNeeded,
            'instructions': (instructions?.trim().isNotEmpty ?? false)
                ? instructions!.trim()
                : null,
            'deleted_at': null,
          })
          .eq('baby_id', babyId)
          .ilike('name', _likeEscape(name.trim()))
          .select()
          .single();

      return BabyMedication.fromJson(data);
    }
  }

  /// Update an existing catalog medication. Sends every schedule column
  /// explicitly so a cleared schedule actually clears in the database.
  static Future<BabyMedication?> update({
    required String id,
    required String name,
    String? defaultDosage,
    int? frequencyPerDay,
    bool asNeeded = false,
    double? minIntervalHours,
    String? instructions,
  }) async {
    final data = await SupabaseService.client
        .from('baby_medications')
        .update({
          'name': name,
          'default_dosage': (defaultDosage?.trim().isNotEmpty ?? false)
              ? defaultDosage!.trim()
              : null,
          'frequency_per_day': frequencyPerDay,
          'as_needed': asNeeded,
          'min_interval_hours': minIntervalHours,
          'instructions': (instructions?.trim().isNotEmpty ?? false)
              ? instructions!.trim()
              : null,
        })
        .eq('id', id)
        .select()
        .single();

    return BabyMedication.fromJson(data);
  }

  /// Delete one administered dose (a health_logs row) by id.
  static Future<void> deleteDoseLog(String healthLogId) async {
    await SupabaseService.client
        .from('health_logs')
        .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', healthLogId);
  }

  static Future<void> delete(String id) async {
    await SupabaseService.client
        .from('baby_medications')
        .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', id);
  }

  /// Administered doses of [medName] since [since] (newest first, local time).
  static Future<List<DateTime>> dosesSince(
    String babyId,
    String medName,
    DateTime since,
  ) async {
    final data = await SupabaseService.client
        .from('health_logs')
        .select('logged_at')
        .eq('baby_id', babyId)
        .ilike('medication', _likeEscape(medName.trim()))
        .isFilter('deleted_at', null)
        .gte('logged_at', since.toUtc().toIso8601String())
        .order('logged_at', ascending: false);

    return data
        .map<DateTime>(
            (row) => DateTime.parse(row['logged_at'] as String).toLocal())
        .toList();
  }

  /// Administered doses of [medName] since local midnight (newest first).
  static Future<List<DateTime>> dosesToday(
      String babyId, String medName) async {
    final now = DateTime.now();
    return dosesSince(babyId, medName, DateTime(now.year, now.month, now.day));
  }

  /// The most recent dose of [medName] within [window], or null.
  static Future<DateTime?> lastDose(
    String babyId,
    String medName, {
    Duration window = const Duration(hours: 24),
  }) async {
    final doses =
        await dosesSince(babyId, medName, DateTime.now().subtract(window));
    return doses.isEmpty ? null : doses.first;
  }
}
