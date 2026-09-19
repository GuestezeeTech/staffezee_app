import 'package:vibration/vibration.dart';
import 'package:flutter/services.dart';
import 'dart:io';

class VibrationService {
  static bool _isVibrationSupported = false;
  static bool _isInitialized = false;

  /// Initialize vibration service and check device support
  static Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Check if device supports vibration
      bool? hasVibrator = await Vibration.hasVibrator();
      _isVibrationSupported = hasVibrator == true;

      print('📳 Vibration support: $_isVibrationSupported');
      _isInitialized = true;
    } catch (e) {
      print('❌ Error initializing vibration service: $e');
      _isVibrationSupported = false;
      _isInitialized = true;
    }
  }

  /// Trigger vibration for notification received
  static Future<void> vibrateForNotification() async {
    // Always attempt HapticFeedback on iOS as it's very reliable
    if (Platform.isIOS) {
      HapticFeedback.vibrate();
    }

    if (!_isVibrationSupported) {
      print('⚠️ Vibration plugin not supported on this device');
      return;
    }

    try {
      // Check if device supports custom vibration patterns
      bool? hasCustomVibrationsSupport =
          await Vibration.hasCustomVibrationsSupport();

      if (hasCustomVibrationsSupport == true) {
        // Use custom vibration pattern for notifications
        // Pattern: [0, 500, 200, 500] - pause, vibrate, pause, vibrate
        await Vibration.vibrate(duration: 1000, pattern: [0, 500, 200, 500]);
        print('📳 Custom vibration pattern triggered for notification');
      } else {
        // Fallback to simple vibration
        await Vibration.vibrate(duration: 500);
        print('📳 Simple vibration triggered for notification');
      }
    } catch (e) {
      print('❌ Error triggering vibration plugin: $e');
      // Already attempted HapticFeedback on iOS, but for Android we try it as fallback here
      if (Platform.isAndroid) {
        try {
          HapticFeedback.heavyImpact();
          print('📳 Haptic feedback triggered as fallback on Android');
        } catch (hapticError) {
          print('❌ Error triggering haptic feedback: $hapticError');
        }
      }
    }
  }

  /// Trigger gentle vibration (for UI interactions)
  static Future<void> vibrateGentle() async {
    if (!_isVibrationSupported) return;

    try {
      await Vibration.vibrate(duration: 100);
      print('📳 Gentle vibration triggered');
    } catch (e) {
      print('❌ Error triggering gentle vibration: $e');
    }
  }

  /// Trigger strong vibration (for important notifications)
  static Future<void> vibrateStrong() async {
    // Always attempt heavy haptics on iOS
    if (Platform.isIOS) {
      HapticFeedback.heavyImpact();
      // Also trigger standard vibrate for more duration
      Future.delayed(Duration(milliseconds: 200), () => HapticFeedback.vibrate());
    }

    if (!_isVibrationSupported) return;

    try {
      bool? hasCustomVibrationsSupport =
          await Vibration.hasCustomVibrationsSupport();

      if (hasCustomVibrationsSupport == true) {
        // Strong pattern: longer vibration with pauses
        await Vibration.vibrate(duration: 1500, pattern: [0, 800, 300, 800]);
        print('📳 Strong vibration pattern triggered');
      } else {
        await Vibration.vibrate(duration: 800);
        print('📳 Strong vibration triggered');
      }
    } catch (e) {
      print('❌ Error triggering strong vibration: $e');
    }
  }

  /// Check if vibration is supported on this device
  static bool get isVibrationSupported => _isVibrationSupported;

  /// Cancel any ongoing vibration
  static Future<void> cancelVibration() async {
    try {
      await Vibration.cancel();
      print('📳 Vibration cancelled');
    } catch (e) {
      print('❌ Error cancelling vibration: $e');
    }
  }

  /// Test vibration functionality (for debugging/testing)
  static Future<void> testVibration() async {
    print('🧪 Testing vibration functionality...');
    await vibrateForNotification();
    await Future.delayed(const Duration(seconds: 2));
    await vibrateGentle();
    await Future.delayed(const Duration(seconds: 2));
    await vibrateStrong();
    print('🧪 Vibration test completed');
  }
}
