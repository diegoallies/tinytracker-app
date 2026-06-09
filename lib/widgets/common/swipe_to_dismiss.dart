import 'package:flutter/material.dart';
import '../../utils/haptics.dart';

class SwipeToDismiss extends StatefulWidget {
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
  State<SwipeToDismiss> createState() => _SwipeToDismissState();
}

class _SwipeToDismissState extends State<SwipeToDismiss> {
  // Once Dismissible animates out, Flutter requires it be removed from the
  // tree by the next frame. Parents that delete via an async network call +
  // provider refetch can't remove it that fast, so we hide ourselves
  // synchronously and let the parent's eventual refetch clean up the data.
  bool _dismissed = false;

  @override
  void didUpdateWidget(covariant SwipeToDismiss oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the parent reuses this widget for a different item id (very rare due
    // to keying, but possible), reset the dismissed state.
    if (oldWidget.itemId != widget.itemId) {
      _dismissed = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();

    return Dismissible(
      key: Key(widget.itemId),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => widget.onConfirmDismiss(),
      onDismissed: (_) {
        Haptics.heavyTap();
        if (mounted) setState(() => _dismissed = true);
        widget.onDismissed();
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
      child: widget.child,
    );
  }
}
