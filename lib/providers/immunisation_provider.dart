import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/immunisation.dart';
import '../services/supabase_service.dart';
import 'baby_provider.dart';
import 'care_pack_provider.dart' show SchemaNotReadyException;

bool _isSchemaNotReady(Object e) {
  if (e is PostgrestException) {
    final code = e.code ?? '';
    return code == '42P01' || // undefined table
        code == '42703' || // undefined column
        code == 'PGRST204' || // column not in schema cache
        code == 'PGRST205'; // table not in schema cache
  }
  return false;
}

Never _handle(Object e, StackTrace st, String where) {
  debugPrint('$where error: $e\n$st');
  if (_isSchemaNotReady(e)) throw SchemaNotReadyException();
  throw e; // ignore: only_throw_errors
}

String _dateString(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// All recorded immunisations for the selected baby.
final immunisationsProvider =
    FutureProvider<List<Immunisation>>((ref) async {
  final baby = ref.watch(selectedBabyProvider);
  if (baby == null) return [];

  try {
    final data = await SupabaseService.client
        .from('immunisations')
        .select('*')
        .eq('baby_id', baby.id)
        .isFilter('deleted_at', null)
        .order('given_on', ascending: true);
    return data.map<Immunisation>(Immunisation.fromJson).toList();
  } catch (e, st) {
    _handle(e, st, 'immunisationsProvider');
  }
});

class ImmunisationActions {
  /// Records a dose as given. Upsert on (baby_id, vaccine_key) so re-marking
  /// (e.g. correcting the date) updates the existing row.
  static Future<void> markGiven({
    required String babyId,
    required String vaccineKey,
    required DateTime givenOn,
    String? notes,
  }) async {
    final userId = SupabaseService.userId;
    if (userId == null) return;
    await SupabaseService.client.from('immunisations').upsert(
      {
        'baby_id': babyId,
        'user_id': userId,
        'vaccine_key': vaccineKey,
        'given_on': _dateString(givenOn),
        'notes': _orNull(notes),
        // Resurrect a soft-deleted record occupying this unique key.
        'deleted_at': null,
      },
      onConflict: 'baby_id,vaccine_key',
    );
  }

  /// Removes the record for a dose (undo a mistaken tick).
  static Future<void> unmark({
    required String babyId,
    required String vaccineKey,
  }) async {
    await SupabaseService.client
        .from('immunisations')
        .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
        .eq('baby_id', babyId)
        .eq('vaccine_key', vaccineKey);
  }

  static String? _orNull(String? s) =>
      (s == null || s.trim().isEmpty) ? null : s.trim();
}
