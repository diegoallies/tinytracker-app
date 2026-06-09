import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../config/design_tokens.dart';
import '../../config/theme.dart';
import '../../providers/prediction_provider.dart';
import '../../services/prediction_service.dart';
import '../common/animated_card.dart';

/// "Next up" — pattern-based predictions for the next feeding and nap,
/// computed from the last week of logs (see PredictionService).
class NextUpCard extends ConsumerWidget {
  const NextUpCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feeding = ref.watch(nextFeedingPredictionProvider).valueOrNull;
    final nap = ref.watch(nextNapPredictionProvider).valueOrNull;

    if (feeding == null && nap == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: AnimatedCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome_rounded,
                    color: AppColors.primary, size: 18),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  'Next up',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                Text(
                  'from his patterns',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                if (feeding != null)
                  Expanded(
                    child: _PredictionTile(
                      icon: Icons.restaurant_rounded,
                      label: 'Feeding',
                      prediction: feeding,
                      tint: AppColors.pastelPinkLight,
                    ),
                  ),
                if (feeding != null && nap != null)
                  const SizedBox(width: AppSpacing.sm),
                if (nap != null)
                  Expanded(
                    child: _PredictionTile(
                      icon: Icons.bedtime_rounded,
                      label: 'Nap',
                      prediction: nap,
                      tint: AppColors.pastelBlueLight,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PredictionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final NextEventPrediction prediction;
  final Color tint;

  const _PredictionTile({
    required this.icon,
    required this.label,
    required this.prediction,
    required this.tint,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final overdue = prediction.isOverdue(now);
    final until = prediction.timeUntil(now);
    final timeLabel = DateFormat('h:mm a').format(prediction.expectedAt);

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.primary.withValues(alpha: 0.10)
            : tint,
        borderRadius: AppRadius.mdAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon,
                  size: 16,
                  color: overdue ? AppColors.warning : AppColors.primary),
              const SizedBox(width: 6),
              Text(label, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            '~$timeLabel',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: overdue ? AppColors.warning : null,
                ),
          ),
          Text(
            overdue ? 'around now' : 'in ${_formatDuration(until)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  static String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h > 0) return m > 0 ? '${h}h ${m}m' : '${h}h';
    return '${m}m';
  }
}
