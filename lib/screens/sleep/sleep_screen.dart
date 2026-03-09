import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/theme.dart';
import '../../providers/baby_provider.dart';
import '../../providers/sleep_provider.dart';
import '../../utils/date_utils.dart';
import '../../utils/extensions.dart';
import '../../widgets/common/animated_card.dart';
import '../../widgets/common/empty_state.dart';

class SleepScreen extends ConsumerStatefulWidget {
  const SleepScreen({super.key});

  @override
  ConsumerState<SleepScreen> createState() => _SleepScreenState();
}

class _SleepScreenState extends ConsumerState<SleepScreen>
    with SingleTickerProviderStateMixin {
  Timer? _timer;
  Duration _elapsed = Duration.zero;
  bool _isStarting = false;
  bool _isStopping = false;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  void _startElapsedTimer(DateTime startTime) {
    _timer?.cancel();
    _updateElapsed(startTime);
    _pulseController.repeat(reverse: true);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateElapsed(startTime);
    });
  }

  void _updateElapsed(DateTime startTime) {
    setState(() {
      _elapsed = DateTime.now().difference(startTime);
    });
  }

  void _stopElapsedTimer() {
    _timer?.cancel();
    _pulseController.stop();
    _pulseController.reset();
    setState(() {
      _elapsed = Duration.zero;
    });
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  Future<void> _startSleep() async {
    final baby = ref.read(selectedBabyProvider);
    if (baby == null) return;

    setState(() => _isStarting = true);

    try {
      final session = await SleepActions.startSleep(baby.id);
      if (session != null) {
        ref.invalidate(activeSleepProvider);
        ref.invalidate(recentSleepsProvider);
        if (mounted) {
          context.showSuccessSnackBar('Sleep started');
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to start sleep: $e'),
            backgroundColor: Colors.red.shade400,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isStarting = false);
    }
  }

  Future<void> _stopSleep(String sleepId, DateTime startTime) async {
    setState(() => _isStopping = true);

    try {
      await SleepActions.stopSleep(sleepId, startTime);
      _stopElapsedTimer();
      ref.invalidate(activeSleepProvider);
      ref.invalidate(recentSleepsProvider);
      if (mounted) {
        context.showSuccessSnackBar('Sleep ended');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to stop sleep: $e'),
            backgroundColor: Colors.red.shade400,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isStopping = false);
    }
  }

  Future<void> _deleteSleep(String sleepId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Sleep'),
        content:
            const Text('Are you sure you want to delete this sleep session?'),
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

    if (confirmed == true) {
      try {
        await SleepActions.deleteSleep(sleepId);
        ref.invalidate(activeSleepProvider);
        ref.invalidate(recentSleepsProvider);
        if (mounted) {
          context.showSuccessSnackBar('Sleep session deleted');
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
  }

  @override
  Widget build(BuildContext context) {
    final activeSleep = ref.watch(activeSleepProvider);
    final recentSleeps = ref.watch(recentSleepsProvider);

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.text),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Sleep',
          style: TextStyle(
            color: AppColors.text,
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildTimerCard(activeSleep),
              const SizedBox(height: 24),
              _buildRecentList(recentSleeps),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTimerCard(AsyncValue<dynamic> activeSleep) {
    return activeSleep.when(
      loading: () => AnimatedCard(
        child: const Padding(
          padding: EdgeInsets.all(48),
          child: Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          ),
        ),
      ),
      error: (error, _) => AnimatedCard(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Center(
            child: Text(
              'Failed to load sleep status',
              style: TextStyle(color: AppColors.muted),
            ),
          ),
        ),
      ),
      data: (session) {
        final isActive = session != null;

        if (isActive && _timer == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _startElapsedTimer(session.startTime as DateTime);
          });
        } else if (!isActive && _timer != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _stopElapsedTimer();
          });
        }

        return AnimatedCard(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
            child: Column(
              children: [
                Icon(
                  isActive ? Icons.bedtime_rounded : Icons.bedtime_outlined,
                  size: 48,
                  color: isActive
                      ? AppColors.primary
                      : AppColors.muted.withValues(alpha:0.5),
                ),
                const SizedBox(height: 20),
                if (isActive)
                  ScaleTransition(
                    scale: _pulseAnimation,
                    child: Text(
                      _formatDuration(_elapsed),
                      style: const TextStyle(
                        fontSize: 52,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  )
                else
                  const Text(
                    'Not sleeping',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w600,
                      color: AppColors.muted,
                    ),
                  ),
                if (isActive) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Started at ${AppDateUtils.formatTime(session.startTime as DateTime)}',
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 14,
                    ),
                  ),
                ],
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: (_isStarting || _isStopping)
                        ? null
                        : () {
                            if (isActive) {
                              _stopSleep(
                                session.id as String,
                                session.startTime as DateTime,
                              );
                            } else {
                              _startSleep();
                            }
                          },
                    icon: (_isStarting || _isStopping)
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : Icon(
                            isActive
                                ? Icons.stop_rounded
                                : Icons.play_arrow_rounded,
                            size: 24,
                          ),
                    label: Text(
                      isActive ? 'Wake Up' : 'Start Sleep',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 17,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          isActive ? Colors.orange.shade400 : AppColors.primary,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: isActive
                          ? Colors.orange.shade200
                          : AppColors.primary.withValues(alpha:0.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRecentList(AsyncValue<List<dynamic>> recentSleeps) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Recent Sleep Sessions',
          style: TextStyle(
            color: AppColors.text,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        const SizedBox(height: 12),
        recentSleeps.when(
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          ),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                'Failed to load sleep sessions',
                style: TextStyle(color: AppColors.muted),
              ),
            ),
          ),
          data: (sleeps) {
            if (sleeps.isEmpty) {
              return const EmptyState(
                icon: Icons.bedtime_outlined,
                title: 'No sleep sessions yet',
                description: 'Start tracking sleep above',
              );
            }
            return ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: sleeps.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final sleep = sleeps[index];
                return _buildSleepItem(sleep);
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildSleepItem(dynamic sleep) {
    final startTime = sleep.startTime as DateTime;
    final endTime = sleep.endTime as DateTime?;
    final isOngoing = endTime == null;

    String durationText;
    if (isOngoing) {
      durationText = 'Ongoing';
    } else {
      final duration = endTime.difference(startTime);
      final hours = duration.inHours;
      final minutes = duration.inMinutes % 60;
      if (hours > 0) {
        durationText = '${hours}h ${minutes}m';
      } else {
        durationText = '${minutes}m';
      }
    }

    String timeRange;
    if (isOngoing) {
      timeRange = 'Started ${AppDateUtils.formatTime(startTime)}';
    } else {
      timeRange =
          '${AppDateUtils.formatTime(startTime)} - ${AppDateUtils.formatTime(endTime)}';
    }

    return AnimatedCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isOngoing
                    ? AppColors.primary.withValues(alpha:0.15)
                    : AppColors.pastelPurple,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                isOngoing ? Icons.bedtime_rounded : Icons.bedtime_outlined,
                color: AppColors.primary,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    timeRange,
                    style: const TextStyle(
                      color: AppColors.text,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    AppDateUtils.timeAgo(startTime),
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text(
                durationText,
                style: TextStyle(
                  color: isOngoing ? Colors.orange.shade400 : AppColors.primary,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ),
            if (!isOngoing)
              IconButton(
                icon: Icon(Icons.delete_outline,
                    color: AppColors.muted.withValues(alpha:0.6), size: 20),
                onPressed: () => _deleteSleep(sleep.id as String),
                splashRadius: 20,
              ),
          ],
        ),
      ),
    );
  }
}
