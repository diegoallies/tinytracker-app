import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tinytrack_app/services/pending_writes.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('pending_writes_test');
    await PendingWrites.init(testPath: tempDir.path);
  });

  tearDownAll(() async {
    await tempDir.delete(recursive: true);
  });

  test('enqueue then flush sends entries oldest-first and clears the queue',
      () async {
    await PendingWrites.enqueue('feedings', {'type': 'bottle', 'amount_ml': 120});
    await PendingWrites.enqueue('diapers', {'type': 'wet'});
    expect(PendingWrites.count, 2);

    final sent = <String>[];
    final synced = await PendingWrites.flush(
      insert: (table, payload) async => sent.add(table),
    );

    expect(synced, 2);
    expect(sent, ['feedings', 'diapers']);
    expect(PendingWrites.count, 0);
  });

  test('flush stops at a connectivity failure and keeps remaining entries',
      () async {
    await PendingWrites.enqueue('feedings', {'a': 1});
    await PendingWrites.enqueue('feedings', {'a': 2});

    var calls = 0;
    final synced = await PendingWrites.flush(
      insert: (table, payload) async {
        calls++;
        if (calls == 2) throw const SocketException('offline again');
      },
    );

    expect(synced, 1);
    expect(PendingWrites.count, 1, reason: 'second entry stays queued');

    // Cleanup for next test.
    await PendingWrites.flush(insert: (t, p) async {});
    expect(PendingWrites.count, 0);
  });

  test('server-rejected entries are dropped, not retried forever', () async {
    await PendingWrites.enqueue('feedings', {'bad': true});
    await PendingWrites.enqueue('feedings', {'good': true});

    final sent = <Map<String, dynamic>>[];
    final synced = await PendingWrites.flush(
      insert: (table, payload) async {
        if (payload['bad'] == true) {
          throw const PostgrestException(message: 'constraint violation');
        }
        sent.add(payload);
      },
    );

    expect(synced, 1);
    expect(sent.single['good'], true);
    expect(PendingWrites.count, 0, reason: 'rejected entry was dropped');
  });

  test('isConnectivityError treats PostgrestException as non-connectivity',
      () {
    expect(
      PendingWrites.isConnectivityError(
          const PostgrestException(message: 'x')),
      isFalse,
    );
    expect(
      PendingWrites.isConnectivityError(const SocketException('x')),
      isTrue,
    );
  });
}
