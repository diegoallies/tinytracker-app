import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/theme.dart';

class NightModeToggle extends StatefulWidget {
  const NightModeToggle({super.key});

  @override
  State<NightModeToggle> createState() => _NightModeToggleState();
}

class _NightModeToggleState extends State<NightModeToggle> {
  bool _isNightMode = false;

  @override
  void initState() {
    super.initState();
    _loadPref();
  }

  Future<void> _loadPref() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _isNightMode = prefs.getBool('night_mode') ?? false);
  }

  Future<void> _toggle() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _isNightMode = !_isNightMode);
    await prefs.setBool('night_mode', _isNightMode);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _toggle,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: _isNightMode ? AppColors.primary.withValues(alpha: 0.2) : AppColors.surface,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          _isNightMode ? Icons.wb_sunny_rounded : Icons.nightlight_round,
          size: 20,
          color: _isNightMode ? AppColors.primary : AppColors.muted,
        ),
      ),
    );
  }
}
