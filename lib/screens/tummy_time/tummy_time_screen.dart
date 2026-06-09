import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/theme.dart';
import '../../providers/baby_provider.dart';
import '../../providers/tummy_time_provider.dart';
import '../../utils/date_utils.dart';
import '../../utils/haptics.dart';
import '../../widgets/common/animated_card.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/swipe_to_dismiss.dart';

class TummyTimeScreen extends ConsumerStatefulWidget {
  const TummyTimeScreen({super.key});

  @override
  ConsumerState<TummyTimeScreen> createState() => _TummyTimeScreenState();
}

class _TummyTimeScreenState extends ConsumerState<TummyTimeScreen> {
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
        final diff = DateTime.now().difference(_sessionStartTime!);
        _elapsed = diff.isNegative ? Duration.zero : diff;
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

    Haptics.mediumTap();
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

    Haptics.mediumTap();
    setState(() => _isStopping = true);

    try {
      await TummyTimeActions.stop(_activeSessionId!, _sessionStartTime!);
      _stopTimer();
      ref.invalidate(recentTummyTimesProvider);
      ref.invalidate(todayTummyTimeMinutesProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tummy time saved!'),
            behavior: SnackBarBehavior.floating,
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

  Future<bool?> _confirmDelete() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
  }

  Future<void> _handleDelete(String id) async {
    try {
      await TummyTimeActions.delete(id);
      ref.invalidate(recentTummyTimesProvider);
      ref.invalidate(todayTummyTimeMinutesProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Session deleted'),
            behavior: SnackBarBehavior.floating,
          ),
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
    final clamped = d.isNegative ? Duration.zero : d;
    final minutes = clamped.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = clamped.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Future<void> _onRefresh() async {
    Haptics.lightTap();
    ref.invalidate(recentTummyTimesProvider);
    ref.invalidate(todayTummyTimeMinutesProvider);
    await ref.read(recentTummyTimesProvider.future);
  }

  Future<void> _showGoalEditor() async {
    final current = ref.read(tummyTimeGoalProvider);
    int selected = current;

    final result = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
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
                  'Daily Goal',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: ctx.palette.text,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'How many minutes of tummy time per day?',
                  style: TextStyle(fontSize: 13, color: ctx.palette.muted),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      '$selected',
                      style: const TextStyle(
                        fontSize: 64,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'min',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: ctx.palette.muted,
                      ),
                    ),
                  ],
                ),
                SliderTheme(
                  data: SliderTheme.of(ctx).copyWith(
                    activeTrackColor: AppColors.primary,
                    inactiveTrackColor: AppColors.pastelPurple,
                    thumbColor: AppColors.primary,
                    overlayColor: AppColors.primary.withValues(alpha: 0.15),
                  ),
                  child: Slider(
                    value: selected.toDouble(),
                    min: 5,
                    max: 120,
                    divisions: 23,
                    label: '$selected min',
                    onChanged: (v) => setSheet(() => selected = v.round()),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [15, 20, 30, 45, 60].map((m) {
                    final isActive = selected == m;
                    return GestureDetector(
                      onTap: () => setSheet(() => selected = m),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: isActive
                              ? AppColors.primary
                              : AppColors.pastelPurple.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${m}m',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isActive ? Colors.white : AppColors.primary,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, selected),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Save Goal',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (result != null && result != current) {
      await ref.read(tummyTimeGoalProvider.notifier).setGoal(result);
      Haptics.lightTap();
    }
  }

  Future<void> _showBackdateSheet() async {
    final baby = ref.read(selectedBabyProvider);
    if (baby == null) return;

    DateTime selectedDate = DateTime.now();
    TimeOfDay startTime = const TimeOfDay(hour: 10, minute: 0);
    TimeOfDay endTime = const TimeOfDay(hour: 10, minute: 10);

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final startMinutes = startTime.hour * 60 + startTime.minute;
          final endMinutes = endTime.hour * 60 + endTime.minute;
          final diffMinutes = endMinutes - startMinutes;
          final isValid = diffMinutes > 0;

          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                24,
                12,
                24,
                MediaQuery.of(ctx).viewInsets.bottom + 24,
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
                    'Log Past Session',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: ctx.palette.text,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Backdate a tummy time session',
                    style: TextStyle(fontSize: 13, color: ctx.palette.muted),
                  ),
                  const SizedBox(height: 20),

                  _SheetPickerTile(
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
                  _SheetPickerTile(
                    icon: Icons.play_arrow_rounded,
                    label: 'Start Time',
                    value: startTime.format(ctx),
                    onTap: () async {
                      final picked = await showTimePicker(
                        context: ctx,
                        initialTime: startTime,
                      );
                      if (picked == null) return;
                      setSheet(() {
                        startTime = picked;
                        // Auto-bump end time if it's now <= start
                        final s = picked.hour * 60 + picked.minute;
                        final e = endTime.hour * 60 + endTime.minute;
                        if (e <= s) {
                          final newEnd = (s + 10) % (24 * 60);
                          endTime = TimeOfDay(
                              hour: newEnd ~/ 60, minute: newEnd % 60);
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  _SheetPickerTile(
                    icon: Icons.stop_rounded,
                    label: 'End Time',
                    value: endTime.format(ctx),
                    onTap: () async {
                      final picked = await showTimePicker(
                        context: ctx,
                        initialTime: endTime,
                      );
                      if (picked != null) setSheet(() => endTime = picked);
                    },
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: isValid
                          ? AppColors.pastelPurple.withValues(alpha: 0.4)
                          : Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isValid
                              ? Icons.timer_outlined
                              : Icons.warning_amber_rounded,
                          size: 18,
                          color: isValid
                              ? AppColors.primary
                              : Colors.orange.shade700,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            isValid
                                ? 'Duration: $diffMinutes min'
                                : 'End time must be after start time',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isValid
                                  ? AppColors.primary
                                  : Colors.orange.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: isValid ? () => Navigator.pop(ctx, true) : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor:
                            AppColors.primary.withValues(alpha: 0.4),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Save Session',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    if (result != true) return;

    final start = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
      startTime.hour,
      startTime.minute,
    );
    final end = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
      endTime.hour,
      endTime.minute,
    );

    try {
      await TummyTimeActions.logBackdated(
        babyId: baby.id,
        start: start,
        end: end,
      );
      ref.invalidate(recentTummyTimesProvider);
      ref.invalidate(todayTummyTimeMinutesProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Session logged'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: $e'),
            backgroundColor: Colors.red.shade400,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(selectedBabyProvider);
    final babyState = ref.watch(babyProvider);
    final activeSession = ref.watch(activeTummyTimeProvider);
    final recentSessions = ref.watch(recentTummyTimesProvider);
    final todayMinutes = ref.watch(todayTummyTimeMinutesProvider);
    final goalMinutes = ref.watch(tummyTimeGoalProvider);
    final isOwner = babyState.isOwner;

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
        (totalMinutes / goalMinutes).clamp(0.0, 1.0);
    final int progressPercent = (progress * 100).round();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tummy Time'),
        elevation: 0,
        actions: [
          if (isOwner)
            IconButton(
              tooltip: 'Daily goal',
              icon: const Icon(Icons.tune_rounded),
              onPressed: _showGoalEditor,
            ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _onRefresh,
          color: AppColors.primary,
          child: ListView(
            physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics()),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              _HeroCard(
                isRunning: isRunning,
                progress: progress,
                progressPercent: progressPercent,
                totalMinutes: totalMinutes,
                goalMinutes: goalMinutes,
                elapsedText: _formatDuration(_elapsed),
                isOwner: isOwner,
                onEditGoal: _showGoalEditor,
              ),
              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed: (_isStarting || _isStopping)
                            ? null
                            : (isRunning ? _handleStop : _handleStart),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isRunning
                              ? Colors.red.shade400
                              : AppColors.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 0,
                        ),
                        child: (_isStarting || _isStopping)
                            ? const SizedBox(
                                width: 22,
                                height: 22,
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
                                    size: 22,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    isRunning ? 'Stop' : 'Start',
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: OutlinedButton(
                        onPressed: isRunning ? null : _showBackdateSheet,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          side: BorderSide(
                            color: AppColors.primary.withValues(alpha: 0.3),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        child: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.add_rounded, size: 18),
                              SizedBox(width: 4),
                              Text(
                                'Log past',
                                style: TextStyle(
                                  fontSize: 14,
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
              const SizedBox(height: 24),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  "Today's Sessions",
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: context.palette.text,
                  ),
                ),
              ),
              const SizedBox(height: 10),

              recentSessions.when(
                data: (sessions) {
                  final now = DateTime.now();
                  final todaySessions = sessions.where((s) {
                    final dt = s.startTime.toLocal();
                    return now.year == dt.year &&
                        now.month == dt.month &&
                        now.day == dt.day;
                  }).toList();

                  if (todaySessions.isEmpty) {
                    return const EmptyState(
                      icon: Icons.child_care_rounded,
                      title: 'No sessions today',
                      description:
                          'Start a tummy time session or log a past one.',
                    );
                  }

                  return ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: todaySessions.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final session = todaySessions[index];
                      return _SessionTile(
                        session: session,
                        onDeleteConfirm: _confirmDelete,
                        onDelete: () => _handleDelete(session.id),
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
                      style: TextStyle(color: context.palette.muted),
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

// ──────────────────────────────────────────────────────────────────────
// Hero card with ring + live timer overlay
// ──────────────────────────────────────────────────────────────────────

class _HeroCard extends StatelessWidget {
  final bool isRunning;
  final double progress;
  final int progressPercent;
  final double totalMinutes;
  final int goalMinutes;
  final String elapsedText;
  final bool isOwner;
  final VoidCallback onEditGoal;

  const _HeroCard({
    required this.isRunning,
    required this.progress,
    required this.progressPercent,
    required this.totalMinutes,
    required this.goalMinutes,
    required this.elapsedText,
    required this.isOwner,
    required this.onEditGoal,
  });

  @override
  Widget build(BuildContext context) {
    final goalReached = progress >= 1.0;

    return AnimatedCard(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
        child: Column(
          children: [
            Row(
              children: [
                _StatusDot(running: isRunning),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isRunning ? 'Session in progress' : 'Daily progress',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: context.palette.muted,
                      letterSpacing: 0.2,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: isOwner ? onEditGoal : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.pastelPurple.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.flag_rounded,
                          size: 13,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${goalMinutes}m goal',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                        if (isOwner) ...[
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.tune_rounded,
                            size: 12,
                            color: AppColors.primary,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: 180,
              height: 180,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 180,
                    height: 180,
                    child: CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 14,
                      backgroundColor:
                          AppColors.pastelPurple.withValues(alpha: 0.3),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        goalReached ? Colors.green : AppColors.primary,
                      ),
                      strokeCap: StrokeCap.round,
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isRunning) ...[
                        Text(
                          elapsedText,
                          style: const TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.w300,
                            fontFeatures: [FontFeature.tabularFigures()],
                            color: AppColors.primary,
                            letterSpacing: -1,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'live',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: context.palette.muted,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ] else ...[
                        Text(
                          '$progressPercent%',
                          style: TextStyle(
                            fontSize: 40,
                            fontWeight: FontWeight.w700,
                            color: context.palette.text,
                            letterSpacing: -1,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${totalMinutes.toStringAsFixed(0)} / $goalMinutes min',
                          style: TextStyle(
                            fontSize: 12,
                            color: context.palette.muted,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            if (goalReached) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.emoji_events_rounded,
                      size: 14,
                      color: Colors.green,
                    ),
                    SizedBox(width: 6),
                    Text(
                      'Goal reached!',
                      style: TextStyle(
                        color: Colors.green,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  final bool running;
  const _StatusDot({required this.running});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: running ? Colors.green : context.palette.muted.withValues(alpha: 0.4),
        boxShadow: running
            ? [
                BoxShadow(
                  color: Colors.green.withValues(alpha: 0.5),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
// Session tile with visible delete + swipe-to-dismiss
// ──────────────────────────────────────────────────────────────────────

class _SessionTile extends StatelessWidget {
  final dynamic session;
  final Future<bool?> Function() onDeleteConfirm;
  final VoidCallback onDelete;

  const _SessionTile({
    required this.session,
    required this.onDeleteConfirm,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final duration = (session.durationMinutes as int?) ?? 0;
    final start = (session.startTime as DateTime).toLocal();
    final startFormatted = AppDateUtils.formatTime(start);

    return SwipeToDismiss(
      itemId: session.id as String,
      onConfirmDismiss: onDeleteConfirm,
      onDismissed: onDelete,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.pastelPurple,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.child_care_rounded,
                color: AppColors.primary,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$duration min',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: context.palette.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Started at $startFormatted',
                    style: TextStyle(
                      color: context.palette.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () async {
                  final ok = await onDeleteConfirm();
                  if (ok == true) onDelete();
                },
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.delete_outline_rounded,
                    size: 18,
                    color: Colors.red.shade400,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
// Reusable sheet picker tile (date / time selector)
// ──────────────────────────────────────────────────────────────────────

class _SheetPickerTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  const _SheetPickerTile({
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

