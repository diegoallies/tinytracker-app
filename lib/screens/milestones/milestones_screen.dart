import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/milestone.dart';
import '../../providers/milestone_provider.dart';
import '../../utils/date_utils.dart';
import '../../widgets/common/animated_card.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/loading_skeleton.dart';

class MilestonesScreen extends ConsumerStatefulWidget {
  const MilestonesScreen({super.key});

  @override
  ConsumerState<MilestonesScreen> createState() => _MilestonesScreenState();
}

class _MilestonesScreenState extends ConsumerState<MilestonesScreen>
    with SingleTickerProviderStateMixin {
  static const _categories = [
    'All',
    'Motor',
    'Social',
    'Language',
    'Cognitive',
  ];

  String _selectedCategory = 'All';
  final Set<String> _animatingIds = {};

  Color _categoryColor(String category) {
    return switch (category.toLowerCase()) {
      'motor' => const Color(0xFFD5E8F5),
      'social' => const Color(0xFFF5D5E8),
      'language' => const Color(0xFFF5F0D5),
      'cognitive' => const Color(0xFFD5F5E8),
      _ => const Color(0xFFE8D5F5),
    };
  }

  Color _categoryTextColor(String category) {
    return switch (category.toLowerCase()) {
      'motor' => const Color(0xFF3D7AB5),
      'social' => const Color(0xFFB55A8A),
      'language' => const Color(0xFFA89540),
      'cognitive' => const Color(0xFF40A870),
      _ => const Color(0xFF9B72CF),
    };
  }

  IconData _categoryIcon(String category) {
    return switch (category.toLowerCase()) {
      'motor' => Icons.directions_run,
      'social' => Icons.people_outline,
      'language' => Icons.chat_bubble_outline,
      'cognitive' => Icons.psychology_outlined,
      _ => Icons.star_outline,
    };
  }

  Future<void> _toggleMilestone(Milestone milestone) async {
    final newAchieved = !milestone.achieved;

    setState(() => _animatingIds.add(milestone.id));

    try {
      await MilestoneActions.toggleAchieved(milestone.id, newAchieved);
      ref.invalidate(milestonesProvider);

      if (mounted && newAchieved) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.celebration, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${milestone.title} achieved!',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF4CAF50),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        Future.delayed(const Duration(milliseconds: 400), () {
          if (mounted) {
            setState(() => _animatingIds.remove(milestone.id));
          }
        });
      }
    }
  }

  String _ageLabel(int months) {
    if (months == 0) return 'Birth';
    if (months < 12) return '$months month${months == 1 ? '' : 's'}';
    final years = months ~/ 12;
    final remaining = months % 12;
    if (remaining == 0) {
      return '$years year${years == 1 ? '' : 's'}';
    }
    return '$years year${years == 1 ? '' : 's'} $remaining month${remaining == 1 ? '' : 's'}';
  }

  @override
  Widget build(BuildContext context) {
    final milestones = ref.watch(milestonesProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFFAF8FC),
      appBar: AppBar(
        title: const Text('Milestones'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF2D2640),
        elevation: 0,
        scrolledUnderElevation: 1,
      ),
      body: SafeArea(
        child: milestones.when(
          loading: () => const LoadingSkeleton(),
          error: (error, _) => Center(child: Text('Error: $error')),
          data: (allMilestones) {
            if (allMilestones.isEmpty) {
              return const EmptyState(
                icon: Icons.emoji_events_outlined,
                title: 'No milestones available',
                description: 'Milestones will appear here once set up',
              );
            }

            final filtered = _selectedCategory == 'All'
                ? allMilestones
                : allMilestones
                    .where((m) =>
                        m.category.toLowerCase() ==
                        _selectedCategory.toLowerCase())
                    .toList();

            final achievedCount =
                filtered.where((m) => m.achieved).length;
            final totalCount = filtered.length;

            // Group by expected age
            final grouped = <int, List<Milestone>>{};
            for (final m in filtered) {
              grouped.putIfAbsent(m.expectedAgeMonths, () => []).add(m);
            }
            final sortedAges = grouped.keys.toList()..sort();

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                _buildProgressCard(achievedCount, totalCount),
                const SizedBox(height: 16),
                _buildCategoryFilter(),
                const SizedBox(height: 20),
                ...sortedAges.map((age) =>
                    _buildAgeGroup(age, grouped[age]!)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildProgressCard(int achieved, int total) {
    final progress = total > 0 ? achieved / total : 0.0;

    return AnimatedCard(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8D5F5),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.emoji_events,
                        color: Color(0xFF9B72CF),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Progress',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF2D2640),
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD5F5E8),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$achieved / $total',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF40A870),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: progress),
                duration: const Duration(milliseconds: 600),
                curve: Curves.easeOutCubic,
                builder: (context, value, _) {
                  return LinearProgressIndicator(
                    value: value,
                    minHeight: 10,
                    backgroundColor: const Color(0xFFE8D5F5),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Color(0xFF9B72CF),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${(progress * 100).toInt()}% complete',
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF8B85A0),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryFilter() {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _categories.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final category = _categories[index];
          final isSelected = _selectedCategory == category;

          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            child: Material(
              color: isSelected
                  ? const Color(0xFF9B72CF)
                  : Colors.white,
              borderRadius: BorderRadius.circular(20),
              elevation: isSelected ? 2 : 0,
              child: InkWell(
                onTap: () =>
                    setState(() => _selectedCategory = category),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected
                          ? Colors.transparent
                          : const Color(0xFFE8D5F5),
                    ),
                  ),
                  child: Row(
                    children: [
                      if (category != 'All') ...[
                        Icon(
                          _categoryIcon(category),
                          size: 14,
                          color: isSelected
                              ? Colors.white
                              : const Color(0xFF8B85A0),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        category,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isSelected
                              ? Colors.white
                              : const Color(0xFF8B85A0),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAgeGroup(int ageMonths, List<Milestone> milestones) {
    final achievedInGroup = milestones.where((m) => m.achieved).length;

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF9B72CF),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _ageLabel(ageMonths),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '$achievedInGroup/${milestones.length}',
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF8B85A0),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...milestones.map((m) => _buildMilestoneItem(m)),
        ],
      ),
    );
  }

  Widget _buildMilestoneItem(Milestone milestone) {
    final isAnimating = _animatingIds.contains(milestone.id);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AnimatedScale(
        scale: isAnimating ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 200),
        child: AnimatedCard(
          child: InkWell(
            onTap: () => _toggleMilestone(milestone),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutBack,
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: milestone.achieved
                          ? const Color(0xFF4CAF50)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: milestone.achieved
                            ? const Color(0xFF4CAF50)
                            : const Color(0xFFD5D0E0),
                        width: 2,
                      ),
                    ),
                    child: AnimatedOpacity(
                      opacity: milestone.achieved ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      child: const Icon(
                        Icons.check,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                milestone.title,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF2D2640),
                                  decoration: milestone.achieved
                                      ? TextDecoration.lineThrough
                                      : null,
                                  decorationColor: const Color(0xFF8B85A0),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: _categoryColor(milestone.category),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _categoryIcon(milestone.category),
                                    size: 10,
                                    color: _categoryTextColor(
                                        milestone.category),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    milestone.category,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: _categoryTextColor(
                                          milestone.category),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (milestone.description != null &&
                            milestone.description!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            milestone.description!,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF8B85A0),
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        if (milestone.achieved &&
                            milestone.achievedAt != null) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(
                                Icons.celebration,
                                size: 12,
                                color: Color(0xFF4CAF50),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Achieved ${AppDateUtils.timeAgo(milestone.achievedAt!)}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF4CAF50),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
