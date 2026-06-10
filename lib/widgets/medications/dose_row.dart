import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../config/design_tokens.dart';
import '../../config/theme.dart';
import '../../models/baby_medication.dart';
import '../../utils/haptics.dart';

/// Short, human schedule line for a catalog med - '2× daily',
/// 'As needed · min 4h gap'. The long [BabyMedication.instructions] text
/// belongs in the detail sheet, never in list rows.
String medScheduleLabel(BabyMedication med) {
  final gap = med.minIntervalHours;
  final gapText = gap == null ? null : 'min ${_fmtHours(gap)}h gap';

  if (med.asNeeded) {
    return gapText == null ? 'As needed' : 'As needed · $gapText';
  }
  final freq = med.frequencyPerDay;
  if (freq != null) {
    final base = '$freq× daily';
    return gapText == null ? base : '$base · $gapText';
  }
  if (gapText != null) return 'Any time · $gapText';
  final dosage = med.defaultDosage;
  if (dosage != null && dosage.isNotEmpty) return dosage;
  return 'No schedule set';
}

String _fmtHours(double hours) {
  return hours == hours.roundToDouble()
      ? hours.toInt().toString()
      : hours.toStringAsFixed(1);
}

/// One row of the "Today's doses" checklist on the Health screen.
///
/// Scheduled meds show one circle per daily dose slot (filled = given);
/// as-needed meds show the last dose time and a compact Give button.
/// Tapping anywhere (or Give) opens the med's detail sheet via [onOpen].
class MedDoseRow extends StatelessWidget {
  final BabyMedication med;

  /// Today's administered doses, newest first.
  final List<DateTime> dosesToday;
  final VoidCallback onOpen;

  const MedDoseRow({
    super.key,
    required this.med,
    required this.dosesToday,
    required this.onOpen,
  });

  static final _timeFmt = DateFormat('HH:mm');

  void _handleTap() {
    Haptics.lightTap();
    onOpen();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final freq = med.asNeeded ? null : med.frequencyPerDay;
    final given = dosesToday.length;
    final done = freq != null && given >= freq;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Material(
        color: done
            ? AppColors.success.withValues(alpha: 0.10)
            : palette.surface,
        borderRadius: AppRadius.lgAll,
        child: InkWell(
          onTap: _handleTap,
          borderRadius: AppRadius.lgAll,
          child: Container(
            constraints: const BoxConstraints(minHeight: 64),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              borderRadius: AppRadius.lgAll,
              border: Border.all(
                color: done
                    ? AppColors.success.withValues(alpha: 0.35)
                    : palette.border,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: (done ? AppColors.success : AppColors.primary)
                        .withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.medication_rounded,
                    size: 19,
                    color: done ? AppColors.success : AppColors.primary,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        med.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: palette.text,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        done ? 'Done for today ✓' : medScheduleLabel(med),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: done ? AppColors.success : palette.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                if (freq != null)
                  _DoseSlots(total: freq, given: given)
                else
                  _AsNeededTrailing(
                    lastDose: given == 0 ? null : dosesToday.first,
                    timeFmt: _timeFmt,
                    onGive: _handleTap,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// ●○○-style slot indicators for a scheduled med's day.
class _DoseSlots extends StatelessWidget {
  final int total;
  final int given;

  const _DoseSlots({required this.total, required this.given});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < total; i++)
          Padding(
            padding: EdgeInsets.only(left: i == 0 ? 0 : AppSpacing.xxs),
            child: i < given
                ? Container(
                    width: 22,
                    height: 22,
                    decoration: const BoxDecoration(
                      color: AppColors.success,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      size: 14,
                      color: Colors.white,
                    ),
                  )
                : Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: context.palette.border,
                        width: 1.5,
                      ),
                    ),
                  ),
          ),
      ],
    );
  }
}

class _AsNeededTrailing extends StatelessWidget {
  final DateTime? lastDose;
  final DateFormat timeFmt;
  final VoidCallback onGive;

  const _AsNeededTrailing({
    required this.lastDose,
    required this.timeFmt,
    required this.onGive,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          lastDose == null ? 'none today' : 'last ${timeFmt.format(lastDose!)}',
          style: TextStyle(fontSize: 12, color: context.palette.muted),
        ),
        const SizedBox(width: AppSpacing.xs),
        SizedBox(
          height: 44,
          child: ElevatedButton(
            onPressed: onGive,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(60, 44),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              shape: const RoundedRectangleBorder(
                borderRadius: AppRadius.mdAll,
              ),
              textStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            child: const Text('Give'),
          ),
        ),
      ],
    );
  }
}
