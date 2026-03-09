import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../common/quick_log_fab.dart';
import 'bottom_nav_bar.dart';

class AppScaffold extends StatelessWidget {
  final Widget child;

  const AppScaffold({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    final showFab = location.startsWith('/dashboard') || location == '/';

    return Scaffold(
      body: child,
      bottomNavigationBar: const BottomNavBar(),
      floatingActionButton: showFab ? const QuickLogFAB() : null,
    );
  }
}
