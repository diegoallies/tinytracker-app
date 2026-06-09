import 'dart:async';
import 'package:flutter/material.dart';
import '../../config/theme.dart';

class LastActivityBanner extends StatefulWidget {
  final String babyName;
  final DateTime? lastFeedTime;
  final DateTime? lastDiaperTime;

  const LastActivityBanner({
    super.key,
    required this.babyName,
    this.lastFeedTime,
    this.lastDiaperTime,
  });

  @override
  State<LastActivityBanner> createState() => _LastActivityBannerState();
}

class _LastActivityBannerState extends State<LastActivityBanner>
    with SingleTickerProviderStateMixin {
  Timer? _timer;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
    _checkOverdue();
  }

  @override
  void didUpdateWidget(LastActivityBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    _checkOverdue();
  }

  void _checkOverdue() {
    if (widget.lastFeedTime != null) {
      final mins = DateTime.now().difference(widget.lastFeedTime!).inMinutes;
      if (mins >= 240) {
        if (!_pulseController.isAnimating) _pulseController.repeat(reverse: true);
      } else {
        _pulseController.stop();
        _pulseController.value = 0;
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.lastFeedTime == null) return const SizedBox.shrink();

    final diff = DateTime.now().difference(widget.lastFeedTime!);
    final mins = diff.inMinutes;

    final Color bgColor;
    final Color iconColor;
    final IconData icon;

    if (mins < 120) {
      bgColor = AppColors.pastelGreenLight;
      iconColor = AppColors.success;
      icon = Icons.check_circle_rounded;
    } else if (mins < 180) {
      bgColor = AppColors.pastelYellowLight;
      iconColor = AppColors.warning;
      icon = Icons.access_time_rounded;
    } else if (mins < 240) {
      bgColor = const Color(0xFFFFF3E0);
      iconColor = const Color(0xFFFF9800);
      icon = Icons.warning_amber_rounded;
    } else {
      bgColor = const Color(0xFFFFEBEE);
      iconColor = AppColors.error;
      icon = Icons.notification_important_rounded;
    }

    final timeAgo = _formatTimeAgo(diff);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          final scale = mins >= 240 ? 1.0 + (_pulseController.value * 0.02) : 1.0;
          return Transform.scale(scale: scale, child: child!);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            // Tinted-surface rule: pastel fill in light, dark card with the
            // status color as the accent border in dark.
            color: Theme.of(context).brightness == Brightness.dark
                ? context.palette.card
                : bgColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: iconColor.withValues(
                  alpha: Theme.of(context).brightness == Brightness.dark
                      ? 0.55
                      : 0.3),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, color: iconColor, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${widget.babyName} last ate $timeAgo',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: context.palette.text,
                      ),
                    ),
                    if (widget.lastDiaperTime != null)
                      Text(
                        'Last diaper ${_formatTimeAgo(DateTime.now().difference(widget.lastDiaperTime!))}',
                        style: TextStyle(fontSize: 12, color: context.palette.muted),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTimeAgo(Duration diff) {
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    final h = diff.inHours;
    final m = diff.inMinutes % 60;
    if (m == 0) return '${h}h ago';
    return '${h}h ${m}m ago';
  }
}
