import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

/// Hive-backed queue of log inserts that couldn't reach Supabase (offline,
/// DNS failure, timeouts). Entries are flushed automatically when
/// connectivity returns and on app start, oldest first.
///
/// Semantics: an enqueued entry is treated as a successful log by the UI
/// ("saved, will sync") — the banner shows how many are waiting.
class PendingWrites {
  PendingWrites._();

  static const _boxName = 'pending_writes';
  static bool _initialized = false;

  /// [testPath] lets unit tests use a plain directory instead of the
  /// Flutter app-documents location.
  static Future<void> init({String? testPath}) async {
    if (_initialized) return;
    if (testPath != null) {
      Hive.init(testPath);
    } else {
      await Hive.initFlutter();
    }
    await Hive.openBox<Map>(_boxName);
    _initialized = true;
  }

  static Box<Map> get _box => Hive.box<Map>(_boxName);

  static int get count => _initialized ? _box.length : 0;

  /// Listen for queue-size changes (offline banner chip).
  static ValueListenable<Box<Map>>? listenable() =>
      _initialized ? _box.listenable() : null;

  static Future<void> enqueue(String table, Map<String, dynamic> payload) async {
    if (!_initialized) await init();
    await _box.add({
      'table': table,
      'payload': payload,
      'queued_at': DateTime.now().toUtc().toIso8601String(),
    });
    debugPrint('pending_writes: queued $table insert (${_box.length} pending)');
  }

  /// True when [e] looks like "couldn't reach the server" rather than the
  /// server rejecting the data. PostgrestException means the request arrived.
  static bool isConnectivityError(Object e) => e is! PostgrestException;

  static bool _flushing = false;

  /// Attempts to send all queued entries, oldest first. Stops at the first
  /// connectivity failure (still offline). Entries the server REJECTS
  /// (PostgrestException) are dropped after logging — they would poison the
  /// queue forever. Returns how many entries were successfully synced.
  static Future<int> flush({
    Future<void> Function(String table, Map<String, dynamic> payload)? insert,
  }) async {
    if (!_initialized || _flushing || _box.isEmpty) return 0;
    _flushing = true;
    var synced = 0;
    try {
      final doInsert = insert ??
          (String table, Map<String, dynamic> payload) async {
            await SupabaseService.client.from(table).insert(payload);
          };

      // Keys snapshot — entries enqueued mid-flush are picked up next time.
      final keys = _box.keys.toList();
      for (final key in keys) {
        final raw = _box.get(key);
        if (raw == null) continue;
        final table = raw['table'] as String;
        final payload = Map<String, dynamic>.from(raw['payload'] as Map);
        try {
          await doInsert(table, payload);
          await _box.delete(key);
          synced++;
        } catch (e) {
          if (isConnectivityError(e)) {
            debugPrint('pending_writes: still offline, ${_box.length} left');
            break;
          }
          // Server saw it and said no — drop it rather than retry forever.
          debugPrint('pending_writes: dropping rejected $table entry: $e');
          await _box.delete(key);
        }
      }
      if (synced > 0) {
        debugPrint('pending_writes: synced $synced queued entries');
      }
      return synced;
    } finally {
      _flushing = false;
    }
  }
}
