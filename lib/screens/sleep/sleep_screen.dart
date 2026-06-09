import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/theme.dart';
import '../../providers/baby_provider.dart';
import '../../providers/sleep_provider.dart';
import '../../utils/date_utils.dart';
import '../../utils/extensions.dart';
import '../../utils/haptics.dart';
import '../../widgets/common/animated_card.dart';
import '../../widgets/common/app_dialogs.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/swipe_to_dismiss.dart';

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
      final diff = DateTime.now().difference(startTime);
      _elapsed = diff.isNegative ? Duration.zero : diff;
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

    Haptics.mediumTap();
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
        context.showErrorSnackBar(
          'Couldn’t start the sleep timer. Check your connection and try again.',
          onRetry: _startSleep,
        );
      }
    } finally {
      if (mounted) setState(() => _isStarting = false);
    }
  }

  Future<void> _stopSleep(String sleepId, DateTime startTime) async {
    Haptics.mediumTap();
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
        context.showErrorSnackBar(
          'Couldn’t end the sleep session. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _isStopping = false);
    }
  }

  Future<bool?> _confirmDelete() {
    return showDeleteDialog(context, what: 'Sleep Session');
  }

  Future<void> _deleteSleep(String sleepId) async {
    try {
      await SleepActions.deleteSleep(sleepId);
      ref.invalidate(activeSleepProvider);
      ref.invalidate(recentSleepsProvider);
      if (mounted) {
        context.showSuccessSnackBar('Sleep session deleted');
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar(
          'Couldn’t delete the sleep session. Check your connection and try again.',
        );
      }
    }
  }

  Future<void> _onRefresh() async {
    Haptics.lightTap();
    ref.invalidate(activeSleepProvider);
    ref.invalidate(recentSleepsProvider);
    await ref.read(recentSleepsProvider.future);
  }

  @override
  Widget build(BuildContext context) {
    final activeSleep = ref.watch(activeSleepProvider);
    final recentSleeps = ref.watch(recentSleepsProvider);

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Sleep',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _onRefresh,
          color: AppColors.primary,
          child: ListView(
            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
              style: TextStyle(color: context.palette.muted),
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
                      : context.palette.muted.withValues(alpha:0.5),
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
                  Text(
                    'Not sleeping',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w600,
                      color: context.palette.muted,
                    ),
                  ),
                if (isActive) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Started at ${AppDateUtils.formatTime(session.startTime as DateTime)}',
                    style: TextStyle(
                      color: context.palette.muted,
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
                if (!isActive) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 44,
                          child: OutlinedButton(
                            onPressed: _isStarting ? null : _showStartEarlierSheet,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.primary,
                              side: BorderSide(
                                color: AppColors.primary.withValues(alpha: 0.3),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                            ),
                            child: const FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.history_rounded, size: 16),
                                  SizedBox(width: 4),
                                  Text(
                                    'Start earlier',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SizedBox(
                          height: 44,
                          child: OutlinedButton(
                            onPressed: _showLogPastSheet,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.primary,
                              side: BorderSide(
                                color: AppColors.primary.withValues(alpha: 0.3),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                            ),
                            child: const FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.add_rounded, size: 16),
                                  SizedBox(width: 4),
                                  Text(
                                    'Log past',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
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
      },
    );
  }

  Future<void> _showStartEarlierSheet() async {
    final baby = ref.read(selectedBabyProvider);
    if (baby == null) return;

    final start = await _pickPastDateTime(
      title: 'Start time',
      subtitle: 'When did baby fall asleep?',
      initial: DateTime.now().subtract(const Duration(minutes: 30)),
    );
    if (start == null) return;

    Haptics.mediumTap();
    setState(() => _isStarting = true);

    try {
      final session =
          await SleepActions.startSleepAt(babyId: baby.id, start: start);
      if (session != null) {
        ref.invalidate(activeSleepProvider);
        ref.invalidate(recentSleepsProvider);
        if (mounted) {
          context.showSuccessSnackBar('Sleep started');
        }
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar(
          'Couldn’t start the sleep session. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _isStarting = false);
    }
  }

  Future<void> _showLogPastSheet() async {
    final baby = ref.read(selectedBabyProvider);
    if (baby == null) return;

    DateTime selectedDate = DateTime.now();
    TimeOfDay startTime = const TimeOfDay(hour: 13, minute: 0);
    TimeOfDay endTime = const TimeOfDay(hour: 14, minute: 30);

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              24, 12, 24, MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(
                  'Log Past Sleep',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: ctx.palette.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Record a completed sleep session',
                  style: TextStyle(fontSize: 13, color: ctx.palette.muted),
                ),
                const SizedBox(height: 20),

                _SleepPickerTile(
                  icon: Icons.calendar_today_rounded,
                  label: 'Date',
                  value: AppDateUtils.formatDate(selectedDate),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: selectedDate,
                      firstDate:
                          DateTime.now().subtract(const Duration(days: 365)),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) setSheet(() => selectedDate = picked);
                  },
                ),
                const SizedBox(height: 10),
                _SleepPickerTile(
                  icon: Icons.bedtime_rounded,
                  label: 'Fell asleep',
                  value: startTime.format(ctx),
                  onTap: () async {
                    final picked = await showTimePicker(
                      context: ctx,
                      initialTime: startTime,
                    );
                    if (picked != null) setSheet(() => startTime = picked);
                  },
                ),
                const SizedBox(height: 10),
                _SleepPickerTile(
                  icon: Icons.wb_sunny_rounded,
                  label: 'Woke up',
                  value: endTime.format(ctx),
                  onTap: () async {
                    final picked = await showTimePicker(
                      context: ctx,
                      initialTime: endTime,
                    );
                    if (picked != null) setSheet(() => endTime = picked);
                  },
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Save Session',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (result != true) return;

    var start = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
      startTime.hour,
      startTime.minute,
    );
    var end = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
      endTime.hour,
      endTime.minute,
    );

    // If end is before start, assume the session crossed midnight.
    if (!end.isAfter(start)) {
      end = end.add(const Duration(days: 1));
    }

    try {
      await SleepActions.logBackdated(
        babyId: baby.id,
        start: start,
        end: end,
      );
      ref.invalidate(recentSleepsProvider);
      ref.invalidate(activeSleepProvider);
      if (mounted) {
        context.showSuccessSnackBar('Sleep session saved');
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar(
          'Couldn’t save the sleep session. Check your connection and try again.',
        );
      }
    }
  }

  Future<DateTime?> _pickPastDateTime({
    required String title,
    required String subtitle,
    required DateTime initial,
  }) async {
    DateTime selectedDate = DateTime(initial.year, initial.month, initial.day);
    TimeOfDay selectedTime = TimeOfDay.fromDateTime(initial);

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              24, 12, 24, MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: ctx.palette.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 13, color: ctx.palette.muted),
                ),
                const SizedBox(height: 20),
                _SleepPickerTile(
                  icon: Icons.calendar_today_rounded,
                  label: 'Date',
                  value: AppDateUtils.formatDate(selectedDate),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: selectedDate,
                      firstDate:
                          DateTime.now().subtract(const Duration(days: 365)),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) setSheet(() => selectedDate = picked);
                  },
                ),
                const SizedBox(height: 10),
                _SleepPickerTile(
                  icon: Icons.access_time_rounded,
                  label: 'Time',
                  value: selectedTime.format(ctx),
                  onTap: () async {
                    final picked = await showTimePicker(
                      context: ctx,
                      initialTime: selectedTime,
                    );
                    if (picked != null) setSheet(() => selectedTime = picked);
                  },
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Start Sleep',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (result != true) return null;

    final picked = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
      selectedTime.hour,
      selectedTime.minute,
    );

    if (picked.isAfter(DateTime.now())) {
      if (mounted) {
        context.showErrorSnackBar('Can’t start in the future.');
      }
      return null;
    }

    return picked;
  }

  Widget _buildRecentList(AsyncValue<List<dynamic>> recentSleeps) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recent Sleep Sessions',
          style: TextStyle(
            color: context.palette.text,
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
                style: TextStyle(color: context.palette.muted),
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
              separatorBuilder: (_, _) => const SizedBox(height: 8),
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
    final sleepId = sleep.id as String;

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

    final itemWidget = AnimatedCard(
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
                    style: TextStyle(
                      color: context.palette.text,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    AppDateUtils.timeAgo(startTime),
                    style: TextStyle(
                      color: context.palette.muted,
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
          ],
        ),
      ),
    );

    if (isOngoing) return itemWidget;

    return SwipeToDismiss(
      itemId: sleepId,
      onConfirmDismiss: _confirmDelete,
      onDismissed: () => _deleteSleep(sleepId),
      child: itemWidget,
    );
  }
}

class _SleepPickerTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  const _SleepPickerTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: context.palette.surface,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.pastelPurple,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: AppColors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 11,
                        color: context.palette.muted,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: context.palette.text,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: context.palette.muted.withValues(alpha: 0.6),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
