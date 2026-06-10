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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: '.env');

  await Supabase.initialize(
    url: Env.supabaseUrl,
    anonKey: Env.supabaseAnonKey,
  );

  await NotificationService.initialize();
  await PendingWrites.init();

  runApp(
    const ProviderScope(
      child: TinyTrackApp(),
    ),
  );

  setupDeepLinks();
  // Push any logs that were saved offline last session.
  PendingWrites.flush();

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
    );
  }
}
