import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final connectivityProvider = StreamProvider<List<ConnectivityResult>>(
  (ref) => Connectivity().onConnectivityChanged,
);

/// True only when the device reports no network path at all. Unknown/loading
/// counts as online so the banner never flashes on app start.
final isOfflineProvider = Provider<bool>((ref) {
  final results = ref.watch(connectivityProvider).valueOrNull;
  if (results == null || results.isEmpty) return false;
  return results.every((r) => r == ConnectivityResult.none);
});
