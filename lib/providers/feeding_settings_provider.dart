import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Provider to control whether breast feeding options are shown
final showBreastFeedingProvider = StateNotifierProvider<ShowBreastFeedingNotifier, bool>((ref) {
  return ShowBreastFeedingNotifier();
});

class ShowBreastFeedingNotifier extends StateNotifier<bool> {
  ShowBreastFeedingNotifier() : super(false) {
    _load();
  }

  static const _key = 'show_breast_feeding';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    // Default to false (bottle only) as requested
    state = prefs.getBool(_key) ?? false;
  }

  Future<void> toggle() async {
    state = !state;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, state);
  }

  Future<void> setEnabled(bool enabled) async {
    state = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, state);
  }
}
