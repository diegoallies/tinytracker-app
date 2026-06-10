import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

import '../services/supabase_service.dart';
import 'router.dart';

/// Invite token parked until the app can act on it - set on cold-start links
/// (consumed by the splash screen once the session is restored) and on links
/// arriving while logged out (consumed by the login screen after sign-in).
String? pendingInviteToken;

String? _tokenFrom(Uri uri) {
  // tinytracker://invite/<token>
  if (uri.scheme != 'tinytracker' || uri.host != 'invite') return null;
  if (uri.pathSegments.isEmpty) return null;
  final token = uri.pathSegments.first.trim();
  return token.isEmpty ? null : token;
}

/// Call once from main() after runApp.
///
/// app_links re-emits the launch link on the stream when the listener
/// attaches, so a single stream listener covers both cold and warm starts -
/// no separate getInitialLink() call (which would double-deliver).
void setupDeepLinks() {
  AppLinks().uriLinkStream.listen((uri) {
    final token = _tokenFrom(uri);
    if (token == null) return;

    if (SupabaseService.currentUser == null) {
      // Session not restored yet (cold start) or genuinely logged out -
      // park it; splash/login will pick it up.
      pendingInviteToken = token;
    } else {
      pendingInviteToken = null;
      appRouter.go('/invites?code=$token');
    }
  }, onError: (Object e) {
    debugPrint('deep link stream error: $e');
  });
}