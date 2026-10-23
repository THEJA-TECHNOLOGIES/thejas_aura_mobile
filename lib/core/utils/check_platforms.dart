import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

class PlatformChecker {
  static bool _isAndroidTV = false;
  static bool _initialized = false;

  static bool get isWeb => kIsWeb;

  static bool get isIOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static bool get isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static bool get isAndroidTV => isAndroid && _isAndroidTV;

  static bool get isAndroidMobile => isAndroid && !isAndroidTV;

  static bool get isLinux =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.linux;

  static bool get isMacOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  static bool get isWindows =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  static bool get isDesktop => isLinux || isMacOS || isWindows;

  static Future<void> initialize() async {
    if (_initialized) return;

    if (!isAndroid) {
      _initialized = true;
      return;
    }

    try {
      final info = await DeviceInfoPlugin().androidInfo;

      _isAndroidTV =
          info.systemFeatures.contains('android.software.leanback') ||
          info.systemFeatures.contains('android.hardware.type.television');
    } catch (error, stackTrace) {
      debugPrint('Android TV detection failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      _isAndroidTV = false;
    } finally {
      _initialized = true;
    }
  }
}
