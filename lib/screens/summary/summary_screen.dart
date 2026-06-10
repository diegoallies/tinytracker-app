import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/theme.dart';
import '../../providers/baby_provider.dart';
import '../../services/ai_service.dart';
import '../../services/supabase_service.dart';
import '../../utils/date_utils.dart';
import '../../utils/extensions.dart';
import '../../widgets/common/animated_card.dart';
import '../../widgets/common/loading_skeleton.dart';

class SummaryScreen extends ConsumerStatefulWidget {
  const SummaryScreen({super.key});

  @override
  ConsumerState<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends ConsumerState<SummaryScreen> {
  String? _aiSummary;
  bool _isLoadingSummary = false;
  bool _isLoadingStats = true;

  int _todayFeedings = 0;
  int _yesterdayFeedings = 0;
  int _todayDiapers = 0;
  int _yesterdayDiapers = 0;
  int _todaySleepMinutes = 0;
  int _yesterdaySleepMinutes = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  Future<void> _loadData() async {
    await Future.wait([
      _loadStats(),
      _loadAiSummary(),
    ]);
  }

  Future<void> _loadStats() async {
    final baby = ref.read(selectedBabyProvider);
    if (baby == null) return;

    setState(() => _isLoadingStats = true);

    try {
      final supabase = SupabaseService.client;
      final todayStart = AppDateUtils.todayStart;
      final yesterdayStart = AppDateUtils.yesterdayStart;
      final yesterdayEnd = AppDateUtils.yesterdayEnd;
      final now = DateTime.now().toUtc().toIso8601String();

      // Fetch today's data
      final todayFeedingsResult = await supabase
          .from('feedings')
          .select('id')
          .eq('baby_id', baby.id)
          .isFilter('deleted_at', null)
          .gte('created_at', todayStart.toUtc().toIso8601String())
          .lte('created_at', now);

      final todayDiapersResult = await supabase
          .from('diapers')
          .select('id')
          .eq('baby_id', baby.id)
          .isFilter('deleted_at', null)
          .gte('created_at', todayStart.toUtc().toIso8601String())
          .lte('created_at', now);

      final todaySleepsResult = await supabase
          .from('sleeps')
          .select('duration_minutes')
          .eq('baby_id', baby.id)
          .isFilter('deleted_at', null)
          .gte('created_at', todayStart.toUtc().toIso8601String())
          .lte('created_at', now);

      // Fetch yesterday's data
      final yesterdayFeedingsResult = await supabase
          .from('feedings')
          .select('id')
          .eq('baby_id', baby.id)
          .isFilter('deleted_at', null)
          .gte('created_at', yesterdayStart.toUtc().toIso8601String())
          .lte('created_at', yesterdayEnd.toUtc().toIso8601String());

      final yesterdayDiapersResult = await supabase
          .from('diapers')
          .select('id')
          .eq('baby_id', baby.id)
          .isFilter('deleted_at', null)
          .gte('created_at', yesterdayStart.toUtc().toIso8601String())
          .lte('created_at', yesterdayEnd.toUtc().toIso8601String());

      final yesterdaySleepsResult = await supabase
          .from('sleeps')
          .select('duration_minutes')
          .eq('baby_id', baby.id)
          .isFilter('deleted_at', null)
          .gte('created_at', yesterdayStart.toUtc().toIso8601String())
          .lte('created_at', yesterdayEnd.toUtc().toIso8601String());

      // Calculate sleep totals
      int todaySleep = 0;
      for (final row in todaySleepsResult) {
        todaySleep += (row['duration_minutes'] as num?)?.toInt() ?? 0;
      }

      int yesterdaySleep = 0;
      for (final row in yesterdaySleepsResult) {
        yesterdaySleep += (row['duration_minutes'] as num?)?.toInt() ?? 0;
      }

      if (mounted) {
        setState(() {
          _todayFeedings = todayFeedingsResult.length;
          _yesterdayFeedings = yesterdayFeedingsResult.length;
          _todayDiapers = todayDiapersResult.length;
          _yesterdayDiapers = yesterdayDiapersResult.length;
          _todaySleepMinutes = todaySleep;
          _yesterdaySleepMinutes = yesterdaySleep;
          _isLoadingStats = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingStats = false);
        context.showErrorSnackBar(
          'Couldn’t load today’s stats. Check your connection and try again.',
          onRetry: _loadStats,
        );
      }
    }
  }

  Future<void> _loadAiSummary({bool forceRefresh = false}) async {
    final baby = ref.read(selectedBabyProvider);
    if (baby == null) return;

    setState(() => _isLoadingSummary = true);

    try {
      final todayData = {
        'feedings': _todayFeedings,
        'diapers': _todayDiapers,
        'sleep_minutes': _todaySleepMinutes,
      };
      final yesterdayData = {
        'feedings': _yesterdayFeedings,
        'diapers': _yesterdayDiapers,
        'sleep_minutes': _yesterdaySleepMinutes,
      };

      final summary = await AiService.getDailySummary(
        babyId: baby.id,
        babyName: baby.name,
        gender: baby.gender ?? 'unknown',
        todayData: todayData,
        yesterdayData: yesterdayData,
      );

      if (mounted) {
        setState(() {
          _aiSummary = summary;
          _isLoadingSummary = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _aiSummary = null;
          _isLoadingSummary = false;
        });
      }
    }
  }

  Future<void> _refreshAll() async {
    await _loadStats();
    await _loadAiSummary(forceRefresh: true);
  }

  _TrendDirection _getTrend(int today, int yesterday) {
    if (today > yesterday) return _TrendDirection.up;
    if (today < yesterday) return _TrendDirection.down;
    return _TrendDirection.flat;
  }

  String _formatSleepHours(int minutes) {
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    if (hours == 0) return '${mins}m';
    if (mins == 0) return '${hours}h';
    return '${hours}h ${mins}m';
  }

  @override
  Widget build(BuildContext context) {
    final baby = ref.watch(selectedBabyProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Daily Summary'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _isLoadingSummary || _isLoadingStats
                ? null
                : _refreshAll,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: SafeArea(
        child: baby == null
            ? const Center(child: Text('No baby selected'))
            : RefreshIndicator(
                onRefresh: _refreshAll,
                color: AppColors.primary,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // AI Summary Card
                      _buildAiSummaryCard(),
                      const SizedBox(height: 20),

                      // Comparison Header
                      Text(
                        'Today vs Yesterday',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: context.palette.text,
                        ),
                      ),
                      const SizedBox(height: 12),

                      if (_isLoadingStats)
                        const LoadingSkeleton()
                      else ...[
                        // Feedings comparison
                        _buildComparisonCard(
                          icon: Icons.restaurant_rounded,
                          label: 'Feedings',
                          todayValue: '$_todayFeedings',
                          yesterdayValue: '$_yesterdayFeedings',
                          trend: _getTrend(_todayFeedings, _yesterdayFeedings),
                        ),
                        const SizedBox(height: 12),

                        // Diapers comparison
                        _buildComparisonCard(
                          icon: Icons.baby_changing_station_rounded,
                          label: 'Diapers',
                          todayValue: '$_todayDiapers',
                          yesterdayValue: '$_yesterdayDiapers',
                          trend: _getTrend(_todayDiapers, _yesterdayDiapers),
                        ),
                        const SizedBox(height: 12),

                        // Sleep comparison
                        _buildComparisonCard(
                          icon: Icons.bedtime_rounded,
                          label: 'Sleep',
                          todayValue: _formatSleepHours(_todaySleepMinutes),
                          yesterdayValue:
                              _formatSleepHours(_yesterdaySleepMinutes),
                          trend: _getTrend(
                              _todaySleepMinutes, _yesterdaySleepMinutes),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildAiSummaryCard() {
    return AnimatedCard(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.pastelPurple,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.auto_awesome_rounded,
                    color: AppColors.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'AI Summary',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: context.palette.text,
                    ),
                  ),
                ),
                if (!_isLoadingSummary)
                  IconButton(
                    icon: Icon(
                      Icons.refresh_rounded,
                      color: context.palette.muted,
                      size: 20,
                    ),
                    onPressed: () => _loadAiSummary(forceRefresh: true),
                    tooltip: 'Regenerate',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (_isLoadingSummary)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildShimmerLine(width: double.infinity),
                  const SizedBox(height: 8),
                  _buildShimmerLine(width: double.infinity),
                  const SizedBox(height: 8),
                  _buildShimmerLine(width: 200),
                ],
              )
            else if (_aiSummary != null)
              Text(
                _aiSummary!,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.6,
                  color: context.palette.text.withValues(alpha: 0.85),
                ),
              )
            else
              Text(
                'Unable to generate summary. Tap refresh to try again.',
                style: TextStyle(
                  fontSize: 14,
                  color: context.palette.muted,
                  fontStyle: FontStyle.italic,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildShimmerLine({required double width}) {
    return Container(
      width: width,
      height: 14,
      decoration: BoxDecoration(
        color: AppColors.pastelPurple.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(7),
      ),
    );
  }

  Widget _buildComparisonCard({
    required IconData icon,
    required String label,
    required String todayValue,
    required String yesterdayValue,
    required _TrendDirection trend,
  }) {
    final trendIcon = switch (trend) {
      _TrendDirection.up => Icons.arrow_upward_rounded,
      _TrendDirection.down => Icons.arrow_downward_rounded,
      _TrendDirection.flat => Icons.remove_rounded,
    };

    final trendColor = switch (trend) {
      _TrendDirection.up => Colors.green,
      _TrendDirection.down => Colors.red,
      _TrendDirection.flat => Colors.grey,
    };

    return AnimatedCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.pastelPurple,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppColors.primary, size: 22),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      color: context.palette.muted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        todayValue,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: context.palette.text,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'vs $yesterdayValue',
                        style: TextStyle(
                          fontSize: 13,
                          color: context.palette.muted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: trendColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(trendIcon, color: trendColor, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}

enum _TrendDirection { up, down, flat }
