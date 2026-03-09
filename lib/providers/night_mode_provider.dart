import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final nightModeEnabledProvider = StateNotifierProvider<NightModeNotifier, bool>((ref) {
  return NightModeNotifier();
});

class NightModeNotifier extends StateNotifier<bool> {
  NightModeNotifier() : super(false) {
    _loadPref();
  }

  Future<void> _loadPref() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool('night_mode_auto') ?? true;
  }

  Future<void> toggle() async {
    state = !state;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('night_mode_auto', state);
  }
}

final isNightTimeProvider = StateNotifierProvider<NightTimeNotifier, bool>((ref) {
  return NightTimeNotifier();
});

class NightTimeNotifier extends StateNotifier<bool> {
  Timer? _timer;

  NightTimeNotifier() : super(_checkNightTime()) {
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      state = _checkNightTime();
    });
  }

  static bool _checkNightTime() {
    final hour = DateTime.now().hour;
    return hour >= 20 || hour < 6;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final nightModeActiveProvider = Provider<bool>((ref) {
  final enabled = ref.watch(nightModeEnabledProvider);
  final isNight = ref.watch(isNightTimeProvider);
  return enabled && isNight;
});
