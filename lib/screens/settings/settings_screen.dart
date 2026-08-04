import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../config/design_tokens.dart';
import '../../config/theme.dart';
import '../../providers/feeding_settings_provider.dart';
import '../../providers/notification_provider.dart';
import '../../services/app_info.dart';
import '../../services/notification_service.dart';
import '../../widgets/common/night_mode_toggle.dart';

final weeklyReportReminderEnabledProvider =
    StateNotifierProvider<WeeklyReportReminderEnabledNotifier, bool>((ref) {
  return WeeklyReportReminderEnabledNotifier();
});

class WeeklyReportReminderEnabledNotifier extends StateNotifier<bool> {
  WeeklyReportReminderEnabledNotifier() : super(false) {
    _load();
  }

  Future<void> _load() async {
    state = await NotificationService.isWeeklyReportReminderEnabled();
  }

  Future<void> toggle() async {
    state = !state;
    await NotificationService.setWeeklyReportReminderEnabled(state);
    if (state) {
      await NotificationService.requestPermissions();
    }
  }
}

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reminderEnabled = ref.watch(feedingReminderEnabledProvider);
    final reminderInterval = ref.watch(feedingReminderIntervalProvider);
    final sleepReminderEnabled = ref.watch(sleepReminderEnabledProvider);
    final sleepReminderWindow = ref.watch(sleepReminderWindowProvider);
    final medicationReminderEnabled = ref.watch(medicationReminderEnabledProvider);
    final weeklyReportReminderEnabled =
        ref.watch(weeklyReportReminderEnabledProvider);
    final showBreastFeeding = ref.watch(showBreastFeedingProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.xxl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionHeader(title: 'Appearance'),
              _SettingsCard(
                children: [
                  _SettingsRow(
                    icon: Icons.dark_mode_rounded,
                    iconBg: context.palette.text.withValues(alpha: 0.08),
                    iconColor: context.palette.text,
                    title: 'Dark Mode',
                    subtitle: 'Switch between light and dark themes',
                    trailing: const NightModeToggle(),
                  ),
                ],
              ),

              const SizedBox(height: AppSpacing.xl),
              const _SectionHeader(title: 'Reminders'),
              _SettingsCard(
                children: [
                  _SettingsRow(
                    icon: Icons.notifications_active_rounded,
                    iconBg: AppColors.pastelPink,
                    iconColor: const Color(0xFFE91E63),
                    title: 'Feeding Reminders',
                    subtitle: "Alert when it's time to feed",
                    trailing: Switch.adaptive(
                      value: reminderEnabled,
                      onChanged: (_) => ref
                          .read(feedingReminderEnabledProvider.notifier)
                          .toggle(),
                    ),
                  ),
                  if (reminderEnabled) ...[
                    const _SettingsDivider(),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 16, 16),
                      child: Row(
                        children: [
                          Text(
                            'Remind after',
                            style: TextStyle(
                                fontSize: 13, color: context.palette.muted),
                          ),
                          const Spacer(),
                          for (final m in const [120, 150, 180, 240])
                            Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: _IntervalChip(
                                label: m == 150 ? '2.5h' : '${m ~/ 60}h',
                                selected: reminderInterval == m,
                                onTap: () => ref
                                    .read(feedingReminderIntervalProvider
                                        .notifier)
                                    .setInterval(m),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                  const _SettingsDivider(),
                  _SettingsRow(
                    icon: Icons.bedtime_rounded,
                    iconBg: AppColors.pastelPurple,
                    iconColor: const Color(0xFF7E57C2),
                    title: 'Sleep Reminders',
                    subtitle: "Alert when it's time for a nap",
                    trailing: Switch.adaptive(
                      value: sleepReminderEnabled,
                      onChanged: (_) => ref
                          .read(sleepReminderEnabledProvider.notifier)
                          .toggle(),
                    ),
                  ),
                  if (sleepReminderEnabled) ...[
                    const _SettingsDivider(),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 16, 16),
                      child: Row(
                        children: [
                          Text(
                            'Wake window',
                            style: TextStyle(
                                fontSize: 13, color: context.palette.muted),
                          ),
                          const Spacer(),
                          for (final m in const [90, 120, 150, 180])
                            Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: _IntervalChip(
                                label: m == 90
                                    ? '1.5h'
                                    : (m == 150 ? '2.5h' : '${m ~/ 60}h'),
                                selected: sleepReminderWindow == m,
                                onTap: () => ref
                                    .read(sleepReminderWindowProvider.notifier)
                                    .setWindow(m),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                  const _SettingsDivider(),
                  _SettingsRow(
                    icon: Icons.medication_rounded,
                    iconBg: AppColors.pastelGreen,
                    iconColor: AppColors.success,
                    title: 'Medication Reminders',
                    subtitle: "Alert when a scheduled medicine is due",
                    trailing: Switch.adaptive(
                      value: medicationReminderEnabled,
                      onChanged: (_) => ref
                          .read(medicationReminderEnabledProvider.notifier)
                          .toggle(),
                    ),
                  ),
                  const _SettingsDivider(),
                  _SettingsRow(
                    icon: Icons.assignment_rounded,
                    iconBg: AppColors.pastelBlue,
                    iconColor: AppColors.info,
                    title: 'Weekly report (Fri 2pm)',
                    subtitle: 'Nudge to finish and share the report',
                    trailing: Switch.adaptive(
                      value: weeklyReportReminderEnabled,
                      onChanged: (_) => ref
                          .read(weeklyReportReminderEnabledProvider.notifier)
                          .toggle(),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: AppSpacing.xl),
              const _SectionHeader(title: 'Feeding'),
              _SettingsCard(
                children: [
                  _SettingsRow(
                    icon: Icons.woman_rounded,
                    iconBg: AppColors.pastelPurple,
                    iconColor: AppColors.primary,
                    title: 'Breast Feeding',
                    subtitle: 'Show breast feeding options',
                    trailing: Switch.adaptive(
                      value: showBreastFeeding,
                      onChanged: (_) => ref
                          .read(showBreastFeedingProvider.notifier)
                          .toggle(),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: AppSpacing.xl),
              const _SectionHeader(title: 'About'),
              _SettingsCard(
                children: [
                  _SettingsRow(
                    icon: Icons.menu_book_rounded,
                    iconBg: AppColors.pastelBlue,
                    iconColor: AppColors.info,
                    title: 'Care Guide',
                    subtitle: 'Tips, routines and emergency info',
                    trailing: Icon(
                      Icons.chevron_right_rounded,
                      color: context.palette.muted,
                    ),
                    onTap: () => context.push('/care-guide'),
                  ),
                  const _SettingsDivider(),
                  _SettingsRow(
                    icon: Icons.info_outline_rounded,
                    iconBg: AppColors.pastelGreen,
                    iconColor: AppColors.success,
                    title: 'App Version',
                    subtitle: 'TinyTracker',
                    trailing: Text(
                      AppInfo.display,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: context.palette.muted,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: AppSpacing.xxl),
              Center(
                child: Column(
                  children: [
                    Text(
                      'TinyTracker',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: context.palette.muted.withValues(alpha: 0.6),
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      'Made with love in Kimberley',
                      style: TextStyle(
                        fontSize: 11,
                        color: context.palette.muted.withValues(alpha: 0.5),
                        letterSpacing: 0.3,
                      ),
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
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: context.palette.muted,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;
  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.palette.card,
        borderRadius: AppRadius.xlAll,
        boxShadow: AppShadows.card(Theme.of(context).brightness),
      ),
      child: Column(children: children),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Widget trailing;
  final VoidCallback? onTap;

  const _SettingsRow({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: AppRadius.mdAll,
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: context.palette.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: context.palette.muted,
                  ),
                ),
              ],
            ),
          ),
          trailing,
        ],
      ),
    );

    if (onTap == null) return row;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.xlAll,
        child: row,
      ),
    );
  }
}

class _SettingsDivider extends StatelessWidget {
  const _SettingsDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 60, right: 16),
      child: Container(height: 1, color: context.palette.border),
    );
  }
}

class _IntervalChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _IntervalChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : context.palette.surface,
          borderRadius: AppRadius.smAll,
          border: Border.all(
            color: selected
                ? AppColors.primary
                : context.palette.muted.withValues(alpha: 0.3),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : context.palette.text,
          ),
        ),
      ),
    );
  }
}
