import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/design_tokens.dart';
import '../../config/theme.dart';
import '../../providers/baby_provider.dart';
import '../../providers/trends_provider.dart';
import '../../widgets/common/animated_card.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/loading_skeleton.dart';

const _weekdayInitials = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

/// Accent for a reflux severity: 1–2 settled, 3 caution, 4–5 alert.
Color _severityColor(int severity) {
  if (severity <= 2) return AppColors.success;
  if (severity == 3) return AppColors.warning;
  return AppColors.error;
}

String _signed(double v, {int decimals = 1}) =>
    '${v < 0 ? '-' : '+'}${v.abs().toStringAsFixed(decimals)}';

String _formatMinutes(int minutes) =>
    minutes < 60 ? '${minutes}m' : '${minutes ~/ 60}h ${minutes % 60}m';

/// Grid/axis step that keeps roughly 3–5 lines on screen.
double _niceInterval(double maxY, List<int> steps) {
  for (final step in steps) {
    if (maxY / step <= 5) return step.toDouble();
  }
  return steps.last * 2.0;
}

/// 14-day charts of feeding, sleep, nappies and reflux with
/// week-over-week deltas.
class TrendsScreen extends ConsumerWidget {
  const TrendsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final baby = ref.watch(selectedBabyProvider);
    final trendsAsync = ref.watch(trendsDataProvider);

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/dashboard'),
        ),
        title: const Text(
          'Trends',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: baby == null
            ? const EmptyState(
                icon: Icons.child_care_rounded,
                title: 'No baby selected',
                description: 'Add or select a baby to see trends.',
                illustrationType: 'no_baby',
              )
            : RefreshIndicator(
                color: AppColors.primary,
                onRefresh: () async {
                  ref.invalidate(trendsDataProvider);
                  try {
                    await ref.read(trendsDataProvider.future);
                  } catch (_) {
                    // Errors surface through the AsyncValue in build.
                  }
                },
                child: ListView(
                  physics: const BouncingScrollPhysics(
                      parent: AlwaysScrollableScrollPhysics()),
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                  children: _buildSections(ref, trendsAsync),
                ),
              ),
      ),
    );
  }

  List<Widget> _buildSections(WidgetRef ref, AsyncValue<TrendsData> async) {
    return async.when(
      loading: () => const [
        CardSkeleton(),
        SizedBox(height: AppSpacing.md),
        CardSkeleton(),
        SizedBox(height: AppSpacing.md),
        CardSkeleton(),
        SizedBox(height: AppSpacing.md),
        CardSkeleton(),
      ],
      error: (error, _) => [
        EmptyState(
          icon: Icons.cloud_off_rounded,
          title: 'Couldn’t load trends',
          description: 'Check your connection and try again.',
          actionLabel: 'Retry',
          onAction: () => ref.invalidate(trendsDataProvider),
        ),
      ],
      data: (data) => [
        _FeedingCard(data: data),
        const SizedBox(height: AppSpacing.md),
        _SleepCard(data: data),
        const SizedBox(height: AppSpacing.md),
        _NappiesCard(data: data),
        const SizedBox(height: AppSpacing.md),
        _RefluxCard(data: data),
        const SizedBox(height: AppSpacing.xl),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Shared chart pieces
// ---------------------------------------------------------------------------

FlTitlesData _chartTitles(
  BuildContext context,
  List<TrendsDayEntry> days, {
  String Function(double value)? leftLabel,
  double leftInterval = 1,
}) {
  return FlTitlesData(
    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    bottomTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 22,
        interval: 1,
        getTitlesWidget: (value, meta) {
          final i = value.toInt();
          if (i < 0 || i >= days.length) return const SizedBox.shrink();
          final isToday = i == days.length - 1;
          return Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xxs),
            child: Text(
              _weekdayInitials[days[i].day.weekday - 1],
              style: TextStyle(
                fontSize: 10,
                fontWeight: isToday ? FontWeight.w800 : FontWeight.w500,
                color: isToday ? AppColors.primary : context.palette.muted,
              ),
            ),
          );
        },
      ),
    ),
    leftTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: leftLabel != null,
        reservedSize: 32,
        interval: leftInterval,
        getTitlesWidget: (value, meta) => Text(
          leftLabel?.call(value) ?? '',
          style: TextStyle(fontSize: 9, color: context.palette.muted),
          textAlign: TextAlign.right,
        ),
      ),
    ),
  );
}

FlGridData _chartGrid(BuildContext context, double interval) {
  return FlGridData(
    show: true,
    drawVerticalLine: false,
    horizontalInterval: interval,
    getDrawingHorizontalLine: (_) =>
        FlLine(color: context.palette.border, strokeWidth: 1),
  );
}

BarTouchData _chartTouch(String Function(TrendsDayEntry day) label,
    List<TrendsDayEntry> days) {
  return BarTouchData(
    touchTooltipData: BarTouchTooltipData(
      getTooltipColor: (_) => AppColors.text,
      tooltipRoundedRadius: 10,
      getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem(
        label(days[group.x]),
        const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    ),
  );
}

class _CardTitle extends StatelessWidget {
  const _CardTitle({
    required this.icon,
    required this.color,
    required this.title,
  });

  final IconData icon;
  final Color color;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: AppRadius.mdAll,
          ),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: AppSpacing.xs),
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: context.palette.text,
          ),
        ),
        const Spacer(),
        Text(
          'Last 14 days',
          style: TextStyle(fontSize: 11, color: context.palette.muted),
        ),
      ],
    );
  }
}

enum _DeltaTone { neutral, upIsGood, downIsGood }

/// Week-over-week pill: direction arrow + label, coloured by whether the
/// change is an improvement (or neutral when direction has no judgement).
class _DeltaChip extends StatelessWidget {
  const _DeltaChip({
    required this.delta,
    required this.label,
    required this.tone,
  });

  final double delta;
  final String label;
  final _DeltaTone tone;

  @override
  Widget build(BuildContext context) {
    final flat = delta.abs() < 0.05;
    final up = delta > 0;

    final Color color;
    if (flat) {
      color = context.palette.muted;
    } else {
      color = switch (tone) {
        _DeltaTone.neutral => AppColors.primary,
        _DeltaTone.upIsGood => up ? AppColors.success : AppColors.error,
        _DeltaTone.downIsGood => up ? AppColors.error : AppColors.success,
      };
    }
    final icon = flat
        ? Icons.trending_flat_rounded
        : (up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded);

    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs, vertical: AppSpacing.xxs),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: AppRadius.smAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({
    required this.statLabel,
    required this.statValue,
    required this.chips,
  });

  final String statLabel;
  final String statValue;
  final List<Widget> chips;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '$statLabel  ',
                style:
                    TextStyle(fontSize: 12, color: context.palette.muted),
              ),
              TextSpan(
                text: statValue,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: context.palette.text,
                ),
              ),
            ],
          ),
        ),
        ...chips,
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Feeding
// ---------------------------------------------------------------------------

class _FeedingCard extends StatelessWidget {
  const _FeedingCard({required this.data});

  final TrendsData data;

  @override
  Widget build(BuildContext context) {
    final days = data.days;
    final maxCount =
        days.fold<int>(0, (m, d) => d.feedsCount > m ? d.feedsCount : m);
    final maxY = maxCount == 0 ? 4.0 : maxCount * 1.25;
    final interval = _niceInterval(maxY, const [1, 2, 5, 10, 20]);
    final avgMl = data.avgMlPerFeed.current;

    return AnimatedCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle(
            icon: Icons.restaurant_rounded,
            color: AppColors.primary,
            title: 'Feeding',
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 160,
            child: BarChart(
              BarChartData(
                maxY: maxY,
                gridData: _chartGrid(context, interval),
                titlesData: _chartTitles(
                  context,
                  days,
                  leftLabel: (v) => v.toStringAsFixed(0),
                  leftInterval: interval,
                ),
                borderData: FlBorderData(show: false),
                barTouchData: _chartTouch(
                  (d) => d.feedsCount == 1 ? '1 feed' : '${d.feedsCount} feeds',
                  days,
                ),
                barGroups: [
                  for (final (i, d) in days.indexed)
                    BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: d.feedsCount.toDouble(),
                          width: 12,
                          color: i == days.length - 1
                              ? AppColors.primary
                              : AppColors.primary.withValues(alpha: 0.55),
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(4)),
                        ),
                      ],
                    ),
                ],
              ),
              duration: AppMotion.normal,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _StatRow(
            statLabel: 'Avg per feed',
            statValue: avgMl > 0 ? '${avgMl.round()} ml' : '—',
            chips: [
              // More or fewer feeds isn't good or bad — show direction only.
              _DeltaChip(
                delta: data.feedsPerDay.delta,
                label: '${_signed(data.feedsPerDay.delta)} feeds/day',
                tone: _DeltaTone.neutral,
              ),
              _DeltaChip(
                delta: data.avgMlPerFeed.delta,
                label:
                    '${_signed(data.avgMlPerFeed.delta, decimals: 0)} ml/feed',
                tone: _DeltaTone.neutral,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sleep
// ---------------------------------------------------------------------------

class _SleepCard extends StatelessWidget {
  const _SleepCard({required this.data});

  final TrendsData data;

  @override
  Widget build(BuildContext context) {
    final days = data.days;
    final maxMinutes =
        days.fold<int>(0, (m, d) => d.sleepMinutes > m ? d.sleepMinutes : m);
    final maxY = maxMinutes == 0 ? 240.0 : maxMinutes * 1.25;
    final interval = _niceInterval(maxY, const [60, 120, 180, 240, 360]);
    final longest = days.fold<int>(
        0, (m, d) => d.longestSleepMinutes > m ? d.longestSleepMinutes : m);

    return AnimatedCard(
      index: 1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle(
            icon: Icons.nightlight_round,
            color: AppColors.info,
            title: 'Sleep',
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 160,
            child: BarChart(
              BarChartData(
                maxY: maxY,
                gridData: _chartGrid(context, interval),
                titlesData: _chartTitles(
                  context,
                  days,
                  leftLabel: (v) => '${(v / 60).round()}h',
                  leftInterval: interval,
                ),
                borderData: FlBorderData(show: false),
                barTouchData:
                    _chartTouch((d) => _formatMinutes(d.sleepMinutes), days),
                barGroups: [
                  for (final (i, d) in days.indexed)
                    BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: d.sleepMinutes.toDouble(),
                          width: 12,
                          color: i == days.length - 1
                              ? AppColors.info
                              : AppColors.info.withValues(alpha: 0.55),
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(4)),
                        ),
                      ],
                    ),
                ],
              ),
              duration: AppMotion.normal,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _StatRow(
            statLabel: 'Longest stretch',
            statValue: longest > 0 ? _formatMinutes(longest) : '—',
            chips: [
              _DeltaChip(
                delta: data.sleepMinutesPerDay.delta,
                label:
                    '${_signed(data.sleepMinutesPerDay.delta, decimals: 0)} min/day',
                tone: _DeltaTone.upIsGood,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Nappies
// ---------------------------------------------------------------------------

class _NappiesCard extends StatelessWidget {
  const _NappiesCard({required this.data});

  final TrendsData data;

  static const _wetColor = AppColors.info;
  static const _dirtyColor = AppColors.poopBrown;

  @override
  Widget build(BuildContext context) {
    final days = data.days;
    final maxCount = days.fold<int>(
        0, (m, d) => d.wetCount + d.dirtyCount > m ? d.wetCount + d.dirtyCount : m);
    final maxY = maxCount == 0 ? 4.0 : maxCount * 1.25;
    final interval = _niceInterval(maxY, const [1, 2, 5, 10, 20]);

    return AnimatedCard(
      index: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle(
            icon: Icons.water_drop_rounded,
            color: AppColors.warning,
            title: 'Nappies',
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 160,
            child: BarChart(
              BarChartData(
                maxY: maxY,
                gridData: _chartGrid(context, interval),
                titlesData: _chartTitles(
                  context,
                  days,
                  leftLabel: (v) => v.toStringAsFixed(0),
                  leftInterval: interval,
                ),
                borderData: FlBorderData(show: false),
                barTouchData: _chartTouch(
                  (d) => '${d.wetCount} wet • ${d.dirtyCount} dirty',
                  days,
                ),
                barGroups: [
                  for (final (i, d) in days.indexed)
                    BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: (d.wetCount + d.dirtyCount).toDouble(),
                          width: 12,
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(4)),
                          rodStackItems: [
                            BarChartRodStackItem(
                                0, d.wetCount.toDouble(), _wetColor),
                            BarChartRodStackItem(
                              d.wetCount.toDouble(),
                              (d.wetCount + d.dirtyCount).toDouble(),
                              _dirtyColor,
                            ),
                          ],
                        ),
                      ],
                    ),
                ],
              ),
              duration: AppMotion.normal,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          const Row(
            children: [
              _LegendDot(color: _wetColor, label: 'Wet'),
              SizedBox(width: AppSpacing.md),
              _LegendDot(color: _dirtyColor, label: 'Dirty'),
            ],
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: AppSpacing.xxs),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: context.palette.muted),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Reflux
// ---------------------------------------------------------------------------

class _RefluxCard extends StatelessWidget {
  const _RefluxCard({required this.data});

  final TrendsData data;

  @override
  Widget build(BuildContext context) {
    final days = data.days;

    return AnimatedCard(
      index: 3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle(
            icon: Icons.sentiment_neutral_rounded,
            color: AppColors.error,
            title: 'Reflux',
          ),
          const SizedBox(height: AppSpacing.md),
          if (!data.hasRefluxData)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Center(
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: AppColors.pastelPurple.withValues(alpha: 0.3),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.sentiment_satisfied_alt_rounded,
                        size: 28,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'No reflux data yet',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: context.palette.text,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      'Spit-ups you log will show up here.',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.palette.muted,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            _buildChart(context, days),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // Fewer reflux events week-over-week means improving.
                _DeltaChip(
                  delta: data.refluxPerDay.delta,
                  label: '${_signed(data.refluxPerDay.delta)} events/day',
                  tone: _DeltaTone.downIsGood,
                ),
                const _LegendDot(color: AppColors.success, label: 'Mild'),
                const _LegendDot(color: AppColors.warning, label: 'Moderate'),
                const _LegendDot(color: AppColors.error, label: 'Severe'),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildChart(BuildContext context, List<TrendsDayEntry> days) {
    final maxCount =
        days.fold<int>(0, (m, d) => d.refluxCount > m ? d.refluxCount : m);
    final maxY = maxCount == 0 ? 4.0 : maxCount * 1.25;
    final interval = _niceInterval(maxY, const [1, 2, 5, 10, 20]);

    return SizedBox(
      height: 160,
      child: BarChart(
        BarChartData(
          maxY: maxY,
          gridData: _chartGrid(context, interval),
          titlesData: _chartTitles(
            context,
            days,
            leftLabel: (v) => v.toStringAsFixed(0),
            leftInterval: interval,
          ),
          borderData: FlBorderData(show: false),
          barTouchData: _chartTouch(
            (d) => d.refluxCount == 0
                ? 'No events'
                : '${d.refluxCount} event${d.refluxCount == 1 ? '' : 's'} • max severity ${d.maxRefluxSeverity}',
            days,
          ),
          barGroups: [
            for (final (i, d) in days.indexed)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: d.refluxCount.toDouble(),
                    width: 12,
                    color: d.refluxCount == 0
                        ? context.palette.border
                        : _severityColor(d.maxRefluxSeverity),
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(4)),
                  ),
                ],
              ),
          ],
        ),
        duration: AppMotion.normal,
      ),
    );
  }
}
