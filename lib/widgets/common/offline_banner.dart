import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/design_tokens.dart';
import '../../config/theme.dart';
import '../../providers/connectivity_provider.dart';

/// Slim banner shown across the top of the app shell while offline.
/// Renders nothing (zero layout cost) when online.
class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offline = ref.watch(isOfflineProvider);

    return AnimatedSize(
      duration: AppMotion.normal,
      curve: AppMotion.ease,
      child: offline
          ? Material(
              color: AppColors.warning,
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
                      const Icon(Icons.wifi_off_rounded,
                          color: Colors.white, size: 16),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        'You’re offline — new entries won’t save until you reconnect',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Colors.white),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            )
          : const SizedBox.shrink(),
    );
  }
}
