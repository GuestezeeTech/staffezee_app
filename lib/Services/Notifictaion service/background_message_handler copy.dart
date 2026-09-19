import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:guestezee_staffs_app/Services/Notifictaion%20service/alarm_service.dart';
import 'package:guestezee_staffs_app/firebase_options.dart';
import 'package:vibration/vibration.dart';

// Static flag to prevent duplicate notifications
String? _lastNotificationMessageId;
DateTime? _lastNotificationTime;

/// Helper function to decode JSON strings iteratively until no longer a string
/// Handles cases where JSON is encoded multiple times (e.g., server serializes object -> JSON string -> FCM payload serialization -> network layer)
/// Returns the final decoded value (usually a Map) and logs how many times it was decoded
dynamic _decodeJsonStringIteratively(dynamic value, {int maxAttempts = 10}) {
  if (value is! String) {
    return value; // Already decoded or not a string
  }

  try {
    dynamic decoded = jsonDecode(value);
    int decodeAttempts = 0;

    // Keep decoding as long as it's still a string and we haven't hit max attempts
    while (decoded is String && decodeAttempts < maxAttempts) {
      try {
        final nextDecoded = jsonDecode(decoded);
        // If decoding resulted in the same string, stop (prevents infinite loops)
        if (nextDecoded == decoded ||
            (nextDecoded is String && nextDecoded == decoded)) {
          break;
        }
        decoded = nextDecoded;
        decodeAttempts++;
        print('🔔 Decoded JSON string level ${decodeAttempts + 1}');
      } catch (_) {
        // Not a valid JSON string anymore, stop decoding
        break;
      }
    }

    if (decodeAttempts > 0) {
      print(
        '🔔✅ Decoded JSON string $decodeAttempts time(s) (max allowed: $maxAttempts)',
      );
    }

    return decoded;
  } catch (e) {
    print('⚠️ Failed to decode JSON string: $e');
    return value; // Return original value if decoding fails
  }
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print('🔔✅✅✅✅✅✅✅✅✅✅✅✅✅✅✅✅✅✅✅✅✅✅✅✅');
  print('🔔✅✅✅ BACKGROUND MESSAGE HANDLER CALLED! ✅✅✅');
  print('🔔✅✅✅✅✅✅✅✅✅✅✅✅✅✅✅✅✅✅✅✅✅✅✅✅');
  print('🔔 This handler is ONLY called when message has a "data" payload');
  print('🔔 Message ID: ${message.messageId}');
  print('🔔 From: ${message.from}');
  print('🔔 Has data payload: ${message.data.isNotEmpty}');
  print('🔔 Data payload: ${message.data}');
  print('🔔 Has notification object: ${message.notification != null}');
  print(
    '🔔 Notification: ${message.notification?.title} - ${message.notification?.body}',
  );
  print('🔔✅✅✅ If you see this, background handler is working! ✅✅✅');

  // CRITICAL: This handler is ONLY called when message has a "data" payload
  // If message has ONLY "notification" payload, Android shows it automatically
  // but this handler is NOT called
  if (message.data.isEmpty) {
    print('⚠️ WARNING: Message has no data payload!');
    print(
      '⚠️ This handler should not be called for notification-only messages',
    );
    print('⚠️ Server must send BOTH notification AND data payloads');
  }

  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Prevent duplicate notifications - check if same message received recently
  final messageId = message.messageId ??
      message.data['message_id'] ??
      message.data.toString();
  final now = DateTime.now();

  if (_lastNotificationMessageId == messageId &&
      _lastNotificationTime != null &&
      now.difference(_lastNotificationTime!).inSeconds < 5) {
    print('⚠️ Duplicate notification ignored: $messageId');
    return;
  }

  _lastNotificationMessageId = messageId;
  _lastNotificationTime = now;

  // Initialize alarm service for background/terminated state
  await AlarmService.initialize();

  // Extract message data first to check if we have order data
  // FCM Payload structure:
  // - data.title = display title
  // - data.body = display body text ("Tap to view details")
  // - data.message = order JSON (body_data) - THIS IS WHERE ORDER DATA IS
  // - data.sound = "alarm"
  Map<String, dynamic>? orderData;
  try {
    // PRIORITY 1: Check 'message' field first (contains order JSON)
    if (message.data.containsKey('message')) {
      final msgData = message.data['message'];
      final decoded = _decodeJsonStringIteratively(msgData);

      // If decoded is a Map, use it as orderData (it's the order JSON)
      if (decoded is Map) {
        orderData = Map<String, dynamic>.from(decoded);
        // Check if it has order structure for logging
        if (decoded.containsKey('orderdetails1') ||
            decoded.containsKey('order_id') ||
            decoded.containsKey('orderId')) {
          print('🔔✅ Found order data in "message" field');
        } else {
          print('🔔 Found JSON in "message" field (using as order data)');
        }
      } else {
        // Decoded is not a Map, use all data
        orderData = Map<String, dynamic>.from(message.data);
        print('🔔 Message field decoded to non-Map type, using all data');
      }
    } else {
      // No 'message' field, use all data
      orderData = Map<String, dynamic>.from(message.data);
      print('🔔 No "message" field, using all data');
    }
    print('🔔 Extracted order data: ${orderData.isNotEmpty}');
  } catch (e) {
    print('⚠️ Error extracting order data: $e');
    orderData = Map<String, dynamic>.from(message.data);
  }

  // Check if we have meaningful order data
  final hasOrderData = orderData.isNotEmpty &&
      (orderData.containsKey('orderdetails1') ||
          orderData.containsKey('order_id') ||
          orderData.containsKey('orderId'));

  print('🔔 Has order data: $hasOrderData');

  // Extract title and body for display
  // IMPORTANT: If body contains order JSON, don't use it as display body
  final notificationText = _extractNotificationText(message);
  String? title = notificationText['title'];
  String? body = notificationText['body'];

  // If body is actually order JSON (starts with { or [), don't use it as display body
  if (body != null &&
      (body.trim().startsWith('{') || body.trim().startsWith('['))) {
    print('🔔 Body field contains JSON, not using as display body');
    body = null; // Will use default body instead
  }

  // Trim and validate title/body
  final finalTitle = title?.trim();
  final finalBody = body?.trim();

  // If we have order data, use defaults for title/body if they're missing
  // Don't skip if we have order data - we can still show notification
  if ((finalTitle == null || finalTitle.isEmpty) &&
      (finalBody == null || finalBody.isEmpty) &&
      !hasOrderData) {
    print('⚠️ Skipping: both title and body are null/empty AND no order data');
    return;
  }

  // Use defaults if title/body are missing but we have order data
  final displayTitle = finalTitle ?? 'New Order';
  final displayBody = finalBody ?? 'You have received a new order';

  print('🔔 Using title: $displayTitle');
  print('🔔 Using body: $displayBody');

  // Merge title/body/sound/click_action with parsed order data for complete message
  // This ensures all data needed for the popup is stored
  if (orderData.isNotEmpty) {
    orderData['title'] ??= displayTitle;
    orderData['body'] ??= displayBody;
    orderData['sound'] ??= message.data['sound'];
    orderData['click_action'] ??= message.data['click_action'];
    print('🔔✅ Merged title/body with parsed order data for storage');
  }

  // Check if FCM will automatically show a notification
  // FCM shows notification automatically ONLY if message.notification exists
  final fcmWillShowNotification = message.notification != null;
  print(
    '🔔 FCM will show notification automatically: $fcmWillShowNotification',
  );
  print('🔔 message.notification is null: ${message.notification == null}');

  // Generate unique message ID for alarm
  final uniqueMessageId = message.messageId ??
      message.data['message_id'] ??
      '${DateTime.now().millisecondsSinceEpoch}_${message.data.hashCode}';

  // Decision logic:
  // 1. If notification object exists → FCM will show it automatically (default sound)
  //    BUT we also create our own notification as backup to ensure it always shows
  // 2. If NO notification object → Use AlarmService with custom sound
  if (fcmWillShowNotification) {
    // Message has notification object → FCM will show notification automatically
    // FCM uses default notification sound (single sound)
    print(
      '🔔✅ Notification object exists - FCM will show notification automatically with default sound',
    );
    print('🔔 FCM notification will use system default sound (single sound)');

    // ALSO create our own notification as backup to ensure it always shows
    print('🔔 Creating backup notification via AlarmService...');
    await AlarmService.playAlarm(
      title: displayTitle,
      body: displayBody,
      loop: true,
      messageId: uniqueMessageId.toString(),
      messageData: orderData,
    );

    // Optional: vibrate if needed
    if (_shouldPlayCustomSound(message)) {
      print('🔔 Playing vibration pattern');
      await _vibratePattern();
    }
  } else {
    // NO notification object → Use custom alarm with custom sound
    print('🔔❌ No notification object - Using AlarmService with custom sound');
    print('🔔 AlarmService will show notification with custom alarm sound');

    // Always use AlarmService when there's no notification object
    await AlarmService.playAlarm(
      title: displayTitle,
      body: displayBody,
      loop: true,
      messageId: uniqueMessageId.toString(),
      messageData: orderData,
    );
    await _vibratePattern();
  }

  print('🔔✅ Background message handler completed');
}

bool _shouldPlayCustomSound(RemoteMessage message) {
  final dataSound = message.data['sound'];
  if (dataSound == 'alarm') return true;
  final androidSound = message.notification?.android?.sound;
  return androidSound == 'alarm';
}

Future<void> _vibratePattern() async {
  try {
    final hasVibrator = await Vibration.hasVibrator();
    if (hasVibrator == true) {
      await Vibration.vibrate(duration: 1000);
      await Future.delayed(const Duration(milliseconds: 500));
      await Vibration.vibrate(duration: 1000);
    }
  } catch (_) {}
}

Map<String, String?> _extractNotificationText(RemoteMessage message) {
  String? _clean(dynamic value) {
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isNotEmpty && trimmed.toLowerCase() != 'null') {
        return trimmed;
      }
    }
    return null;
  }

  String? title = _clean(message.notification?.title);
  String? body = _clean(message.notification?.body);

  title ??= _clean(message.data['title']);
  body ??= _clean(message.data['body']);

  final rawMessage = message.data['message'];
  if (rawMessage is String) {
    try {
      final decoded = jsonDecode(rawMessage);
      if (decoded is String) {
        final nested = jsonDecode(decoded);
        if (nested is Map) {
          title ??= _clean(nested['title']);
          body ??= _clean(nested['body']);
        }
      } else if (decoded is Map) {
        title ??= _clean(decoded['title']);
        body ??= _clean(decoded['body']);
      }
    } catch (_) {}
  } else if (rawMessage is Map) {
    title ??= _clean(rawMessage['title']);
    body ??= _clean(rawMessage['body']);
  }

  return {'title': title, 'body': body};
}
