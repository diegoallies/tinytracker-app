import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../models/baby_medication.dart';
import '../providers/baby_medication_provider.dart';

/// Result of a pre-administration safety check.
class DoseCheck {
  final bool ok;
  final String? warning;

  const DoseCheck({required this.ok, this.warning});

  static const pass = DoseCheck(ok: true);
}

/// Dose-safety checks run before a medication health_log is inserted.
///
/// Never blocks logging because a check itself failed - network errors
/// resolve to [DoseCheck.pass].
class MedicationGuard {
  static const int _asNeededMaxPer24h = 4;

  static final _timeFmt = DateFormat('h:mm a');

  static Future<DoseCheck> check({
    required String babyId,
    required BabyMedication med,
    DateTime? at,
  }) async {
    try {
      final now = at ?? DateTime.now();
      final warnings = <String>[];

      final dosesToday =
          await BabyMedicationActions.dosesToday(babyId, med.name);

      // Scheduled meds: already at (or over) today's count.
      final freq = med.frequencyPerDay;
      if (freq != null && dosesToday.length >= freq) {
        // Always the canonical phrase - `instructions` is free text and
        // reads badly mid-sentence.
        final schedule = freq == 1 ? 'once a day' : '$freq× a day';
        final n = dosesToday.length;
        warnings.add(
          '"${med.name}" is $schedule - already given $n '
          'time${n == 1 ? '' : 's'} today '
          '(last at ${_timeFmt.format(dosesToday.first)}).',
        );
      }

      // Minimum gap between doses (scheduled or as-needed). For backdated
      // logging, the gap is measured to the nearest dose BEFORE the chosen
      // time - a later dose shouldn't produce a negative-gap warning here.
      final gap = med.minIntervalHours;
      if (gap != null) {
        final last = await BabyMedicationActions.lastDose(babyId, med.name);
        final lastBefore = last != null && !last.isAfter(now)
            ? last
            : (dosesToday.where((d) => !d.isAfter(now)).isEmpty
                ? null
                : dosesToday.firstWhere((d) => !d.isAfter(now)));
        if (lastBefore != null) {
          final elapsed = now.difference(lastBefore);
          if (elapsed < Duration(minutes: (gap * 60).round())) {
            final hoursAgo =
                (elapsed.inMinutes / 60).clamp(0, double.infinity);
            warnings.add(
              '"${med.name}" was given at ${_timeFmt.format(lastBefore)} - '
              'that\'s only ${_fmtHours(hoursAgo)}h ago. '
              'The minimum gap is ${_fmtHours(gap)} hours.',
            );
          }
        }
      }

      // As-needed meds: cap on doses in the 24h window ending at the dose
      // time being checked.
      if (med.asNeeded) {
        final recent = (await BabyMedicationActions.dosesSince(
          babyId,
          med.name,
          now.subtract(const Duration(hours: 24)),
        ))
            .where((d) => !d.isAfter(now))
            .toList();
        if (recent.length >= _asNeededMaxPer24h) {
          warnings.add(
            '"${med.name}" has already been given ${recent.length} times '
            'in the last 24 hours - the maximum is '
            '$_asNeededMaxPer24h doses per 24h.',
          );
        }
      }

      if (warnings.isEmpty) return DoseCheck.pass;
      return DoseCheck(ok: false, warning: warnings.join('\n\n'));
    } catch (e) {
      debugPrint('MedicationGuard.check failed (allowing dose): $e');
      return DoseCheck.pass;
    }
  }

  /// Free-text variant: match [name] against the catalog case-insensitively
  /// and defer to [check]; unknown meds are allowed through.
  static Future<DoseCheck> checkByName({
    required String babyId,
    required String name,
    required List<BabyMedication> catalog,
    DateTime? at,
  }) async {
    final lower = name.trim().toLowerCase();
    if (lower.isEmpty) return DoseCheck.pass;
    for (final med in catalog) {
      if (med.name.trim().toLowerCase() == lower) {
        return check(babyId: babyId, med: med, at: at);
      }
    }
    return DoseCheck.pass;
  }

  /// Compact "today" status for a catalog med, from the doses-today map
  /// produced by [medicationDosesTodayProvider] (newest first).
  /// `done` is true once a scheduled med has hit today's count.
  static ({String label, bool done}) todayStatus(
    BabyMedication med,
    List<DateTime> dosesToday,
  ) {
    final freq = med.frequencyPerDay;
    if (freq != null) {
      return (
        label: '${dosesToday.length}/$freq today',
        done: dosesToday.length >= freq,
      );
    }
    if (dosesToday.isEmpty) return (label: 'none today', done: false);
    return (
      label: 'last ${DateFormat('HH:mm').format(dosesToday.first)}',
      done: false,
    );
  }

  static String _fmtHours(num hours) {
    final rounded = (hours * 10).round() / 10;
    return rounded == rounded.roundToDouble()
        ? rounded.toInt().toString()
        : rounded.toStringAsFixed(1);
  }
}
