import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// Saves screenshots emitted by integration tests to build/screenshots/.
/// Run with:
///   flutter drive --driver=test_driver/integration_test.dart \
///     --target=integration_test/smoke_test.dart -d emulator-5554
Future<void> main() => integrationDriver(
      onScreenshot: (String name, List<int> bytes, [Map<String, Object?>? args]) async {
        final file = File('build/screenshots/$name.png')
          ..createSync(recursive: true);
        file.writeAsBytesSync(bytes);
        return true;
      },
    );
