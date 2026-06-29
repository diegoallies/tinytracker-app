import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/env.dart';
import 'config/theme.dart';
import 'app/deep_links.dart';
import 'app/router.dart';
import 'providers/night_mode_provider.dart';
import 'services/notification_service.dart';
import 'services/pending_writes.dart';
import 'services/watch_bridge.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: '.env');

  await Supabase.initialize(
    url: Env.supabaseUrl,
    anonKey: Env.supabaseAnonKey,
  );

  await NotificationService.initialize();
  await PendingWrites.init();

  // Explicit container so the Apple Watch bridge can read providers + call the
  // same action classes the UI uses, outside the widget tree.
  final container = ProviderContainer();
  WatchBridge.instance.init(container);

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const TinyTrackApp(),
    ),
  );

  setupDeepLinks();
  // Push any logs that were saved offline last session.
  PendingWrites.flush();
  // Seed the watch with the current summary on launch.
  WatchBridge.instance.pushSummary();

  // Navigating away never blurs the focused field, so the keyboard would
  // stay up on the next page. Drop focus whenever the route changes.
  appRouter.routerDelegate.addListener(() {
    FocusManager.instance.primaryFocus?.unfocus();
  });

  // Password-recovery emails deep-link back into the app; supabase_flutter
  // consumes the link and emits this event once the recovery session is live.
  Supabase.instance.client.auth.onAuthStateChange.listen((state) {
    if (state.event == AuthChangeEvent.passwordRecovery) {
      appRouter.go('/reset-password');
    }
  });
}

class TinyTrackApp extends ConsumerWidget {
  const TinyTrackApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final isDark = mode == ThemeMode.dark;

    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      ),
    );

    return MaterialApp.router(
      title: 'TinyTrack',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: mode,
      routerConfig: appRouter,
      // Tap anywhere outside a field to dismiss the keyboard. Widgets with
      // their own tap handlers win the gesture arena, so buttons/fields are
      // unaffected; only dead space triggers the unfocus.
      builder: (context, child) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: child,
      ),
    );
  }
}
