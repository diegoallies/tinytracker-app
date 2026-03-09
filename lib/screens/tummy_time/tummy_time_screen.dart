import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/theme.dart';
import '../../providers/baby_provider.dart';
import '../../providers/tummy_time_provider.dart';
import '../../utils/date_utils.dart';
import '../../widgets/common/animated_card.dart';
import '../../widgets/common/empty_state.dart';

class TummyTimeScreen extends ConsumerStatefulWidget {
  const TummyTimeScreen({super.key});

  @override
  ConsumerState<TummyTimeScreen> createState() => _TummyTimeScreenState();
}

class _TummyTimeScreenState extends ConsumerState<TummyTimeScreen> {
  static const int _dailyGoalMinutes = 30;

  Timer? _timer;
  Duration _elapsed = Duration.zero;
  DateTime? _sessionStartTime;
  String? _activeSessionId;
  bool _isStarting = false;
  bool _isStopping = false;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    _elapsed = Duration.zero;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _elapsed = DateTime.now().difference(_sessionStartTime!);
      });
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
    setState(() {
      _elapsed = Duration.zero;
      _sessionStartTime = null;
      _activeSessionId = null;
    });
  }

  Future<void> _handleStart() async {
    final baby = ref.read(selectedBabyProvider);
    if (baby == null) return;

    setState(() => _isStarting = true);

    try {
      final session = await TummyTimeActions.start(baby.id);
      if (session != null && mounted) {
        setState(() {
          _activeSessionId = session.id;
          _sessionStartTime = session.startTime;
        });
        _startTimer();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to start session: $e'),
            backgroundColor: Colors.red.shade400,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isStarting = false);
    }
  }

  Future<void> _handleStop() async {
    if (_activeSessionId == null || _sessionStartTime == null) return;

    setState(() => _isStopping = true);

    try {
      await TummyTimeActions.stop(_activeSessionId!, _sessionStartTime!);
      _stopTimer();
      ref.invalidate(recentTummyTimesProvider);
      ref.invalidate(todayTummyTimeMinutesProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Tummy time session saved!'),
            backgroundColor: AppColors.primary,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to stop session: $e'),
            backgroundColor: Colors.red.shade400,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isStopping = false);
    }
  }

  Future<void> _handleDelete(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Session'),
        content: const Text(
          'Are you sure you want to delete this tummy time session?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await TummyTimeActions.delete(id);
      ref.invalidate(recentTummyTimesProvider);
      ref.invalidate(todayTummyTimeMinutesProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Session deleted')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete: $e'),
            backgroundColor: Colors.red.shade400,
          ),
        );
      }
    }
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(selectedBabyProvider);
    final activeSession = ref.watch(activeTummyTimeProvider);
    final recentSessions = ref.watch(recentTummyTimesProvider);
    final todayMinutes = ref.watch(todayTummyTimeMinutesProvider);

    // Sync with active session from provider if we don't have one locally
    if (_activeSessionId == null && activeSession.valueOrNull != null) {
      final active = activeSession.valueOrNull!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _activeSessionId == null) {
          setState(() {
            _activeSessionId = active.id;
            _sessionStartTime = active.startTime;
          });
          _startTimer();
        }
      });
    }

    final bool isRunning = _activeSessionId != null;
    final double totalMinutes =
        (todayMinutes.valueOrNull ?? 0).toDouble() +
        (isRunning ? _elapsed.inSeconds / 60.0 : 0);
    final double progress =
        (totalMinutes / _dailyGoalMinutes).clamp(0.0, 1.0);
    final int progressPercent = (progress * 100).round();

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('Tummy Time'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.text,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Daily Progress Card
              AnimatedCard(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Text(
                        'Daily Progress',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text,
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: 160,
                        height: 160,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            SizedBox(
                              width: 160,
                              height: 160,
                              child: CircularProgressIndicator(
                                value: progress,
                                strokeWidth: 12,
                                backgroundColor:
                                    AppColors.pastelPurple.withValues(alpha: 0.3),
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  progress >= 1.0
                                      ? Colors.green
                                      : AppColors.primary,
                                ),
                                strokeCap: StrokeCap.round,
                              ),
                            ),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '$progressPercent%',
                                  style: TextStyle(
                                    fontSize: 32,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.text,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${totalMinutes.toStringAsFixed(1)} / $_dailyGoalMinutes min',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: AppColors.muted,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (progress >= 1.0) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'Goal reached!',
                            style: TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Timer Card
              AnimatedCard(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Text(
                        isRunning ? 'Session in Progress' : 'Start a Session',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        _formatDuration(_elapsed),
                        style: TextStyle(
                          fontSize: 56,
                          fontWeight: FontWeight.w300,
                          fontFeatures: const [FontFeature.tabularFigures()],
                          color: isRunning ? AppColors.primary : AppColors.muted,
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: (_isStarting || _isStopping)
                              ? null
                              : (isRunning ? _handleStop : _handleStart),
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                isRunning ? Colors.red.shade400 : AppColors.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            elevation: 0,
                          ),
                          child: (_isStarting || _isStopping)
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white,
                                    ),
                                  ),
                                )
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      isRunning
                                          ? Icons.stop_rounded
                                          : Icons.play_arrow_rounded,
                                      size: 24,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      isRunning ? 'Stop' : 'Start',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Today's Sessions
              Text(
                "Today's Sessions",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 12),
              recentSessions.when(
                data: (sessions) {
                  final now = DateTime.now();
                  final todaySessions = sessions.where((s) {
                    final dt = s.startTime;
                    return now.year == dt.year && now.month == dt.month && now.day == dt.day;
                  }).toList();

                  if (todaySessions.isEmpty) {
                    return const EmptyState(
                      icon: Icons.child_care_rounded,
                      title: 'No sessions today',
                      description: 'Start a tummy time session to track progress',
                    );
                  }

                  return ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: todaySessions.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final session = todaySessions[index];
                      final duration = session.durationMinutes ?? 0;
                      final startFormatted =
                          AppDateUtils.formatTime(session.startTime);

                      return AnimatedCard(
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          leading: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: AppColors.pastelPurple,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.child_care_rounded,
                              color: AppColors.primary,
                              size: 22,
                            ),
                          ),
                          title: Text(
                            '$duration min',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AppColors.text,
                            ),
                          ),
                          subtitle: Text(
                            'Started at $startFormatted',
                            style: TextStyle(
                              color: AppColors.muted,
                              fontSize: 13,
                            ),
                          ),
                          trailing: IconButton(
                            icon: Icon(
                              Icons.delete_outline_rounded,
                              color: AppColors.muted,
                              size: 20,
                            ),
                            onPressed: () => _handleDelete(session.id),
                          ),
                        ),
                      );
                    },
                  );
                },
                loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: CircularProgressIndicator(),
                  ),
                ),
                error: (error, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      'Failed to load sessions',
                      style: TextStyle(color: AppColors.muted),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
