import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class OrientationLock {
  const OrientationLock._();

  static bool get _isNativeMobile {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  static Future<void> appPortraitOnly() async {
    if (!_isNativeMobile) return;
    try {
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    } catch (_) {
      return;
    }
  }

  static Future<void> operatorDisplayLandscapeOnly() async {
    if (!_isNativeMobile) return;
    try {
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } catch (_) {
      return;
    }
  }
}
