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
import '../../widgets/common/app_dialogs.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/loading_skeleton.dart';
import '../../widgets/common/swipe_to_dismiss.dart';

/// Accent for a reflux severity: 1-2 settled, 3 caution, 4-5 alert.
Color _severityColor(int severity) {
  if (severity <= 2) return AppColors.success;
  if (severity == 3) return AppColors.warning;
  return AppColors.error;
}

DateTime _dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

String _timeLabel(DateTime loggedAt) {
  final now = DateTime.now();
  final isToday = _dayOf(loggedAt) == _dayOf(now);
  final isYesterday =
      _dayOf(loggedAt) == _dayOf(now.subtract(const Duration(days: 1)));
  final time = DateFormat('h:mm a').format(loggedAt);
  if (isToday) return 'Today, $time';
  if (isYesterday) return 'Yesterday, $time';
  return DateFormat('EEE, MMM d • h:mm a').format(loggedAt);
}

/// Digitises the family's paper "Reflux Tracker": log a spit-up in seconds,
/// see the last 14 days at a glance, and get an automatic weekly summary.
class RefluxScreen extends ConsumerStatefulWidget {
  const RefluxScreen({super.key});

  @override
  ConsumerState<RefluxScreen> createState() => _RefluxScreenState();
}

class _RefluxScreenState extends ConsumerState<RefluxScreen> {
  int _severity = 1;
  bool _painfulCrying = false;
  bool _archingBack = false;
  final TextEditingController _triggerController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  bool _isSaving = false;

  @override
  void dispose() {
    _triggerController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _log() async {
    final baby = ref.read(selectedBabyProvider);
    if (baby == null) return;

    setState(() => _isSaving = true);
    try {
      await RefluxActions.logEvent(
        babyId: baby.id,
        severity: _severity,
        painfulCrying: _painfulCrying,
        archingBack: _archingBack,
        triggerNoticed: _triggerController.text.trim(),
        notes: _notesController.text.trim(),
      );

      if (!mounted) return;
      ref.invalidate(recentRefluxEventsProvider);
      setState(() {
        _severity = 1;
        _painfulCrying = false;
        _archingBack = false;
        _triggerController.clear();
        _notesController.clear();
      });

      Haptics.mediumTap();
      if (mounted) context.showSuccessSnackBar('Reflux event logged');
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar(
          'Couldn’t save the reflux event. Check your connection and try again.',
          onRetry: _log,
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<bool?> _confirmDelete() {
    return showDeleteDialog(context, what: 'reflux event');
  }

  Future<void> _delete(String id) async {
    try {
      await RefluxActions.delete(id);
      if (!mounted) return;
      ref.invalidate(recentRefluxEventsProvider);
      context.showSuccessSnackBar('Reflux event deleted');
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar(
          'Couldn’t delete the reflux event. Check your connection and try again.',
        );
      }
    }
  }

  Future<void> _onRefresh() async {
    Haptics.lightTap();
    ref.invalidate(recentRefluxEventsProvider);
    try {
      await ref.read(recentRefluxEventsProvider.future);
    } catch (_) {
      // Errors surface through the AsyncValue in build.
    }
  }

  @override
  Widget build(BuildContext context) {
    final events = ref.watch(recentRefluxEventsProvider);

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/dashboard'),
        ),
        title: const Text(
          'Reflux',
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
              _buildQuickLogCard(),
              const SizedBox(height: AppSpacing.md),
              ..._buildDataSections(events),
              const SizedBox(height: AppSpacing.xl),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildDataSections(AsyncValue<List<RefluxEvent>> events) {
    return events.when(
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
              ref.invalidate(recentRefluxEventsProvider);
            },
          )
        else
          EmptyState(
            icon: Icons.cloud_off_rounded,
            title: 'Couldn’t load reflux history',
            description: 'Check your connection and try again.',
            actionLabel: 'Retry',
            onAction: () {
              Haptics.lightTap();
              ref.invalidate(recentRefluxEventsProvider);
            },
          ),
      ],
      data: (list) => [
        _WeeklySummaryCard(events: list),
        const SizedBox(height: AppSpacing.md),
        _sectionHeader('Last 14 days'),
        const SizedBox(height: AppSpacing.sm),
        _FourteenDayStrip(events: list),
        const SizedBox(height: AppSpacing.lg),
        _sectionHeader('Recent events'),
        const SizedBox(height: AppSpacing.sm),
        if (list.isEmpty)
          const EmptyState(
            icon: Icons.sentiment_satisfied_alt_rounded,
            title: 'No reflux events yet',
            description: 'Log a spit-up above - it takes a few seconds',
          )
        else
          for (final (i, event) in list.indexed) ...[
            if (i > 0) const SizedBox(height: AppSpacing.xs),
            _EventTile(
              event: event,
              onConfirmDismiss: _confirmDelete,
              onDismissed: () => _delete(event.id),
            ),
          ],
      ],
    );
  }

  Widget _sectionHeader(String title) {
    return Text(
      title,
      style: TextStyle(
        color: context.palette.text,
        fontWeight: FontWeight.w700,
        fontSize: 18,
      ),
    );
  }

  Widget _buildQuickLogCard() {
    final point = CarePackData.refluxSeverity[_severity - 1];
    final color = _severityColor(_severity);

    return AnimatedCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Log a spit-up',
              style: TextStyle(
                color: context.palette.text,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'How bad was it? 1 = small spit-up, 5 = severe',
              style: TextStyle(color: context.palette.muted, fontSize: 12),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                for (final p in CarePackData.refluxSeverity) ...[
                  if (p.value > 1) const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: _SeverityPill(
                      value: p.value,
                      selected: _severity == p.value,
                      color: _severityColor(p.value),
                      onTap: () {
                        Haptics.selectionClick();
                        setState(() => _severity = p.value);
                      },
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            AnimatedSwitcher(
              duration: AppMotion.fast,
              child: Text(
                point.label,
                key: ValueKey(_severity),
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
            if (_severity == 5) ...[
              const SizedBox(height: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.1),
                  borderRadius: AppRadius.mdAll,
                  border: Border.all(
                      color: AppColors.error.withValues(alpha: 0.4)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        color: AppColors.error, size: 18),
                    SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        'Severity 5 - tell the parents the same day.',
                        style: TextStyle(
                          color: AppColors.error,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                _ToggleChip(
                  label: 'Painful crying',
                  icon: Icons.sentiment_very_dissatisfied_rounded,
                  selected: _painfulCrying,
                  onTap: () {
                    Haptics.selectionClick();
                    setState(() => _painfulCrying = !_painfulCrying);
                  },
                ),
                _ToggleChip(
                  label: 'Arching back / legs up',
                  icon: Icons.accessibility_new_rounded,
                  selected: _archingBack,
                  onTap: () {
                    Haptics.selectionClick();
                    setState(() => _archingBack = !_archingBack);
                  },
                ),
              ],
            ),
            const SizedBox(height: 14),
            _buildTextField(_triggerController, 'Trigger noticed (optional)'),
            const SizedBox(height: AppSpacing.xs + 2),
            _buildTextField(_notesController, 'Add notes (optional)',
                maxLines: 3),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _log,
                child: _isSaving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: Colors.white),
                      )
                    : const Text('Log Reflux'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String hint,
      {int maxLines = 1}) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      minLines: 1,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle:
            TextStyle(color: context.palette.muted.withValues(alpha: 0.6)),
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
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
// Severity pill (1-5)
// ──────────────────────────────────────────────────────────────────────

class _SeverityPill extends StatelessWidget {
  final int value;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _SeverityPill({
    required this.value,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppMotion.fast,
        curve: AppMotion.ease,
        height: 48,
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.15)
              : context.palette.surface,
          borderRadius: AppRadius.mdAll,
          border: Border.all(
            color: selected
                ? color
                : context.palette.muted.withValues(alpha: 0.25),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Center(
          child: Text(
            '$value',
            style: TextStyle(
              color: selected ? color : context.palette.muted,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              fontSize: 17,
            ),
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
// Toggle chip ("Painful crying", "Arching back / legs up")
// ──────────────────────────────────────────────────────────────────────

class _ToggleChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ToggleChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppMotion.fast,
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
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
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: selected ? AppColors.primary : context.palette.muted,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: selected ? AppColors.primary : context.palette.text,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
// 14-day compact strip: one cell per day, colored by max severity
// ──────────────────────────────────────────────────────────────────────

class _FourteenDayStrip extends StatelessWidget {
  final List<RefluxEvent> events;

  const _FourteenDayStrip({required this.events});

  @override
  Widget build(BuildContext context) {
    final today = _dayOf(DateTime.now());
    final counts = <DateTime, int>{};
    final maxSeverity = <DateTime, int>{};
    for (final e in events) {
      final day = _dayOf(e.loggedAt);
      counts[day] = (counts[day] ?? 0) + 1;
      if (e.severity > (maxSeverity[day] ?? 0)) {
        maxSeverity[day] = e.severity;
      }
    }

    return AnimatedCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Row(
          children: [
            for (var i = 13; i >= 0; i--)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1.5),
                  child: _dayCell(
                    context,
                    today.subtract(Duration(days: i)),
                    counts[today.subtract(Duration(days: i))] ?? 0,
                    maxSeverity[today.subtract(Duration(days: i))] ?? 0,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _dayCell(BuildContext context, DateTime day, int count, int maxSev) {
    final hasEvents = count > 0;
    final color = hasEvents ? _severityColor(maxSev) : context.palette.muted;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: 34,
          decoration: BoxDecoration(
            color: hasEvents
                ? color.withValues(alpha: 0.18)
                : context.palette.surface,
            borderRadius: AppRadius.smAll,
            border: Border.all(
              color: hasEvents
                  ? color.withValues(alpha: 0.5)
                  : context.palette.border,
            ),
          ),
          child: Center(
            child: hasEvents
                ? Text(
                    '$count',
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  )
                : null,
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          DateFormat('E').format(day).substring(0, 1),
          style: TextStyle(color: context.palette.muted, fontSize: 10),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
// Weekly auto-summary: avg spit-ups/day + painful episodes, vs last week
// ──────────────────────────────────────────────────────────────────────

class _WeeklySummaryCard extends StatelessWidget {
  final List<RefluxEvent> events;

  const _WeeklySummaryCard({required this.events});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final weekAgo = now.subtract(const Duration(days: 7));
    final thisWeek =
        events.where((e) => e.loggedAt.isAfter(weekAgo)).toList();
    final prevWeek =
        events.where((e) => !e.loggedAt.isAfter(weekAgo)).toList();

    final avgPerDay = (thisWeek.length / 7).toStringAsFixed(1);
    final painful = thisWeek.where((e) => e.painfulCrying).length;

    final (trendLabel, trendColor, trendIcon) =
        switch (thisWeek.length.compareTo(prevWeek.length)) {
      < 0 => ('Better', AppColors.success, Icons.trending_down_rounded),
      > 0 => ('Worse', AppColors.error, Icons.trending_up_rounded),
      _ => ('Same', context.palette.muted, Icons.trending_flat_rounded),
    };

    return AnimatedCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'This week',
                  style: TextStyle(
                    color: context.palette.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs + 2, vertical: AppSpacing.xxs),
                  decoration: BoxDecoration(
                    color: trendColor.withValues(alpha: 0.12),
                    borderRadius: AppRadius.lgAll,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(trendIcon, size: 14, color: trendColor),
                      const SizedBox(width: AppSpacing.xxs),
                      Text(
                        '$trendLabel vs last week',
                        style: TextStyle(
                          color: trendColor,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _stat(context, avgPerDay, 'Avg spit-ups / day'),
                ),
                Expanded(
                  child: _stat(
                    context,
                    '$painful',
                    'Painful episodes',
                    color: painful > 0 ? AppColors.error : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${thisWeek.length} this week · ${prevWeek.length} last week',
              style: TextStyle(color: context.palette.muted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(BuildContext context, String value, String label,
      {Color? color}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: TextStyle(
            color: color ?? AppColors.primary,
            fontWeight: FontWeight.w800,
            fontSize: 24,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(color: context.palette.muted, fontSize: 12),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
// Recent event row (time, severity badge, flags, trigger)
// ──────────────────────────────────────────────────────────────────────

class _EventTile extends StatelessWidget {
  final RefluxEvent event;
  final Future<bool?> Function() onConfirmDismiss;
  final VoidCallback onDismissed;

  const _EventTile({
    required this.event,
    required this.onConfirmDismiss,
    required this.onDismissed,
  });

  @override
  Widget build(BuildContext context) {
    final color = _severityColor(event.severity);
    final badges = <(String, Color)>[
      if (event.painfulCrying) ('Painful crying', AppColors.error),
      if (event.archingBack) ('Arching back', AppColors.warning),
      if (event.triggerNoticed != null)
        ('Trigger: ${event.triggerNoticed}', AppColors.info),
    ];

    return SwipeToDismiss(
      itemId: event.id,
      onConfirmDismiss: onConfirmDismiss,
      onDismissed: onDismissed,
      child: AnimatedCard(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: AppRadius.mdAll,
                ),
                child: Center(
                  child: Text(
                    '${event.severity}',
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _timeLabel(event.loggedAt),
                      style: TextStyle(
                        color: context.palette.text,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      CarePackData.refluxSeverity[event.severity - 1].label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: context.palette.muted, fontSize: 12),
                    ),
                    if (badges.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: AppSpacing.xxs + 2,
                        runSpacing: AppSpacing.xxs,
                        children: [
                          for (final (label, badgeColor) in badges)
                            _MiniBadge(label: label, color: badgeColor),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _MiniBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs, vertical: AppSpacing.xxs),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: AppRadius.smAll,
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
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
