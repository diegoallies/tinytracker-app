import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../config/design_tokens.dart';
import '../../config/theme.dart';
import '../../models/care_pack_models.dart';
import '../../providers/baby_provider.dart';
import '../../providers/care_pack_provider.dart';
import '../../utils/care_pack_data.dart';
import '../../utils/extensions.dart';
import '../../utils/haptics.dart';
import '../../widgets/common/animated_card.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/loading_skeleton.dart';

DateTime _dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

/// Accent for a 0–3 cramps/gas level.
Color _levelColor(BuildContext context, int level) {
  return switch (level) {
    0 => context.palette.muted,
    1 => AppColors.success,
    2 => AppColors.warning,
    _ => AppColors.error,
  };
}

const _moods = [
  ('happy', '😊', 'Happy'),
  ('okay', '🙂', 'Okay'),
  ('fussy', '😣', 'Fussy'),
  ('very_fussy', '😭', 'Very fussy'),
];

String _moodEmoji(String? mood) {
  for (final m in _moods) {
    if (m.$1 == mood) return m.$2;
  }
  return '·';
}

/// Digitises the paper "Mood & Activity" + cramps/gas daily journal.
/// One entry per day, editable all day.
class DailyJournalScreen extends ConsumerStatefulWidget {
  const DailyJournalScreen({super.key});

  @override
  ConsumerState<DailyJournalScreen> createState() =>
      _DailyJournalScreenState();
}

class _DailyJournalScreenState extends ConsumerState<DailyJournalScreen> {
  DateTime _date = _dayOf(DateTime.now());
  String? _populatedFor;

  String? _mood;
  int? _cramps;
  int? _gas;
  final TextEditingController _activitiesController = TextEditingController();
  final TextEditingController _newThingsController = TextEditingController();
  final TextEditingController _upsetsController = TextEditingController();
  final TextEditingController _fussyTimesController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  bool _isSaving = false;

  @override
  void dispose() {
    _activitiesController.dispose();
    _newThingsController.dispose();
    _upsetsController.dispose();
    _fussyTimesController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _selectDate(DateTime date) {
    final day = _dayOf(date);
    if (day == _date) return;
    Haptics.selectionClick();
    setState(() => _date = day);
  }

  void _applyJournal(DailyJournal? journal) {
    _mood = journal?.mood;
    _cramps = journal?.cramps;
    _gas = journal?.gas;
    _activitiesController.text = journal?.activities ?? '';
    _newThingsController.text = journal?.newThings ?? '';
    _upsetsController.text = journal?.upsets ?? '';
    _fussyTimesController.text = journal?.fussyTimes ?? '';
    _notesController.text = journal?.notes ?? '';
  }

  Future<void> _save() async {
    final baby = ref.read(selectedBabyProvider);
    if (baby == null) return;

    setState(() => _isSaving = true);
    try {
      await JournalActions.upsert(
        babyId: baby.id,
        date: _date,
        mood: _mood,
        cramps: _cramps,
        gas: _gas,
        fussyTimes: _fussyTimesController.text,
        activities: _activitiesController.text,
        newThings: _newThingsController.text,
        upsets: _upsetsController.text,
        notes: _notesController.text,
      );

      ref.invalidate(journalForDateProvider(_date));
      ref.invalidate(recentJournalsProvider);

      Haptics.mediumTap();
      if (mounted) context.showSuccessSnackBar('Journal saved');
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar(
          'Couldn’t save the journal. Check your connection and try again.',
          onRetry: _save,
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _onRefresh() async {
    Haptics.lightTap();
    ref.invalidate(journalForDateProvider(_date));
    ref.invalidate(recentJournalsProvider);
    try {
      await ref.read(journalForDateProvider(_date).future);
    } catch (_) {
      // Errors surface through the AsyncValue in build.
    }
  }

  @override
  Widget build(BuildContext context) {
    final journalAsync = ref.watch(journalForDateProvider(_date));
    final hydrationKey = '${ref.watch(selectedBabyProvider)?.id}|$_date';

    // Prefill once per selected baby + day, synchronously so this build uses it.
    if (_populatedFor != hydrationKey &&
        journalAsync.hasValue &&
        !journalAsync.isLoading) {
      _populatedFor = hydrationKey;
      _applyJournal(journalAsync.valueOrNull);
    }

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/dashboard'),
        ),
        title: const Text(
          'Daily Journal',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _onRefresh,
          color: AppColors.primary,
          child: ListView(
            physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics()),
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: AppSpacing.xs),
            children: [
              _buildDateSelector(),
              const SizedBox(height: AppSpacing.md),
              ..._buildBody(journalAsync, hydrationKey),
              const SizedBox(height: AppSpacing.xl),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildBody(
      AsyncValue<DailyJournal?> journalAsync, String hydrationKey) {
    if (journalAsync.hasError) {
      final error = journalAsync.error;
      return [
        if (error is SchemaNotReadyException)
          _SchemaPendingCard(
            onRefresh: () {
              Haptics.lightTap();
              ref.invalidate(journalForDateProvider(_date));
            },
          )
        else
          EmptyState(
            icon: Icons.cloud_off_rounded,
            title: 'Couldn’t load the journal',
            description: 'Check your connection and try again.',
            actionLabel: 'Retry',
            onAction: () {
              Haptics.lightTap();
              ref.invalidate(journalForDateProvider(_date));
            },
          ),
      ];
    }

    if (_populatedFor != hydrationKey) {
      return const [
        CardSkeleton(),
        SizedBox(height: AppSpacing.md),
        CardSkeleton(),
        SizedBox(height: AppSpacing.md),
        CardSkeleton(),
      ];
    }

    return [
      _buildMoodCard(),
      const SizedBox(height: AppSpacing.md),
      _buildTummyCard(),
      const SizedBox(height: AppSpacing.md),
      _buildNotesCard(),
      const SizedBox(height: AppSpacing.lg),
      SizedBox(
        height: 52,
        child: ElevatedButton(
          onPressed: _isSaving ? null : _save,
          child: _isSaving
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5, color: Colors.white),
                )
              : const Text('Save Journal'),
        ),
      ),
      const SizedBox(height: AppSpacing.xl),
      _buildRecentDays(),
    ];
  }

  // ── Date selector: yesterday/today chips + 7-day picker ─────────────

  Widget _buildDateSelector() {
    final today = _dayOf(DateTime.now());
    final yesterday = today.subtract(const Duration(days: 1));

    return AnimatedCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              DateFormat('EEEE, MMM d').format(_date),
              style: TextStyle(
                color: context.palette.text,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: _DateChip(
                    label: 'Yesterday',
                    selected: _date == yesterday,
                    onTap: () => _selectDate(yesterday),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: _DateChip(
                    label: 'Today',
                    selected: _date == today,
                    onTap: () => _selectDate(today),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                for (var i = 6; i >= 0; i--) ...[
                  if (i < 6) const SizedBox(width: AppSpacing.xxs + 2),
                  Expanded(
                    child: _DayCell(
                      day: today.subtract(Duration(days: i)),
                      selected: _date == today.subtract(Duration(days: i)),
                      onTap: () =>
                          _selectDate(today.subtract(Duration(days: i))),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Mood ─────────────────────────────────────────────────────────────

  Widget _buildMoodCard() {
    return AnimatedCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Overall mood',
              style: TextStyle(
                color: context.palette.text,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                for (final (i, mood) in _moods.indexed) ...[
                  if (i > 0) const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: _MoodOption(
                      emoji: mood.$2,
                      label: mood.$3,
                      selected: _mood == mood.$1,
                      onTap: () {
                        Haptics.selectionClick();
                        setState(
                            () => _mood = _mood == mood.$1 ? null : mood.$1);
                      },
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Cramps & gas ─────────────────────────────────────────────────────

  Widget _buildTummyCard() {
    return AnimatedCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Cramps & gas',
              style: TextStyle(
                color: context.palette.text,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              '0 = none noticed, 3 = severe',
              style: TextStyle(color: context.palette.muted, fontSize: 12),
            ),
            const SizedBox(height: 14),
            _ScaleRow(
              title: 'Cramps',
              value: _cramps,
              onChanged: (v) => setState(() => _cramps = v),
            ),
            const SizedBox(height: AppSpacing.md),
            _ScaleRow(
              title: 'Gas',
              value: _gas,
              onChanged: (v) => setState(() => _gas = v),
            ),
          ],
        ),
      ),
    );
  }

  // ── Free-text fields ─────────────────────────────────────────────────

  Widget _buildNotesCard() {
    return AnimatedCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'The day in words',
              style: TextStyle(
                color: context.palette.text,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 14),
            _labeledField('Playtime activities', _activitiesController),
            _labeledField(
                'New things he tried or noticed', _newThingsController),
            _labeledField('Anything that upset him', _upsetsController),
            _labeledField('Fussy / crying times', _fussyTimesController),
            _labeledField('Notes', _notesController, isLast: true),
          ],
        ),
      ),
    );
  }

  Widget _labeledField(String label, TextEditingController controller,
      {bool isLast = false}) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: context.palette.muted,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs + 2),
          TextField(
            controller: controller,
            minLines: 1,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: 'Optional',
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
            style: TextStyle(color: context.palette.text, fontSize: 14),
          ),
        ],
      ),
    );
  }

  // ── Recent days strip ────────────────────────────────────────────────

  Widget _buildRecentDays() {
    final recent = ref.watch(recentJournalsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recent days',
          style: TextStyle(
            color: context.palette.text,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        recent.when(
          loading: () => const CardSkeleton(),
          error: (_, _) => Text(
            'Couldn’t load recent journals',
            style: TextStyle(color: context.palette.muted, fontSize: 13),
          ),
          data: (journals) {
            if (journals.isEmpty) {
              return const EmptyState(
                icon: Icons.menu_book_rounded,
                title: 'No journal entries yet',
                description: 'Today’s entry will show up here once saved',
              );
            }
            return Column(
              children: [
                for (final (i, j) in journals.take(7).indexed) ...[
                  if (i > 0) const SizedBox(height: AppSpacing.xs),
                  _RecentDayRow(
                    journal: j,
                    onTap: () => _selectDate(j.journalDate),
                  ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
// Date chips + day cells
// ──────────────────────────────────────────────────────────────────────

class _DateChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _DateChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppMotion.fast,
        height: 44,
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.15)
              : context.palette.surface,
          borderRadius: AppRadius.mdAll,
          border: Border.all(
            color: selected
                ? AppColors.primary
                : context.palette.muted.withValues(alpha: 0.3),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: selected ? AppColors.primary : context.palette.text,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  final DateTime day;
  final bool selected;
  final VoidCallback onTap;

  const _DayCell({
    required this.day,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppMotion.fast,
        height: 54,
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : context.palette.surface,
          borderRadius: AppRadius.mdAll,
          border: Border.all(
            color: selected ? AppColors.primary : context.palette.border,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              DateFormat('E').format(day).substring(0, 1),
              style: TextStyle(
                color: selected
                    ? Colors.white.withValues(alpha: 0.8)
                    : context.palette.muted,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${day.day}',
              style: TextStyle(
                color: selected ? Colors.white : context.palette.text,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
// Mood option
// ──────────────────────────────────────────────────────────────────────

class _MoodOption extends StatelessWidget {
  final String emoji;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _MoodOption({
    required this.emoji,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppMotion.fast,
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.12)
              : context.palette.surface,
          borderRadius: AppRadius.mdAll,
          border: Border.all(
            color: selected
                ? AppColors.primary
                : context.palette.muted.withValues(alpha: 0.25),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 26)),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? AppColors.primary : context.palette.muted,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
// 0–3 scale row (cramps / gas)
// ──────────────────────────────────────────────────────────────────────

class _ScaleRow extends StatelessWidget {
  final String title;
  final int? value;
  final ValueChanged<int?> onChanged;

  const _ScaleRow({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final point = value == null ? null : CarePackData.crampsGasScale[value!];
    final isAlert = point?.alert ?? false;
    final accent = value == null
        ? AppColors.primary
        : (isAlert ? AppColors.error : _levelColor(context, value!));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: context.palette.text,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: [
            for (final p in CarePackData.crampsGasScale) ...[
              if (p.value > 0) const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    Haptics.selectionClick();
                    onChanged(value == p.value ? null : p.value);
                  },
                  child: AnimatedContainer(
                    duration: AppMotion.fast,
                    height: 44,
                    decoration: BoxDecoration(
                      color: value == p.value
                          ? _scaleAccent(context, p).withValues(alpha: 0.15)
                          : context.palette.surface,
                      borderRadius: AppRadius.mdAll,
                      border: Border.all(
                        color: value == p.value
                            ? _scaleAccent(context, p)
                            : context.palette.muted.withValues(alpha: 0.25),
                        width: value == p.value ? 1.5 : 1,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        '${p.value}',
                        style: TextStyle(
                          color: value == p.value
                              ? _scaleAccent(context, p)
                              : context.palette.muted,
                          fontWeight: value == p.value
                              ? FontWeight.w800
                              : FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        if (point != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              if (isAlert) ...[
                const Icon(Icons.warning_amber_rounded,
                    color: AppColors.error, size: 16),
                const SizedBox(width: AppSpacing.xxs),
              ],
              Expanded(
                child: Text(
                  point.label,
                  style: TextStyle(
                    color: accent,
                    fontWeight: isAlert ? FontWeight.w700 : FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Color _scaleAccent(BuildContext context, CareScalePoint p) =>
      p.alert ? AppColors.error : _levelColor(context, p.value);
}

// ──────────────────────────────────────────────────────────────────────
// Recent day row (date, mood emoji, cramps/gas badges)
// ──────────────────────────────────────────────────────────────────────

class _RecentDayRow extends StatelessWidget {
  final DailyJournal journal;
  final VoidCallback onTap;

  const _RecentDayRow({required this.journal, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final today = _dayOf(DateTime.now());
    final day = _dayOf(journal.journalDate);
    final String label;
    if (day == today) {
      label = 'Today';
    } else if (day == today.subtract(const Duration(days: 1))) {
      label = 'Yesterday';
    } else {
      label = DateFormat('EEE, MMM d').format(day);
    }

    return AnimatedCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Text(
              _moodEmoji(journal.mood),
              style: const TextStyle(fontSize: 22),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: context.palette.text,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
          if (journal.cramps != null) ...[
            _LevelBadge(prefix: 'Cramps', level: journal.cramps!),
            const SizedBox(width: AppSpacing.xxs + 2),
          ],
          if (journal.gas != null)
            _LevelBadge(prefix: 'Gas', level: journal.gas!),
          const SizedBox(width: AppSpacing.xs),
          Icon(Icons.chevron_right_rounded,
              color: context.palette.muted, size: 20),
        ],
      ),
    );
  }
}

class _LevelBadge extends StatelessWidget {
  final String prefix;
  final int level;

  const _LevelBadge({required this.prefix, required this.level});

  @override
  Widget build(BuildContext context) {
    final color = _levelColor(context, level);
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs, vertical: AppSpacing.xxs),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: AppRadius.smAll,
      ),
      child: Text(
        '$prefix $level',
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 11,
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
