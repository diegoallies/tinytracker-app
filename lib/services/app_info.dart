import 'package:package_info_plus/package_info_plus.dart';

/// Loaded once at startup so screens can read the version synchronously.
///
/// Always reflects the installed binary — including CI's build-number
/// override — unlike a hardcoded string, which is how Settings ended up
/// showing 1.1.2 on a 1.1.7 build.
class AppInfo {
  static PackageInfo? _info;

  static Future<void> init() async {
    _info = await PackageInfo.fromPlatform();
  }

  /// "v1.1.7 (16)", or an empty string if init() hasn't completed.
  static String get display =>
      _info == null ? '' : 'v${_info!.version} (${_info!.buildNumber})';
}
