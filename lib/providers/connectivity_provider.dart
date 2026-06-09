import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/pending_writes.dart';

final connectivityProvider = StreamProvider<List<ConnectivityResult>>(
  (ref) => Connectivity().onConnectivityChanged,
);

/// Flushes offline-queued logs the moment connectivity comes back.
/// Watched once from the app shell so it lives for the whole session.
final pendingWritesFlusherProvider = Provider<void>((ref) {
  ref.listen<bool>(isOfflineProvider, (wasOffline, isOffline) {
    if (wasOffline == true && !isOffline) {
      PendingWrites.flush();
    }
  });
});

/// True only when the device reports no network path at all. Unknown/loading
/// counts as online so the banner never flashes on app start.
final isOfflineProvider = Provider<bool>((ref) {
  final results = ref.watch(connectivityProvider).valueOrNull;
  if (results == null || results.isEmpty) return false;
  return results.every((r) => r == ConnectivityResult.none);
});
