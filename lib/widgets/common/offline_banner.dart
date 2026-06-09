import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../config/design_tokens.dart';
import '../../config/theme.dart';
import '../../providers/connectivity_provider.dart';
import '../../services/pending_writes.dart';

/// Slim banner shown across the top of the app shell while offline.
/// Renders nothing (zero layout cost) when online with an empty sync queue.
class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offline = ref.watch(isOfflineProvider);
    final queue = PendingWrites.listenable();

    Widget strip(Color color, IconData icon, String message) {
      return Material(
        color: color,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: 6,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: Colors.white, size: 16),
                const SizedBox(width: AppSpacing.xs),
                Flexible(
                  child: Text(
                    message,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Colors.white),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    Widget buildFor(int pending) {
      if (offline) {
        final suffix = pending > 0
            ? ' · $pending saved locally'
            : ' — feeds & nappies still save locally';
        return strip(AppColors.warning, Icons.wifi_off_rounded,
            'You’re offline$suffix');
      }
      if (pending > 0) {
        return strip(AppColors.info, Icons.sync_rounded,
            'Syncing $pending saved ${pending == 1 ? 'entry' : 'entries'}…');
      }
      return const SizedBox.shrink();
    }

    final child = queue == null
        ? buildFor(0)
        : ValueListenableBuilder<Box<Map>>(
            valueListenable: queue,
            builder: (context, box, _) => buildFor(box.length),
          );

    return AnimatedSize(
      duration: AppMotion.normal,
      curve: AppMotion.ease,
      child: child,
    );
  }
}
