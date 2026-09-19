import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class NotificationSettingsService {
  /// Check if notification permissions are granted
  static Future<bool> areNotificationsEnabled() async {
    try {
      // Check Firebase messaging permission status
      NotificationSettings settings =
          await FirebaseMessaging.instance.getNotificationSettings();

      // Check Android runtime permission (Android 13+)
      PermissionStatus androidStatus = await Permission.notification.status;

      // For Android, both Firebase and runtime permissions must be granted
      // For iOS, only Firebase permission matters
      bool firebaseGranted =
          settings.authorizationStatus == AuthorizationStatus.authorized;
      bool androidGranted = androidStatus == PermissionStatus.granted;

      // On Android, both permissions must be granted
      // On iOS, only Firebase permission is checked
      return firebaseGranted &&
          (androidGranted || androidStatus == PermissionStatus.denied);
    } catch (e) {
      print('❌ Error checking notification permissions: $e');
      return false;
    }
  }

  /// Get detailed permission status for debugging
  static Future<Map<String, dynamic>> getPermissionStatus() async {
    try {
      NotificationSettings firebaseSettings =
          await FirebaseMessaging.instance.getNotificationSettings();
      PermissionStatus androidStatus = await Permission.notification.status;

      return {
        'firebase_authorization':
            firebaseSettings.authorizationStatus.toString(),
        'firebase_alert': firebaseSettings.alert.toString(),
        'firebase_sound': firebaseSettings.sound.toString(),
        'firebase_badge': firebaseSettings.badge.toString(),
        'android_runtime_status': androidStatus.toString(),
        'are_enabled': await areNotificationsEnabled(),
      };
    } catch (e) {
      print('❌ Error getting permission status: $e');
      return {'error': e.toString()};
    }
  }

  /// Open app settings to allow user to enable notifications
  static Future<void> openDeviceSettings() async {
    try {
      await openAppSettings();
      print('📱 Opened app settings');
    } catch (e) {
      print('❌ Error opening app settings: $e');
    }
  }

  /// Request notification permissions
  static Future<bool> requestNotificationPermissions() async {
    try {
      // Request Firebase messaging permissions
      NotificationSettings settings =
          await FirebaseMessaging.instance.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      // Request Android runtime permission (Android 13+)
      PermissionStatus androidStatus = await Permission.notification.request();

      bool firebaseGranted =
          settings.authorizationStatus == AuthorizationStatus.authorized;
      bool androidGranted = androidStatus == PermissionStatus.granted;

      print('📱 Firebase permission: ${settings.authorizationStatus}');
      print('📱 Android runtime permission: $androidStatus');

      return firebaseGranted &&
          (androidGranted || androidStatus == PermissionStatus.denied);
    } catch (e) {
      print('❌ Error requesting notification permissions: $e');
      return false;
    }
  }

  /// Show notification settings dialog
  static Future<void> showNotificationSettingsDialog(
      BuildContext context) async {
    bool areEnabled = await areNotificationsEnabled();

    if (!context.mounted) return;

    if (areEnabled) {
      // Show snackbar if notifications are already enabled
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.notifications_active, color: Colors.white),
              SizedBox(width: 8),
              Text('App notifications are already turned on'),
            ],
          ),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );
    } else {
      // Show dialog to guide user to enable notifications
      if (!context.mounted) return;
      showDialog(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          backgroundColor: Colors.white,
          content: Container(
            padding: EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  Icons.notifications_off,
                  size: 48,
                  color: Colors.orange,
                ),
                SizedBox(height: 16),
                Text(
                  'Enable Notifications',
                  style: TextStyle(
                    fontSize: MediaQuery.of(context).size.width * 0.05,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'To receive important task updates, please enable notifications in your device settings.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: MediaQuery.of(context).size.width * 0.04,
                    color: Colors.grey[600],
                  ),
                ),
                SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: MediaQuery.of(context).size.height * 0.056,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        child: ElevatedButton(
                          style: TextButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor:
                                Theme.of(context).colorScheme.primary,
                          ),
                          onPressed: () {
                            Navigator.pop(context);
                          },
                          child: Text(
                            'Cancel',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: MediaQuery.of(context).size.width * 0.025),
                    Expanded(
                      child: Container(
                        height: MediaQuery.of(context).size.height * 0.056,
                        child: ElevatedButton(
                          onPressed: () async {
                            Navigator.pop(context);
                            await openDeviceSettings();
                          },
                          child: Text(
                            'Settings',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }
  }
}
