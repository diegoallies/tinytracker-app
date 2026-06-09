import 'package:flutter/material.dart';

import '../../config/design_tokens.dart';
import '../../config/theme.dart';
import '../../utils/haptics.dart';

/// Shared confirmation dialog used across the app, replacing the
/// hand-rolled AlertDialogs in every screen.
///
/// Returns true when the user confirms. Destructive actions get a red
/// confirm button and a warning icon.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool destructive = false,
  IconData? icon,
}) async {
  Haptics.lightTap();
  final accent = destructive ? AppColors.error : AppColors.primary;
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.12),
          borderRadius: AppRadius.lgAll,
        ),
        child: Icon(
          icon ?? (destructive ? Icons.delete_outline_rounded : Icons.help_outline_rounded),
          color: accent,
          size: 26,
        ),
      ),
      title: Text(title, textAlign: TextAlign.center),
      content: Text(message, textAlign: TextAlign.center),
      actionsAlignment: MainAxisAlignment.center,
      actionsPadding: const EdgeInsets.fromLTRB(
        AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
      actions: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(false),
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.palette.muted,
                  side: BorderSide(color: context.palette.border),
                  minimumSize: const Size(0, 48),
                ),
                child: Text(cancelLabel),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: ElevatedButton(
                onPressed: () {
                  Haptics.mediumTap();
                  Navigator.of(context).pop(true);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: accent,
                  minimumSize: const Size(0, 48),
                ),
                child: Text(confirmLabel),
              ),
            ),
          ],
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Confirmation preset for delete actions.
Future<bool> showDeleteDialog(
  BuildContext context, {
  required String what,
  String? message,
}) {
  return showConfirmDialog(
    context,
    title: 'Delete $what?',
    message: message ?? 'This can’t be undone.',
    confirmLabel: 'Delete',
    destructive: true,
  );
}
