import 'dart:convert';
import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/services.dart';
import 'package:guestezee_staffs_app/Services/continuous_sound_service.dart';
import 'package:guestezee_staffs_app/Services/high_priority_badge_service.dart';
import 'package:guestezee_staffs_app/Services/local_storage_service.dart';
import 'package:guestezee_staffs_app/Services/Notifictaion%20service/alarm_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Background message handler for FCM
/// This function runs in a separate isolate when the app is in background/terminated
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print('🚀 BACKGROUND HANDLER CALLED - App state: Background/Terminated');
  print('📱 Background message received: ${message.messageId}');
  print('📱 Message data: ${message.data}');
  print('📱 Full Background Notification Response Body: ${message.toMap()}');

  await LocalStorageService.init();
  if (!LocalStorageService.isLoggedIn) {
    print('🔐 Background FCM: user logged out – skipping alarm/sound');
    if (Platform.isAndroid) {
      await _stopAndroidOrderAlarmService();
    }
    return;
  }

  // Silent token-validation push (from logout check) – no alarm/sound/UI.
  if (_isTestPayload(message.data)) {
    print('🔕 Background: test notification (testing:true) – ignoring');
    return;
  }

  // Extract task ID and status first (support data-only payloads: title in data['title'])
  final int? taskId = _extractTaskId(message);
  final String? taskStatus = message.data['title']?.toString() ??
      message.notification?.title?.toString();

  print('🔊 Background: Extracted task ID: $taskId');
  print('🔊 Background: Task status from notification: $taskStatus');

  // Handle escalated / cancelled / completed - stop any continuous sound/alarm, do NOT start alarm.
  // NOTE: On Android in background we let the native CustomFirebaseMessagingService
  //       send a mute command to OrderAlertService directly (method channels from
  //       background isolate are unreliable). Here we only handle iOS.
  final bool isStopOnlyStatus = taskStatus != null &&
      (taskStatus.toLowerCase() == 'escalated' ||
          taskStatus.toLowerCase() == 'cancelled' ||
          taskStatus.toLowerCase() == 'completed');

  if (isStopOnlyStatus && taskId != null) {
    print('🚨 Background: $taskStatus notification received for task $taskId');
    if (taskStatus.toLowerCase() == 'escalated') {
      await HighPriorityBadgeService.recordEscalationNotification(
        taskId: taskId,
      );
    }
    await ContinuousSoundService.stopTaskSound(taskId);

    if (Platform.isIOS) {
      // Background isolate cannot stop the main isolate's looping player.
      // Queue IDs so resume applies stopAllAlarms in the main isolate.
      try {
        final prefs = await SharedPreferences.getInstance();
        final existing = prefs.getString('pending_stop_alarm_task_ids');
        List<int> ids = <int>[];
        if (existing != null && existing.isNotEmpty) {
          try {
            final decoded = jsonDecode(existing);
            if (decoded is List) {
              for (final e in decoded) {
                if (e is int) {
                  ids.add(e);
                } else if (e is String) {
                  final n = int.tryParse(e);
                  if (n != null) ids.add(n);
                }
              }
            }
          } catch (_) {}
        }
        if (!ids.contains(taskId)) ids.add(taskId);
        await prefs.setString('pending_stop_alarm_task_ids', jsonEncode(ids));
        print(
            '🔊 Background (iOS): queued stop loop for task $taskId on app resume');
      } catch (e) {
        print('❌ Background (iOS): failed to queue stop alarm: $e');
      }

      // Play short ~2s alert in this isolate (matches Android short alert).
      try {
        await AlarmService.initialize();
        await AlarmService.playShortStatusAlertForTask(
          taskId: taskId,
          title: taskStatus,
          body: message.data['body']?.toString(),
          messageData: Map<String, dynamic>.from(message.data),
          timeoutSeconds: 2,
          isForeground: false,
        );
      } catch (e) {
        print('❌ Background (iOS): short status alert failed: $e');
      }
    } else {
      print(
          '🔊 Background: Android Escalated/Cancelled handled natively (short alert)');
    }
  }

  // Start alarm only for Assigned (not for Escalated/Cancelled/Completed)
  if (!isStopOnlyStatus) {
    print('🔔 Background: triggering alarm for continuous ring');
    final title = message.data['title'] ?? message.notification?.title;
    final body = message.data['body'] ?? message.notification?.body;
    if (taskId != null) {
      if (Platform.isIOS) {
        await AlarmService.startAlarmForTask(
          taskId: taskId,
          title: title?.toString(),
          body: body?.toString(),
          loop: true,
          messageId: message.messageId,
          messageData: Map<String, dynamic>.from(message.data),
          isForeground: false,
        );
      } else if (Platform.isAndroid) {
        print(
            '🔔 Android background: skipping method-channel start; native FCM service should start OrderAlertService');
      }
    } else {
      if (Platform.isIOS) {
        await AlarmService.playAlarm(
          title: title?.toString(),
          body: body?.toString(),
          loop: true,
          messageId: message.messageId,
          messageData: Map<String, dynamic>.from(message.data),
          isForeground: false,
        );
      } else if (Platform.isAndroid) {
        print(
            '🔔 Android background (non-task): letting native FCM/system handle notification sound only');
      }
    }
  } else {
    print('🔔 Background: Escalated/Cancelled/Completed - no alarm start');
  }

  // Legacy one-shot background sound path has been removed to avoid double audio.

  print('📱 Background message handler called - notification arrived');
}

// Android native alarm service integration (foreground service for background alarms)
const MethodChannel _androidAlarmChannel =
    MethodChannel('staff/alarm_service');

Future<void> _stopAndroidOrderAlarmService() async {
  if (!Platform.isAndroid) return;
  try {
    await _androidAlarmChannel.invokeMethod('stopOrderAlarmService');
    print('🔇 Android OrderAlertService stopped (logged out)');
  } catch (e) {
    print('❌ Error stopping Android OrderAlertService: $e');
  }
}

/// Detect the silent token-validation push (`{"testing":true}`) sent during
/// logout so background devices ignore it (no alarm/sound/UI).
bool _isTestPayload(Map<String, dynamic> data) {
  final direct = data['testing']?.toString().toLowerCase();
  if (direct == 'true' || direct == '1') return true;

  final msg = data['message']?.toString();
  if (msg != null && msg.isNotEmpty) {
    // The message value can be double-encoded, e.g. "{\"testing\":true}".
    final normalized =
        msg.replaceAll('\\', '').replaceAll(' ', '').toLowerCase();
    if (normalized.contains('"testing":true')) return true;

    try {
      dynamic decoded = jsonDecode(msg);
      if (decoded is String) decoded = jsonDecode(decoded);
      if (decoded is Map) {
        final t = decoded['testing'];
        if (t == true || t?.toString().toLowerCase() == 'true') return true;
      }
    } catch (_) {}
  }
  return false;
}

/// Extract task ID from notification data
int? _extractTaskId(RemoteMessage message) {
  try {
    // Try to get task_id from data
    String? taskIdStr = message.data['task_id'];
    if (taskIdStr != null) {
      return int.tryParse(taskIdStr);
    }

    // Try to get order_id from data (sometimes used instead of task_id)
    String? orderIdStr = message.data['order_id'];
    if (orderIdStr != null) {
      return int.tryParse(orderIdStr);
    }

    // Try to extract from message field if it contains JSON
    String? messageStr = message.data['message'];
    if (messageStr != null) {
      try {
        print('🔊 Background: Parsing message JSON: $messageStr');

        // First decode
        final dynamic firstDecode = jsonDecode(messageStr);
        print(
            '🔊 Background: First decode: $firstDecode (type: ${firstDecode.runtimeType})');

        // If it's still a string, decode again
        if (firstDecode is String) {
          print('🔊 Background: JSON is string, decoding again...');
          final dynamic secondDecode = jsonDecode(firstDecode);
          print(
              '🔊 Background: Second decode: $secondDecode (type: ${secondDecode.runtimeType})');

          if (secondDecode is Map<String, dynamic>) {
            String? taskIdStr = secondDecode['task_id']?.toString();
            if (taskIdStr != null) {
              print('🔊 Background: Found task_id in message: $taskIdStr');
              return int.tryParse(taskIdStr);
            }
            String? orderIdStr = secondDecode['order_id']?.toString();
            if (orderIdStr != null) {
              print('🔊 Background: Found order_id in message: $orderIdStr');
              return int.tryParse(orderIdStr);
            }
          }
        } else if (firstDecode is Map<String, dynamic>) {
          String? taskIdStr = firstDecode['task_id']?.toString();
          if (taskIdStr != null) {
            print('🔊 Background: Found task_id in message: $taskIdStr');
            return int.tryParse(taskIdStr);
          }
          String? orderIdStr = firstDecode['order_id']?.toString();
          if (orderIdStr != null) {
            print('🔊 Background: Found order_id in message: $orderIdStr');
            return int.tryParse(orderIdStr);
          }
        }
      } catch (e) {
        print('❌ Background: Error parsing message JSON: $e');
      }
    }

    print('Could not extract task ID from notification data');
    return null;
  } catch (e) {
    print('Error extracting task ID: $e');
    return null;
  }
}

/// Check if custom sound should be played based on notification data
// Legacy one-shot sound/vibration helpers removed – AlarmService now owns all alarm audio.
