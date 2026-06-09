import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/theme.dart';
import '../../models/pattern_badge.dart';
import '../../providers/badge_provider.dart';

class PatternBadgesWidget extends ConsumerWidget {
  const PatternBadgesWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final badgesAsync = ref.watch(earnedBadgesProvider);

    return badgesAsync.when(
      data: (badges) {
        final earned = badges.where((b) => b.isEarned).toList();
        if (earned.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'Achievements',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.pastelPurple,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${earned.length}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => _showAllBadges(context, badges),
                    child: const Text(
                      'See all',
                      style: TextStyle(fontSize: 13, color: AppColors.primary, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 100,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: earned.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    return _BadgeChip(badge: earned[index]);
                  },
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }

  void _showAllBadges(BuildContext context, List<PatternBadge> badges) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => _AllBadgesSheet(badges: badges),
    );
  }
}

class _BadgeChip extends StatelessWidget {
  final PatternBadge badge;

  const _BadgeChip({required this.badge});

  @override
  Widget build(BuildContext context) {
    final bgColor = _categoryColor(badge.category);

    return GestureDetector(
      onTap: () => _showBadgeDetail(context, badge),
      child: Container(
        width: 90,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: context.palette.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: bgColor, width: 2),
          boxShadow: [
            BoxShadow(
              color: bgColor.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: bgColor.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(badge.icon, size: 22, color: _categoryIconColor(badge.category)),
            ),
            const SizedBox(height: 6),
            Text(
              badge.title,
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

void _showBadgeDetail(BuildContext context, PatternBadge badge) {
  showDialog(
    context: context,
    builder: (context) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _categoryColor(badge.category).withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                badge.icon,
                size: 44,
                color: _categoryIconColor(badge.category),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              badge.title,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: context.palette.text),
            ),
            const SizedBox(height: 8),
            Text(
              badge.description,
              style: TextStyle(fontSize: 14, color: context.palette.muted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Awesome!'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Color _categoryColor(BadgeCategory category) {
  return switch (category) {
    BadgeCategory.sleep => AppColors.pastelBlue,
    BadgeCategory.feeding => AppColors.pastelPink,
    BadgeCategory.diaper => AppColors.pastelYellow,
    BadgeCategory.general => AppColors.pastelPurple,
  };
}

Color _categoryIconColor(BadgeCategory category) {
  return switch (category) {
    BadgeCategory.sleep => const Color(0xFF2196F3),
    BadgeCategory.feeding => const Color(0xFFE91E63),
    BadgeCategory.diaper => const Color(0xFFFF9800),
    BadgeCategory.general => AppColors.primary,
  };
}

class _AllBadgesSheet extends StatelessWidget {
  final List<PatternBadge> badges;

  const _AllBadgesSheet({required this.badges});

  @override
  Widget build(BuildContext context) {
    final earned = badges.where((b) => b.isEarned).toList();
    final locked = badges.where((b) => !b.isEarned).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      maxChildSize: 0.9,
      minChildSize: 0.5,
      expand: false,
      builder: (context, scrollController) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.palette.muted.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Achievements (${earned.length}/${badges.length})',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  children: [
                    if (earned.isNotEmpty) ...[
                      Text('Earned', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: context.palette.muted)),
                      const SizedBox(height: 8),
                      ...earned.map((b) => _BadgeListTile(badge: b, isLocked: false)),
                      const SizedBox(height: 20),
                    ],
                    if (locked.isNotEmpty) ...[
                      Text('Locked', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: context.palette.muted)),
                      const SizedBox(height: 8),
                      ...locked.map((b) => _BadgeListTile(badge: b, isLocked: true)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _BadgeListTile extends StatelessWidget {
  final PatternBadge badge;
  final bool isLocked;

  const _BadgeListTile({required this.badge, required this.isLocked});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isLocked ? context.palette.surface : context.palette.card,
          borderRadius: BorderRadius.circular(16),
          border: isLocked ? null : Border.all(color: _categoryColor(badge.category), width: 1.5),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isLocked
                    ? context.palette.muted.withValues(alpha: 0.1)
                    : _categoryColor(badge.category).withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                isLocked ? Icons.lock_rounded : badge.icon,
                size: 22,
                color: isLocked ? context.palette.muted : _categoryIconColor(badge.category),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    badge.title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isLocked ? context.palette.muted : context.palette.text,
                    ),
                  ),
                  Text(
                    badge.description,
                    style: TextStyle(
                      fontSize: 12,
                      color: isLocked ? context.palette.muted.withValues(alpha: 0.7) : context.palette.muted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
