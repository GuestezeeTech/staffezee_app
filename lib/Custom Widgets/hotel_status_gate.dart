import 'package:flutter/material.dart';
import 'package:guestezee_staffs_app/Screens/login_page.dart';
import 'package:guestezee_staffs_app/Services/Notifictaion%20service/alarm_service.dart';
import 'package:guestezee_staffs_app/Services/continuous_sound_service.dart';
import 'package:guestezee_staffs_app/Services/hotel_status_service.dart';
import 'package:guestezee_staffs_app/Services/local_storage_service.dart';

/// Wraps the whole app. Blocks the UI when staff is inactive or the hotel is
/// disabled, with non-dismissible modals (Back on login, Logout when logged in).
class HotelStatusGate extends StatelessWidget {
  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;

  const HotelStatusGate({
    super.key,
    required this.child,
    required this.navigatorKey,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: HotelStatusService.staffActive,
      builder: (context, active, _) {
        return ValueListenableBuilder<bool>(
          valueListenable: HotelStatusService.blockedInactiveAtLogin,
          builder: (context, inactiveAtLogin, __) {
            final inactiveBlocked = !active &&
                (LocalStorageService.isLoggedIn || inactiveAtLogin);

            return ValueListenableBuilder<bool>(
              valueListenable: HotelStatusService.hotelEnabled,
              builder: (context, enabled, ___) {
                return ValueListenableBuilder<bool>(
                  valueListenable: HotelStatusService.blockedAtLogin,
                  builder: (context, atLogin, ____) {
                    final hotelBlocked = !enabled &&
                        (LocalStorageService.isLoggedIn || atLogin);

                    return Stack(
                      children: [
                        child,
                        if (inactiveBlocked)
                          Positioned.fill(
                            child: _InactiveStaffOverlay(
                              navigatorKey: navigatorKey,
                              isLoginBlock: inactiveAtLogin,
                            ),
                          )
                        else if (hotelBlocked)
                          Positioned.fill(
                            child: _HotelDisabledOverlay(
                              navigatorKey: navigatorKey,
                              isLoginBlock: atLogin,
                            ),
                          ),
                      ],
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

class _InactiveStaffOverlay extends StatefulWidget {
  final GlobalKey<NavigatorState> navigatorKey;
  final bool isLoginBlock;

  const _InactiveStaffOverlay({
    required this.navigatorKey,
    this.isLoginBlock = false,
  });

  @override
  State<_InactiveStaffOverlay> createState() => _InactiveStaffOverlayState();
}

class _InactiveStaffOverlayState extends State<_InactiveStaffOverlay> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _stopSounds();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusManager.instance.primaryFocus?.unfocus();
    });
  }

  Future<void> _stopSounds() async {
    try {
      await AlarmService.stopAllAlarms();
    } catch (_) {}
    try {
      await ContinuousSoundService.stopAllSounds();
    } catch (_) {}
  }

  void _back() {
    if (_busy) return;
    FocusManager.instance.primaryFocus?.unfocus();
    HotelStatusService.dismissInactiveLoginBlock();
  }

  Future<void> _logout() async {
    if (_busy) return;
    setState(() => _busy = true);

    await HotelStatusService.performLogout();

    final navigator = widget.navigatorKey.currentState;
    if (navigator != null) {
      navigator.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.black.withOpacity(0.6),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.person_off_outlined,
                    size: 44,
                    color: Colors.orange.shade700,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Inactive staff found',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Please contact admin for further details',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[700],
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed:
                        _busy ? null : (widget.isLoginBlock ? _back : _logout),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Icon(widget.isLoginBlock
                            ? Icons.arrow_back
                            : Icons.logout),
                    label: Text(
                      widget.isLoginBlock ? 'Back' : 'Logout',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HotelDisabledOverlay extends StatefulWidget {
  final GlobalKey<NavigatorState> navigatorKey;
  final bool isLoginBlock;

  const _HotelDisabledOverlay({
    required this.navigatorKey,
    this.isLoginBlock = false,
  });

  @override
  State<_HotelDisabledOverlay> createState() => _HotelDisabledOverlayState();
}

class _HotelDisabledOverlayState extends State<_HotelDisabledOverlay> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _stopSounds();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusManager.instance.primaryFocus?.unfocus();
    });
  }

  Future<void> _stopSounds() async {
    try {
      await AlarmService.stopAllAlarms();
    } catch (_) {}
    try {
      await ContinuousSoundService.stopAllSounds();
    } catch (_) {}
  }

  void _back() {
    if (_busy) return;
    FocusManager.instance.primaryFocus?.unfocus();
    HotelStatusService.dismissLoginBlock();
  }

  Future<void> _logout() async {
    if (_busy) return;
    setState(() => _busy = true);

    await HotelStatusService.performLogout();

    final navigator = widget.navigatorKey.currentState;
    if (navigator != null) {
      navigator.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.black.withOpacity(0.6),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                            Icons.error_outline,
                    size: 44,
                    color: Colors.red.shade600,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Account Deactivated',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Your hotel account is deactivated. Please contact the administrator for assistance.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[700],
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed:
                        _busy ? null : (widget.isLoginBlock ? _back : _logout),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Icon(widget.isLoginBlock
                            ? Icons.arrow_back
                            : Icons.logout),
                    label: Text(
                      widget.isLoginBlock ? 'Back' : 'Logout',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
