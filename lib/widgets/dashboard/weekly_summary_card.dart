import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../config/theme.dart';
import '../../models/weekly_summary.dart';
import '../../providers/weekly_summary_provider.dart';
import '../common/loading_skeleton.dart';

class WeeklySummaryCard extends ConsumerWidget {
  const WeeklySummaryCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(weeklySummaryProvider);

    return summaryAsync.when(
      data: (summary) {
        if (summary == null) return const SizedBox.shrink();
        return _buildCard(summary);
      },
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: CardSkeleton(),
      ),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildCard(WeeklySummary summary) {
    final now = DateTime.now();
    final weekStart = now.subtract(const Duration(days: 7));
    final dateRange = '${DateFormat('MMM d').format(weekStart)} - ${DateFormat('MMM d').format(now)}';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFF3E8FF), Color(0xFFE8D5F5)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.1),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.bar_chart_rounded, color: AppColors.primary, size: 22),
                const SizedBox(width: 8),
                const Text(
                  'This Week',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppColors.text),
                ),
                const Spacer(),
                Text(
                  dateRange,
                  style: TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _SummaryRow(
              icon: Icons.restaurant_rounded,
              iconColor: const Color(0xFFE91E63),
              label: 'Feeds',
              value: '${summary.feedCount}',
              trend: summary.feedTrend,
              changeLabel: summary.feedChangePercent,
            ),
            const SizedBox(height: 12),
            _SummaryRow(
              icon: Icons.water_drop_rounded,
              iconColor: const Color(0xFFFF9800),
              label: 'Diapers',
              value: '${summary.diaperCount}',
              trend: summary.diaperTrend,
              changeLabel: summary.diaperChangePercent,
            ),
            const SizedBox(height: 12),
            _SummaryRow(
              icon: Icons.nightlight_round,
              iconColor: const Color(0xFF2196F3),
              label: 'Sleep',
              value: '${summary.sleepMinutes ~/ 60}h ${summary.sleepMinutes % 60}m',
              trend: summary.sleepTrend,
              changeLabel: summary.sleepChangePercent,
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _MiniStat(label: 'Avg feeds/day', value: summary.avgFeedsPerDay.toStringAsFixed(1)),
                  Container(width: 1, height: 24, color: AppColors.muted.withValues(alpha: 0.2)),
                  _MiniStat(label: 'Avg sleep/day', value: '${summary.avgDailySleepHours.toStringAsFixed(1)}h'),
                  Container(width: 1, height: 24, color: AppColors.muted.withValues(alpha: 0.2)),
                  _MiniStat(label: 'Avg diapers/day', value: summary.avgDiapersPerDay.toStringAsFixed(1)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final TrendDirection trend;
  final String changeLabel;

  const _SummaryRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.trend,
    required this.changeLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: iconColor),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(fontSize: 14, color: AppColors.text)),
        const Spacer(),
        Text(
          value,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.text),
        ),
        const SizedBox(width: 10),
        _TrendBadge(trend: trend, label: changeLabel),
      ],
    );
  }
}

class _TrendBadge extends StatelessWidget {
  final TrendDirection trend;
  final String label;

  const _TrendBadge({required this.trend, required this.label});

  @override
  Widget build(BuildContext context) {
    final color = switch (trend) {
      TrendDirection.up => AppColors.success,
      TrendDirection.down => AppColors.error,
      TrendDirection.same => AppColors.muted,
    };
    final icon = switch (trend) {
      TrendDirection.up => Icons.trending_up_rounded,
      TrendDirection.down => Icons.trending_down_rounded,
      TrendDirection.same => Icons.trending_flat_rounded,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 3),
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;

  const _MiniStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.text)),
        Text(label, style: TextStyle(fontSize: 10, color: AppColors.muted)),
      ],
    );
  }
}
