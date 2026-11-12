import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

/// Opens OS settings so staff can enable notifications.
///
/// iOS opens Settings → this app. Android 8+ opens the app notification screen.
class NotificationSettingsLauncher {
  static const MethodChannel _channel =
      MethodChannel('com.guestezee.staff/app_settings');

  static Future<bool> open() async {
    if (kIsWeb) return false;

    if (Platform.isIOS) {
      try {
        final opened = await _channel.invokeMethod<bool>('openAppSettings');
        return opened == true;
      } catch (_) {
        return false;
      }
    }

    try {
      final opened =
          await _channel.invokeMethod<bool>('openNotificationSettings');
      if (opened == true) return true;
    } catch (_) {}

    try {
      return await openAppSettings();
    } catch (_) {
      return false;
    }
  }
}
