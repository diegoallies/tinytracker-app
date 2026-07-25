import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/router.dart';
import '../../config/theme.dart';
import '../../utils/haptics.dart';
import '../../providers/baby_provider.dart';
import '../../providers/stats_provider.dart';
import '../../providers/activity_provider.dart';
import '../../utils/date_utils.dart';
import '../../widgets/common/animated_card.dart';
import '../../widgets/common/baby_selector.dart';
import '../../widgets/common/count_up_text.dart';
import '../../widgets/common/last_activity_banner.dart';
import '../../widgets/common/loading_skeleton.dart';
import '../../widgets/common/night_mode_toggle.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/ai/smart_insights.dart';
import '../../widgets/dashboard/next_up_card.dart';
import '../../widgets/dashboard/weekly_summary_card.dart';
import '../../widgets/dashboard/pattern_badges_widget.dart';
import '../../providers/notification_provider.dart';
import '../../providers/weekly_summary_provider.dart';
import '../../providers/badge_provider.dart';
import 'package:intl/intl.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen>
    with RouteAware, WidgetsBindingObserver {
  Timer? _sleepTimer;
  String _sleepDuration = '00:00';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      shellRouteObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    shellRouteObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    _sleepTimer?.cancel();
    super.dispose();
  }

  /// Refetch everything the dashboard cares about. Called on:
  /// • initial entry (build)
  /// • returning from a sibling tab (didPopNext)
  /// • app coming back from background (didChangeAppLifecycleState)
  void _refreshAll() {
    if (!mounted) return;
    ref.invalidate(dashboardStatsProvider);
    ref.invalidate(activityFeedProvider);
    ref.invalidate(weeklySummaryProvider);
    ref.invalidate(earnedBadgesProvider);
  }

  @override
  void didPopNext() {
    // Another tab was popped off - dashboard is now on top again.
    _refreshAll();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshAll();
    }
  }

  void _startSleepTimer(DateTime startTime) {
    _sleepTimer?.cancel();
    _sleepTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          final diff = DateTime.now().difference(startTime);
          _sleepDuration = AppDateUtils.formatElapsed(
            diff.isNegative ? Duration.zero : diff,
          );
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final babyState = ref.watch(babyProvider);
    final stats = ref.watch(dashboardStatsProvider);
    final activity = ref.watch(activityFeedProvider);

    // Medication reminders are still scheduled on-device (they're driven by a
    // fixed schedule, not by activity, so a phone can time them correctly).
    // Feeding and sleep reminders moved to the check-overdue cron — see
    // notification_provider.dart.
    ref.watch(medicationReminderSchedulerProvider);

    if (babyState.loading) return const Center(child: PageSkeleton());

    final baby = babyState.selectedBaby;
    if (baby == null) {
      return EmptyState(
        icon: Icons.child_care_rounded,
        title: 'No baby yet',
        description: 'Add your baby to start tracking',
        actionLabel: 'Add Baby',
        onAction: () => context.go('/baby'),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(dashboardStatsProvider);
        ref.invalidate(activityFeedProvider);
        ref.invalidate(weeklySummaryProvider);
        ref.invalidate(earnedBadgesProvider);
      },
      color: AppColors.primary,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          // Header
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        Haptics.lightTap();
                        context.go('/baby');
                      },
                      child: Row(
                        children: [
                          // Baby photo avatar
                          stats.when(
                            data: (s) => _BabyAvatar(
                              photoUrl: baby.photoUrl ?? s.latestPhotoUrl,
                              babyName: baby.name,
                            ),
                            loading: () => _BabyAvatar(
                              photoUrl: baby.photoUrl,
                              babyName: baby.name,
                            ),
                            error: (_, _) => _BabyAvatar(
                              photoUrl: baby.photoUrl,
                              babyName: baby.name,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  baby.name,
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: context.palette.text,
                                  ),
                                ),
                                Text(
                                  '${baby.ageDisplay} old  \u2022  ${DateFormat('EEEE, MMM d').format(DateTime.now())}',
                                  style: TextStyle(fontSize: 13, color: context.palette.muted),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const NightModeToggle(),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const BabySelector(),
          const SizedBox(height: 12),

          // Last activity banner
          stats.when(
            data: (s) => LastActivityBanner(
              babyName: baby.name,
              lastFeedTime: s.lastFeedTime,
              lastDiaperTime: s.lastDiaperTime,
            ),
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),
          const SizedBox(height: 12),

          // Active sleep banner
          stats.when(
            data: (s) {
              if (s.isSleeping && s.sleepStartTime != null) {
                _startSleepTimer(s.sleepStartTime!);
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: AnimatedCard(
                    tint: AppColors.pastelBlue,
                    child: Row(
                      children: [
                        const Icon(Icons.nightlight_round, color: AppColors.primary, size: 28),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Currently Sleeping',
                                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                              Text(_sleepDuration,
                                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.primary)),
                            ],
                          ),
                        ),
                        ElevatedButton(
                          onPressed: () => context.go('/sleep'),
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(80, 36),
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                          ),
                          child: const Text('Wake Up', style: TextStyle(fontSize: 13)),
                        ),
                      ],
                    ),
                  ),
                );
              }
              return const SizedBox.shrink();
            },
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),
          const SizedBox(height: 12),

          // Pattern-based predictions
          const NextUpCard(),
          const SizedBox(height: 16),

          // Stats cards
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: stats.when(
              data: (s) => Row(
                children: [
                  _StatCard(
                    icon: Icons.restaurant_rounded,
                    label: 'Feeds',
                    numericValue: s.feedCount,
                    color: AppColors.pastelPink,
                    cardColor: AppColors.pastelPinkLight,
                    iconColor: const Color(0xFFE91E63),
                    index: 0,
                    onTap: () => context.go('/feeding'),
                  ),
                  const SizedBox(width: 10),
                  _StatCard(
                    icon: Icons.water_drop_rounded,
                    label: 'Diapers',
                    numericValue: s.diaperCount,
                    color: AppColors.pastelYellow,
                    cardColor: AppColors.pastelYellowLight,
                    iconColor: const Color(0xFFFF9800),
                    index: 1,
                    onTap: () => context.go('/diaper'),
                  ),
                  const SizedBox(width: 10),
                  _StatCard(
                    icon: Icons.nightlight_round,
                    label: 'Sleep',
                    sleepMinutes: s.sleepMinutes,
                    color: AppColors.pastelBlue,
                    cardColor: AppColors.pastelBlueLight,
                    iconColor: const Color(0xFF2196F3),
                    index: 2,
                    onTap: () => context.go('/sleep'),
                  ),
                ],
              ),
              loading: () => const Row(
                children: [
                  Expanded(child: CardSkeleton()),
                  SizedBox(width: 10),
                  Expanded(child: CardSkeleton()),
                  SizedBox(width: 10),
                  Expanded(child: CardSkeleton()),
                ],
              ),
              error: (_, _) => const SizedBox.shrink(),
            ),
          ),
          const SizedBox(height: 16),

          // Last events
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: stats.when(
              data: (s) => Row(
                children: [
                  Expanded(
                    child: AnimatedCard(
                      index: 3,
                      tint: AppColors.pastelPinkLight,
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.restaurant_rounded, size: 16, color: context.palette.muted),
                              const SizedBox(width: 6),
                              Text('Last Feed', style: TextStyle(fontSize: 12, color: context.palette.muted)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            s.lastFeedTime != null ? AppDateUtils.timeAgo(s.lastFeedTime!) : 'No feeds yet',
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                          ),
                          if (s.lastFeedType != null)
                            Text(
                              _feedTypeLabel(s.lastFeedType!),
                              style: TextStyle(fontSize: 12, color: context.palette.muted),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: AnimatedCard(
                      index: 4,
                      tint: AppColors.pastelYellowLight,
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.water_drop_rounded, size: 16, color: context.palette.muted),
                              const SizedBox(width: 6),
                              Text('Last Diaper', style: TextStyle(fontSize: 12, color: context.palette.muted)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            s.lastDiaperTime != null ? AppDateUtils.timeAgo(s.lastDiaperTime!) : 'No diapers yet',
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                          ),
                          if (s.lastDiaperType != null)
                            Text(
                              s.lastDiaperType!.substring(0, 1).toUpperCase() + s.lastDiaperType!.substring(1),
                              style: TextStyle(fontSize: 12, color: context.palette.muted),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              loading: () => const Row(
                children: [
                  Expanded(child: CardSkeleton()),
                  SizedBox(width: 10),
                  Expanded(child: CardSkeleton()),
                ],
              ),
              error: (_, _) => const SizedBox.shrink(),
            ),
          ),
          const SizedBox(height: 20),

          // AI Insights
          SmartInsights(babyId: baby.id, babyName: baby.name, gender: baby.gender ?? 'boy'),
          const SizedBox(height: 20),

          // Weekly Summary
          const WeeklySummaryCard(),
          const SizedBox(height: 20),

          // Pattern Badges
          const PatternBadgesWidget(),
          const SizedBox(height: 20),

          // Quick Actions
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Quick Actions', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _QuickAction(icon: Icons.restaurant_rounded, label: 'Feed', color: AppColors.pastelPink, onTap: () => context.go('/feeding')),
                    _QuickAction(icon: Icons.water_drop_rounded, label: 'Diaper', color: AppColors.pastelYellow, onTap: () => context.go('/diaper')),
                    _QuickAction(icon: Icons.nightlight_round, label: 'Sleep', color: AppColors.pastelBlue, onTap: () => context.go('/sleep')),
                    _QuickAction(icon: Icons.show_chart_rounded, label: 'Growth', color: AppColors.pastelGreen, onTap: () => context.go('/growth')),
                    _QuickAction(icon: Icons.thermostat_rounded, label: 'Health', color: AppColors.pastelPink, onTap: () => context.go('/health')),
                    _QuickAction(icon: Icons.star_rounded, label: 'Milestones', color: AppColors.pastelYellow, onTap: () => context.go('/milestones')),
                    _QuickAction(icon: Icons.accessibility_new_rounded, label: 'Tummy', color: AppColors.pastelGreen, onTap: () => context.go('/tummy-time')),
                    _QuickAction(icon: Icons.camera_alt_rounded, label: 'Photos', color: AppColors.pastelBlue, onTap: () => context.go('/photos')),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Summary button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: AnimatedCard(
              index: 6,
              tint: AppColors.pastelPurpleLight,
              onTap: () => context.go('/summary'),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.pastelPurple,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.auto_awesome, color: AppColors.primary, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Daily Summary', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                        Text('AI-powered insights & comparison', style: TextStyle(fontSize: 12, color: context.palette.muted)),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: context.palette.muted),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Activity Feed
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Recent Activity', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                activity.when(
                  data: (items) {
                    if (items.isEmpty) {
                      return AnimatedCard(
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Text('No activity in the last 24 hours',
                                style: TextStyle(color: context.palette.muted)),
                          ),
                        ),
                      );
                    }
                    return Column(
                      children: items.asMap().entries.map((entry) {
                        final item = entry.value;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: AnimatedCard(
                            index: entry.key,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: _activityColor(item.type),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  // Fixed dark ink on the pastel chip (see _QuickAction).
                                  child: Icon(_activityIcon(item.type), size: 18, color: AppColors.text),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(item.label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                                      Text(
                                        AppDateUtils.timeAgo(item.time),
                                        style: TextStyle(fontSize: 12, color: context.palette.muted),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    );
                  },
                  loading: () => const Column(children: [CardSkeleton(), SizedBox(height: 8), CardSkeleton()]),
                  error: (_, _) => const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _feedTypeLabel(String type) {
    switch (type) {
      case 'breast_left': return 'Left breast';
      case 'breast_right': return 'Right breast';
      case 'bottle': return 'Bottle';
      case 'solids': return 'Solids';
      default: return type;
    }
  }

  Color _activityColor(String type) {
    switch (type) {
      case 'feeding': return AppColors.pastelPink;
      case 'diaper': return AppColors.pastelYellow;
      case 'sleep': return AppColors.pastelBlue;
      default: return AppColors.pastelPurple;
    }
  }

  IconData _activityIcon(String type) {
    switch (type) {
      case 'feeding': return Icons.restaurant_rounded;
      case 'diaper': return Icons.water_drop_rounded;
      case 'sleep': return Icons.nightlight_round;
      default: return Icons.circle;
    }
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color cardColor;
  final Color iconColor;
  final int index;
  final int? numericValue;
  final int? sleepMinutes;
  final VoidCallback? onTap;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.cardColor,
    required this.iconColor,
    required this.index,
    this.numericValue,
    this.sleepMinutes,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: AnimatedCard(
        index: index,
        tint: cardColor,
        onTap: onTap,
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 20, color: iconColor),
            ),
            const SizedBox(height: 8),
            if (sleepMinutes != null)
              CountUpDuration(
                totalMinutes: sleepMinutes!,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: context.palette.text),
              )
            else
              CountUpText(
                targetValue: numericValue ?? 0,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: context.palette.text),
              ),
            Text(label, style: TextStyle(fontSize: 11, color: context.palette.muted)),
          ],
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final width = (MediaQuery.of(context).size.width - 62) / 4;
    return GestureDetector(
      onTap: () {
        Haptics.lightTap();
        onTap();
      },
      child: SizedBox(
        width: width,
        child: Column(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(16),
              ),
              // The chip stays pastel in both themes, so the glyph must be
              // the FIXED dark ink - palette.text goes white in dark mode
              // and vanishes against the light pastel.
              child: Icon(icon, color: AppColors.text, size: 24),
            ),
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _BabyAvatar extends StatelessWidget {
  final String? photoUrl;
  final String babyName;

  const _BabyAvatar({this.photoUrl, required this.babyName});

  @override
  Widget build(BuildContext context) {
    final hasPhoto = photoUrl != null && photoUrl!.isNotEmpty;
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.pastelPurple,
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3), width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: hasPhoto
          ? CachedNetworkImage(
              key: ValueKey(photoUrl),
              imageUrl: photoUrl!,
              fit: BoxFit.cover,
              fadeInDuration: const Duration(milliseconds: 150),
              placeholder: (_, _) => _fallbackIcon(),
              errorWidget: (_, _, _) => _fallbackIcon(),
            )
          : _fallbackIcon(),
    );
  }

  Widget _fallbackIcon() {
    return Center(
      child: Text(
        babyName.isNotEmpty ? babyName[0].toUpperCase() : '?',
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: AppColors.primary,
        ),
      ),
    );
  }
}
