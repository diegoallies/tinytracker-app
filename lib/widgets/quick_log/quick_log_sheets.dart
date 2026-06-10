import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/design_tokens.dart';
import '../../config/theme.dart';
import '../../models/baby_medication.dart';
import '../../providers/baby_provider.dart';
import '../../providers/baby_medication_provider.dart';
import '../../providers/feeding_provider.dart';
import '../../providers/diaper_provider.dart';
import '../../providers/sleep_provider.dart';
import '../../services/medication_guard.dart';
import '../../utils/extensions.dart';
import '../../utils/haptics.dart';
import '../medications/dose_row.dart' show medScheduleLabel;
import '../medications/give_dose_sheet.dart';

class QuickLogSheets {
  static void show(BuildContext context, WidgetRef ref, int navIndex) {
    HapticFeedback.mediumImpact();

    final baby = ref.read(selectedBabyProvider);
    if (baby == null) {
      context.showErrorSnackBar('Please add a baby first');
      return;
    }

    Widget sheet;
    switch (navIndex) {
      case 1:
        sheet = const _QuickLogFeedingSheet();
      case 2:
        sheet = const _QuickLogDiaperSheet();
      case 3:
        sheet = const _QuickLogSleepSheet();
      default:
        return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => sheet,
    );
  }
}

class _DragHandle extends StatelessWidget {
  const _DragHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        margin: const EdgeInsets.only(top: 12, bottom: 8),
        decoration: BoxDecoration(
          color: context.palette.border,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

class _SheetContainer extends StatelessWidget {
  final List<Widget> children;

  const _SheetContainer({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.palette.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _DragHandle(),
          ...children,
        ],
      ),
    );
  }
}

// ─── Quick Log Feeding ───────────────────────────────────────────────

class _QuickLogFeedingSheet extends ConsumerStatefulWidget {
  const _QuickLogFeedingSheet();

  @override
  ConsumerState<_QuickLogFeedingSheet> createState() =>
      _QuickLogFeedingSheetState();
}

class _QuickLogFeedingSheetState extends ConsumerState<_QuickLogFeedingSheet> {
  String _selectedType = 'bottle';
  int _amountMl = 60;
  int? _quality; // optional 1–5 "how did the feed go?"
  bool _hadSpitup = false;
  bool _isSaving = false;

  static const _feedTypes = [
    ('breast_left', 'Left', Icons.woman),
    ('breast_right', 'Right', Icons.woman),
    ('bottle', 'Bottle', Icons.local_drink_rounded),
    ('solids', 'Solids', Icons.restaurant),
  ];

  bool get _isBottle => _selectedType == 'bottle';

  Future<void> _save() async {
    final baby = ref.read(selectedBabyProvider);
    if (baby == null) return;

    setState(() => _isSaving = true);
    try {
      await FeedingActions.logFeeding(
        babyId: baby.id,
        type: _selectedType,
        durationMinutes: _isBottle ? null : 0,
        amountMl: _isBottle ? _amountMl : null,
        quality: _quality,
        hadSpitup: _hadSpitup,
      );
      ref.invalidate(recentFeedingsProvider);
      ref.invalidate(todayFeedCountProvider);
      if (mounted) {
        Navigator.pop(context);
        context.showSuccessSnackBar('Feeding logged');
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar(
          'Couldn’t log the feeding. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SheetContainer(
      children: [
        const SizedBox(height: 8),
        Text(
          'Quick Log Feeding',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: context.palette.text,
          ),
        ),
        const SizedBox(height: 16),
        // Type selector
        Row(
          children: _feedTypes.map((t) {
            final isSelected = _selectedType == t.$1;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: GestureDetector(
                  onTap: () => setState(() => _selectedType = t.$1),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.pastelPurple
                          : context.palette.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color:
                            isSelected ? AppColors.primary : Colors.transparent,
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(t.$3,
                            size: 20,
                            color: isSelected
                                ? AppColors.primary
                                : context.palette.muted),
                        const SizedBox(height: 4),
                        Text(
                          t.$2,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.w500,
                            color: isSelected
                                ? AppColors.primary
                                : context.palette.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),

        // Amount stepper for bottle
        if (_isBottle) ...[
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: _amountMl > 10
                    ? () => setState(() => _amountMl -= 10)
                    : null,
                icon: const Icon(Icons.remove_circle_outline),
                color: AppColors.primary,
              ),
              const SizedBox(width: 8),
              Text(
                '$_amountMl ml',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: context.palette.text,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _amountMl < 500
                    ? () => setState(() => _amountMl += 10)
                    : null,
                icon: const Icon(Icons.add_circle_outline),
                color: AppColors.primary,
              ),
            ],
          ),
        ],

        // Optional feed quality + spit-up flag (kept compact)
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var star = 1; star <= 5; star++)
              GestureDetector(
                onTap: () {
                  Haptics.selectionClick();
                  setState(() => _quality = _quality == star ? null : star);
                },
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: Icon(
                    Icons.star_rounded,
                    size: 28,
                    color: _quality != null && star <= _quality!
                        ? AppColors.warning
                        : context.palette.muted.withValues(alpha: 0.3),
                  ),
                ),
              ),
          ],
        ),
        Center(
          child: GestureDetector(
            onTap: () {
              Haptics.selectionClick();
              setState(() => _hadSpitup = !_hadSpitup);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: _hadSpitup
                    ? AppColors.warning.withValues(alpha: 0.15)
                    : context.palette.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _hadSpitup
                      ? AppColors.warning
                      : context.palette.muted.withValues(alpha: 0.3),
                  width: _hadSpitup ? 1.5 : 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.water_drop_outlined,
                    size: 16,
                    color: _hadSpitup
                        ? AppColors.warning
                        : context.palette.muted,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Spit-up after feed',
                    style: TextStyle(
                      color: _hadSpitup
                          ? AppColors.warning
                          : context.palette.text,
                      fontWeight:
                          _hadSpitup ? FontWeight.w600 : FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: _isSaving ? null : _save,
          child: _isSaving
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Text('Log Feeding'),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

// ─── Quick Log Diaper ────────────────────────────────────────────────

class _QuickLogDiaperSheet extends ConsumerStatefulWidget {
  const _QuickLogDiaperSheet();

  @override
  ConsumerState<_QuickLogDiaperSheet> createState() =>
      _QuickLogDiaperSheetState();
}

class _QuickLogDiaperSheetState extends ConsumerState<_QuickLogDiaperSheet> {
  String _selectedType = 'wet';
  bool _isSaving = false;

  static const _diaperTypes = [
    ('wet', 'Wet', Icons.water_drop_outlined),
    ('dirty', 'Dirty', Icons.circle),
    ('both', 'Both', Icons.layers_outlined),
  ];

  Future<void> _save() async {
    final baby = ref.read(selectedBabyProvider);
    if (baby == null) return;

    setState(() => _isSaving = true);
    try {
      await DiaperActions.logDiaper(
        babyId: baby.id,
        type: _selectedType,
      );
      ref.invalidate(recentDiapersProvider);
      ref.invalidate(todayDiaperStatsProvider);
      ref.invalidate(todayDiaperCountProvider);
      if (mounted) {
        Navigator.pop(context);
        context.showSuccessSnackBar('Diaper logged');
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar(
          'Couldn’t log the diaper. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SheetContainer(
      children: [
        const SizedBox(height: 8),
        Text(
          'Quick Log Diaper',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: context.palette.text,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: _diaperTypes.map((t) {
            final isSelected = _selectedType == t.$1;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: GestureDetector(
                  onTap: () => setState(() => _selectedType = t.$1),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.pastelPurple
                          : context.palette.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color:
                            isSelected ? AppColors.primary : Colors.transparent,
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(t.$3,
                            size: 24,
                            color: isSelected
                                ? AppColors.primary
                                : context.palette.muted),
                        const SizedBox(height: 4),
                        Text(
                          t.$2,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.w500,
                            color: isSelected
                                ? AppColors.primary
                                : context.palette.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: _isSaving ? null : _save,
          child: _isSaving
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Text('Log Diaper'),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

// ─── Quick Log Sleep ─────────────────────────────────────────────────

class _QuickLogSleepSheet extends ConsumerStatefulWidget {
  const _QuickLogSleepSheet();

  @override
  ConsumerState<_QuickLogSleepSheet> createState() =>
      _QuickLogSleepSheetState();
}

class _QuickLogSleepSheetState extends ConsumerState<_QuickLogSleepSheet> {
  bool _isLoading = false;
  Timer? _timer;
  Duration _elapsed = Duration.zero;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startElapsedTimer(DateTime startTime) {
    _timer?.cancel();
    _updateElapsed(startTime);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateElapsed(startTime);
    });
  }

  void _updateElapsed(DateTime startTime) {
    if (mounted) {
      setState(() {
        _elapsed = DateTime.now().difference(startTime);
      });
    }
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  Future<void> _startSleep() async {
    final baby = ref.read(selectedBabyProvider);
    if (baby == null) return;

    setState(() => _isLoading = true);
    try {
      await SleepActions.startSleep(baby.id);
      ref.invalidate(activeSleepProvider);
      if (mounted) {
        Navigator.pop(context);
        context.showSuccessSnackBar('Sleep started');
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar(
          'Couldn’t start the sleep session. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _stopSleep(String sleepId, DateTime startTime) async {
    setState(() => _isLoading = true);
    try {
      await SleepActions.stopSleep(sleepId, startTime);
      ref.invalidate(activeSleepProvider);
      ref.invalidate(recentSleepsProvider);
      ref.invalidate(todaySleepMinutesProvider);
      if (mounted) {
        Navigator.pop(context);
        context.showSuccessSnackBar('Sleep ended');
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar(
          'Couldn’t end the sleep session. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeSleep = ref.watch(activeSleepProvider);

    return _SheetContainer(
      children: [
        const SizedBox(height: 8),
        Text(
          'Quick Log Sleep',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: context.palette.text,
          ),
        ),
        const SizedBox(height: 20),
        activeSleep.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text('Error: $e',
                style: const TextStyle(color: AppColors.error)),
          ),
          data: (session) {
            if (session != null) {
              // Active sleep — show elapsed time and wake up button
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (_timer == null || !_timer!.isActive) {
                  _startElapsedTimer(session.startTime);
                }
              });

              return Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        vertical: 20, horizontal: 24),
                    decoration: BoxDecoration(
                      color: AppColors.pastelPurple,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        const Icon(Icons.nightlight_round,
                            size: 32, color: AppColors.primary),
                        const SizedBox(height: 8),
                        const Text(
                          'Baby is sleeping',
                          style: TextStyle(
                            fontSize: 14,
                            // Fixed dark tone: sits on the light pastel chip
                            // in both light and dark mode.
                            color: AppColors.primaryDark,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _formatDuration(_elapsed),
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _isLoading
                        ? null
                        : () => _stopSleep(session.id, session.startTime),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.warning,
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Wake Up'),
                  ),
                ],
              );
            }

            // No active sleep — show start button
            return Column(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
                  decoration: BoxDecoration(
                    color: context.palette.surface,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.nightlight_round,
                          size: 32, color: context.palette.muted),
                      const SizedBox(height: 8),
                      Text(
                        'Baby is awake',
                        style: TextStyle(fontSize: 14, color: context.palette.muted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _isLoading ? null : _startSleep,
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Start Sleep'),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

// ─── Quick Log Medicine ──────────────────────────────────────────────

/// Standalone medicine quick-log: lists the selected baby's catalog meds;
/// tapping one closes this sheet and opens the full [GiveDoseSheet]
/// (guard warnings, time, dosage, notes) — no feed log required.
Future<void> showQuickMedicineSheet(BuildContext context, WidgetRef ref) async {
  HapticFeedback.mediumImpact();

  final baby = ref.read(selectedBabyProvider);
  if (baby == null) {
    context.showErrorSnackBar('Please add a baby first');
    return;
  }

  final med = await showModalBottomSheet<BabyMedication>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _QuickLogMedicineSheet(),
  );
  if (med == null || !context.mounted) return;

  // Open the existing give-dose flow, exactly like the Health screen does.
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => GiveDoseSheet(
      babyId: baby.id,
      med: med,
      canEdit: ref.read(babyProvider).isOwner,
    ),
  );
}

class _QuickLogMedicineSheet extends ConsumerWidget {
  const _QuickLogMedicineSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final medsAsync = ref.watch(babyMedicationsProvider);
    final dosesToday =
        ref.watch(medicationDosesTodayProvider).asData?.value ??
            const <String, List<DateTime>>{};

    return _SheetContainer(
      children: [
        const SizedBox(height: 8),
        Text(
          'Give Medicine',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: context.palette.text,
          ),
        ),
        const SizedBox(height: 16),
        medsAsync.when(
          loading: () => const SizedBox(
            height: 64,
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
          error: (_, _) => Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Text(
              'Couldn’t load medications. Check your connection and try again.',
              style: TextStyle(fontSize: 13, color: context.palette.muted),
            ),
          ),
          data: (meds) {
            if (meds.isEmpty) return const _EmptyMedicineCatalog();
            return ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.5,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final med in meds)
                      _QuickMedicineRow(
                        med: med,
                        dosesToday:
                            dosesToday[med.name.trim().toLowerCase()] ??
                                const [],
                      ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _EmptyMedicineCatalog extends StatelessWidget {
  const _EmptyMedicineCatalog();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.lg,
        horizontal: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: palette.border),
      ),
      child: Column(
        children: [
          Icon(Icons.medication_rounded, size: 32, color: palette.muted),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'No medications saved yet',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: palette.text,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Add your baby’s daily meds on the Health page, '
            'then log doses here in one tap.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: palette.muted),
          ),
        ],
      ),
    );
  }
}

/// One catalog med row: icon, name, short schedule line, and a compact
/// today-status chip ('1/3 today' / 'last 14:30'). Tap selects the med.
class _QuickMedicineRow extends StatelessWidget {
  final BabyMedication med;

  /// Today's administered doses, newest first.
  final List<DateTime> dosesToday;

  const _QuickMedicineRow({required this.med, required this.dosesToday});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final status = MedicationGuard.todayStatus(med, dosesToday);
    final accent = status.done ? AppColors.success : AppColors.primary;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Material(
        color: status.done
            ? AppColors.success.withValues(alpha: 0.10)
            : palette.surface,
        borderRadius: AppRadius.lgAll,
        child: InkWell(
          onTap: () {
            Haptics.lightTap();
            Navigator.of(context).pop(med);
          },
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
                color: status.done
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
                    color: accent.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.medication_rounded,
                    size: 19,
                    color: accent,
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
                        medScheduleLabel(med),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: palette.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  status.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: status.done ? AppColors.success : palette.muted,
                  ),
                ),
                const SizedBox(width: AppSpacing.xxs),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: palette.muted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
