import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../services/ai_service.dart';
import '../../services/supabase_service.dart';
import '../../utils/date_utils.dart';
import '../../widgets/common/animated_card.dart';
import '../../widgets/common/loading_skeleton.dart';

class SmartInsights extends StatefulWidget {
  final String babyId;
  final String babyName;
  final String gender;

  const SmartInsights({
    super.key,
    required this.babyId,
    required this.babyName,
    required this.gender,
  });

  @override
  State<SmartInsights> createState() => _SmartInsightsState();
}

class _SmartInsightsState extends State<SmartInsights> {
  List<String> _insights = [];
  bool _loading = true;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _fetchInsights();
  }

  Future<void> _fetchInsights() async {
    setState(() => _loading = true);

    try {
      final client = SupabaseService.client;
      final weekAgo = AppDateUtils.weekAgoStart().toUtc().toIso8601String();

      // Fetch week data
      final results = await Future.wait([
        client.from('feedings').select('type, logged_at, duration_minutes, amount_ml')
            .eq('baby_id', widget.babyId).gte('logged_at', weekAgo),
        client.from('diapers').select('type, color, logged_at')
            .eq('baby_id', widget.babyId).gte('logged_at', weekAgo),
        client.from('sleeps').select('start_time, end_time, duration_minutes')
            .eq('baby_id', widget.babyId).gte('start_time', weekAgo),
        client.from('growth').select('weight_kg, height_cm, measured_at')
            .eq('baby_id', widget.babyId).gte('measured_at', weekAgo),
      ]);

      final totalEvents = (results[0] as List).length +
          (results[1] as List).length +
          (results[2] as List).length;

      if (totalEvents < 5) {
        setState(() {
          _insights = ['Keep logging to unlock AI insights! We need at least 5 activities.'];
          _loading = false;
        });
        return;
      }

      final weekData = <String, dynamic>{
        'feedings': results[0],
        'diapers': results[1],
        'sleeps': results[2],
        'growth': results[3],
      };

      // Care Pack extras (reflux, digestion, feed quality). These tables and
      // columns ship with a later migration — each query is wrapped so a
      // failure just leaves its key out of the payload, never breaks the call.
      try {
        final reflux = await client
            .from('reflux_events')
            .select('severity, painful_crying')
            .eq('baby_id', widget.babyId)
            .gte('logged_at', weekAgo);
        if (reflux.isNotEmpty) {
          weekData['reflux'] = {
            'events_total': reflux.length,
            'avg_per_day': (reflux.length / 7).toStringAsFixed(1),
            'painful_count':
                reflux.where((r) => r['painful_crying'] == true).length,
            'worst_severity': reflux
                .map((r) => (r['severity'] as num?)?.toInt() ?? 0)
                .reduce((a, b) => a > b ? a : b),
          };
        }
      } catch (_) {}

      try {
        final start = AppDateUtils.weekAgoStart();
        final startDate =
            '${start.year}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}';
        final journals = await client
            .from('daily_journals')
            .select('cramps, gas')
            .eq('baby_id', widget.babyId)
            .gte('journal_date', startDate);
        final diapers = results[1] as List;
        final digestion = <String, dynamic>{
          'dirty_diapers':
              diapers.where((d) => (d as Map)['type'] != 'wet').length,
          'days_with_cramps_ge2': journals
              .where((j) => ((j['cramps'] as num?)?.toInt() ?? 0) >= 2)
              .length,
          'days_with_gas_ge2': journals
              .where((j) => ((j['gas'] as num?)?.toInt() ?? 0) >= 2)
              .length,
        };
        // stool_type ships with a later diapers migration — its own guard so
        // the rest of the digestion summary survives without it.
        try {
          final stools = await client
              .from('diapers')
              .select('stool_type')
              .eq('baby_id', widget.babyId)
              .gte('logged_at', weekAgo)
              .not('stool_type', 'is', null);
          digestion['stool_types_seen'] = stools
              .map((d) => (d['stool_type'] as num).toInt())
              .toSet()
              .toList()
            ..sort();
        } catch (_) {}
        weekData['digestion'] = digestion;
      } catch (_) {}

      try {
        final feeds = await client
            .from('feedings')
            .select('quality, had_spitup')
            .eq('baby_id', widget.babyId)
            .gte('logged_at', weekAgo);
        final qualities = [
          for (final f in feeds)
            if (f['quality'] != null) (f['quality'] as num).toDouble()
        ];
        weekData['feed_quality'] = {
          if (qualities.isNotEmpty)
            'avg_quality': (qualities.reduce((a, b) => a + b) / qualities.length)
                .toStringAsFixed(1),
          'spitup_count': feeds.where((f) => f['had_spitup'] == true).length,
        };
      } catch (_) {}

      final insights = await AiService.getInsights(
        babyId: widget.babyId,
        babyName: widget.babyName,
        gender: widget.gender,
        weekData: weekData,
      );

      setState(() {
        _insights = insights.isNotEmpty ? insights : ['No insights available yet.'];
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _insights = ['Unable to generate insights right now.'];
        _loading = false;
      });
    }
  }

  IconData _getIcon(String insight) {
    final lower = insight.toLowerCase();
    if (lower.contains('sleep') || lower.contains('nap')) return Icons.nightlight_round;
    if (lower.contains('feed') || lower.contains('bottle') || lower.contains('breast')) return Icons.restaurant_rounded;
    if (lower.contains('diaper') || lower.contains('poop')) return Icons.water_drop_rounded;
    if (lower.contains('growth') || lower.contains('weight')) return Icons.show_chart_rounded;
    return Icons.auto_awesome;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: CardSkeleton(),
      );
    }

    if (_insights.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: AnimatedCard(
        index: 5,
        color: AppColors.pastelPurple.withValues(alpha: 0.4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome, color: AppColors.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  'AI Insights',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: context.palette.text),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: _fetchInsights,
                  child: Icon(Icons.refresh_rounded, size: 18, color: context.palette.muted),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Insight content
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Row(
                key: ValueKey(_currentIndex),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(_getIcon(_insights[_currentIndex]), size: 18, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _insights[_currentIndex],
                      style: TextStyle(fontSize: 14, color: context.palette.text, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
            if (_insights.length > 1) ...[
              const SizedBox(height: 12),
              // Dots indicator
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (int i = 0; i < _insights.length; i++)
                    GestureDetector(
                      onTap: () => setState(() => _currentIndex = i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: _currentIndex == i ? 20 : 8,
                        height: 8,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          color: _currentIndex == i ? AppColors.primary : AppColors.primary.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
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
}
