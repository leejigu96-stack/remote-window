// Tailscale 설치 여부 체크 + Play Store 안내
//
// MainActivity.kt 의 platform channel 호출.

import 'package:flutter/services.dart';

class Tailscale {
  static const _ch = MethodChannel('remote_window/native');
  static const String packageName = 'com.tailscale.ipn';

  /// Tailscale 앱이 폰에 깔려있나?
  static Future<bool> isInstalled() async {
    try {
      final r = await _ch.invokeMethod<bool>(
        'isPackageInstalled',
        {'package': packageName},
      );
      return r ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Play Store 의 Tailscale 페이지 열기 (없으면 웹 폴백)
  static Future<void> openPlayStore() async {
    try {
      await _ch.invokeMethod('openPlayStore', {'package': packageName});
    } catch (_) {}
  }

  /// Tailscale 앱 실행 (있을 때만)
  static Future<bool> launch() async {
    try {
      final r = await _ch.invokeMethod<bool>(
        'launchApp',
        {'package': packageName},
      );
      return r ?? false;
    } catch (_) {
      return false;
    }
  }
}
