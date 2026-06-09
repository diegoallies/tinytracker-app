import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/theme.dart';
import '../../providers/feeding_settings_provider.dart';
import '../../providers/notification_provider.dart';
import '../../widgets/common/night_mode_toggle.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reminderEnabled = ref.watch(feedingReminderEnabledProvider);
    final reminderInterval = ref.watch(feedingReminderIntervalProvider);
    final showBreastFeeding = ref.watch(showBreastFeedingProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
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

              const SizedBox(height: 24),
              const _SectionHeader(title: 'Notifications'),
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
                      activeTrackColor:
                          AppColors.primary.withValues(alpha: 0.5),
                      activeThumbColor: AppColors.primary,
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
                ],
              ),

              const SizedBox(height: 24),
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
                      activeTrackColor:
                          AppColors.primary.withValues(alpha: 0.5),
                      activeThumbColor: AppColors.primary,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 32),
              Center(
                child: Text(
                  'TinyTracker',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: context.palette.muted.withValues(alpha: 0.6),
                    letterSpacing: 0.4,
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 3),
          ),
        ],
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

  const _SettingsRow({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(12),
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
  }
}

class _SettingsDivider extends StatelessWidget {
  const _SettingsDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 60, right: 16),
      child: Container(height: 1, color: Colors.grey.shade100),
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
          borderRadius: BorderRadius.circular(8),
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
