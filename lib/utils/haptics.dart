import 'package:flutter/services.dart';

/// Semantic haptic feedback utility for consistent tactile responses.
class Haptics {
  Haptics._();

  /// Light tap for selections, navigation, quick actions.
  static void lightTap() => HapticFeedback.lightImpact();

  /// Medium tap for timer start/stop, save buttons.
  static void mediumTap() => HapticFeedback.mediumImpact();

  /// Heavy tap for destructive actions like delete.
  static void heavyTap() => HapticFeedback.heavyImpact();

  /// Selection click for toggling options, type selectors.
  static void selectionClick() => HapticFeedback.selectionClick();
}
