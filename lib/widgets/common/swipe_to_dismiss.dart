import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../utils/haptics.dart';

class SwipeToDismiss extends StatelessWidget {
  final String itemId;
  final Widget child;
  final Future<bool?> Function() onConfirmDismiss;
  final VoidCallback onDismissed;

  const SwipeToDismiss({
    super.key,
    required this.itemId,
    required this.child,
    required this.onConfirmDismiss,
    required this.onDismissed,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key(itemId),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => onConfirmDismiss(),
      onDismissed: (_) {
        Haptics.heavyTap();
        onDismissed();
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(
          color: Colors.red.shade400,
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Delete',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            SizedBox(width: 8),
            Icon(Icons.delete_outline, color: Colors.white, size: 22),
          ],
        ),
      ),
      child: child,
    );
  }
}
