import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/theme.dart';
import '../../providers/night_mode_provider.dart';

class NightModeToggle extends ConsumerWidget {
  const NightModeToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(nightModeEnabledProvider);
    final isActive = ref.watch(nightModeActiveProvider);

    return GestureDetector(
      onTap: () => ref.read(nightModeEnabledProvider.notifier).toggle(),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isActive ? AppColors.primary.withValues(alpha: 0.2) : AppColors.surface,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          enabled ? Icons.wb_sunny_rounded : Icons.nightlight_round,
          size: 20,
          color: isActive ? AppColors.primary : AppColors.muted,
        ),
      ),
    );
  }
}
