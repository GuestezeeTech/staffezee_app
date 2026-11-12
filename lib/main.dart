import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:guestezee_staffs_app/Custom%20Widgets/navigation_page.dart';
import 'package:guestezee_staffs_app/Custom%20Widgets/notification_permission_bottom_sheet.dart';
import 'package:guestezee_staffs_app/Custom%20Widgets/hotel_status_gate.dart';
import 'package:guestezee_staffs_app/Screens/login_page.dart';
import 'package:guestezee_staffs_app/Screens/escalated_tasks_page.dart';
import 'package:guestezee_staffs_app/Services/version_service.dart';
import 'package:guestezee_staffs_app/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:guestezee_staffs_app/Services/high_priority_badge_service.dart';
import 'package:guestezee_staffs_app/Services/hotel_status_service.dart';
import 'package:guestezee_staffs_app/Services/local_storage_service.dart';
import 'package:guestezee_staffs_app/Services/manager_level_service.dart';
import 'package:guestezee_staffs_app/Services/push_notification_service.dart';
import 'package:guestezee_staffs_app/Services/background_message_handler.dart';
import 'package:guestezee_staffs_app/Services/continuous_sound_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:guestezee_staffs_app/firebase_options.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';

// Global navigator key for push notifications
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// Global messenger key so services can show snackbars app-wide.
final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

/// Force logout (e.g. staff record removed): go to login + red snackbar.
Future<void> _handleForcedLogout([String? message]) async {
  navigatorKey.currentState?.pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const LoginPage()),
    (route) => false,
  );
  scaffoldMessengerKey.currentState?.showSnackBar(
    SnackBar(
      content: Text(message?.trim().isNotEmpty == true
          ? message!.trim()
          : "You've been logged out"),
      backgroundColor: Colors.red,
      duration: const Duration(seconds: 3),
    ),
  );
}

// Background message handler for terminated state
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print('🔥 MAIN BACKGROUND HANDLER CALLED - Initializing Firebase...');

  // Initialize Firebase in background isolate
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  print('🔥 Firebase initialized, calling custom background handler...');

  // Use our custom background message handler
  await firebaseMessagingBackgroundHandler(message);

  print('🔥 Custom background handler completed');
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize local storage
  await LocalStorageService.init();
  await HighPriorityBadgeService.init();

  // Restore session status (staff is_active + hotel_enabled); poll when logged in.
  HotelStatusService.onForcedLogout = _handleForcedLogout;
  await HotelStatusService.initFromStorage();
  ManagerLevelService.onDemotedToStaff = () async {
    navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const NavigationPage(initialIndex: 0),
      ),
      (route) => false,
    );
  };
  ManagerLevelService.onPromotedToManager = () async {
    navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const EscalatedTasksPage()),
      (route) => false,
    );
  };
  if (LocalStorageService.rememberMe && LocalStorageService.isLoggedIn) {
    HotelStatusService.startPolling();
    await ManagerLevelService.refreshFromServer();
  }

  // Initialize Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Set background message handler for terminated state
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Initialize push notifications
  await PushNotificationService.initialize(navigatorKey);

  // When user is already logged in, refresh FCM token with backend (add to array or update availability)
  WidgetsBinding.instance.addPostFrameCallback((_) {
    PushNotificationService.refreshFcmTokenWithBackendIfLoggedIn();
    if (LocalStorageService.rememberMe && LocalStorageService.isLoggedIn) {
      scheduleNotificationPromptAfterLogin();
    }
  });

  // Initialize continuous sound service
  ContinuousSoundService.instance;

  // Lock orientation to portrait mode only
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  runApp(ProviderScope(child: const MyApp()));
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Future<bool> didPopRoute() async {
    // Block hardware back while inactive-staff or hotel-disabled modals are shown.
    if (!HotelStatusService.staffActive.value &&
        (LocalStorageService.isLoggedIn ||
            HotelStatusService.blockedInactiveAtLogin.value)) {
      return true;
    }
    if (!HotelStatusService.hotelEnabled.value &&
        (LocalStorageService.isLoggedIn ||
            HotelStatusService.blockedAtLogin.value)) {
      return true;
    }
    return super.didPopRoute();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.resumed) {
      // App became active (from background or terminated). Run after a short delay
      // so the navigator has a frame to build. First check native pending notification data (tap),
      // then run full pending-notification checks.
      print(
          "🔄 App became active (onResume), checking for pending notifications");
      Future.delayed(const Duration(milliseconds: 250), () async {
        await PushNotificationService.handleNativeNotificationTapIfAny();
        PushNotificationService.checkAndProcessPendingNotifications();
      });

      // Re-check hotel status and manager level immediately on resume.
      if (LocalStorageService.isLoggedIn) {
        HotelStatusService.startPolling();
        ManagerLevelService.refreshFromServer();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Determine initial route based on login state and staff level
    Widget initialScreen = const LoginPage();

    if (LocalStorageService.rememberMe && LocalStorageService.isLoggedIn) {
      if (LocalStorageService.isManagerLevel) {
        initialScreen = const EscalatedTasksPage();
      } else {
        initialScreen = const NavigationPage(initialIndex: 0);
      }
    }

    // Wrap initial screen with version check widget to check for updates on app open
    final wrappedScreen = VersionCheckWidget(child: initialScreen);

    return MaterialApp(
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: scaffoldMessengerKey,
      theme: AppTheme.appTheme,
      home: wrappedScreen,
      builder: (context, child) {
        return HotelStatusGate(
          navigatorKey: navigatorKey,
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}

class AppVersionChecker {
  static Future<bool> checkForUpdate() async {
    if (kIsWeb) return false;

    try {
      PackageInfo packageInfo = await PackageInfo.fromPlatform();
      String currentVersion = packageInfo.version;

      await LocalStorageService.storeVersion(currentVersion);

      final res = await VersionService.getUpdatedVersion();
      final parsed = jsonDecode(res.body);

      if (parsed['success'] == 1 && parsed['status_code'] == 200) {
        final latestVersion = Platform.isAndroid
            ? parsed['result']['data'][0]['staff_android_app_version']
                ?.toString()
            : parsed['result']['data'][0]['staff_ios_app_version']?.toString();

        if (latestVersion == null || latestVersion.isEmpty) return false;

        return _isVersionBehind(currentVersion, latestVersion);
      }
    } catch (e) {
      print('❌ Error checking for app version update: $e');
    }
    return false;
  }

  static bool _isVersionBehind(String current, String latest) {
    final currentParts = current.split('.').map(int.parse).toList();
    final latestParts = latest.split('.').map(int.parse).toList();

    for (int i = 0; i < latestParts.length; i++) {
      if (i >= currentParts.length) return true;
      if (currentParts[i] < latestParts[i]) return true;
      if (currentParts[i] > latestParts[i]) return false;
    }
    return false;
  }

  /// Check for app version update and show dialog if update is needed
  /// Call this method in initState of landing screens (HomeScreen, LoginScreen)
  static Future<void> checkAndShowUpdateDialog(BuildContext context) async {
    if (kIsWeb) return;

    try {
      bool updateNeeded = await checkForUpdate();
      if (updateNeeded && context.mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) {
            return WillPopScope(
              onWillPop: () async => false,
              child: Dialog(
                backgroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.system_update_outlined,
                          size: 60,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          "Update Available!",
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          "A newer version of the app is available.\nPlease update to continue.",
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  Theme.of(context).colorScheme.primary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            onPressed: () async {
                              final url = Platform.isAndroid
                                  ? Uri.parse(
                                      "https://play.google.com/store/apps/details?id=com.guestezee.staff",
                                    )
                                  : Uri.parse(
                                      "https://apps.apple.com/app/6758706838",
                                    );

                              if (await canLaunchUrl(url)) {
                                await launchUrl(
                                  url,
                                  mode: LaunchMode.externalApplication,
                                );
                              }
                            },
                            child: const Text(
                              "Update Now",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      }
    } catch (e) {
      print('❌ Error showing update dialog: $e');
    }
  }
}

class VersionCheckWidget extends StatefulWidget {
  final Widget child;
  const VersionCheckWidget({super.key, required this.child});

  @override
  State<VersionCheckWidget> createState() => _VersionCheckWidgetState();
}

class _VersionCheckWidgetState extends State<VersionCheckWidget> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        AppVersionChecker.checkAndShowUpdateDialog(context);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
