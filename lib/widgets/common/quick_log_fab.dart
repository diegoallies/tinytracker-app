import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../config/theme.dart';

class QuickLogFAB extends StatefulWidget {
  const QuickLogFAB({super.key});

  @override
  State<QuickLogFAB> createState() => _QuickLogFABState();
}

class _QuickLogFABState extends State<QuickLogFAB>
    with SingleTickerProviderStateMixin {
  bool _isOpen = false;
  late AnimationController _controller;
  late Animation<double> _expandAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _expandAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _isOpen = !_isOpen);
    if (_isOpen) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  void _close() {
    if (_isOpen) _toggle();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      height: 280,
      child: AnimatedBuilder(
        animation: _expandAnimation,
        builder: (context, _) {
          return Stack(
            alignment: Alignment.bottomRight,
            children: [
              // Scrim
              if (_isOpen)
                Positioned.fill(
                  child: GestureDetector(
                    onTap: _close,
                    child: Container(color: Colors.transparent),
                  ),
                ),
              // Mini FABs
              _buildMiniFAB(
                index: 2,
                icon: Icons.nightlight_round,
                label: 'Sleep',
                color: AppColors.pastelBlue,
                iconColor: const Color(0xFF2196F3),
                onTap: () {
                  _close();
                  context.go('/sleep');
                },
              ),
              _buildMiniFAB(
                index: 1,
                icon: Icons.water_drop_rounded,
                label: 'Diaper',
                color: AppColors.pastelYellow,
                iconColor: const Color(0xFFFF9800),
                onTap: () {
                  _close();
                  context.go('/diaper');
                },
              ),
              _buildMiniFAB(
                index: 0,
                icon: Icons.restaurant_rounded,
                label: 'Feed',
                color: AppColors.pastelPink,
                iconColor: const Color(0xFFE91E63),
                onTap: () {
                  _close();
                  context.go('/feeding');
                },
              ),
              // Main FAB
              Positioned(
                bottom: 0,
                right: 0,
                child: FloatingActionButton(
                  onPressed: _toggle,
                  backgroundColor: AppColors.primary,
                  elevation: 4,
                  child: Transform.rotate(
                    angle: _expandAnimation.value * 0.785,
                    child: const Icon(Icons.add, color: Colors.white, size: 28),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildMiniFAB({
    required int index,
    required IconData icon,
    required String label,
    required Color color,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    final offset = (index + 1) * 64.0;
    return Positioned(
      bottom: offset * _expandAnimation.value,
      right: 4,
      child: Opacity(
        opacity: _expandAnimation.value,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: context.palette.card,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: context.palette.text,
                ),
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: onTap,
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
