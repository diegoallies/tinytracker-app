import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../config/theme.dart';
import '../../widgets/common/animated_card.dart';

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  static const _features = <_FeatureItem>[
    _FeatureItem(
      icon: Icons.settings_rounded,
      label: 'Settings',
      description: 'Preferences',
      route: '/settings',
      color: Color(0xFFEDEAF3),
      iconColor: AppColors.text,
    ),
    _FeatureItem(
      icon: Icons.auto_awesome_rounded,
      label: 'Summary',
      description: 'AI daily insights',
      route: '/summary',
      color: Color(0xFFe8d5f5),
      iconColor: Color(0xFF9b72cf),
    ),
    _FeatureItem(
      icon: Icons.trending_up_rounded,
      label: 'Growth',
      description: 'Track measurements',
      route: '/growth',
      color: Color(0xFFd5f5e8),
      iconColor: Color(0xFF5bbf8c),
    ),
    _FeatureItem(
      icon: Icons.emoji_events_rounded,
      label: 'Milestones',
      description: 'Development firsts',
      route: '/milestones',
      color: Color(0xFFf5f0d5),
      iconColor: Color(0xFFb0a040),
    ),
    _FeatureItem(
      icon: Icons.medical_services_rounded,
      label: 'Health',
      description: 'Medical records',
      route: '/health',
      color: Color(0xFFf5d5e8),
      iconColor: Color(0xFFbf5b8c),
    ),
    _FeatureItem(
      icon: Icons.self_improvement_rounded,
      label: 'Tummy Time',
      description: 'Practice sessions',
      route: '/tummy-time',
      color: Color(0xFFd5e8f5),
      iconColor: Color(0xFF5b8cbf),
    ),
    _FeatureItem(
      icon: Icons.photo_library_rounded,
      label: 'Photos',
      description: 'Memory gallery',
      route: '/photos',
      color: Color(0xFFe8d5f5),
      iconColor: Color(0xFF9b72cf),
    ),
    _FeatureItem(
      icon: Icons.file_download_rounded,
      label: 'Export',
      description: 'Download data',
      route: '/export',
      color: Color(0xFFd5f5e8),
      iconColor: Color(0xFF5bbf8c),
    ),
    _FeatureItem(
      icon: Icons.child_care_rounded,
      label: 'Baby',
      description: 'Profile & sharing',
      route: '/baby',
      color: Color(0xFFf5d5e8),
      iconColor: Color(0xFFbf5b8c),
    ),
  ];

  /// Daily care + reporting workflow, digitised from the family's paper
  /// "Baby Care Tracking & Reporting Pack".
  static const _carePack = <_FeatureItem>[
    _FeatureItem(
      icon: Icons.water_drop_rounded,
      label: 'Reflux',
      description: 'Spit-up tracker',
      route: '/reflux',
      color: Color(0xFFf5d5e8),
      iconColor: Color(0xFFbf5b8c),
    ),
    _FeatureItem(
      icon: Icons.menu_book_rounded,
      label: 'Daily Journal',
      description: 'Mood & activity',
      route: '/journal',
      color: Color(0xFFf5f0d5),
      iconColor: Color(0xFFb0a040),
    ),
    _FeatureItem(
      icon: Icons.assignment_rounded,
      label: 'Weekly Report',
      description: 'For the parents',
      route: '/weekly-report',
      color: Color(0xFFe8d5f5),
      iconColor: Color(0xFF9b72cf),
    ),
    _FeatureItem(
      icon: Icons.fact_check_rounded,
      label: 'Monthly Review',
      description: 'Milestone check',
      route: '/monthly-review',
      color: Color(0xFFd5f5e8),
      iconColor: Color(0xFF5bbf8c),
    ),
    _FeatureItem(
      icon: Icons.health_and_safety_rounded,
      label: 'Care Guide',
      description: 'Red flags & contacts',
      route: '/care-guide',
      color: Color(0xFFd5e8f5),
      iconColor: Color(0xFF5b8cbf),
    ),
    _FeatureItem(
      icon: Icons.vaccines_rounded,
      label: 'Immunisations',
      description: 'SA EPI schedule',
      route: '/immunisations',
      color: Color(0xFFd5f5e8),
      iconColor: Color(0xFF5bbf8c),
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('More'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionHeader(
                title: 'Care Pack',
                subtitle: 'Daily care, reports & safety — the paper pack, digitised',
              ),
              const SizedBox(height: 16),
              _FeatureGrid(items: _carePack),

              const SizedBox(height: 28),

              _SectionHeader(
                title: 'Features',
                subtitle: 'Everything you need to track your little one',
              ),
              const SizedBox(height: 16),
              _FeatureGrid(items: _features),

              const SizedBox(height: 32),

              // App info
              Center(
                child: Column(
                  children: [
                    Text(
                      'TinyTracker',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: context.palette.muted.withValues(alpha:0.6),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Made with care for tiny humans',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.palette.muted.withValues(alpha:0.5),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionHeader({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: context.palette.text,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: 14,
            color: context.palette.muted,
          ),
        ),
      ],
    );
  }
}

class _FeatureGrid extends StatelessWidget {
  final List<_FeatureItem> items;

  const _FeatureGrid({required this.items});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const crossAxisCount = 3;
        const spacing = 12.0;
        final itemWidth =
            (constraints.maxWidth - (spacing * (crossAxisCount - 1))) /
                crossAxisCount;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: items.map((feature) {
            return SizedBox(
              width: itemWidth,
              child: _FeatureCard(feature: feature),
            );
          }).toList(),
        );
      },
    );
  }
}

class _FeatureCard extends StatelessWidget {
  final _FeatureItem feature;

  const _FeatureCard({required this.feature});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push(feature.route),
      child: AnimatedCard(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: feature.color,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  feature.icon,
                  size: 24,
                  color: feature.iconColor,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                feature.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: context.palette.text,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                feature.description,
                style: TextStyle(
                  fontSize: 11,
                  color: context.palette.muted,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureItem {
  final IconData icon;
  final String label;
  final String description;
  final String route;
  final Color color;
  final Color iconColor;

  const _FeatureItem({
    required this.icon,
    required this.label,
    required this.description,
    required this.route,
    required this.color,
    required this.iconColor,
  });
}

