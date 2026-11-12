import 'package:flutter/material.dart';
import 'package:guestezee_staffs_app/Services/local_storage_service.dart';
import 'package:guestezee_staffs_app/Services/notification_settings_launcher.dart';
import 'package:guestezee_staffs_app/Services/push_notification_service.dart';

bool _notificationPromptScheduled = false;

/// Shows the in-app sheet 1 second after login, once per launch, when
/// notifications are still off. The system dialog is not shown here.
void scheduleNotificationPromptAfterLogin() {
  if (_notificationPromptScheduled) return;
  _notificationPromptScheduled = true;
  Future<void>.delayed(const Duration(seconds: 1), () async {
    if (!LocalStorageService.isLoggedIn) return;
    final granted =
        await PushNotificationService.isNotificationPermissionGranted();
    if (granted) {
      await LocalStorageService.clearNotificationPermissionPromptState();
      return;
    }
    final context = PushNotificationService.promptContext;
    if (context == null || !context.mounted) return;
    await showNotificationPermissionBottomSheet(context);
  });
}

/// In-app sheet. The system permission dialog runs only after Allow.
/// If the system dialog was already denied, the button opens app settings.
Future<void> showNotificationPermissionBottomSheet(BuildContext context) async {
  await PushNotificationService.refreshNotificationPermissionState();
  if (!context.mounted) return;

  await showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => const _NotificationPermissionSheet(),
  );
}

class _NotificationPermissionSheet extends StatefulWidget {
  const _NotificationPermissionSheet();

  @override
  State<_NotificationPermissionSheet> createState() =>
      _NotificationPermissionSheetState();
}

class _NotificationPermissionSheetState
    extends State<_NotificationPermissionSheet> with WidgetsBindingObserver {
  bool _skipped = false;
  bool _allowPop = false;

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
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _closeOnlyIfEnabled();
    }
  }

  void _popSheet() {
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  /// Sheet stays until Skip for now, or notifications are actually on.
  Future<void> _closeOnlyIfEnabled() async {
    if (_skipped || !mounted) return;
    final granted =
        await PushNotificationService.isNotificationPermissionGranted();
    if (!mounted || _skipped) return;
    if (granted) {
      await LocalStorageService.clearNotificationPermissionPromptState();
      _popSheet();
      return;
    }
    await PushNotificationService.refreshNotificationPermissionState();
    if (mounted) setState(() {});
  }

  Future<void> _closeAsDeclined() async {
    if (_skipped) return;
    _skipped = true;
    await LocalStorageService.setNotificationModalResponse('declined');
    if (!mounted) return;
    _popSheet();
  }

  Future<void> _onEnable() async {
    if (_skipped) return;
    await LocalStorageService.setNotificationModalResponse('allowed');
    await PushNotificationService.refreshNotificationPermissionState();
    if (!mounted) return;

    if (PushNotificationService.shouldRequestOsPromptAfterModalAllow()) {
      await PushNotificationService.requestNotificationPermission();
      if (!mounted) return;
      await _closeOnlyIfEnabled();
      return;
    }

    if (PushNotificationService.shouldOpenSettingsAfterModalAllow()) {
      await NotificationSettingsLauncher.open();
      return;
    }

    await _closeOnlyIfEnabled();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_allowPop) {
          Navigator.of(context).pop();
        }
      },
      child: _NotificationPermissionCard(
        onNotNow: _closeAsDeclined,
        onEnable: _onEnable,
      ),
    );
  }
}

class _NotificationPermissionCard extends StatelessWidget {
  final Future<void> Function() onNotNow;
  final Future<void> Function() onEnable;

  const _NotificationPermissionCard({
    required this.onNotNow,
    required this.onEnable,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final gold = theme.colorScheme.secondary;

    final openSettings =
        PushNotificationService.shouldOpenSettingsAfterModalAllow() &&
            !PushNotificationService.shouldRequestOsPromptAfterModalAllow();

    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF9FAFC),
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(24),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(22, 12, 22, 24 + bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),

            const SizedBox(height: 28),

            Center(
              child: Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: gold.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.notifications_active_rounded,
                  size: 36,
                  color: primary,
                ),
              ),
            ),

            const SizedBox(height: 20),

            Text(
              'Stay on top of your tasks',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: const Color(0xFF202938),
              ),
            ),

            const SizedBox(height: 9),

            Text(
              openSettings
                  ? 'Notifications are currently disabled. Enable them in your phone settings to receive task updates.'
                  : 'Get instant updates whenever something needs your attention.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF727987),
                height: 1.5,
              ),
            ),

            // const SizedBox(height: 24),

            // _NotificationBenefit(
            //   icon: Icons.assignment_add,
            //   title: 'New task assignments',
            //   subtitle: 'Know immediately when a task comes your way.',
            //   primary: primary,
            // ),

            // const SizedBox(height: 12),

            // _NotificationBenefit(
            //   icon: Icons.priority_high_rounded,
            //   title: 'Important task updates',
            //   subtitle: 'Stay informed about escalations and cancellations.',
            //   primary: primary,
            // ),

            const SizedBox(height: 26),

            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: onEnable,
                style: ElevatedButton.styleFrom(
                  backgroundColor: primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      openSettings ? 'Open settings' : 'Enable notifications',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.arrow_forward_rounded, size: 18),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 10),

            TextButton(
              onPressed: onNotNow,
              child: const Text(
                'Maybe later',
                style: TextStyle(
                  color: Color(0xFF777F8C),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationBenefit extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color primary;

  const _NotificationBenefit({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.primary,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: const Color(0xFFE9EBEF),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: primary, size: 22),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF252B36),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: Color(0xFF7A8290),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
