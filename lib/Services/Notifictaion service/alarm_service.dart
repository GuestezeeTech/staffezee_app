import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:alarm/alarm.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Android native alarm (foreground service) – same channel as background handler
const MethodChannel _androidAlarmChannel = MethodChannel('staff/alarm_service');

/// Service to handle alarm playback using the alarm package
class AlarmService {
  static const int _baseAlarmId = 9000; // Base ID for FCM alarms
  static const int _baseShortStatusAlarmId = 8500; // Escalated/Cancelled/Completed
  static bool _isInitialized = false;
  static final Set<int> _activeAlarmIds = <int>{};
  // Track which tasks currently require an alarm. We use this to ensure:
  // - Only ONE alarm sound plays, even if multiple tasks are assigned
  // - Alarm stops only when all task IDs have been cleared
  static final Set<int> _activeTaskIds = <int>{};
  static Timer? _cleanupTimer;
  // Store last message data for alarm package notification tap handling
  static Map<String, dynamic>? _lastMessageData;
  // iOS-specific background audio player for continuous playback after banner disappears
  static AudioPlayer? _iosBackgroundPlayer;
  // iOS short status alert player (Escalated/Cancelled/Completed – ~2s, no loop)
  static AudioPlayer? _iosShortStatusPlayer;
  static Timer? _iosShortStatusTimer;
  // iOS background audio timeout timer (auto-stop after max duration to prevent battery drain)
  static Timer? _iosAudioTimeoutTimer;
  static const Duration _maxIOSBackgroundAudioDuration = Duration(minutes: 5);

  /// Initialize the alarm service
  static Future<void> initialize() async {
    if (_isInitialized || kIsWeb) return;

    try {
      await Alarm.init();
      _isInitialized = true;
      debugPrint('🔔 Alarm service initialized');

      // Handle notification taps if supported by this version of the package
      // or if we can intercept them via local notifications

      // Start periodic cleanup timer to cancel alarm package notifications
      _startCleanupTimer();
    } catch (e) {
      debugPrint('❌ Error initializing alarm service: $e');
      _isInitialized = true; // Mark as initialized to prevent repeated attempts
    }
  }

  /// Start periodic timer to continuously cancel alarm package notifications
  /// NOTE: This timer is DISABLED to allow notifications to show properly
  /// The alarm package will show notifications with the content we provide in NotificationSettings
  static void _startCleanupTimer() {
    // DISABLED: Don't cancel notifications - we want them to show!
    // The alarm package will automatically show notifications with the content we set
    // in NotificationSettings, so we don't need to cancel them
    _cleanupTimer?.cancel();
    // Timer disabled - notifications should show normally
    debugPrint('🔔 Cleanup timer disabled - notifications will show normally');
  }

  /// Generate a unique alarm ID based on message ID or timestamp
  static int _generateAlarmId(String? messageId) {
    if (messageId != null) {
      // Use hash of message ID to generate consistent ID
      final hash = messageId.hashCode;
      // Ensure positive ID in valid range (9000-9999)
      return _baseAlarmId + (hash.abs() % 999);
    }
    // Fallback to timestamp-based ID
    return _baseAlarmId + (DateTime.now().millisecondsSinceEpoch % 999);
  }

  /// Play alarm sound immediately with looping
  static Future<void> playAlarm({
    String? title,
    String? body,
    bool loop = true,
    String? messageId,
    Map<String, dynamic>? messageData,
    bool isForeground = false,
  }) async {
    if (kIsWeb) return;

    // Android: use native OrderAlertService (FCM title/body, custom sound, vibration)
    if (Platform.isAndroid) {
      await _startAndroidOrderAlarmService(
        title: title ?? 'New Task',
        body: body ?? 'Please respond.',
      );
      return;
    }

    try {
      if (!_isInitialized) {
        await initialize();
      }

      // Store message data for notification tap handling (both in-memory and persistent)
      if (messageData != null && messageData.isNotEmpty) {
        _lastMessageData = messageData;
        // Also store persistently in SharedPreferences so it survives app restarts
        try {
          final prefs = await SharedPreferences.getInstance();
          final jsonString = jsonEncode(messageData);
          await prefs.setString('lastNotificationMessageData', jsonString);
          debugPrint(
            '🔔 Stored message data for notification tap (in-memory & persistent): ${messageData.keys}',
          );
        } catch (e) {
          debugPrint('⚠️ Failed to store message data persistently: $e');
        }
      } else {
        debugPrint('⚠️ No message data to store (null or empty)');
      }

      // Generate unique alarm ID for this notification
      final alarmId = _generateAlarmId(messageId);

      // Stop all previous alarms to ensure only the latest notification's alarm plays
      // This prevents multiple alarms from playing simultaneously
      for (final id in _activeAlarmIds.toList()) {
        try {
          await Alarm.stop(id);
          debugPrint('🔇 Stopped previous alarm: $id');
        } catch (e) {
          debugPrint('⚠️ Error stopping previous alarm $id: $e');
        }
      }
      _activeAlarmIds.clear();

      // Add new alarm ID to active set
      _activeAlarmIds.add(alarmId);

      // Always use defaults for title/body to ensure notification always shows
      final notificationTitle = (title != null && title.trim().isNotEmpty)
          ? title.trim()
          : 'New Order';
      final notificationBody = (body != null && body.trim().isNotEmpty)
          ? body.trim()
          : 'You have received a new order';

      debugPrint(
        '🔔 Alarm title: "$notificationTitle", body: "$notificationBody"',
      );

      final alarmSettings = AlarmSettings(
        id: alarmId,
        dateTime: DateTime.now().add(const Duration(seconds: 1)),
        assetAudioPath: 'assets/audio/alarm.mp3',
        loopAudio: true,
        vibrate: true,
        volumeSettings: VolumeSettings.fixed(volume: 1.0),
        notificationSettings: NotificationSettings(
          title: notificationTitle,
          body: notificationBody,
        ),
        allowAlarmOverlap: true,
      );

      // iOS logic: Differentiate between foreground (AudioPlayer only) and background (Alarm package ONLY)
      if (Platform.isIOS) {
        if (isForeground) {
          debugPrint('🔔 iOS Foreground: Using AudioPlayer ONLY (skipping Alarm.set to avoid duplicate banner)');
          await _startIosAudioPlayer();
        } else {
          debugPrint('🔔 iOS Background: Using Alarm package ONLY (skipping manual AudioPlayer to avoid double sound)');
          await Alarm.set(alarmSettings: alarmSettings);
          debugPrint('🔔 Alarm set with ID: $alarmId');
        }
      } else {
        // Android is already handled or non-iOS fallback
        await Alarm.set(alarmSettings: alarmSettings);
        debugPrint('🔔 Alarm set with ID: $alarmId');
      }

      // Note: we no longer create our own notification here.
      // Visual notifications are handled by FCM / system notification payload.
    } catch (e) {
      debugPrint('❌ Error playing alarm: $e');
    }
  }

  /// Stop all active alarms
  static Future<void> stopAllAlarms() async {
    if (kIsWeb) return;

    if (Platform.isAndroid) {
      await _stopAndroidOrderAlarmService();
      _activeTaskIds.clear();
      return;
    }

    try {
      // Stop all tracked active alarms
      for (final alarmId in _activeAlarmIds.toList()) {
        try {
          await Alarm.stop(alarmId);
          debugPrint('🔇 Alarm stopped: $alarmId');
        } catch (e) {
          debugPrint('⚠️ Error stopping alarm $alarmId: $e');
        }
      }
      _activeAlarmIds.clear();

      // Also stop any remaining alarms from alarm package
      try {
        final alarms = await Alarm.getAlarms();
        for (final alarm in alarms) {
          if (alarm.id >= _baseAlarmId && alarm.id < _baseAlarmId + 1000) {
            await Alarm.stop(alarm.id);
          }
        }
      } catch (e) {
        debugPrint('⚠️ Error cleaning up alarms: $e');
      }

      // Cancel all alarm package notifications
      try {
        final localNotifications = await _getLocalNotificationsPlugin();
        for (int id = _baseAlarmId; id < _baseAlarmId + 1000; id++) {
          await localNotifications.cancel(id);
        }
      } catch (e) {
        debugPrint('⚠️ Error cancelling alarm notifications: $e');
      }

      // iOS-specific: Stop background + short status audio players
      if (Platform.isIOS) {
        try {
          _iosShortStatusTimer?.cancel();
          _iosShortStatusTimer = null;
          if (_iosShortStatusPlayer != null) {
            await _iosShortStatusPlayer!.stop();
            await _iosShortStatusPlayer!.dispose();
            _iosShortStatusPlayer = null;
          }
        } catch (e) {
          debugPrint('⚠️ Error stopping iOS short status player: $e');
          _iosShortStatusPlayer = null;
          _iosShortStatusTimer = null;
        }

        try {
          // Cancel timeout timer
          _iosAudioTimeoutTimer?.cancel();
          _iosAudioTimeoutTimer = null;

          // Stop and dispose looping foreground player
          if (_iosBackgroundPlayer != null) {
            await _iosBackgroundPlayer!.stop();
            await _iosBackgroundPlayer!.dispose();
            _iosBackgroundPlayer = null;
            debugPrint('🔇 iOS background audio player stopped');
          }
        } catch (e) {
          debugPrint('⚠️ Error stopping iOS background audio player: $e');
          _iosBackgroundPlayer = null;
          _iosAudioTimeoutTimer = null;
        }
      }
    } catch (e) {
      debugPrint('⚠️ Error stopping alarms: $e');
    }

    // Clear any tracked task IDs as well
    _activeTaskIds.clear();
  }

  /// Stop the currently playing alarm (backward compatibility)
  static Future<void> stopAlarm() async {
    await stopAllAlarms();
  }

  /// Check if alarm is currently playing
  static Future<bool> isPlaying() async {
    if (kIsWeb) return false;
    // On Android we use native OrderAlertService; "playing" = we have active tasks
    if (Platform.isAndroid) return _activeTaskIds.isNotEmpty;

    try {
      final alarms = await Alarm.getAlarms();
      return alarms.any(
        (alarm) => alarm.id >= _baseAlarmId && alarm.id < _baseAlarmId + 1000,
      );
    } catch (e) {
      debugPrint('⚠️ Error checking alarm status: $e');
      return false;
    }
  }

  static Future<void> _startAndroidOrderAlarmService({
    int timeoutSeconds = 600,
    String? title,
    String? body,
    int? taskId,
    String? messageJson,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      final args = <String, dynamic>{'timeoutSeconds': timeoutSeconds};
      if (title != null) args['title'] = title;
      if (body != null) args['body'] = body;
      if (taskId != null) args['taskId'] = taskId;
      if (messageJson != null) args['messageJson'] = messageJson;
      await _androidAlarmChannel.invokeMethod('startOrderAlarmService', args);
      debugPrint('🔔 Android OrderAlertService started: $title / $body taskId=$taskId');
    } catch (e) {
      debugPrint('❌ Error starting Android OrderAlertService: $e');
    }
  }

  static Future<void> _stopAndroidOrderAlarmService() async {
    if (!Platform.isAndroid) return;
    try {
      await _androidAlarmChannel.invokeMethod('stopOrderAlarmService');
      debugPrint('🔇 Android OrderAlertService stopped');
    } catch (e) {
      debugPrint('❌ Error stopping Android OrderAlertService: $e');
    }
  }

  /// Remove a single task's status notification (Escalated / Cancelled /
  /// Completed / Task update) from the tray by its deterministic native id.
  /// This NEVER cancels the ongoing "Assigned" alert notification – that is
  /// removed only when the alarm service is stopped (on accept).
  /// Android only; on iOS the tapped notification is dismissed by the OS.
  static Future<void> clearTaskStatusNotifications(int taskId) async {
    if (Platform.isIOS) {
      // iOS removes a tapped notification from Notification Center automatically,
      // and the assigned alarm notification is cleared when the alarm is stopped
      // on accept. Best-effort: also clear any plugin-posted delivered banner.
      try {
        final plugin = await _getLocalNotificationsPlugin();
        await plugin.cancel(taskId);
        debugPrint(
            '🧹 iOS: cleared/auto-cleared notification for task $taskId');
      } catch (e) {
        debugPrint('⚠️ iOS: error clearing task notification: $e');
      }
      return;
    }

    if (!Platform.isAndroid) return;
    try {
      await _androidAlarmChannel.invokeMethod(
        'clearTaskNotifications',
        {'taskId': taskId},
      );
      debugPrint('🧹 Cleared status notification(s) for task $taskId');
    } catch (e) {
      debugPrint('⚠️ Error clearing task notification(s): $e');
    }
  }

  static Future<void> _muteAndroidOrderAlarmService() async {
    if (!Platform.isAndroid) return;
    try {
      await _androidAlarmChannel.invokeMethod('muteOrderAlarmService');
      debugPrint('🔇 Android OrderAlertService muted');
    } catch (e) {
      debugPrint('❌ Error muting Android OrderAlertService: $e');
    }
  }

  static Future<void> _startAndroidShortStatusAlert({
    int timeoutSeconds = 3,
    String? title,
    String? body,
    int? taskId,
    String? messageJson,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      final args = <String, dynamic>{'timeoutSeconds': timeoutSeconds};
      if (title != null) args['title'] = title;
      if (body != null) args['body'] = body;
      if (taskId != null) args['taskId'] = taskId;
      if (messageJson != null) args['messageJson'] = messageJson;
      await _androidAlarmChannel.invokeMethod('startShortStatusAlert', args);
      debugPrint('🔔 Android short status alert started ($timeoutSeconds s)');
    } catch (e) {
      debugPrint('❌ Error starting Android short status alert: $e');
    }
  }

  /// Escalated / Cancelled / Completed: stop loop, play ~2s alert, show notification.
  static Future<void> playShortStatusAlertForTask({
    required int taskId,
    String? title,
    String? body,
    Map<String, dynamic>? messageData,
    int timeoutSeconds = 3,
    bool isForeground = false,
  }) async {
    _activeTaskIds.remove(taskId);

    if (Platform.isAndroid) {
      final messageJson = messageData != null && messageData['message'] != null
          ? messageData['message'].toString()
          : '{"task_id":$taskId,"msg":""}';
      await _startAndroidShortStatusAlert(
        timeoutSeconds: timeoutSeconds,
        title: title ?? 'Task update',
        body: body ?? '',
        taskId: taskId,
        messageJson: messageJson,
      );
      return;
    }

    await _playIosShortStatusAlert(
      taskId: taskId,
      timeoutSeconds: timeoutSeconds,
      title: title,
      body: body,
      messageData: messageData,
      isForeground: isForeground,
    );
  }

  static Future<void> _persistMessageDataForTap(
      Map<String, dynamic>? messageData) async {
    if (messageData == null || messageData.isEmpty) return;
    _lastMessageData = messageData;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          'lastNotificationMessageData', jsonEncode(messageData));
    } catch (e) {
      debugPrint('⚠️ Failed to persist message data for tap: $e');
    }
  }

  /// Stop loop alarm, play alarm once for [timeoutSeconds], then stop (iOS).
  /// Foreground: AudioPlayer. Background/terminated: alarm package (AudioPlayer
  /// cannot play from the FCM background isolate).
  static Future<void> _playIosShortStatusAlert({
    required int taskId,
    int timeoutSeconds = 3,
    String? title,
    String? body,
    Map<String, dynamic>? messageData,
    bool isForeground = false,
  }) async {
    if (!Platform.isIOS) return;

    await _persistMessageDataForTap(messageData);
    await stopAllAlarms();

    if (!isForeground) {
      await _playIosShortStatusAlertInBackground(
        taskId: taskId,
        timeoutSeconds: timeoutSeconds,
        title: title,
        body: body,
      );
      return;
    }

    try {
      _iosShortStatusTimer?.cancel();
      if (_iosShortStatusPlayer != null) {
        try {
          await _iosShortStatusPlayer!.stop();
          await _iosShortStatusPlayer!.dispose();
        } catch (_) {}
        _iosShortStatusPlayer = null;
      }

      _iosShortStatusPlayer = AudioPlayer();
      await _iosShortStatusPlayer!.setReleaseMode(ReleaseMode.release);
      await _iosShortStatusPlayer!.play(
        AssetSource('audio/alarm.mp3'),
        volume: 1.0,
      );
      debugPrint(
          '🔔 iOS foreground short status alert started (${timeoutSeconds}s): ${title ?? "Task update"}');

      _iosShortStatusTimer = Timer(Duration(seconds: timeoutSeconds), () async {
        try {
          await _iosShortStatusPlayer?.stop();
          await _iosShortStatusPlayer?.dispose();
        } catch (_) {}
        _iosShortStatusPlayer = null;
        _iosShortStatusTimer = null;
        debugPrint('🔇 iOS foreground short status alert finished');
      });
    } catch (e) {
      debugPrint('⚠️ iOS foreground short status alert error: $e');
      _iosShortStatusPlayer = null;
      _iosShortStatusTimer = null;
    }
  }

  /// iOS background/terminated: alarm package (same native path as Assigned).
  static Future<void> _playIosShortStatusAlertInBackground({
    required int taskId,
    int timeoutSeconds = 3,
    String? title,
    String? body,
  }) async {
    if (!Platform.isIOS) return;

    try {
      if (!_isInitialized) {
        await initialize();
      }

      final alarmId = _baseShortStatusAlarmId + (taskId % 999);
      try {
        await Alarm.stop(alarmId);
      } catch (_) {}

      _iosShortStatusTimer?.cancel();

      final notificationTitle =
          (title != null && title.trim().isNotEmpty) ? title.trim() : 'Task update';
      final notificationBody =
          (body != null && body.trim().isNotEmpty) ? body.trim() : '';

      final alarmSettings = AlarmSettings(
        id: alarmId,
        dateTime: DateTime.now().add(const Duration(milliseconds: 300)),
        assetAudioPath: 'assets/audio/alarm.mp3',
        loopAudio: false,
        vibrate: true,
        volumeSettings: VolumeSettings.fixed(volume: 1.0),
        notificationSettings: NotificationSettings(
          title: notificationTitle,
          body: notificationBody,
        ),
        allowAlarmOverlap: true,
        warningNotificationOnKill: false,
        iOSBackgroundAudio: true,
      );

      await Alarm.set(alarmSettings: alarmSettings);
      _activeAlarmIds.add(alarmId);

      debugPrint(
          '🔔 iOS background short status alert scheduled (${timeoutSeconds}s): $notificationTitle');

      _iosShortStatusTimer =
          Timer(Duration(seconds: timeoutSeconds + 1), () async {
        try {
          await Alarm.stop(alarmId);
          _activeAlarmIds.remove(alarmId);
        } catch (_) {}
        _iosShortStatusTimer = null;
        debugPrint('🔇 iOS background short status alert finished');
      });
    } catch (e) {
      debugPrint('⚠️ iOS background short status alert error: $e');
      _iosShortStatusTimer = null;
    }
  }

  /// Start an alarm for a specific task ID.
  /// - First task ID starts the global alarm sound
  /// - Additional task IDs are tracked but do NOT start extra alarms
  /// - Android: native OrderAlertService (notification + sound). iOS: alarm package / audio.
  static Future<void> startAlarmForTask({
    required int taskId,
    String? title,
    String? body,
    bool loop = true,
    String? messageId,
    Map<String, dynamic>? messageData,
    bool isForeground = false,
  }) async {
    // If this task is already active, don't restart or duplicate the alarm.
    if (_activeTaskIds.contains(taskId)) {
      debugPrint(
          '🔔 Alarm already active for task $taskId, not starting a new one. Active tasks: $_activeTaskIds');
      return;
    }

    // Add to active set
    _activeTaskIds.add(taskId);

    // Android: single native OrderAlertService (FCM title/body, custom sound, vibration)
    if (Platform.isAndroid) {
      if (_activeTaskIds.length == 1) {
        debugPrint('🔔 Starting Android native alarm for task $taskId');
        final messageJson = messageData != null && messageData['message'] != null
            ? messageData['message'].toString()
            : '{"task_id":$taskId,"msg":""}';
        await _startAndroidOrderAlarmService(
          title: title ?? 'Assigned',
          body: body ?? 'Please accept the task',
          taskId: taskId,
          messageJson: messageJson,
        );
      } else {
        debugPrint('🔔 Task $taskId added; native alarm already running: $_activeTaskIds');
      }
      return;
    }

    // iOS: alarm package / background audio
    final hasOtherTasks = _activeTaskIds.length > 1;
    final alarmCurrentlyPlaying = await isPlaying();

    if (!hasOtherTasks || !alarmCurrentlyPlaying) {
      debugPrint(
          '🔔 Starting alarm for task $taskId (hasOtherTasks: $hasOtherTasks, isPlaying: $alarmCurrentlyPlaying)');
      await playAlarm(
        title: title,
        body: body,
        loop: loop,
        messageId: messageId,
        messageData: messageData,
        isForeground: isForeground,
      );
    } else {
      debugPrint(
          '🔔 Task $taskId added to active tasks while alarm already playing: $_activeTaskIds');
    }
  }

  /// Mute alarm sound for a specific task on Android, but keep the notification visible.
  /// Used for Escalated status so the card stays while sound stops.
  static Future<void> muteAlarmForTask(int taskId) async {
    // We still remove from active set so when all tasks are cleared we can
    // fully stop alarms via stopAlarmForTask from other flows if needed.
    if (_activeTaskIds.remove(taskId)) {
      debugPrint('🔔 Task $taskId muted/removed from active alarm tasks (Android).');
    }

    if (Platform.isAndroid) {
      await _muteAndroidOrderAlarmService();
      return;
    }

    // On non-Android platforms, fall back to normal stop behavior.
    await stopAlarmForTask(taskId);
  }

  /// Register a task ID when alarm was started from Android background handler.
  /// Ensures stopAlarmForTask(taskId) will stop the native service when the last task is cleared.
  static void registerTaskIdForAndroid(int taskId) {
    if (!Platform.isAndroid) return;
    _activeTaskIds.add(taskId);
    debugPrint('🔔 Registered task $taskId for Android alarm (from background). Active: $_activeTaskIds');
  }

  /// Stop an alarm for a specific task ID.
  /// - Removes the task ID from the active set
  /// - Stops the global alarm ONLY when there are no remaining active tasks
  static Future<void> stopAlarmForTask(int taskId) async {
    if (_activeTaskIds.remove(taskId)) {
      debugPrint('🔔 Task $taskId removed from active alarm tasks.');
    }

    if (_activeTaskIds.isEmpty) {
      debugPrint('🔔 No active tasks remain. Stopping all alarms.');
      await stopAllAlarms();
    } else {
      debugPrint(
          '🔔 Active tasks still present, keeping alarm running: $_activeTaskIds');
    }
  }

  /// Get last message data for alarm package notification tap handling
  /// Tries in-memory first, then falls back to SharedPreferences for persistence
  static Future<Map<String, dynamic>?> getLastMessageData() async {
    // First try in-memory (faster)
    if (_lastMessageData != null && _lastMessageData!.isNotEmpty) {
      debugPrint('🔔✅ Retrieved message data from memory');
      return _lastMessageData;
    }

    // Fallback to SharedPreferences (persistent storage)
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString('lastNotificationMessageData');
      if (jsonString != null && jsonString.isNotEmpty) {
        final decoded = jsonDecode(jsonString) as Map<String, dynamic>;
        debugPrint('🔔✅ Retrieved message data from SharedPreferences');
        // Also restore to in-memory for faster access
        _lastMessageData = decoded;
        return decoded;
      }
    } catch (e) {
      debugPrint(
        '⚠️ Failed to retrieve message data from SharedPreferences: $e',
      );
    }

    debugPrint('⚠️ No message data found in memory or SharedPreferences');
    return null;
  }

  /// Clear last message data (both in-memory and persistent)
  static Future<void> clearLastMessageData() async {
    _lastMessageData = null;
    // Also clear from SharedPreferences
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('lastNotificationMessageData');
      debugPrint('🔔✅ Cleared message data from memory and SharedPreferences');
    } catch (e) {
      debugPrint('⚠️ Failed to clear message data from SharedPreferences: $e');
    }
  }

  /// Get local notifications plugin instance to cancel alarm package notifications
  static Future<FlutterLocalNotificationsPlugin>
      _getLocalNotificationsPlugin() async {
    final localNotifications = FlutterLocalNotificationsPlugin();

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await localNotifications.initialize(initSettings);
    return localNotifications;
  }

  /// Helper to start iOS audio player (for foreground use)
  static Future<void> _startIosAudioPlayer() async {
    try {
      // Stop any existing iOS background audio player
      if (_iosBackgroundPlayer != null) {
        try {
          await _iosBackgroundPlayer!.stop();
          await _iosBackgroundPlayer!.dispose();
        } catch (_) {}
        _iosBackgroundPlayer = null;
      }

      // Create new audio player
      _iosBackgroundPlayer = AudioPlayer();
      await _iosBackgroundPlayer!.setReleaseMode(ReleaseMode.loop);

      await _iosBackgroundPlayer!.play(
        AssetSource('audio/alarm.mp3'),
        volume: 1.0,
      );
      debugPrint('🔔✅ iOS foreground audio player started');

      // Safety: Auto-stop after maximum duration
      _iosAudioTimeoutTimer?.cancel();
      _iosAudioTimeoutTimer = Timer(_maxIOSBackgroundAudioDuration, () {
        debugPrint('🔔⏱️ iOS audio auto-stopped after max duration');
        if (_iosBackgroundPlayer != null) {
          _iosBackgroundPlayer!.stop().catchError((e) => debugPrint('⚠️ Error auto-stopping iOS audio: $e'));
        }
      });
    } catch (e) {
      debugPrint('⚠️ Error starting iOS audio player: $e');
    }
  }
}
