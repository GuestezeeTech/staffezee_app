import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:guestezee_staffs_app/Services/customer_service.dart';
import 'package:guestezee_staffs_app/Services/high_priority_badge_service.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalStorageService {
  static const String _authBoxName = 'authBox';
  static const String _versionKey = 'app_version';

  /// Synced to SharedPreferences so Android native FCM can skip alarm when logged out.
  static const String loggedInPrefKey = 'staff_is_logged_in';

  /// Old notification tap while logged out (open task screen after next login).
  static const String pendingNotificationTapKey =
      'pending_notification_tap_after_login';

  static const String _notificationModalResponseKey =
      'notification_modal_response';
  static const String _notificationOsDeniedAfterModalKey =
      'notification_os_denied_after_modal';

  /// Initialize Hive (safe to call multiple times)
  static Future<void> init() async {
    if (!Hive.isAdapterRegistered(0)) {
      // No adapters used; placeholder to prevent analysis warni.   ngs.
    }
    if (!Hive.isBoxOpen(_authBoxName)) {
      await Hive.initFlutter();
      await Hive.openBox(_authBoxName);
    }
    await _syncLoggedInPref(isLoggedIn);
  }

  static Future<void> _syncLoggedInPref(bool isLoggedIn) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(loggedInPrefKey, isLoggedIn);
    } catch (e) {
      debugPrint('⚠️ Failed to sync login pref: $e');
    }
  }

  static Box get _authBox => Hive.box(_authBoxName);

  /// Save the entire login response (including user map) for later use
  static Future<void> saveLoginResponse(
      Map<String, dynamic> loginResponse) async {
    await init();
    // Store top-level fields
    for (final entry in loginResponse.entries) {
      if (entry.key == 'user' && entry.value is Map) {
        // Store user map under 'user'
        await _authBox.put('user', entry.value);
      } else {
        await _authBox.put(entry.key, entry.value);
      }
    }

    // Convenience: also hoist common fields from user
    final user = loginResponse['user'];
    if (user is Map) {
      for (final entry in user.entries) {
        await _authBox.put('user_${entry.key}', entry.value);
      }
    }
  }

  static Future<void> setLoginState(bool isLoggedIn) async {
    await init();
    await _authBox.put('isLoggedIn', isLoggedIn);
    await _syncLoggedInPref(isLoggedIn);
  }

  static Future<void> setRememberMe(bool remember) async {
    await init();
    await _authBox.put('rememberMe', remember);
  }

  static Future<void> logout() async {
    await init();
    final modalResponse = getNotificationModalResponse();
    final osDenied = getNotificationOsDeniedAfterModal();
    await _syncLoggedInPref(false);
    await _authBox.clear();
    await _authBox.put('isLoggedIn', false);
    if (modalResponse != null) {
      await setNotificationModalResponse(modalResponse);
    }
    if (osDenied) {
      await setNotificationOsDeniedAfterModal(true);
    }
    HighPriorityBadgeService.reset();
  }

  static String? getNotificationModalResponse() {
    final raw =
        _authBox.get(_notificationModalResponseKey)?.toString().trim();
    if (raw == null || raw.isEmpty) return null;
    return raw;
  }

  static Future<void> setNotificationModalResponse(String value) async {
    await init();
    await _authBox.put(_notificationModalResponseKey, value.trim());
  }

  static bool getNotificationOsDeniedAfterModal() {
    return _authBox.get(_notificationOsDeniedAfterModalKey,
            defaultValue: false) ==
        true;
  }

  static Future<void> setNotificationOsDeniedAfterModal(bool value) async {
    await init();
    await _authBox.put(_notificationOsDeniedAfterModalKey, value);
  }

  static Future<void> clearNotificationPermissionPromptState() async {
    await init();
    await _authBox.delete(_notificationModalResponseKey);
    await _authBox.delete(_notificationOsDeniedAfterModalKey);
  }

  /// Persist notification tap payload (survives logout until login consumes it).
  static Future<void> savePendingNotificationTap(
      Map<String, dynamic> data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(pendingNotificationTapKey, jsonEncode(data));
      debugPrint('💾 Saved notification tap for post-login task navigation');
    } catch (e) {
      debugPrint('⚠️ Failed to save notification tap: $e');
    }
  }

  static Future<Map<String, dynamic>?> loadPendingNotificationTap() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(pendingNotificationTapKey);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (e) {
      debugPrint('⚠️ Failed to load notification tap: $e');
    }
    return null;
  }

  static Future<void> clearPendingNotificationTap() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(pendingNotificationTapKey);
    } catch (e) {
      debugPrint('⚠️ Failed to clear notification tap: $e');
    }
  }

  static Future<void> storeVersion(String version) async {
    await init();
    await _authBox.put(_versionKey, version);
  }

  // Get stored app version
  static String? getStoredVersion() {
    return _authBox.get(_versionKey);
  }

  static bool get isLoggedIn => (_authBox.get('isLoggedIn') as bool?) ?? false;
  static bool get rememberMe => (_authBox.get('rememberMe') as bool?) ?? false;

  static Map<String, dynamic>? get user {
    final data = _authBox.get('user');
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    return null;
  }

  /// Merge latest staff getall into the stored logged-in user
  /// (hierarchy, at_desk, departments, etc.).
  static Future<void> mergeLoggedInUser(Map<String, dynamic> staff) async {
    await init();
    final current = user ?? <String, dynamic>{};
    final merged = Map<String, dynamic>.from(current)..addAll(staff);
    await _authBox.put('user', merged);
    for (final entry in staff.entries) {
      await _authBox.put('user_${entry.key}', entry.value);
    }
  }

  static dynamic getValue(String key) => _authBox.get(key);

  /// Convenience getter for hotel name from login response or customer API cache.
  /// Supports top-level `hotel_name`, `user.hotel_name`, and `customer_hotel_name`.
  static String get hotelName {
    final dynamic fromCustomer = _authBox.get('customer_hotel_name');
    if (fromCustomer is String && fromCustomer.trim().isNotEmpty) {
      return fromCustomer.trim();
    }
    final dynamic topLevel = _authBox.get('hotel_name');
    if (topLevel is String && topLevel.trim().isNotEmpty) {
      return topLevel.trim();
    }
    final userMap = user;
    final dynamic fromUser =
        userMap?['hotel_name'] ?? _authBox.get('user_hotel_name');
    if (fromUser is String && fromUser.trim().isNotEmpty) {
      return fromUser.trim();
    }
    return 'Hotel';
  }

  /// Fetch hotel name from customer API using staff `member_id` and cache locally.
  static Future<String?> fetchHotelNameFromCustomerApi({
    String? memberIdOverride,
  }) async {
    await init();
    final userMap = user;
    final memberId = (memberIdOverride ??
            userMap?['member_id'] ??
            userMap?['staff_member_id'] ??
            '')
        .toString()
        .trim();
    if (memberId.isEmpty) return null;

    try {
      final response = await CustomerService.getCustomerByMemberId(memberId);
      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final hotelName = CustomerService.parseHotelName(data);
        if (hotelName != null && hotelName.isNotEmpty) {
          await _authBox.put('customer_hotel_name', hotelName);
          return hotelName;
        }
      }
    } catch (e) {
      debugPrint('Error fetching hotel name: $e');
    }
    return null;
  }

  /// Save lower staff IDs array
  static Future<void> saveLowerStaffIds(List<int> staffIds) async {
    await init();
    await _authBox.put('lower_staff_ids', staffIds);
  }

  /// Persist whether logged-in user is higher-level (manager) staff.
  static Future<void> saveIsManagerLevel(bool isManager) async {
    await init();
    await _authBox.put('is_manager_level', isManager);
  }

  static bool get isManagerLevel {
    return _authBox.get('is_manager_level', defaultValue: false) == true;
  }

  /// Persist hotel active/payment status (`user.hotel_enabled`).
  static Future<void> saveHotelEnabled(bool enabled) async {
    await init();
    await _authBox.put('hotel_enabled', enabled);
  }

  /// `hotel_enabled`: missing key => enabled (true); explicit false => disabled.
  static bool get hotelEnabled {
    final value = _authBox.get('hotel_enabled');
    if (value is bool) return value;
    return true;
  }

  /// `is_active`: missing key => active (true); explicit false => inactive.
  static bool get staffActive {
    final value = _authBox.get('staff_active');
    if (value is bool) return value;
    return true;
  }

  static Future<void> saveStaffActive(bool active) async {
    await init();
    await _authBox.put('staff_active', active);
  }

  static const String _unreadHighPriorityTaskIdsKey =
      'unread_high_priority_task_ids';

  static List<int> getUnreadHighPriorityTaskIds() {
    final data = _authBox.get(_unreadHighPriorityTaskIdsKey);
    if (data is List) {
      return data.map((e) => e is int ? e : int.parse(e.toString())).toList();
    }
    return [];
  }

  static int getUnreadHighPriorityEscalationCount() {
    return getUnreadHighPriorityTaskIds().length;
  }

  static Future<void> saveUnreadHighPriorityTaskIds(List<int> taskIds) async {
    await init();
    await _authBox.put(_unreadHighPriorityTaskIdsKey, taskIds);
  }

  /// Get lower staff IDs array
  static List<int> getLowerStaffIds() {
    final data = _authBox.get('lower_staff_ids');
    if (data is List) {
      return data.cast<int>();
    }
    return [];
  }

  /// Get the first hierarchy entry (since hierarchy is now an array)
  /// Returns null if hierarchy is not available or empty
  static Map<String, dynamic>? get primaryHierarchy {
    final userMap = user;
    if (userMap == null) return null;

    final hierarchy = userMap['hierarchy'];
    if (hierarchy is List && hierarchy.isNotEmpty) {
      final first = hierarchy[0];
      if (first is Map) {
        return Map<String, dynamic>.from(first);
      }
    }
    return null;
  }

  /// Get all hierarchy entries as a list
  static List<Map<String, dynamic>> get allHierarchies {
    final userMap = user;
    if (userMap == null) return [];

    final hierarchy = userMap['hierarchy'];
    if (hierarchy is List) {
      return hierarchy
          .whereType<Map>()
          .map((h) => Map<String, dynamic>.from(h))
          .toList();
    }
    return [];
  }

  /// Get department from primary hierarchy
  static String get department {
    final primary = primaryHierarchy;
    if (primary != null && primary['department'] is String) {
      return primary['department'];
    }
    return '';
  }

  /// Get all departments as comma-separated string (for multi-department staff)
  static String get allDepartments {
    final hierarchies = allHierarchies;
    if (hierarchies.isEmpty) return '';

    final departments = hierarchies
        .map((h) => h['department']?.toString() ?? '')
        .where((dept) => dept.isNotEmpty)
        .toSet() // Remove duplicates
        .toList();

    return departments.join(', ');
  }

  /// Get a human-readable list of "designation (department)" strings
  /// for all hierarchy entries, e.g.:
  /// [ {designation: "F&B Staff 1", department: "F&B"}, ... ]
  /// -> "F&B Staff 1 (F&B), EHK Staff 1 (EHK)"
  static List<String> get hierarchyDesignationDepartmentLabels {
    final hierarchies = allHierarchies;
    if (hierarchies.isEmpty) return [];

    return hierarchies
        .map((h) {
          final designation = h['designation']?.toString() ?? '';
          final department = h['department']?.toString() ?? '';

          if (designation.isNotEmpty && department.isNotEmpty) {
            return '$designation ($department)';
          } else if (designation.isNotEmpty) {
            return designation;
          } else if (department.isNotEmpty) {
            return department;
          }
          return '';
        })
        .where((label) => label.isNotEmpty)
        .toList();
  }

  /// Same as [hierarchyDesignationDepartmentLabels] but as a single
  /// comma-separated string for easy use in app bars.
  static String get hierarchyDesignationDepartmentDisplay {
    final labels = hierarchyDesignationDepartmentLabels;
    if (labels.isEmpty) return '';
    return labels.join(', ');
  }

  /// Get designation from primary hierarchy
  static String get designation {
    final primary = primaryHierarchy;
    if (primary != null && primary['designation'] is String) {
      return primary['designation'];
    }
    return '';
  }

  /// Get escalation time from primary hierarchy
  static int? get escalationTime {
    final primary = primaryHierarchy;
    if (primary != null) {
      final time = primary['escalationTime'];
      if (time is int) return time;
      if (time is String) return int.tryParse(time);
    }
    return null;
  }

  /// Get hierarchy ID from primary hierarchy
  static dynamic get hierarchyId {
    final primary = primaryHierarchy;
    return primary?['id'];
  }

  /// Get escalation times mapped by department
  /// Returns a Map<String, int> where key is department and value is escalation time in minutes
  static Map<String, int> get departmentEscalationTimes {
    final hierarchies = allHierarchies;
    if (hierarchies.isEmpty) return {};

    final Map<String, int> escalationMap = {};
    for (final hierarchy in hierarchies) {
      final String? department = hierarchy['department']?.toString();
      final dynamic escalationTime = hierarchy['escalationTime'];

      if (department != null && department.isNotEmpty) {
        int? timeInMinutes;
        if (escalationTime is int) {
          timeInMinutes = escalationTime;
        } else if (escalationTime != null) {
          timeInMinutes = int.tryParse(escalationTime.toString());
        }

        if (timeInMinutes != null) {
          escalationMap[department] = timeInMinutes;
        }
      }
    }

    return escalationMap;
  }

  /// Get escalation time for a specific department
  /// Returns null if department not found or no escalation time configured
  static int? getEscalationTimeForDepartment(String? department) {
    if (department == null || department.isEmpty) return null;
    return departmentEscalationTimes[department];
  }

  /// Save department escalation times to local storage
  static Future<void> saveDepartmentEscalationTimes(
      Map<String, int> escalationTimes) async {
    await init();
    await _authBox.put('department_escalation_times', escalationTimes);
  }

  /// Get saved department escalation times from local storage
  static Map<String, int> getSavedDepartmentEscalationTimes() {
    final data = _authBox.get('department_escalation_times');
    if (data is Map) {
      return Map<String, int>.from(data);
    }
    return {};
  }
}
