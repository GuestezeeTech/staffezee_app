import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    as notifications;
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:guestezee_staffs_app/Screens/track_task_page.dart';
import 'package:guestezee_staffs_app/Screens/login_page.dart';
import 'package:guestezee_staffs_app/Services/vibration_service.dart';
import 'package:guestezee_staffs_app/Services/high_priority_badge_service.dart';
import 'package:guestezee_staffs_app/Services/local_storage_service.dart';
import 'package:guestezee_staffs_app/Services/audio_service.dart';
import 'package:guestezee_staffs_app/Services/continuous_sound_service.dart';
import 'package:guestezee_staffs_app/Services/Notifictaion%20service/alarm_service.dart';
import 'package:guestezee_staffs_app/Services/staff_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PushNotificationService {
  static final notifications.FlutterLocalNotificationsPlugin
      _localNotificationsPlugin =
      notifications.FlutterLocalNotificationsPlugin();
  static final FirebaseMessaging _firebaseMessaging =
      FirebaseMessaging.instance;
  static const MethodChannel _alarmServiceChannel =
      MethodChannel('staff/alarm_service');

  static Map<String, dynamic>? _lastForegroundMessageData;
  static GlobalKey<NavigatorState>? _navigatorKey;
  static bool _isNavigatingFromNotification = false;

  // Store pending notification data for navigation after login
  static Map<String, dynamic>? _pendingNotificationData;

  /// True when Android notification permission was permanently denied (user must open Settings).
  static bool _androidNotificationPermanentlyDenied = false;

  /// Initialize the push notification service
  static Future<void> initialize(GlobalKey<NavigatorState> navigatorKey) async {
    _navigatorKey = navigatorKey;

    // STEP 1: Initialize Vibration Service
    await VibrationService.initialize();

    // STEP 1.5: Initialize Audio Service and Alarm Service
    await AudioService.initialize();
    await AlarmService.initialize();

    // STEP 2: Request Permissions
    await _requestPermissions();

    // STEP 2.5: iOS – Disable system foreground alerts/sounds.
    // We handle notifications manually in onMessage to prevent duplicates
    // and to allow AlarmService to control the continuous looping sound.
    if (Platform.isIOS) {
      // alert: true allows the system to show the FCM banner in the foreground.
      // sound: false prevents the system "ping" sound so we can play our looping alarm.
      await _firebaseMessaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: false,
      );
    }

    // STEP 3: Local Notification Init
    const notifications.AndroidInitializationSettings androidSettings =
        notifications.AndroidInitializationSettings('@mipmap/ic_launcher');

    // iOS: request alert, badge, sound so local notifications can be shown
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const notifications.InitializationSettings initSettings =
        notifications.InitializationSettings(
      android: androidSettings,
      iOS: iosInit,
    );

    // Create notification channel with vibration for Android 8.0+
    await _createNotificationChannel();

    print("📬 Initializing local notifications...");
    await _localNotificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse:
          (notifications.NotificationResponse response) {
        print(
            "🔔 Local notification tapped (foreground). payload=${response.payload}");

        VibrationService.vibrateGentle();
        // Removed: AlarmService.stopAllAlarms() - sound should persist until Accept

        if (response.payload != null && response.payload!.isNotEmpty) {
          try {
            final data = jsonDecode(response.payload!) as Map<String, dynamic>;
            _handleNavigationFromData(data);
            return;
          } catch (_) {}
        }
        if (_lastForegroundMessageData != null) {
          _handleNavigationFromData(_lastForegroundMessageData!);
        }
      },
    );
    print("✅ Local notifications initialized");

    // iOS: ensure local notification permission is requested (needed to show banners/sound)
    if (Platform.isIOS) {
      final iosPlugin =
          _localNotificationsPlugin.resolvePlatformSpecificImplementation<
              notifications.IOSFlutterLocalNotificationsPlugin>();
      if (iosPlugin != null) {
        final granted = await iosPlugin.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
        print(
            "🍎 iOS local notification permission requested: ${granted == true ? 'granted' : 'not granted'}");
      }
    }

    // If Android notification permission was permanently denied, prompt user to open Settings
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showOpenSettingsPromptIfNeeded();
    });

    // If app was opened by tapping OrderAlertService notification, navigate to task screen.
    // Also listen for native 'orderAlertTapped' calls so taps are handled even when
    // the app is already in foreground.
    if (Platform.isAndroid) {
      _alarmServiceChannel.setMethodCallHandler((call) async {
        if (call.method == 'orderAlertTapped') {
          await _checkOrderAlertLaunchExtras();
        }
        return;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await Future.delayed(const Duration(milliseconds: 800));
        await _checkOrderAlertLaunchExtras();
      });
    }

    // STEP 4: Foreground message handler
    // On iOS: onMessage only runs when the payload has a "data" section (or both notification+data).
    // Notification-only messages are often shown by the system and never delivered to Dart.
    print('📬 FCM foreground listener registered (onMessage)');
    if (Platform.isIOS) {
      print(
          '🍎 iOS: To receive FCM in foreground, send payload with "data" (e.g. data: { title, body, task_id })');
    }
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      try {
        await LocalStorageService.init();
        if (!LocalStorageService.isLoggedIn) {
          print('🔐 FCM foreground: user logged out – ignoring notification');
          await _stopAllNotificationAudio();
          return;
        }

        // Silent token-validation push (from logout check) – never show UI/sound.
        if (isTestPayload(message.data)) {
          print('🔕 Test notification (testing:true) received – ignoring');
          return;
        }

        print('📬 FCM onMessage triggered');
        print('📬 FCM received in foreground: ${message.toString()}');
        print('🔍 message.data: ${message.data}');
        print('🔍 message.notification: ${message.notification?.toString()}');

        final Map<String, dynamic> messageData = _effectiveMessageData(message);

        // Support both notification+data and data-only payloads
        final String? notifTitle = messageData['title']?.toString();
        final String? notifBody = messageData['body']?.toString();

        if (notifTitle == null && notifBody == null) {
          print(
              '⚠️ FCM onMessage: No title/body in data or notification, ignoring');
          return;
        }

        // iOS Foreground: We no longer show a manual local notification banner here.
        // Instead, we rely on setForegroundNotificationPresentationOptions(alert: true)
        // in initialize(), which lets the system show the FCM banner for us.
        // This ensures the banner appears reliably and allows navigation on tap.

        _lastForegroundMessageData = messageData;

        // Extract task ID and status
        final int? taskId = _extractTaskIdFromData(messageData);
        final String? taskStatus = notifTitle;

        print('🔊 Foreground: Extracted task ID: $taskId');

        final bool isStopOnlyStatus = taskStatus != null &&
            (taskStatus.toLowerCase() == 'escalated' ||
                taskStatus.toLowerCase() == 'cancelled' ||
                taskStatus.toLowerCase() == 'completed');

        // Escalated / Cancelled / Completed – stop loop, short alert (~2s)
        if (isStopOnlyStatus && taskId != null) {
          if (taskStatus.toLowerCase() == 'escalated') {
            HighPriorityBadgeService.recordEscalationNotification(
              taskId: taskId,
            ).catchError((e) => print('⚠️ Badge update failed: $e'));
          }
          _handleStopOnlyStatusNotification(
            taskId: taskId,
            title: notifTitle,
            body: notifBody,
            messageData: messageData,
          );
        } else {
          // Trigger haptic feedback / vibration for new assigned tasks
          VibrationService.vibrateStrong()
              .catchError((e) => print('ℹ️ Vibration notice: $e'));
        }

        // Start alarm only for Assigned
        if (!isStopOnlyStatus) {
          if (taskId != null) {
            AlarmService.startAlarmForTask(
              taskId: taskId,
              title: notifTitle,
              body: notifBody,
              loop: true,
              messageId: message.messageId,
              messageData: Map<String, dynamic>.from(messageData),
              isForeground: true,
            ).catchError((e) => print('❌ Error starting task alarm: $e'));
          } else {
            AlarmService.playAlarm(
              title: notifTitle,
              body: notifBody,
              loop: true,
              messageId: message.messageId,
              messageData: Map<String, dynamic>.from(messageData),
              isForeground: true,
            ).catchError((e) => print('❌ Error playing alarm: $e'));
          }
        }

        // iOS foreground: show local banner for status updates only when FCM
        // did not already include a notification payload (avoids duplicate banners).
        if (Platform.isIOS &&
            notifTitle != null &&
            isStopOnlyStatus &&
            message.notification == null) {
          final payload =
              messageData.isNotEmpty ? jsonEncode(messageData) : null;
          _showNotification(
              title: notifTitle, body: notifBody, payload: payload);
        }
      } catch (e, stack) {
        print('❌ Critical error in FCM onMessage: $e');
        print(stack);
      }
    });

    // STEP 5: Background message handler (app opened from notification)
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print("📲 Notification tapped (background)");
      print("📱 Background tap message.data: ${message.data}");
      // Removed: AlarmService.stopAllAlarms() - sound should persist until Accept

      // Note: We don't play sound or vibration here because this is a tap event,
      // not a notification arrival. Sound and vibration should only happen on arrival.

      _handleNavigationFromData(Map<String, dynamic>.from(message.data));
    });

    // STEP 6: Terminated state handler (app launched from notification)
    RemoteMessage? initialMessage =
        await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      print("🚀 App launched from terminated state via notification");
      print("📱 Initial message data: ${initialMessage.data}");
      // Removed: AlarmService.stopAllAlarms() - sound should persist until Accept

      // Note: We don't play sound or vibration here because this is a tap event,
      // not a notification arrival. Sound and vibration should only happen on arrival.

      // Store the initial message data and use same retry logic as background tap
      _pendingNotificationData = initialMessage.data;
      _schedulePendingNotificationProcessing();
    }
  }

  /// Show local notification (foreground: Android and iOS; FCM does not show banner on iOS when in foreground)
  static Future<void> _showNotification(
      {String? title, String? body, String? payload}) async {
    final int id = DateTime.now().millisecondsSinceEpoch.remainder(100000);
    final String titleStr = title ?? '';
    final String bodyStr = body ?? '';

    if (Platform.isIOS) {
      print('📬 Showing local foreground notification on iOS: $titleStr');
      final iosDetails = notifications.DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: false, // Use AudioPlayer for sound, not the banner itself
      );
      final details = notifications.NotificationDetails(iOS: iosDetails);
      await _localNotificationsPlugin.show(id, titleStr, bodyStr, details,
          payload: payload);
      return;
    }

    if (!Platform.isAndroid) return;

    print('📬 Showing local foreground notification on Android: $titleStr');

    const androidDetails = notifications.AndroidNotificationDetails(
      'alarm_channel',
      'Alarm Notifications',
      channelDescription: 'Notifications for assigned tasks',
      importance: notifications.Importance.max,
      priority: notifications.Priority.high,
      playSound: false, // sound is handled by AlarmService / system
      enableVibration: false,
    );

    const details = notifications.NotificationDetails(android: androidDetails);

    await _localNotificationsPlugin.show(
      id,
      titleStr,
      bodyStr,
      details,
      payload: payload,
    );
  }

  /// Detect the silent token-validation push (sent during logout to check if a
  /// device is still reachable). Such messages carry `{"testing":true}` and must
  /// NOT show any notification, play sound, or trigger navigation.
  static bool isTestPayload(Map<String, dynamic> data) {
    final direct = data['testing']?.toString().toLowerCase();
    if (direct == 'true' || direct == '1') return true;

    final msg = data['message']?.toString();
    if (msg != null && msg.isNotEmpty) {
      // The message value can be double-encoded, e.g. "{\"testing\":true}".
      // Strip backslashes/spaces so the substring match works regardless.
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

  /// Merge FCM [notification] fields into [data] when title/body are missing.
  /// Foreground handling expects `data: { title, body, task_id }`.
  static Map<String, dynamic> _effectiveMessageData(RemoteMessage message) {
    final data = Map<String, dynamic>.from(message.data);
    final notification = message.notification;

    if ((data['title'] == null || data['title'].toString().trim().isEmpty) &&
        notification?.title != null &&
        notification!.title!.trim().isNotEmpty) {
      data['title'] = notification.title;
    }
    if ((data['body'] == null || data['body'].toString().trim().isEmpty) &&
        notification?.body != null &&
        notification!.body!.trim().isNotEmpty) {
      data['body'] = notification.body;
    }
    return data;
  }

  /// Extract task ID from notification data
  static int? _extractTaskIdFromData(Map<String, dynamic> data) {
    try {
      // Try to get task_id from data
      final taskIdValue = data['task_id'];
      if (taskIdValue != null) {
        if (taskIdValue is int) return taskIdValue;
        final parsed = int.tryParse(taskIdValue.toString());
        if (parsed != null) return parsed;
      }

      // Try to extract from message field if it contains JSON
      String? messageStr = data['message']?.toString();
      if (messageStr != null) {
        try {
          print('🔊 Parsing message JSON: $messageStr');

          // First decode
          final dynamic firstDecode = jsonDecode(messageStr);
          print(
              '🔊 First decode: $firstDecode (type: ${firstDecode.runtimeType})');

          // If it's still a string, decode again
          if (firstDecode is String) {
            print('🔊 JSON is string, decoding again...');
            final dynamic secondDecode = jsonDecode(firstDecode);
            print(
                '🔊 Second decode: $secondDecode (type: ${secondDecode.runtimeType})');

            if (secondDecode is Map<String, dynamic>) {
              String? taskIdStr = secondDecode['task_id']?.toString();
              if (taskIdStr != null) {
                print('🔊 Found task_id in message: $taskIdStr');
                return int.tryParse(taskIdStr);
              }
              // String? orderIdStr = secondDecode['order_id']?.toString();
              // if (orderIdStr != null) {
              //   print('🔊 Found order_id in message: $orderIdStr');
              //   return int.tryParse(orderIdStr);
              // }
            }
          } else if (firstDecode is Map<String, dynamic>) {
            String? taskIdStr = firstDecode['task_id']?.toString();
            if (taskIdStr != null) {
              print('🔊 Found task_id in message: $taskIdStr');
              return int.tryParse(taskIdStr);
            }
            // String? orderIdStr = firstDecode['order_id']?.toString();
            // if (orderIdStr != null) {
            //   print('🔊 Found order_id in message: $orderIdStr');
            //   return int.tryParse(orderIdStr);
            // }
          }
        } catch (e) {
          print('❌ Error parsing message JSON: $e');
        }
      }

      print('Could not extract task ID from notification data');
      return null;
    } catch (e) {
      print('Error extracting task ID: $e');
      return null;
    }
  }

  /// Create notification channel with vibration for Android 8.0+
  static Future<void> _createNotificationChannel() async {
    final notifications.AndroidNotificationChannel channel =
        notifications.AndroidNotificationChannel(
      'alarm_channel',
      'Alarm Notifications',
      description:
          'Important task notifications with alarm sound and vibration',
      importance: notifications.Importance.max,
      playSound: true,
      enableVibration: true,
      sound: const notifications.UriAndroidNotificationSound('alarm'),
      vibrationPattern: Int64List.fromList(
          [0, 1000, 500, 1000]), // Pattern: wait, vibrate, pause, vibrate
    );

    await _localNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            notifications.AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  static Future<String?> getDeviceToken() async {
    try {
      if (defaultTargetPlatform == TargetPlatform.iOS &&
          !kIsWeb &&
          Platform.isIOS) {
        // On iOS, getToken() requires APNS; simulator has no APNS. Check first to avoid throwing.
        String? apnsToken = await _firebaseMessaging.getAPNSToken();
        if (apnsToken == null || apnsToken.isEmpty) {
          await Future.delayed(const Duration(seconds: 2));
          apnsToken = await _firebaseMessaging.getAPNSToken();
        }
        if (apnsToken == null || apnsToken.isEmpty) {
          print(
              '📱 FCM token not available (iOS Simulator has no APNS; use a real device for push).');
          return null;
        }
      }

      final token = await _firebaseMessaging.getToken();
      if (token != null && token.isNotEmpty) {
        _printFcmToken(token);
        return token;
      }
      return null;
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('apns-token-not-set') || msg.contains('APNS')) {
        print(
            '📱 FCM token not available (iOS Simulator has no APNS; use a real device for push).');
      } else {
        print('FCM token error: $e');
      }
      return null;
    }
  }

  static void _printFcmToken(String token) {
    print('═══════════════════════════════════════════════════════════');
    print('FCM DEVICE TOKEN:');
    print(token);
    print('═══════════════════════════════════════════════════════════');
  }

  /// On app init (when user is already logged in), refresh FCM token with backend:
  /// ensure current token is in the server's fcm_token array (add if missing, else just update availability).
  static Future<void> refreshFcmTokenWithBackendIfLoggedIn() async {
    if (!LocalStorageService.isLoggedIn) return;
    final user = LocalStorageService.user;
    if (user == null) return;

    final dynamic staffIdValue = user['id'];
    final int? staffDbId = staffIdValue is int
        ? staffIdValue
        : int.tryParse(staffIdValue?.toString() ?? '');
    final String legacyEmployeeNumber =
        (user['staff_employee_number'] ?? user['staff_member_id'] ?? '')
            .toString();
    final dynamic staffIdentifier = staffDbId ??
        (legacyEmployeeNumber.isNotEmpty ? legacyEmployeeNumber : null);

    if (staffIdentifier == null) return;

    try {
      final currentFcmToken = await getDeviceToken();
      if (currentFcmToken == null) {
        await StaffService.updateStaffAvailability(staffIdentifier, true);
        return;
      }

      final staffResponse = await StaffService.getStaffById(
          staffIdentifier is int
              ? staffIdentifier.toString()
              : staffIdentifier.toString());
      if (staffResponse.statusCode != 200 && staffResponse.statusCode != 201) {
        return;
      }
      final staffData = jsonDecode(staffResponse.body);
      if (staffData['success'] != 1 ||
          staffData['result'] == null ||
          staffData['result']['data'] == null) {
        return;
      }
      final List<dynamic> staffList = staffData['result']['data'] ?? [];
      if (staffList.isEmpty) return;

      final staff = staffList[0] as Map<String, dynamic>;
      final existingFcmTokens = staff['fcm_token'];

      if (existingFcmTokens == null) {
        await StaffService.updateStaffAvailabilityWithFcmToken(
            staffIdentifier, true, [currentFcmToken]);
        print('✅ FCM token refreshed on init: [$currentFcmToken]');
        return;
      }

      List<String> fcmTokensList = [];
      if (existingFcmTokens is List) {
        if (existingFcmTokens.isEmpty) {
          await StaffService.updateStaffAvailabilityWithFcmToken(
              staffIdentifier, true, [currentFcmToken]);
          print('✅ FCM token refreshed on init: [$currentFcmToken]');
          return;
        }
        fcmTokensList = existingFcmTokens.map((e) => e.toString()).toList();
      } else if (existingFcmTokens is String) {
        fcmTokensList = [existingFcmTokens];
      }

      if (fcmTokensList.contains(currentFcmToken)) {
        await StaffService.updateStaffAvailability(staffIdentifier, true);
        print('✅ FCM token already in array; availability updated on init.');
      } else {
        fcmTokensList.add(currentFcmToken);
        await StaffService.updateStaffAvailabilityWithFcmToken(
            staffIdentifier, true, fcmTokensList);
        print('✅ FCM token added on init: $fcmTokensList');
      }
    } catch (e) {
      print('⚠️ refreshFcmTokenWithBackendIfLoggedIn: $e');
    }
  }

  /// Request notification permissions
  static Future<void> _requestPermissions() async {
    // iOS & Android 13+ (API 33+)
    NotificationSettings settings = await _firebaseMessaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    print(
        "🔐 FCM Notification permission status: ${settings.authorizationStatus}");

    // Android 13+ runtime permission check
    if (Platform.isAndroid &&
        (await Permission.notification.isDenied ||
            await Permission.notification.isPermanentlyDenied)) {
      final status = await Permission.notification.request();
      print("🔐 Android runtime notification permission status: $status");

      if (status == PermissionStatus.permanentlyDenied) {
        _androidNotificationPermanentlyDenied = true;
        print("⚠️ User did not grant Android runtime notification permission.");
      } else if (status != PermissionStatus.granted) {
        print("⚠️ User did not grant Android runtime notification permission.");
      }
    }
  }

  /// Shows a dialog prompting the user to open app settings when Android notification permission is permanently denied.
  static void _showOpenSettingsPromptIfNeeded() {
    if (!Platform.isAndroid || !_androidNotificationPermanentlyDenied) return;

    final context = _navigatorKey?.currentContext;
    if (context == null || !context.mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Notifications disabled'),
          content: const Text(
            'Notifications are turned off for this app. To receive task alerts and reminders, please enable notifications in Settings.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Not now'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                openAppSettings();
              },
              child: const Text('Open Settings'),
            ),
          ],
        );
      },
    );
    // Only show once per app launch
    _androidNotificationPermanentlyDenied = false;
  }

  // Note: we no longer show our own foreground notification here.
  // Visual notifications come from FCM/system notification payload.

  /// Handle navigation based on notification data
  static void _handleNavigationFromData(Map<String, dynamic> data) {
    print("📍 Handling navigation from data: $data");

    // Check if navigator is ready
    if (_navigatorKey?.currentState == null) {
      print("⚠️ Navigator not ready, storing data for later processing");
      _pendingNotificationData = data;
      // When app opens from background tap, onMessageOpenedApp can fire before
      // the navigator is ready. Schedule retries so we process once it's ready.
      _schedulePendingNotificationProcessing();
      return;
    }

    // Check if user is logged in first
    bool isLoggedIn = LocalStorageService.isLoggedIn;
    print("🔐 User login status: $isLoggedIn");

    if (!isLoggedIn) {
      print(
          "🔐 Logged out – old notification tap saved for after login, opening login");
      _saveNotificationTapForAfterLogin(data);
      _redirectToLoginPage();
      return;
    }

    // User is logged in, proceed with normal navigation
    _processNotificationNavigation(data);
  }

  /// Retry processing _pendingNotificationData when navigator becomes ready
  /// (e.g. after background or terminated tap opens app before first frame is built).
  static void _schedulePendingNotificationProcessing() {
    const maxAttempts = 25; // ~5s at 200ms
    const delayMs = 200;

    Future<void> tryProcess(int attempt) async {
      if (_pendingNotificationData == null) return;
      if (attempt > 0)
        await Future.delayed(const Duration(milliseconds: delayMs));
      if (_pendingNotificationData == null) return;
      if (_navigatorKey?.currentState == null) {
        if (attempt < maxAttempts) {
          tryProcess(attempt + 1);
        } else {
          print(
              "⚠️ Navigator not ready after $maxAttempts attempts; will retry on next app resume");
        }
        return;
      }
      print("📍 Processing pending notification (navigator ready)");
      final data = _pendingNotificationData!;
      if (!LocalStorageService.isLoggedIn) {
        await _saveNotificationTapForAfterLogin(data);
        _redirectToLoginPage();
        return;
      }
      _pendingNotificationData = null;
      _processNotificationNavigation(data);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => tryProcess(0));
  }

  /// Process notification navigation when user is authenticated
  static void _processNotificationNavigation(Map<String, dynamic> data) {
    // Parse the message JSON to extract task_id and redirection_tab
    // Support both: data.task_id + data.message, and message JSON with task_id inside
    int? taskId;

    try {
      // Prefer direct data.task_id (e.g. from FCM data payload on iOS)
      final directTaskId = data['task_id'];
      if (directTaskId != null) {
        if (directTaskId is int) {
          taskId = directTaskId;
        } else if (directTaskId is String) {
          taskId = int.tryParse(directTaskId);
        }
        if (taskId != null) print("✅ task_id from data['task_id']: $taskId");
      }

      // The message field contains JSON string like: {"task_id":333,"msg":"Staff processing the service","redirection_tab":"processing"}
      final messageField = data['message'];
      print(
          "🔍 Raw message field: $messageField (type: ${messageField.runtimeType})");

      if (messageField != null && messageField is String) {
        dynamic messageJson = jsonDecode(messageField);
        print(
            "🔍 First decode: $messageJson (type: ${messageJson.runtimeType})");

        // Handle case where JSON might be double-encoded
        if (messageJson is String) {
          try {
            print("🔍 JSON is string, decoding again...");
            messageJson = jsonDecode(messageJson);
            print(
                "🔍 Second decode: $messageJson (type: ${messageJson.runtimeType})");
          } catch (e) {
            print("❌ Error double-decoding message JSON: $e");
          }
        }

        // Now messageJson should be a Map
        if (messageJson is Map) {
          // Extract task_id only if not already set from data['task_id']
          if (taskId == null) {
            final taskIdValue = messageJson['task_id'];
            print(
                "🔍 Raw task_id value: $taskIdValue (type: ${taskIdValue.runtimeType})");

            if (taskIdValue is int) {
              taskId = taskIdValue;
              print("✅ task_id is int: $taskId");
            } else if (taskIdValue is String) {
              taskId = int.tryParse(taskIdValue);
              print("✅ task_id is string, parsed: $taskId");
            } else if (taskIdValue is double) {
              taskId = taskIdValue.toInt();
              print("✅ task_id is double, converted: $taskId");
            } else {
              print("❌ Unknown task_id type: ${taskIdValue.runtimeType}");
            }
          }
        } else {
          print(
              "❌ messageJson is not a Map after decoding: ${messageJson.runtimeType}");
        }
      }
    } catch (e) {
      print("❌ Error parsing notification data: $e");
      print("❌ Data structure: $data");
      print("❌ Stack trace: ${StackTrace.current}");
    }

    if (taskId == null) {
      print("⚠️ No valid task_id found in notification data");
      return;
    }

    // Clear only THIS tapped notification from the tray, UNLESS it is an
    // "Assigned" task – those must stay (with their sound) until the staff
    // accepts the task on the Track screen.
    final String tapStatus =
        (data['title'] ?? data['status'] ?? '').toString().trim().toLowerCase();
    if (tapStatus == 'assigned') {
      print('🔔 Assigned task tapped – keeping notification until accepted '
          '(task $taskId)');
    } else {
      print('🧹 Notification tapped – clearing notification for task $taskId');
      AlarmService.clearTaskStatusNotifications(taskId);
    }

    // Navigate based on redirection_tab or default to Track Task page
    _navigateToScreen(taskId, originalData: data);
  }

  /// Redirect to login page when user is not authenticated
  static void _redirectToLoginPage() {
    if (_navigatorKey?.currentState != null) {
      _navigatorKey!.currentState!.pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (context) => const LoginPage(),
        ),
        (route) => false, // Remove all previous routes
      );
    } else {
      print("⚠️ Navigator key is null, cannot redirect to login page");
    }
  }

  /// Navigate to task screen on notification tap (same screen for all states: foreground, background, terminated).
  static void _navigateToScreen(
    int taskId,
      {Map<String, dynamic>? originalData}) {
    if (_isNavigatingFromNotification) {
      print("⏳ Navigation already in progress, skipping duplicate tap");
      return;
    }

    _isNavigatingFromNotification = true;
    Future<void>(() async {
      try {
        // Give app lifecycle/resume a brief moment before pushing a route.
        await Future.delayed(const Duration(milliseconds: 200));

        final navigatorState = _navigatorKey?.currentState;
        if (navigatorState == null) {
          print("⚠️ Navigator not ready during notification tap; queueing retry");
          _pendingNotificationData = originalData ?? {'task_id': '$taskId'};
          _schedulePendingNotificationProcessing();
          return;
        }

        print("🚀 Navigating to Track Task page with taskId: $taskId");
        navigatorState.push(
          MaterialPageRoute(
            builder: (context) => TrackTaskPage(taskId: taskId),
          ),
        );
      } catch (e) {
        print("❌ Error navigating from notification tap: $e");
      } finally {
        Future.delayed(const Duration(milliseconds: 500), () {
          _isNavigatingFromNotification = false;
        });
      }
    });
  }

  static void _handleStopOnlyStatusNotification({
    required int taskId,
    String? title,
    String? body,
    required Map<String, dynamic> messageData,
  }) {
    Future<void>(() async {
      try {
        await ContinuousSoundService.stopTaskSound(taskId);
        await AlarmService.playShortStatusAlertForTask(
          taskId: taskId,
          title: title,
          body: body,
          messageData: messageData,
          timeoutSeconds: 2,
          isForeground: true,
        );
        // Gentle haptic for status update (not strong assigned vibration)
        if (Platform.isIOS) {
          VibrationService.vibrateGentle()
              .catchError((e) => print('ℹ️ Vibration notice: $e'));
        }
      } catch (e) {
        print('⚠️ Error handling stop-only status notification: $e');
      }
    });
  }

  /// After login: open task from an old notification tapped while logged out.
  static Future<void> handlePostLoginNavigation() async {
    await _restorePersistedNotificationTapIfNeeded();
    if (_pendingNotificationData == null) return;

    print("🔄 Processing saved notification tap after login");
    final pendingData = _pendingNotificationData!;
    _pendingNotificationData = null;
    await LocalStorageService.clearPendingNotificationTap();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!LocalStorageService.isLoggedIn) return;
      _processNotificationNavigation(pendingData);
    });
  }

  /// Clear in-memory notification state only (keeps saved tap across logout).
  static void clearPendingNotificationData() {
    _pendingNotificationData = null;
    _lastForegroundMessageData = null;
    print("🧹 Cleared in-memory pending notification data");
  }

  /// Save tap payload locally (old tray notification after logout).
  static Future<void> _saveNotificationTapForAfterLogin(
      Map<String, dynamic> data) async {
    _pendingNotificationData = Map<String, dynamic>.from(data);
    await LocalStorageService.savePendingNotificationTap(
        _pendingNotificationData!);
  }

  static Future<void> _restorePersistedNotificationTapIfNeeded() async {
    if (_pendingNotificationData != null) return;
    final stored = await LocalStorageService.loadPendingNotificationTap();
    if (stored != null && stored.isNotEmpty) {
      _pendingNotificationData = stored;
      print('💾 Restored notification tap from local storage');
    }
  }

  /// Stop all notification audio/vibration state. Call on logout and when FCM
  /// arrives while logged out.
  static Future<void> _stopAllNotificationAudio() async {
    try {
      await AlarmService.stopAllAlarms();
    } catch (e) {
      print('⚠️ Error stopping alarms on logout: $e');
    }
    try {
      await ContinuousSoundService.stopAllSounds();
    } catch (e) {
      print('⚠️ Error stopping continuous sounds on logout: $e');
    }
    try {
      await AudioService.stopAudio();
    } catch (e) {
      print('⚠️ Error stopping audio on logout: $e');
    }
  }

  /// Call when user logs out: stop sounds/alarms (keeps saved old-notification tap).
  static Future<void> onUserLoggedOut() async {
    await _stopAllNotificationAudio();
    clearPendingNotificationData();
    print('🔇 Logout: all notification sounds stopped');
  }

  /// Check for pending notifications and process them (call this when app becomes active)
  /// Also checks OrderAlertService tap (Android): if user tapped alarm notif, navigate to task screen.
  /// On iOS: applies any pending "stop alarm" requests written by the background FCM handler (Escalated/Cancelled).
  static Future<void> checkAndProcessPendingNotifications() async {
    // First: if app was brought to front by tapping OrderAlertService notification (Android)
    if (Platform.isAndroid) {
      await _checkOrderAlertLaunchExtras();
    }

    // iOS: Background handler runs in a separate isolate and cannot stop the main isolate's alarm.
    // It writes pending task IDs to SharedPreferences; we apply them here on resume.
    if (Platform.isIOS) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString('pending_stop_alarm_task_ids');
        if (raw != null && raw.isNotEmpty) {
          print(
              '🔇 iOS resume: stopping all alarms (background Escalated/Cancelled queued)');
          await AlarmService.stopAllAlarms();
          await prefs.remove('pending_stop_alarm_task_ids');
        }
      } catch (e) {
        print('⚠️ Error applying pending stop alarm: $e');
      }

      // iOS: if app was launched/opened by tapping a local notification, get payload and navigate
      try {
        final launchDetails =
            await _localNotificationsPlugin.getNotificationAppLaunchDetails();
        if (launchDetails?.didNotificationLaunchApp == true &&
            launchDetails?.notificationResponse?.payload != null &&
            launchDetails!.notificationResponse!.payload!.isNotEmpty) {
          final payload = launchDetails.notificationResponse!.payload!;
          try {
            final data = jsonDecode(payload) as Map<String, dynamic>;
            print(
                '📬 iOS: app launched from local notification tap, navigating from payload');
            _pendingNotificationData ??= data;
          } catch (_) {}
        }
      } catch (e) {
        print('⚠️ iOS getNotificationAppLaunchDetails: $e');
      }
    }

    if (_pendingNotificationData != null) {
      if (_navigatorKey?.currentState != null) {
        print("🔄 Processing pending notification from app activation");
        final data = _pendingNotificationData!;
        _pendingNotificationData = null;
        _handleNavigationFromData(data);
      } else {
        // Navigator not ready yet (e.g. app just opened from background tap);
        // schedule retries until it is ready.
        _schedulePendingNotificationProcessing();
      }
    }
  }

  /// When app is opened by tapping OrderAlertService notification (Android), native stores
  /// task_id + message in SharedPreferences. We read, check isLoggedIn, and navigate to task screen.
  static Future<void> _checkOrderAlertLaunchExtras() async {
    if (!Platform.isAndroid) return;
    try {
      const channel = MethodChannel('staff/alarm_service');
      final dynamic result =
          await channel.invokeMethod('getOrderAlertLaunchExtras');
      if (result is Map && result['message'] != null) {
        final data = <String, dynamic>{
          'message': result['message'],
          if (result['task_id'] != null) 'task_id': result['task_id'],
        };
        print('📬 Noti tap - data stored on that noti: $data');
        _handleNavigationFromData(data);
      }
    } catch (e) {
      print('⚠️ getOrderAlertLaunchExtras: $e');
    }
  }

  /// Called from MyApp.didChangeAppLifecycleState(resumed): read native pending notification data
  /// (from notification tap) and if present, check isLoggedIn and navigate to task screen.
  static Future<void> handleNativeNotificationTapIfAny() async {
    if (Platform.isAndroid) {
      try {
        const channel = MethodChannel('staff/alarm_service');
        final dynamic result = await channel
            .invokeMethod<Map<dynamic, dynamic>>('getPendingNotificationData');
        if (result != null && result.isNotEmpty) {
          final data = result.map((k, v) => MapEntry(k.toString(), v));
          final map = Map<String, dynamic>.from(data);
          if (map['message'] != null || map['task_id'] != null) {
            print('📬 Noti tap - data stored on that noti (Android): $map');
            handleNotificationTapFromNative(map);
          }
        }
      } catch (e) {
        print('⚠️ handleNativeNotificationTapIfAny (Android): $e');
      }
    } else if (Platform.isIOS) {
      // On iOS, if the app was opened/resumed via an alarm banner tap,
      // the data will be stored in AlarmService's persistent storage.
      try {
        final data = await AlarmService.getLastMessageData();
        if (data != null && data.isNotEmpty) {
          print('📬 Noti tap - data retrieved from AlarmService (iOS): ${data.keys}');
          handleNotificationTapFromNative(data);
          // Clear it so we don't process it again on next resume
          await AlarmService.clearLastMessageData();
        }
      } catch (e) {
        print('⚠️ handleNativeNotificationTapIfAny (iOS): $e');
      }
    }
  }

  /// Handle notification tap using data from native (task_id + message). Checks isLoggedIn, then navigates.
  static void handleNotificationTapFromNative(Map<String, dynamic> data) {
    _handleNavigationFromData(data);
  }
}