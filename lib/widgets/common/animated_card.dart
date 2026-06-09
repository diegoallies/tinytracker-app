import 'package:flutter/material.dart';
import '../../config/theme.dart';

class AnimatedCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final int index;
  final EdgeInsets? padding;
  final Color? color;

  /// Brand pastel accent. Prefer this over [color] for tinted cards: light
  /// mode gets the pastel fill, dark mode gets a normal dark card with the
  /// pastel as a border accent (see BuildContext.tintedCard) — so
  /// palette-based text stays readable in both modes.
  final Color? tint;

  const AnimatedCard({
    super.key,
    required this.child,
    this.onTap,
    this.index = 0,
    this.padding,
    this.color,
    this.tint,
  }) : assert(color == null || tint == null, 'use either color or tint');

  @override
  Widget build(BuildContext context) {
    final tinted = tint != null ? context.tintedCard(tint!) : null;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 300 + (index * 50)),
      curve: Curves.easeOut,
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, 20 * (1 - value)),
          child: Opacity(
            opacity: value,
            child: child,
          ),
        );
      },
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: padding ?? const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: tinted?.background ?? color ?? context.palette.card,
            border: tinted?.border,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: Theme.of(context).brightness == Brightness.dark ? 0.3 : 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}
