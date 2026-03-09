import 'package:flutter/material.dart';

enum BadgeCategory { sleep, feeding, diaper, general }

class PatternBadge {
  final String id;
  final String title;
  final String description;
  final IconData icon;
  final BadgeCategory category;
  final bool isEarned;
  final DateTime? earnedAt;

  const PatternBadge({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.category,
    this.isEarned = false,
    this.earnedAt,
  });

  PatternBadge copyWith({bool? isEarned, DateTime? earnedAt}) {
    return PatternBadge(
      id: id,
      title: title,
      description: description,
      icon: icon,
      category: category,
      isEarned: isEarned ?? this.isEarned,
      earnedAt: earnedAt ?? this.earnedAt,
    );
  }

  static const List<PatternBadge> allBadges = [
    // Sleep badges
    PatternBadge(
      id: 'sleep_streak_3',
      title: 'Sweet Dreams',
      description: '3-day streak of 8+ hours sleep!',
      icon: Icons.nights_stay_rounded,
      category: BadgeCategory.sleep,
    ),
    PatternBadge(
      id: 'sleep_streak_5',
      title: 'Sleep Star',
      description: '5-day streak of 8+ hours sleep!',
      icon: Icons.star_rounded,
      category: BadgeCategory.sleep,
    ),
    PatternBadge(
      id: 'sleep_streak_7',
      title: 'Sleep Champion',
      description: '7-day streak of 8+ hours sleep!',
      icon: Icons.emoji_events_rounded,
      category: BadgeCategory.sleep,
    ),
    PatternBadge(
      id: 'sleep_streak_14',
      title: 'Dream Master',
      description: '14-day streak of 8+ hours sleep!',
      icon: Icons.workspace_premium_rounded,
      category: BadgeCategory.sleep,
    ),

    // Feeding badges
    PatternBadge(
      id: 'consistent_feeder_3',
      title: 'Consistent Feeder',
      description: '6+ feeds/day for 3 days straight!',
      icon: Icons.restaurant_rounded,
      category: BadgeCategory.feeding,
    ),
    PatternBadge(
      id: 'feeding_100',
      title: 'Century Club',
      description: '100 feeds logged!',
      icon: Icons.looks_one_rounded,
      category: BadgeCategory.feeding,
    ),
    PatternBadge(
      id: 'feeding_500',
      title: 'Feeding Pro',
      description: '500 feeds logged!',
      icon: Icons.military_tech_rounded,
      category: BadgeCategory.feeding,
    ),

    // Diaper badges
    PatternBadge(
      id: 'diaper_100',
      title: 'Diaper Duty',
      description: '100 diaper changes logged!',
      icon: Icons.water_drop_rounded,
      category: BadgeCategory.diaper,
    ),
    PatternBadge(
      id: 'diaper_500',
      title: 'Diaper Hero',
      description: '500 diaper changes logged!',
      icon: Icons.shield_rounded,
      category: BadgeCategory.diaper,
    ),

    // General badges
    PatternBadge(
      id: 'first_week',
      title: 'First Week',
      description: 'Tracked for 7 days!',
      icon: Icons.celebration_rounded,
      category: BadgeCategory.general,
    ),
    PatternBadge(
      id: 'thirty_days',
      title: 'Month Strong',
      description: '30 days of tracking!',
      icon: Icons.calendar_month_rounded,
      category: BadgeCategory.general,
    ),
    PatternBadge(
      id: 'night_owl',
      title: 'Night Owl',
      description: 'Logged an activity after midnight!',
      icon: Icons.dark_mode_rounded,
      category: BadgeCategory.general,
    ),
    PatternBadge(
      id: 'early_bird',
      title: 'Early Bird',
      description: 'Logged an activity before 5am!',
      icon: Icons.wb_twilight_rounded,
      category: BadgeCategory.general,
    ),
  ];
}
