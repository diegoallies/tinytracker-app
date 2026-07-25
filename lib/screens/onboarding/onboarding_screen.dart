import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../config/theme.dart';
import '../../services/analytics_service.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _checkAlreadySeen();
  }

  Future<void> _checkAlreadySeen() async {
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getBool('has_seen_onboarding') ?? false;
    if (seen && mounted) {
      context.go('/dashboard');
    }
  }

  Future<void> _completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_seen_onboarding', true);
    AnalyticsService.logOnboardingComplete();
    if (mounted) context.go('/dashboard');
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF5B21B6),
              Color(0xFF7C3AED),
              Color(0xFF5B21B6),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Skip button
              Align(
                alignment: Alignment.topRight,
                child: TextButton(
                  onPressed: _completeOnboarding,
                  child: Text(
                    'Skip',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 16,
                    ),
                  ),
                ),
              ),

              // Page view
              Expanded(
                child: PageView(
                  controller: _pageController,
                  onPageChanged: (i) => setState(() => _currentPage = i),
                  children: [
                    _OnboardingSlide(
                      key: const ValueKey(0),
                      icons: const [
                        (Icons.restaurant_rounded, AppColors.pastelPink),
                        (Icons.nightlight_round, AppColors.pastelPurple),
                        (Icons.water_drop_rounded, AppColors.pastelBlue),
                      ],
                      title: 'Track feeding, sleep & diapers',
                      subtitle:
                          'Log every feeding, diaper change, and sleep session with just a tap.',
                    ),
                    _OnboardingSlide(
                      key: const ValueKey(1),
                      icons: const [
                        (Icons.insights_rounded, AppColors.pastelGreen),
                      ],
                      title: 'Growth charts & milestones',
                      subtitle:
                          'Visualize your baby\'s growth and celebrate every milestone.',
                    ),
                    _OnboardingSlide(
                      key: const ValueKey(2),
                      icons: const [
                        (Icons.people_rounded, AppColors.pastelYellow),
                      ],
                      title: 'Share with caregivers',
                      subtitle:
                          'Invite partners, grandparents, or nannies to track together.',
                    ),
                  ],
                ),
              ),

              // Dot indicators
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(3, (i) {
                    final isActive = i == _currentPage;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: isActive ? 24 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: isActive
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    );
                  }),
                ),
              ),

              // Next / Get Started button
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      if (_currentPage < 2) {
                        _pageController.nextPage(
                          duration: const Duration(milliseconds: 400),
                          curve: Curves.easeOut,
                        );
                      } else {
                        _completeOnboarding();
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      _currentPage < 2 ? 'Next' : 'Get Started',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _OnboardingSlide extends StatelessWidget {
  final List<(IconData, Color)> icons;
  final String title;
  final String subtitle;

  const _OnboardingSlide({
    super.key,
    required this.icons,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Icon(s)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: icons.map((entry) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Container(
                  width: icons.length == 1 ? 100 : 72,
                  height: icons.length == 1 ? 100 : 72,
                  decoration: BoxDecoration(
                    color: entry.$2,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    entry.$1,
                    size: icons.length == 1 ? 48 : 32,
                    color: AppColors.primary,
                  ),
                ),
              );
            }).toList(),
          )
              .animate()
              .fadeIn(duration: 400.ms)
              .scale(
                begin: const Offset(0.5, 0.5),
                end: const Offset(1, 1),
                curve: Curves.elasticOut,
                duration: 600.ms,
              ),

          const SizedBox(height: 40),

          // Title
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: 0.5,
            ),
          )
              .animate()
              .fadeIn(delay: 200.ms, duration: 400.ms)
              .slideY(begin: 0.3, end: 0, curve: Curves.easeOut),

          const SizedBox(height: 16),

          // Subtitle
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w400,
              color: Colors.white.withValues(alpha: 0.7),
              height: 1.5,
            ),
          )
              .animate()
              .fadeIn(delay: 400.ms, duration: 400.ms)
              .slideY(begin: 0.3, end: 0, curve: Curves.easeOut),
        ],
      ),
    );
  }
}
