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

    return Scaffold(
      body: Column(
        children: [
          const OfflineBanner(),
          Expanded(
            // The banner already consumed the status-bar inset; stop the
            // screens' own SafeArea/AppBar from padding a second time.
            child: MediaQuery.removePadding(
              context: context,
              removeTop: offline,
              child: child,
            ),
          ),
        ],
      ),
      bottomNavigationBar: const BottomNavBar(),
      floatingActionButton: showFab ? const QuickLogFAB() : null,
    );
  }
}
