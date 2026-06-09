import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/theme.dart';
import '../../providers/baby_provider.dart';

class BabySelector extends ConsumerWidget {
  const BabySelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final babyState = ref.watch(babyProvider);

    if (babyState.babies.length <= 1) return const SizedBox.shrink();

    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: babyState.babies.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final baby = babyState.babies[index];
          final isSelected = baby.id == babyState.selectedBaby?.id;

          return GestureDetector(
            onTap: () => ref.read(babyProvider.notifier).selectBaby(baby),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.primary : context.palette.card,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected ? AppColors.primary : AppColors.pastelPurple,
                ),
              ),
              child: Text(
                baby.name,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white : context.palette.text,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
