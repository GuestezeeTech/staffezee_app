import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:guestezee_staffs_app/Services/customer_service.dart';
import 'package:guestezee_staffs_app/Services/local_storage_service.dart';
import 'package:guestezee_staffs_app/Services/manager_level_service.dart';
import 'package:guestezee_staffs_app/Services/staff_service.dart';
import 'package:guestezee_staffs_app/Services/task_refresh_service.dart';

/// Session monitor: staff getall (presence + is_staff_active), customer getall
/// (hotel_enabled), and task getall refresh every minute while logged in.
class HotelStatusService {
  HotelStatusService._();

  static final ValueNotifier<bool> hotelEnabled = ValueNotifier<bool>(true);
  static final ValueNotifier<bool> staffActive = ValueNotifier<bool>(true);
  static final ValueNotifier<bool> blockedAtLogin = ValueNotifier<bool>(false);
  static final ValueNotifier<bool> blockedInactiveAtLogin =
      ValueNotifier<bool>(false);

  static Timer? _pollTimer;
  static bool _refreshInFlight = false;

  static void Function(String message)? onForcedLogout;

  static bool isEnabledForUser(Map<String, dynamic>? source) {
  return _parseEnabledFlag(source);
  }

  static bool isActiveForUser(Map<String, dynamic>? source) {
    if (source == null) return true;

    // Backend now sends `is_staff_active`; keep `is_active` as fallback.
    final dynamic value = source.containsKey('is_staff_active')
        ? source['is_staff_active']
        : source['is_active'];
    if (value == null) return true;
    if (value is bool) return value;
    final text = value.toString().trim().toLowerCase();
    if (text == 'false' || text == '0' || text == 'no') return false;
    return true;
  }

  static bool _parseEnabledFlag(Map<String, dynamic>? source) {
    if (source == null) return true;
    if (!source.containsKey('hotel_enabled')) return true;
    final value = source['hotel_enabled'];
    if (value == null) return true;
    if (value is bool) return value;
    final text = value.toString().trim().toLowerCase();
    if (text == 'false' || text == '0' || text == 'no') return false;
    return true;
  }

  static Future<void> initFromStorage() async {
    await LocalStorageService.init();
    hotelEnabled.value = LocalStorageService.hotelEnabled;
    staffActive.value = LocalStorageService.staffActive;
  }

  /// Legacy helper — hotel access must come from customer getall only.
  /// Do not read `hotel_enabled` from the staff login user (causes a false
  /// "Account Deactivated" flash then allows login after refresh).
  static Future<void> updateFromUser(Map<String, dynamic>? user) async {
    // Intentionally no-op for hotel_enabled.
  }

  static Future<void> updateStaffActiveFromUser(
      Map<String, dynamic>? user) async {
    final active = isActiveForUser(user);
    staffActive.value = active;
    await LocalStorageService.saveStaffActive(active);
  }

  static Future<void> updateFromCustomerResponse(
      Map<String, dynamic> responseBody) async {
    final enabled = CustomerService.parseHotelEnabled(responseBody);
    await _setHotelEnabled(enabled);
  }

  /// Customer getall hotel gate: empty data OR hotel_enabled false => blocked.
  /// Returns true when hotel is accessible.
  ///
  /// [applyToSession] when false only returns the result without flipping the
  /// global overlay (use for pre-login checks; call [showLoginBlock] on fail).
  static Future<bool> checkCustomerHotelAccess(
    String memberId, {
    bool applyToSession = true,
  }) async {
    final id = memberId.trim();
    if (id.isEmpty) {
      if (applyToSession) await _setHotelEnabled(false);
      return false;
    }

    try {
      final response = await CustomerService.getCustomerByMemberId(id);
      if (response.statusCode != 200 && response.statusCode != 201) {
        if (applyToSession) await _setHotelEnabled(false);
        return false;
      }
      final body = jsonDecode(response.body);
      if (body is! Map) {
        if (applyToSession) await _setHotelEnabled(false);
        return false;
      }
      final enabled = CustomerService.parseHotelEnabled(
        Map<String, dynamic>.from(body),
      );
      if (applyToSession) await _setHotelEnabled(enabled);
      return enabled;
    } catch (e) {
      debugPrint('⚠️ checkCustomerHotelAccess failed: $e');
      if (applyToSession) await _setHotelEnabled(false);
      return false;
    }
  }

  static Future<void> _setHotelEnabled(bool enabled) async {
    hotelEnabled.value = enabled;
    await LocalStorageService.saveHotelEnabled(enabled);
  }

  static void showLoginBlock() {
    blockedAtLogin.value = true;
    hotelEnabled.value = false;
  }

  static void dismissLoginBlock() {
    blockedAtLogin.value = false;
    hotelEnabled.value = true;
  }

  static void showInactiveLoginBlock() {
    blockedInactiveAtLogin.value = true;
    staffActive.value = false;
  }

  static void dismissInactiveLoginBlock() {
    blockedInactiveAtLogin.value = false;
    staffActive.value = true;
  }

  static void startPolling() {
    stopPolling();
    _refresh();
    _pollTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _refresh(),
    );
  }

  static void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  static Future<void> refreshNow() => _refresh();

  static Future<void> performLogout() async {
    stopPolling();
    hotelEnabled.value = true;
    staffActive.value = true;
    blockedAtLogin.value = false;
    blockedInactiveAtLogin.value = false;
    await LocalStorageService.logout();
  }

  static Future<void> _refresh() async {
    if (_refreshInFlight) return;
    if (!LocalStorageService.isLoggedIn) return;

    _refreshInFlight = true;
    try {
      await LocalStorageService.init();
      final user = LocalStorageService.user;
      final empNo = (user?['staff_employee_number'] ?? '').toString().trim();
      if (empNo.isEmpty) return;

      // 1. Staff getall — presence + is_staff_active
      final staffResponse =
          await StaffService.findStaffByEmployeeNumber(empNo);
      if (staffResponse.statusCode != 200 && staffResponse.statusCode != 201) {
        return;
      }

      final staffBody = jsonDecode(staffResponse.body) as Map<String, dynamic>;
      final staffList = staffBody['result']?['data'];
      if (staffList is! List || staffList.isEmpty) {
        await _forceLogout('No staff found. You have been logged out.');
        return;
      }

      final staff = staffList.first;
      if (staff is! Map) return;
      final staffMap = Map<String, dynamic>.from(staff);

      final previousFingerprint =
          StaffService.roleFingerprint(LocalStorageService.user);

      final active = isActiveForUser(staffMap);
      await updateStaffActiveFromUser(staffMap);
      if (!active) {
        return;
      }

      // Always persist latest hierarchy / at_desk / departments for task finds.
      await ManagerLevelService.applyFromStaffRecord(staffMap);

      final nextFingerprint = StaffService.roleFingerprint(staffMap);
      if (previousFingerprint != nextFingerprint) {
        debugPrint(
            '👤 Staff hierarchy/desk role changed — refreshing task lists');
      }

      // 2. Customer getall — hotel_enabled OR empty data (same block modal)
      final memberId = (staffMap['member_id'] ??
              staffMap['staff_member_id'] ??
              user?['member_id'] ??
              user?['staff_member_id'] ??
              '')
          .toString()
          .trim();
      final hotelOk = await checkCustomerHotelAccess(memberId);
      if (!hotelOk) return;

      // 3. Task getall — refresh task list signal
      await TaskRefreshService.poll();
    } catch (e) {
      debugPrint('⚠️ Session monitor refresh failed: $e');
    } finally {
      _refreshInFlight = false;
    }
  }

  static Future<void> _forceLogout(String message) async {
    stopPolling();
    hotelEnabled.value = true;
    staffActive.value = true;
    blockedAtLogin.value = false;
    blockedInactiveAtLogin.value = false;
    await LocalStorageService.logout();
    onForcedLogout?.call(message);
  }
}
