import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

import 'router.dart';

/// Invite token from a cold-start deep link, parked until the splash screen
/// finishes its auth check and can route somewhere meaningful.
String? pendingInviteToken;

String? _tokenFrom(Uri uri) {
  // tinytracker://invite/<token>
  if (uri.scheme != 'tinytracker' || uri.host != 'invite') return null;
  if (uri.pathSegments.isEmpty) return null;
  final token = uri.pathSegments.first.trim();
  return token.isEmpty ? null : token;
}

/// Call once from main() after runApp. Handles both the link that launched
/// the app (parked for splash) and links arriving while it runs.
void setupDeepLinks() {
  final appLinks = AppLinks();

  appLinks.getInitialLink().then((uri) {
    if (uri == null) return;
    pendingInviteToken = _tokenFrom(uri);
  }).catchError((Object e) {
    debugPrint('initial deep link failed: $e');
  });

  appLinks.uriLinkStream.listen((uri) {
    final token = _tokenFrom(uri);
    if (token != null) {
      appRouter.go('/invites?code=$token');
    }
  }, onError: (Object e) {
    debugPrint('deep link stream error: $e');
  });
}
