import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../services/supabase_service.dart';

/// Splash screen matching TinyTrack web - purple baby icon, animated.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _navigate();
  }

  Future<void> _navigate() async {
    await Future.delayed(const Duration(milliseconds: 2500));
    if (!mounted) return;

    final isLoggedIn = SupabaseService.currentUser != null;
    if (isLoggedIn) {
      context.go('/dashboard');
    } else {
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Baby icon in purple circle
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: const Color(0xFF7C3AED).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.child_care,
                size: 56,
                color: Color(0xFF7C3AED),
              ),
            )
                .animate()
                .scale(
                  begin: const Offset(0.5, 0.5),
                  end: const Offset(1.0, 1.0),
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.elasticOut,
                )
                .fadeIn(duration: const Duration(milliseconds: 400)),
            const SizedBox(height: 24),
            // App name
            const Text(
              'TinyTrack',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A1A2E),
                letterSpacing: -0.5,
              ),
            )
                .animate()
                .fadeIn(
                  delay: const Duration(milliseconds: 300),
                  duration: const Duration(milliseconds: 500),
                )
                .slideY(
                  begin: 0.3,
                  delay: const Duration(milliseconds: 300),
                  duration: const Duration(milliseconds: 500),
                ),
            const SizedBox(height: 8),
            // Tagline
            const Text(
              'Track every precious moment',
              style: TextStyle(
                fontSize: 14,
                color: Color(0xFF9CA3AF),
                letterSpacing: 0.2,
              ),
            )
                .animate()
                .fadeIn(
                  delay: const Duration(milliseconds: 600),
                  duration: const Duration(milliseconds: 500),
                ),
            const SizedBox(height: 48),
            // Loading indicator
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation<Color>(
                  const Color(0xFF7C3AED).withOpacity(0.6),
                ),
              ),
            )
                .animate()
                .fadeIn(
                  delay: const Duration(milliseconds: 900),
                  duration: const Duration(milliseconds: 400),
                ),
          ],
        ),
      ),
    );
  }
}
