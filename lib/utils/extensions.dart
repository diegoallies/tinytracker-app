import 'package:flutter/material.dart';
import '../config/theme.dart';

extension ContextExtensions on BuildContext {
  ThemeData get theme => Theme.of(this);
  TextTheme get textTheme => theme.textTheme;
  ColorScheme get colorScheme => theme.colorScheme;
  MediaQueryData get mediaQuery => MediaQuery.of(this);
  double get screenWidth => mediaQuery.size.width;
  double get screenHeight => mediaQuery.size.height;
  EdgeInsets get padding => mediaQuery.padding;

  void _showAppSnackBar(
    String message, {
    required Color color,
    required IconData icon,
    Duration duration = const Duration(seconds: 3),
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final messenger = ScaffoldMessenger.of(this);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(message, maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        duration: duration,
        action: actionLabel != null
            ? SnackBarAction(
                label: actionLabel,
                textColor: color,
                // The snackbar outlives the screen that showed it; never run
                // a retry against a disposed State.
                onPressed: () {
                  if (mounted) onAction?.call();
                },
              )
            : null,
      ),
    );
  }

  void showSnackBar(String message, {bool isError = false}) {
    if (isError) {
      showErrorSnackBar(message);
    } else {
      _showAppSnackBar(message,
          color: AppColors.primaryLight, icon: Icons.info_outline_rounded);
    }
  }

  void showSuccessSnackBar(String message) {
    _showAppSnackBar(
      message,
      color: AppColors.success,
      icon: Icons.check_circle_rounded,
      duration: const Duration(seconds: 2),
    );
  }

  void showErrorSnackBar(String message, {VoidCallback? onRetry}) {
    _showAppSnackBar(
      message,
      color: AppColors.error,
      icon: Icons.error_outline_rounded,
      duration: const Duration(seconds: 4),
      actionLabel: onRetry != null ? 'Retry' : null,
      onAction: onRetry,
    );
  }
}

extension StringExtensions on String {
  String get capitalize => isEmpty ? '' : '${this[0].toUpperCase()}${substring(1)}';
}
