import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../config/design_tokens.dart';
import '../../config/theme.dart';
import '../../models/baby_medication.dart';
import '../../providers/baby_medication_provider.dart';
import '../../providers/health_provider.dart';
import '../../services/medication_guard.dart';
import '../../utils/extensions.dart';
import '../../utils/haptics.dart';
import '../common/app_dialogs.dart';
import 'add_medication_dialog.dart';
import 'dose_row.dart';

/// Detail + give-dose bottom sheet for one catalog medication.
///
/// Shows the full instructions, today's administered doses (each deletable),
/// and a give-dose form (time, dosage, notes) that runs [MedicationGuard]
/// before inserting. Owners also get Edit / Remove for the catalog row.
class GiveDoseSheet extends ConsumerStatefulWidget {
  final String babyId;
  final BabyMedication med;

  /// Whether the current user may edit/remove the catalog med (owner only).
  final bool canEdit;

  const GiveDoseSheet({
    super.key,
    required this.babyId,
    required this.med,
    this.canEdit = false,
  });

  @override
  ConsumerState<GiveDoseSheet> createState() => _GiveDoseSheetState();
}

class _GiveDoseSheetState extends ConsumerState<GiveDoseSheet> {
  static final _timeFmt = DateFormat('HH:mm');

  late BabyMedication _med = widget.med;
  late final TextEditingController _dosageCtrl =
      TextEditingController(text: widget.med.defaultDosage ?? '');
  final _notesCtrl = TextEditingController();

  /// Null means "now".
  TimeOfDay? _customTime;
  bool _saving = false;

  @override
  void dispose() {
    _dosageCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _invalidateDoseData() {
    ref.invalidate(medDoseLogsTodayProvider);
    ref.invalidate(medicationDosesTodayProvider);
    ref.invalidate(healthLogsProvider);
  }

  Future<void> _pickCustomTime() async {
    Haptics.selectionClick();
    final picked = await showTimePicker(
      context: context,
      initialTime: _customTime ?? TimeOfDay.now(),
      helpText: 'When was the dose given?',
    );
    if (picked != null && mounted) {
      setState(() => _customTime = picked);
    }
  }

  Future<void> _giveDose() async {
    final now = DateTime.now();
    final t = _customTime;
    final at = t == null
        ? now
        : DateTime(now.year, now.month, now.day, t.hour, t.minute);

    setState(() => _saving = true);
    try {
      // Dose-safety check before anything is inserted.
      final check = await MedicationGuard.check(
        babyId: widget.babyId,
        med: _med,
        at: at,
      );
      if (!mounted) return;
      if (!check.ok) {
        final proceed = await showConfirmDialog(
          context,
          title: 'Double-check this dose',
          message: '${check.warning}\n\nGive it anyway?',
          confirmLabel: 'Give anyway',
          destructive: true,
          icon: Icons.medication_rounded,
        );
        if (!proceed) return;
        if (!mounted) return;
      }

      await HealthActions.logHealth(
        babyId: widget.babyId,
        medication: _med.name,
        dosage: _dosageCtrl.text.trim(),
        notes: _notesCtrl.text.trim(),
        loggedAt: at,
      );

      if (!mounted) return;
      Haptics.mediumTap();
      _invalidateDoseData();
      context.showSuccessSnackBar(
        '${_med.name} given at ${_timeFmt.format(at)}',
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar(
          'Couldn’t log the dose. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteDose(MedDoseLog dose) async {
    final confirmed = await showDeleteDialog(
      context,
      what: 'Dose',
      message:
          'Remove the ${_timeFmt.format(dose.at)} dose of ${_med.name} '
          'from the log?',
    );
    if (!confirmed || !mounted) return;
    try {
      await BabyMedicationActions.deleteDoseLog(dose.id);
      if (!mounted) return;
      Haptics.heavyTap();
      _invalidateDoseData();
      context.showSuccessSnackBar('Dose removed');
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar(
          'Couldn’t remove the dose. Check your connection and try again.',
        );
      }
    }
  }

  Future<void> _editMed() async {
    Haptics.lightTap();
    final oldDefault = _med.defaultDosage ?? '';
    final updated = await showDialog<BabyMedication>(
      context: context,
      builder: (_) => AddMedicationDialog(
        babyId: widget.babyId,
        existing: _med,
      ),
    );
    if (updated == null || !mounted) return;
    ref.invalidate(babyMedicationsProvider);
    // The name may have changed, and today's list keys off the name.
    ref.invalidate(medDoseLogsTodayProvider);
    setState(() {
      _med = updated;
      // Keep anything the user already typed; only refresh an untouched
      // dosage field to the new default.
      if (_dosageCtrl.text.trim() == oldDefault.trim()) {
        _dosageCtrl.text = updated.defaultDosage ?? '';
      }
    });
  }

  Future<void> _removeMed() async {
    final confirmed = await showDeleteDialog(
      context,
      what: 'Medication',
      message: 'Remove "${_med.name}" from daily medications? '
          'Doses already logged stay in the health log.',
    );
    if (!confirmed || !mounted) return;
    try {
      await BabyMedicationActions.delete(_med.id);
      if (!mounted) return;
      Haptics.heavyTap();
      ref.invalidate(babyMedicationsProvider);
      context.showSuccessSnackBar('${_med.name} removed');
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar(
          'Couldn’t delete the medication. Check your connection and try again.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final dosesAsync = ref.watch(medDoseLogsTodayProvider(_med.name));
    final instructions = _med.instructions?.trim();

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: AppSpacing.sheet,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(palette, instructions),
            const SizedBox(height: AppSpacing.lg),
            _sectionLabel('Today', palette),
            const SizedBox(height: AppSpacing.xs),
            dosesAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
              error: (_, _) => Text(
                'Couldn’t load today’s doses.',
                style: TextStyle(fontSize: 13, color: palette.muted),
              ),
              data: (doses) => _buildTodayList(doses, palette),
            ),
            const SizedBox(height: AppSpacing.lg),
            _sectionLabel('Give a dose', palette),
            const SizedBox(height: AppSpacing.xs),
            _buildTimeChips(palette),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _dosageCtrl,
              decoration: const InputDecoration(
                labelText: 'Dosage',
                hintText: 'e.g. 2.5 ml',
                prefixIcon: Icon(Icons.science_outlined, size: 20),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _notesCtrl,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                prefixIcon: Icon(Icons.notes, size: 20),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            ElevatedButton(
              onPressed: _saving ? null : _giveDose,
              child: _saving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Give dose'),
            ),
            if (widget.canEdit) ...[
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: [
                  Expanded(
                    child: TextButton.icon(
                      onPressed: _saving ? null : _editMed,
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('Edit'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: TextButton.icon(
                      onPressed: _saving ? null : _removeMed,
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.error,
                      ),
                      icon: const Icon(Icons.delete_outline_rounded, size: 18),
                      label: const Text('Remove medication'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(AppPalette palette, String? instructions) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.medication_rounded,
                size: 22,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _med.name,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: palette.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    medScheduleLabel(_med),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: palette.muted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (instructions != null && instructions.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: AppRadius.mdAll,
              border: Border.all(color: palette.border),
            ),
            child: Text(
              instructions,
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: palette.muted,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _sectionLabel(String text, AppPalette palette) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: palette.text,
      ),
    );
  }

  Widget _buildTodayList(List<MedDoseLog> doses, AppPalette palette) {
    if (doses.isEmpty) {
      return Text(
        'No doses given today.',
        style: TextStyle(fontSize: 13, color: palette.muted),
      );
    }
    return Column(
      children: [
        for (final dose in doses)
          SizedBox(
            height: 48,
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    size: 16,
                    color: AppColors.success,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    dose.dosage == null || dose.dosage!.isEmpty
                        ? _timeFmt.format(dose.at)
                        : '${_timeFmt.format(dose.at)} · ${dose.dosage}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: palette.text,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => _deleteDose(dose),
                  tooltip: 'Remove this dose',
                  iconSize: 20,
                  constraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 44,
                  ),
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    color: palette.muted,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildTimeChips(AppPalette palette) {
    final isNow = _customTime == null;
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        ChoiceChip(
          label: const Text('Now'),
          selected: isNow,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: 10,
          ),
          onSelected: (_) {
            Haptics.selectionClick();
            setState(() => _customTime = null);
          },
          selectedColor: AppColors.primary.withValues(alpha: 0.18),
          labelStyle: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isNow ? AppColors.primary : palette.muted,
          ),
        ),
        ChoiceChip(
          avatar: Icon(
            Icons.schedule_rounded,
            size: 16,
            color: isNow ? palette.muted : AppColors.primary,
          ),
          label: Text(
            _customTime == null
                ? 'Pick a time'
                : _customTime!.format(context),
          ),
          selected: !isNow,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: 10,
          ),
          onSelected: (_) => _pickCustomTime(),
          selectedColor: AppColors.primary.withValues(alpha: 0.18),
          labelStyle: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isNow ? palette.muted : AppColors.primary,
          ),
        ),
      ],
    );
  }
}
