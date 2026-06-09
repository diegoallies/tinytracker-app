import 'package:flutter/material.dart';

/// Spacing scale. Use these instead of magic numbers so the whole app
/// shares one rhythm. Screen gutters are [AppSpacing.gutter].
abstract final class AppSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;

  /// Horizontal screen gutter.
  static const double gutter = 20;

  /// Standard padding presets.
  static const EdgeInsets screen = EdgeInsets.symmetric(horizontal: gutter);
  static const EdgeInsets screenWithTop = EdgeInsets.fromLTRB(gutter, md, gutter, 0);
  static const EdgeInsets card = EdgeInsets.all(md);
  static const EdgeInsets cardLarge = EdgeInsets.all(lg);
  static const EdgeInsets sheet = EdgeInsets.fromLTRB(gutter, sm, gutter, xl);
}

/// Corner radius scale.
abstract final class AppRadius {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 28;

  static const BorderRadius smAll = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius mdAll = BorderRadius.all(Radius.circular(md));
  static const BorderRadius lgAll = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius xlAll = BorderRadius.all(Radius.circular(xl));
  static const BorderRadius xxlAll = BorderRadius.all(Radius.circular(xxl));
  static const BorderRadius sheetTop =
      BorderRadius.vertical(top: Radius.circular(xxl));
}

/// Motion durations + curves, tuned for a calm, premium feel.
abstract final class AppMotion {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 250);
  static const Duration slow = Duration(milliseconds: 400);
  static const Duration entrance = Duration(milliseconds: 500);

  static const Curve ease = Curves.easeOutCubic;
  static const Curve emphasized = Curves.easeOutQuart;
  static const Curve spring = Curves.easeOutBack;
}

/// Elevation/shadow presets. Brightness-aware: pass the theme brightness
/// (shadows need to be stronger in dark mode to read at all).
abstract final class AppShadows {
  static List<BoxShadow> card(Brightness brightness) => [
        BoxShadow(
          color: Colors.black.withValues(
            alpha: brightness == Brightness.dark ? 0.35 : 0.06,
          ),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
      ];

  static List<BoxShadow> floating(Brightness brightness) => [
        BoxShadow(
          color: Colors.black.withValues(
            alpha: brightness == Brightness.dark ? 0.5 : 0.12,
          ),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
      ];
}
