import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../config/design_tokens.dart';
import '../../config/theme.dart';
import '../../models/baby.dart';
import '../../models/immunisation.dart';
import '../../providers/baby_provider.dart';
import '../../providers/care_pack_provider.dart' show SchemaNotReadyException;
import '../../providers/immunisation_provider.dart';
import '../../utils/extensions.dart';
import '../../utils/haptics.dart';
import '../../utils/immunisation_data.dart';
import '../../widgets/common/animated_card.dart';
import '../../widgets/common/app_dialogs.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/loading_skeleton.dart';

DateTime _dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

String _dateLabel(DateTime d) => DateFormat('d MMM yyyy').format(d);

/// A visit is "due now" for this long after its due date before it reads
/// as overdue — clinics book the visit within a window, not on the exact day.
const int _dueWindowDays = 14;

enum _VisitStatus { complete, dueNow, overdue, upcoming }

_VisitStatus _statusFor(
    ImmunisationVisit visit, DateTime dob, Set<String> givenKeys) {
  if (visit.vaccines.every((v) => givenKeys.contains(v.key))) {
    return _VisitStatus.complete;
  }
  final today = _dayOf(DateTime.now());
  final due = ImmunisationData.dueDateFor(visit, dob);
  if (today.isBefore(due)) return _VisitStatus.upcoming;
  if (today.isBefore(DateTime(due.year, due.month, due.day + _dueWindowDays))) {
    return _VisitStatus.dueNow;
  }
  return _VisitStatus.overdue;
}

/// South African EPI immunisation schedule tracker: tick off each vaccine as
/// it's given, see what's due next from the baby's date of birth.
class ImmunisationsScreen extends ConsumerStatefulWidget {
  const ImmunisationsScreen({super.key});

  @override
  ConsumerState<ImmunisationsScreen> createState() =>
      _ImmunisationsScreenState();
}

class _ImmunisationsScreenState extends ConsumerState<ImmunisationsScreen> {
  Future<void> _onRefresh() async {
    Haptics.lightTap();
    ref.invalidate(immunisationsProvider);
    try {
      await ref.read(immunisationsProvider.future);
    } catch (_) {
      // Errors surface through the AsyncValue in build.
    }
  }

  Future<void> _markGiven(Baby baby, VaccineItem vaccine) async {
    Haptics.selectionClick();
    final result = await showModalBottomSheet<({DateTime date, String notes})>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _MarkGivenSheet(
        vaccine: vaccine,
        earliestDate: _dayOf(baby.dateOfBirth),
      ),
    );
    if (result == null || !mounted) return;

    try {
      await ImmunisationActions.markGiven(
        babyId: baby.id,
        vaccineKey: vaccine.key,
        givenOn: result.date,
        notes: result.notes,
      );
      if (!mounted) return;
      ref.invalidate(immunisationsProvider);
      Haptics.mediumTap();
      context.showSuccessSnackBar('${vaccine.name} marked as given');
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar(
          'Couldn’t save ${vaccine.name}. Check your connection and try again.',
        );
      }
    }
  }

  Future<void> _undo(Baby baby, VaccineItem vaccine, Immunisation record) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Undo ${vaccine.name}?',
      message:
          'Recorded as given on ${_dateLabel(record.givenOn)}. Remove this record?',
      confirmLabel: 'Undo',
      destructive: true,
      icon: Icons.undo_rounded,
    );
    if (!confirmed || !mounted) return;

    try {
      await ImmunisationActions.unmark(
        babyId: baby.id,
        vaccineKey: vaccine.key,
      );
      if (!mounted) return;
      ref.invalidate(immunisationsProvider);
      context.showSuccessSnackBar('${vaccine.name} record removed');
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar(
          'Couldn’t remove ${vaccine.name}. Check your connection and try again.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final baby = ref.watch(selectedBabyProvider);
    final immunisations = ref.watch(immunisationsProvider);

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Immunisations',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: baby == null
            ? const EmptyState(
                icon: Icons.child_care_rounded,
                title: 'No baby selected',
                description: 'Add or select a baby to track immunisations.',
                illustrationType: 'no_baby',
              )
            : RefreshIndicator(
                onRefresh: _onRefresh,
                color: AppColors.primary,
                child: ListView(
                  physics: const BouncingScrollPhysics(
                      parent: AlwaysScrollableScrollPhysics()),
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                  children: [
                    ..._buildBody(baby, immunisations),
                    const SizedBox(height: AppSpacing.xl),
                  ],
                ),
              ),
      ),
    );
  }

  List<Widget> _buildBody(Baby baby, AsyncValue<List<Immunisation>> async) {
    return async.when(
      loading: () => const [
        CardSkeleton(),
        SizedBox(height: AppSpacing.md),
        CardSkeleton(),
        SizedBox(height: AppSpacing.md),
        CardSkeleton(),
      ],
      error: (error, _) => [
        if (error is SchemaNotReadyException)
          _SchemaPendingCard(
            onRefresh: () {
              Haptics.lightTap();
              ref.invalidate(immunisationsProvider);
            },
          )
        else
          EmptyState(
            icon: Icons.cloud_off_rounded,
            title: 'Couldn’t load immunisations',
            description: 'Check your connection and try again.',
            actionLabel: 'Retry',
            onAction: () {
              Haptics.lightTap();
              ref.invalidate(immunisationsProvider);
            },
          ),
      ],
      data: (list) {
        final dob = _dayOf(baby.dateOfBirth);
        final byKey = {for (final i in list) i.vaccineKey: i};
        return [
          _ProgressCard(dob: dob, givenByKey: byKey),
          const SizedBox(height: AppSpacing.lg),
          for (final (i, visit) in ImmunisationData.schedule.indexed) ...[
            if (i > 0) const SizedBox(height: AppSpacing.lg),
            _VisitSection(
              visit: visit,
              index: i,
              dob: dob,
              givenByKey: byKey,
              onMark: (vaccine) => _markGiven(baby, vaccine),
              onUndo: (vaccine, record) => _undo(baby, vaccine, record),
            ),
          ],
        ];
      },
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
// Progress card: x of y done + the next due visit
// ──────────────────────────────────────────────────────────────────────

class _ProgressCard extends StatelessWidget {
  final DateTime dob;
  final Map<String, Immunisation> givenByKey;

  const _ProgressCard({required this.dob, required this.givenByKey});

  @override
  Widget build(BuildContext context) {
    final total = ImmunisationData.totalVaccines;
    final done = ImmunisationData.schedule
        .expand((v) => v.vaccines)
        .where((v) => givenByKey.containsKey(v.key))
        .length;

    // First visit (schedule order) that still has an unticked vaccine.
    ImmunisationVisit? nextVisit;
    for (final visit in ImmunisationData.schedule) {
      if (visit.vaccines.any((v) => !givenByKey.containsKey(v.key))) {
        nextVisit = visit;
        break;
      }
    }

    return AnimatedCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: AppRadius.mdAll,
                  ),
                  child: const Icon(Icons.vaccines_rounded,
                      color: AppColors.primary, size: 24),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SA immunisation schedule',
                        style: TextStyle(
                          color: context.palette.text,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$done of $total vaccines done',
                        style: TextStyle(
                            color: context.palette.muted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            ClipRRect(
              borderRadius: AppRadius.smAll,
              child: LinearProgressIndicator(
                value: total == 0 ? 0 : done / total,
                minHeight: 8,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            if (nextVisit == null)
              const _NextDueBanner(
                color: AppColors.success,
                icon: Icons.verified_rounded,
                text: 'All caught up — every dose is recorded',
              )
            else
              _nextDueFor(nextVisit),
          ],
        ),
      ),
    );
  }

  Widget _nextDueFor(ImmunisationVisit visit) {
    final due = ImmunisationData.dueDateFor(visit, dob);
    return switch (_statusFor(visit, dob, givenByKey.keys.toSet())) {
      _VisitStatus.overdue => _NextDueBanner(
          color: AppColors.error,
          icon: Icons.error_outline_rounded,
          text:
              '${visit.ageLabel} visit overdue since ${_dateLabel(due)}',
        ),
      _VisitStatus.dueNow => _NextDueBanner(
          color: AppColors.warning,
          icon: Icons.notifications_active_rounded,
          text: '${visit.ageLabel} visit due now',
        ),
      _ => _NextDueBanner(
          color: AppColors.info,
          icon: Icons.event_rounded,
          text: 'Next: ${visit.ageLabel} visit · ${_dateLabel(due)}',
        ),
    };
  }
}

class _NextDueBanner extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String text;

  const _NextDueBanner({
    required this.color,
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
// One section per visit: age label + due date, then a row per vaccine
// ──────────────────────────────────────────────────────────────────────

class _VisitSection extends StatelessWidget {
  final ImmunisationVisit visit;
  final int index;
  final DateTime dob;
  final Map<String, Immunisation> givenByKey;
  final void Function(VaccineItem vaccine) onMark;
  final void Function(VaccineItem vaccine, Immunisation record) onUndo;

  const _VisitSection({
    required this.visit,
    required this.index,
    required this.dob,
    required this.givenByKey,
    required this.onMark,
    required this.onUndo,
  });

  @override
  Widget build(BuildContext context) {
    final due = ImmunisationData.dueDateFor(visit, dob);
    final status = _statusFor(visit, dob, givenByKey.keys.toSet());
    // Rows turn warning-tinted only once the visit's 14-day "due now" window
    // has passed — matches the header's overdue logic.
    final pastDue =
        _dayOf(DateTime.now()).isAfter(due.add(const Duration(days: 14)));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  visit.ageLabel,
                  style: TextStyle(
                    color: context.palette.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
              Text(
                'Due ${_dateLabel(due)}',
                style: TextStyle(color: context.palette.muted, fontSize: 12),
              ),
              if (status == _VisitStatus.complete) ...[
                const SizedBox(width: AppSpacing.xs),
                const Icon(Icons.check_circle_rounded,
                    color: AppColors.success, size: 16),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        AnimatedCard(
          index: index,
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
          child: Column(
            children: [
              for (final (i, vaccine) in visit.vaccines.indexed) ...[
                if (i > 0)
                  Divider(
                      height: 1,
                      indent: AppSpacing.md,
                      color: context.palette.border),
                _VaccineRow(
                  vaccine: vaccine,
                  record: givenByKey[vaccine.key],
                  pastDue: pastDue,
                  onMark: () => onMark(vaccine),
                  onUndo: (record) => onUndo(vaccine, record),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _VaccineRow extends StatelessWidget {
  final VaccineItem vaccine;
  final Immunisation? record;
  final bool pastDue;
  final VoidCallback onMark;
  final void Function(Immunisation record) onUndo;

  const _VaccineRow({
    required this.vaccine,
    required this.record,
    required this.pastDue,
    required this.onMark,
    required this.onUndo,
  });

  @override
  Widget build(BuildContext context) {
    final done = record != null;
    final overdue = !done && pastDue;

    return Material(
      color: overdue
          ? AppColors.warning.withValues(alpha: 0.08)
          : Colors.transparent,
      child: InkWell(
        onTap: done ? () => onUndo(record!) : onMark,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: AppSpacing.xs),
            child: Row(
              children: [
                _CheckMark(done: done, overdue: overdue),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        vaccine.name,
                        style: TextStyle(
                          color: context.palette.text,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        vaccine.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: context.palette.muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                if (done)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Given ${DateFormat('d MMM').format(record!.givenOn)}',
                        style: const TextStyle(
                          color: AppColors.success,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Tap to undo',
                        style: TextStyle(
                            color: context.palette.muted, fontSize: 11),
                      ),
                    ],
                  )
                else if (overdue)
                  const Icon(Icons.warning_amber_rounded,
                      color: AppColors.warning, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CheckMark extends StatelessWidget {
  final bool done;
  final bool overdue;

  const _CheckMark({required this.done, required this.overdue});

  @override
  Widget build(BuildContext context) {
    final borderColor = overdue
        ? AppColors.warning
        : context.palette.muted.withValues(alpha: 0.5);
    return AnimatedContainer(
      duration: AppMotion.fast,
      curve: AppMotion.ease,
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: done ? AppColors.success : Colors.transparent,
        shape: BoxShape.circle,
        border: done ? null : Border.all(color: borderColor, width: 2),
      ),
      child: done
          ? const Icon(Icons.check_rounded, color: Colors.white, size: 18)
          : null,
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
// Mark-given bottom sheet: date (defaults to today) + optional notes
// ──────────────────────────────────────────────────────────────────────

class _MarkGivenSheet extends StatefulWidget {
  final VaccineItem vaccine;
  final DateTime earliestDate;

  const _MarkGivenSheet({required this.vaccine, required this.earliestDate});

  @override
  State<_MarkGivenSheet> createState() => _MarkGivenSheetState();
}

class _MarkGivenSheetState extends State<_MarkGivenSheet> {
  late DateTime _givenOn;
  final TextEditingController _notesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final today = _dayOf(DateTime.now());
    _givenOn =
        today.isBefore(widget.earliestDate) ? widget.earliestDate : today;
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    Haptics.lightTap();
    final today = _dayOf(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: _givenOn,
      firstDate: widget.earliestDate,
      lastDate: today.isBefore(widget.earliestDate)
          ? widget.earliestDate
          : today,
    );
    if (picked != null) setState(() => _givenOn = _dayOf(picked));
  }

  void _confirm() {
    Haptics.mediumTap();
    Navigator.of(context)
        .pop((date: _givenOn, notes: _notesController.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Padding(
        padding: AppSpacing.sheet,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.vaccine.name,
              style: TextStyle(
                color: context.palette.text,
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              widget.vaccine.description,
              style: TextStyle(color: context.palette.muted, fontSize: 13),
            ),
            const SizedBox(height: AppSpacing.md),
            InkWell(
              onTap: _pickDate,
              borderRadius: AppRadius.mdAll,
              child: Container(
                height: 52,
                padding:
                    const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                decoration: BoxDecoration(
                  color: context.palette.surface,
                  borderRadius: AppRadius.mdAll,
                  border: Border.all(color: context.palette.border),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.event_rounded,
                        color: AppColors.primary, size: 20),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'Given on ${_dateLabel(_givenOn)}',
                        style: TextStyle(
                          color: context.palette.text,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    Icon(Icons.edit_calendar_rounded,
                        color: context.palette.muted, size: 18),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _notesController,
              maxLines: 3,
              minLines: 1,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'Add notes (optional)',
                hintStyle: TextStyle(
                    color: context.palette.muted.withValues(alpha: 0.6)),
                filled: true,
                fillColor: context.palette.surface,
                border: const OutlineInputBorder(
                  borderRadius: AppRadius.mdAll,
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md, vertical: AppSpacing.sm),
              ),
              style: TextStyle(color: context.palette.text),
            ),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _confirm,
                child: const Text('Confirm'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
// Friendly "database upgrade pending" state
// ──────────────────────────────────────────────────────────────────────

class _SchemaPendingCard extends StatelessWidget {
  final VoidCallback onRefresh;

  const _SchemaPendingCard({required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return AnimatedCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.info.withValues(alpha: 0.12),
                borderRadius: AppRadius.lgAll,
              ),
              child: const Icon(Icons.storage_rounded,
                  color: AppColors.info, size: 26),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'One-time database upgrade pending',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.palette.text,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Diego needs to run the SQL upgrade. Everything else keeps working.',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.palette.muted, fontSize: 13),
            ),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Refresh'),
            ),
          ],
        ),
      ),
    );
  }
}
