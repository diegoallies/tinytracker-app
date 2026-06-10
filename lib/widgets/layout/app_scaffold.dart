import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/connectivity_provider.dart';
import '../common/offline_banner.dart';
import '../common/quick_log_fab.dart';
import 'bottom_nav_bar.dart';

class AppScaffold extends ConsumerWidget {
  final Widget child;

  const AppScaffold({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).uri.toString();
    final showFab = location.startsWith('/dashboard') || location == '/';
    final offline = ref.watch(isOfflineProvider);
    // Keep the offline-queue flusher alive for the whole session.
    ref.watch(pendingWritesFlusherProvider);

    return Scaffold(
      // The shell must NOT resize for the keyboard — every screen inside has
      // its own Scaffold that already does. Both resizing at once collapses
      // the page to just the focused field over a void.
      resizeToAvoidBottomInset: false,
      body: LayoutBuilder(builder: (context, constraints) {
        // Inner screens sit ABOVE the nav bar but receive keyboard insets
        // measured from the SCREEN bottom — they'd over-inset by exactly the
        // nav bar's height, leaving a dead gap above the keyboard. Hand them
        // an inset measured from the body's bottom instead.
        final mq = MediaQuery.of(context);
        final reservedBelowBody = mq.size.height - constraints.maxHeight;
        final adjustedKeyboard =
            (mq.viewInsets.bottom - reservedBelowBody).clamp(0.0, double.infinity);

        return Column(
          children: [
            const OfflineBanner(),
            Expanded(
              child: MediaQuery(
                data: mq.copyWith(
                  viewInsets:
                      mq.viewInsets.copyWith(bottom: adjustedKeyboard),
                  // The banner already consumed the status-bar inset; stop
                  // the screens' own SafeArea/AppBar from padding twice.
                  padding:
                      offline ? mq.padding.copyWith(top: 0) : mq.padding,
                ),
                child: child,
              ),
            ),
          ],
        );
      }),
      bottomNavigationBar: const BottomNavBar(),
      floatingActionButton: showFab ? const QuickLogFAB() : null,
    );
  }
}
