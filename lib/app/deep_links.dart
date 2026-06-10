import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/supabase_service.dart';
import 'router.dart';

const _prefsKey = 'pending_invite_token';

/// Invite token parked until the app can act on it. Persisted so it survives
/// the register -> confirm email -> reopen -> sign in journey.
String? pendingInviteToken;

Future<void> parkPendingInvite(String token) async {
  pendingInviteToken = token;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, token);
  } catch (e) {
    debugPrint('could not persist pending invite: $e');
  }
}

/// Returns the parked token (memory first, then disk) and clears both.
Future<String?> consumePendingInvite() async {
  var token = pendingInviteToken;
  pendingInviteToken = null;
  try {
    final prefs = await SharedPreferences.getInstance();
    token ??= prefs.getString(_prefsKey);
    await prefs.remove(_prefsKey);
  } catch (e) {
    debugPrint('could not read pending invite: $e');
  }
  return token;
}

String? _tokenFrom(Uri uri) {
  // tinytracker://invite/<token>
  if (uri.scheme != 'tinytracker' || uri.host != 'invite') return null;
  if (uri.pathSegments.isEmpty) return null;
  final token = uri.pathSegments.first.trim();
  return token.isEmpty ? null : token;
}

/// Call once from main() after runApp.
///
/// app_links re-emits the launch link when the listener attaches, so a single
/// stream listener covers cold and warm starts.
void setupDeepLinks() {
  AppLinks().uriLinkStream.listen((uri) async {
    final token = _tokenFrom(uri);
    if (token == null) return;

    await parkPendingInvite(token);
    if (SupabaseService.currentUser == null) {
      // New invitee: land on registration with their email locked in.
      appRouter.go('/register?invite=$token');
    } else {
      await consumePendingInvite();
      appRouter.go('/invites?code=$token');
    }
  }, onError: (Object e) {
    debugPrint('deep link stream error: $e');
  });
}
