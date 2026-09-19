import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:guestezee_staffs_app/Config/api_end_points.dart';
import 'package:guestezee_staffs_app/Config/primary_config.dart';
import 'package:guestezee_staffs_app/Services/local_storage_service.dart';

class StaffService {
  static dynamic _normalizeFindFilterValue(dynamic value) {
    if (value is List && value.length == 1) {
      return value.first;
    }
    return value;
  }

  static Map<String, dynamic> _buildStaffFind(dynamic staffIdentifier) {
    if (staffIdentifier == null) return {};

    if (staffIdentifier is int) {
      return {"id": staffIdentifier};
    }

    final String identifierString = staffIdentifier.toString().trim();
    if (identifierString.isEmpty) return {};

    final int? parsedId = int.tryParse(identifierString);
    if (parsedId != null) {
      return {"id": parsedId};
    }

    // Fallback to legacy staff_employee_number if identifier isn't numeric
    return {"staff_employee_number": identifierString};
  }

  /// Get all staff members
  static Future<http.Response> getAllStaff() async {
    return await http.post(
      Uri.parse("${PrimaryConfigData.domainName}:${ApiEndPoints.getallStaff}"),
      body: jsonEncode({
        "domain_name": PrimaryConfigData.domainName,
        "user_id": PrimaryConfigData.userId,
        "extras": {"find": {}}
      }),
      headers: {
        'Content-Type': 'application/json; charset=UTF-8',
      },
    );
  }

  /// Find staff by employee number
  static Future<http.Response> findStaffByEmployeeNumber(
      String employeeNumber) async {
    return await http.post(
      Uri.parse("${PrimaryConfigData.domainName}:${ApiEndPoints.getallStaff}"),
      body: jsonEncode({
        "domain_name": PrimaryConfigData.domainName,
        "user_id": PrimaryConfigData.userId,
        "extras": {
          "find": {"staff_employee_number": employeeNumber}
        }
      }),
      headers: {
        'Content-Type': 'application/json; charset=UTF-8',
      },
    );
  }

  /// Update staff pin
  static Future<http.Response> updateStaffPin(
      String employeeNumber, String pin) async {
    return await http.post(
      Uri.parse("${PrimaryConfigData.domainName}:${ApiEndPoints.updateStaff}"),
      body: jsonEncode({
        "domain_name": PrimaryConfigData.domainName,
        "user_id": PrimaryConfigData.userId,
        "extras": {
          "find": {"staff_employee_number": employeeNumber}
        },
        "payload": {
          "staff_updation": {"pin": pin}
        }
      }),
      headers: {
        'Content-Type': 'application/json; charset=UTF-8',
      },
    );
  }

  /// Send OTP to staff email and mobile.
  static Future<http.Response> sendOtp({
    required String recipientEmail,
    required int recipientMobile,
  }) async {
    return await http.post(
      Uri.parse("${PrimaryConfigData.domainName}:${ApiEndPoints.otpSend}"),
      body: jsonEncode({
        "domain_name": PrimaryConfigData.domainName,
        "user_id": PrimaryConfigData.userId,
        "recipient_email": recipientEmail,
        "recipient_mobile": recipientMobile,
        "event": "OTP",
      }),
      headers: {
        'Content-Type': 'application/json; charset=UTF-8',
      },
    );
  }

  /// Verify OTP using the [referenceId] returned from [sendOtp].
  static Future<http.Response> verifyOtp({
    required String referenceId,
    required String otpCode,
  }) async {
    return await http.post(
      Uri.parse("${PrimaryConfigData.domainName}:${ApiEndPoints.otpVerify}"),
      body: jsonEncode({
        "domain_name": PrimaryConfigData.domainName,
        "user_id": PrimaryConfigData.userId,
        "reference_id": referenceId,
        "otp_code": otpCode,
      }),
      headers: {
        'Content-Type': 'application/json; charset=UTF-8',
      },
    );
  }

  /// Login staff using employee id and pin (password)
  static Future<http.Response> loginStaff(
      {required String employeeId, required String pin}) async {
    final String username = "$employeeId-${PrimaryConfigData.domainName}";
    return await http.post(
      Uri.parse("${PrimaryConfigData.domainName}:${ApiEndPoints.loginStaff}"),
      body: jsonEncode({
        "domain_name": PrimaryConfigData.domainName,
        "username": username,
        "password": pin,
      }),
      headers: {
        'Content-Type': 'application/json; charset=UTF-8',
      },
    );
  }

  /// Update staff availability
  static Future<http.Response> updateStaffAvailability(
      dynamic staffIdentifier, bool isAvailable) async {
    return await http.post(
      Uri.parse("${PrimaryConfigData.domainName}:${ApiEndPoints.updateStaff}"),
      body: jsonEncode({
        "domain_name": PrimaryConfigData.domainName,
        "user_id": PrimaryConfigData.userId,
        "extras": {"find": _buildStaffFind(staffIdentifier)},
        "payload": {
          "staff_updation": {"is_available": isAvailable}
        }
      }),
      headers: {
        'Content-Type': 'application/json; charset=UTF-8',
      },
    );
  }

  /// Update staff availability and FCM token
  static Future<http.Response> updateStaffAvailabilityWithFcmToken(
      dynamic staffIdentifier, bool isAvailable, List<String> fcmTokens) async {
    return await http.post(
      Uri.parse("${PrimaryConfigData.domainName}:${ApiEndPoints.updateStaff}"),
      body: jsonEncode({
        "domain_name": PrimaryConfigData.domainName,
        "user_id": PrimaryConfigData.userId,
        "extras": {"find": _buildStaffFind(staffIdentifier)},
        "payload": {
          "staff_updation": {
            "is_available": isAvailable,
            "fcm_token": fcmTokens
          }
        }
      }),
      headers: {
        'Content-Type': 'application/json; charset=UTF-8',
      },
    );
  }

  /// Update ONLY the staff FCM token list, without changing is_available.
  /// Used on logout when other devices are still logged in (fcm list not empty),
  /// so we remove this device's token but keep availability untouched.
  static Future<http.Response> updateStaffFcmToken(
      dynamic staffIdentifier, List<String> fcmTokens) async {
    return await http.post(
      Uri.parse("${PrimaryConfigData.domainName}:${ApiEndPoints.updateStaff}"),
      body: jsonEncode({
        "domain_name": PrimaryConfigData.domainName,
        "user_id": PrimaryConfigData.userId,
        "extras": {"find": _buildStaffFind(staffIdentifier)},
        "payload": {
          "staff_updation": {"fcm_token": fcmTokens}
        }
      }),
      headers: {
        'Content-Type': 'application/json; charset=UTF-8',
      },
    );
  }

  /// Time-of-day greeting used as the push title (shown on the device).
  /// Morning / afternoon / evening; night also uses "Good evening" (good eve).
  static String timeGreeting() {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 12) return 'Good morning';
    if (hour >= 12 && hour < 17) return 'Good afternoon';
    if (hour >= 17 && hour < 21) return 'Good evening';
    return 'Good evening'; // night → good eve
  }

  /// Low-level: hit the OrderNotification endpoint for a single [token].
  ///
  /// Returns true when FCM accepts the message (response contains a message
  /// `name`), false when the token is unregistered / not found / unreachable.
  /// The payload carries `{"testing":true}` so receiving devices suppress it
  /// (no sound/alarm); [title] is only the display text.
  static Future<bool> _sendPush(
    String token, {
    required String message,
    required String title,
  }) async {
    if (token.trim().isEmpty) return false;
    try {
      final uri = Uri.parse(
              "${PrimaryConfigData.domainName}:${ApiEndPoints.orderNotification}")
          .replace(queryParameters: {
        "message": message,
        "token": token,
        "title": title,
      });

      final resp = await http.post(uri).timeout(const Duration(seconds: 15));
      final body = resp.body;

      try {
        final decoded = jsonDecode(body);
        if (decoded is Map) {
          if (decoded["name"] != null) return true; // FCM accepted → alive
          if (decoded["error"] != null) return false; // e.g. UNREGISTERED
        }
      } catch (_) {
        // Non-JSON body – fall back to string checks below.
      }

      if (body.contains("UNREGISTERED") || body.contains("NOT_FOUND")) {
        return false;
      }
      if (body.contains('"name"')) return true;

      // Unknown / non-success response → treat as not reachable.
      return false;
    } catch (e) {
      // Network/other error → could not confirm delivery, treat as not reachable.
      return false;
    }
  }

  /// Send a silent validation push to [token] (used on logout to test whether
  /// the device is still reachable). Returns true if reachable.
  static Future<bool> sendTestNotification(String token) =>
      _sendPush(token, message: '{"testing":true}', title: timeGreeting());

  /// Send a silent presence push to [token] with a custom [title] (used on
  /// login to announce a staff login to their other devices). Still carries the
  /// `testing` marker so it never rings an alarm on the receiving device.
  static Future<bool> sendPresencePush(String token, {required String title}) =>
      _sendPush(token, message: '{"testing":true}', title: title);

  /// Sends the test push to EVERY token in a single pass (does NOT stop on the
  /// first success) and classifies them into [valid] (reachable) and [invalid]
  /// (unregistered / unreachable). Used on logout so we can prune dead tokens
  /// from the staff record and avoid re-checking them on future logouts.
  static Future<({List<String> valid, List<String> invalid})> classifyTokens(
      List<String> tokens) async {
    final valid = <String>[];
    final invalid = <String>[];
    for (final token in tokens) {
      if (token.trim().isEmpty) continue;
      if (await sendTestNotification(token)) {
        valid.add(token);
      } else {
        invalid.add(token);
      }
    }
    return (valid: valid, invalid: invalid);
  }

  /// Update staff profile image
  static Future<http.Response> updateStaffProfileImage(
      dynamic staffIdentifier, String profileImage) async {
    return await http.post(
      Uri.parse("${PrimaryConfigData.domainName}:${ApiEndPoints.updateStaff}"),
      body: jsonEncode({
        "domain_name": PrimaryConfigData.domainName,
        "user_id": PrimaryConfigData.userId,
        "extras": {"find": _buildStaffFind(staffIdentifier)},
        "payload": {
          "staff_updation": {"profile_image": profileImage}
        }
      }),
      headers: {
        'Content-Type': 'application/json; charset=UTF-8',
      },
    );
  }

  /// Get staff details by ID
  static Future<http.Response> getStaffById(String staffId) async {
    return await http.post(
      Uri.parse("${PrimaryConfigData.domainName}:${ApiEndPoints.getallStaff}"),
      body: jsonEncode({
        "domain_name": PrimaryConfigData.domainName,
        "user_id": PrimaryConfigData.userId,
        "extras": {
          "find": {"id": staffId}
        }
      }),
      headers: {
        'Content-Type': 'application/json; charset=UTF-8',
      },
    );
  }

  /// Staff getall: find staff whose higher_level_hierarchy.parentId matches
  /// the logged-in staff hierarchy [id].
  static Future<http.Response> findStaffByHigherLevelParentId({
    required String memberId,
    required int hierarchyId,
  }) async {
    return await http.post(
      Uri.parse("${PrimaryConfigData.domainName}:${ApiEndPoints.getallStaff}"),
      body: jsonEncode({
        "domain_name": PrimaryConfigData.domainName,
        "user_id": PrimaryConfigData.userId,
        "extras": {
          "find": {
            "member_id": memberId,
            "higher_level_hierarchy.parentId": hierarchyId,
          }
        }
      }),
      headers: {
        'Content-Type': 'application/json; charset=UTF-8',
      },
    );
  }

  static int _resultCount(Map<String, dynamic> data) {
    final result = data['result'];
    if (result is! Map) return 0;

    final totalCount = result['total_count'];
    if (totalCount is int) return totalCount;
    if (totalCount != null) {
      final parsed = int.tryParse(totalCount.toString());
      if (parsed != null) return parsed;
    }

    final count = result['count'];
    if (count is int) return count;
    if (count != null) {
      final parsed = int.tryParse(count.toString());
      if (parsed != null) return parsed;
    }

    final List<dynamic> staffList = result['data'] ?? [];
    return staffList.length;
  }

  static List<Map<String, dynamic>> hierarchyEntriesFrom(
      dynamic staffHierarchy) {
    if (staffHierarchy is List) {
      return staffHierarchy
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    if (staffHierarchy is Map) {
      return [Map<String, dynamic>.from(staffHierarchy)];
    }
    return [];
  }

  static int? _staffRecordId(dynamic staff) {
    if (staff is! Map) return null;
    final id = staff['id'];
    if (id is int) return id;
    return int.tryParse(id?.toString() ?? '');
  }

  static int? _parseInt(dynamic value) {
    if (value is int) return value;
    if (value == null) return null;
    return int.tryParse(value.toString());
  }

  /// Staff available for desk ASAP task allocation.
  /// Find uses [task_allocation_purpose: true] so the API returns allocatable staff.
  static Future<http.Response> findStaffForTaskAllocation({
    required String memberId,
    required int deskStaffId,
    required String department,
  }) async {
    return await http.post(
      Uri.parse("${PrimaryConfigData.domainName}:${ApiEndPoints.getallStaff}"),
      body: jsonEncode({
        "domain_name": PrimaryConfigData.domainName,
        "user_id": PrimaryConfigData.userId,
        "extras": {
          "find": {
            "is_available": true,
            "at_desk": false,
            "higher_level_officer.id": deskStaffId,
            "member_id": memberId,
            "task_allocation_purpose": true,
            "hierarchy.department": department,
          }
        }
      }),
      headers: {
        'Content-Type': 'application/json; charset=UTF-8',
      },
    );
  }

  /// Bumped when staff getall updates `at_desk` / hierarchy so desk UI rebuilds.
  static final ValueNotifier<int> roleRevision = ValueNotifier<int>(0);

  static void notifyRoleChanged() {
    roleRevision.value++;
  }

  /// Floor staff only. Desk and manager/upper-layer do not accept tasks.
  static bool canAcceptAssignedTasks(Map<String, dynamic>? user) {
    if (isAtDeskStaff(user)) return false;
    if (LocalStorageService.isManagerLevel) return false;
    return true;
  }

  /// Fingerprint of desk flag + hierarchy ids/departments for change detection.
  static String roleFingerprint(Map<String, dynamic>? user) {
    if (user == null) return '';
    final entries = hierarchyEntriesFrom(user['hierarchy']);
    final parts = entries
        .map((e) =>
            '${e['id']}|${(e['department'] ?? '').toString().trim()}')
        .join(',');
    return '${isAtDeskStaff(user)}|$parts';
  }

  /// `at_desk: true` → desk staff (skip hierarchy manager check).
  static bool isAtDeskStaff(Map<String, dynamic>? user) {
    if (user == null) return false;
    if (!user.containsKey('at_desk')) return false;
    final value = user['at_desk'];
    if (value == null) return false;
    if (value is bool) return value;
    final text = value.toString().trim().toLowerCase();
    if (text == 'true' || text == '1' || text == 'yes') return true;
    return false;
  }

  /// Staff vs manager:
  /// 1. If logged-in [at_desk] is true → staff (no hierarchy check).
  /// 2. Else find `{ member_id, "higher_level_hierarchy.parentId": hierarchy.id }`
  ///    — any match → manager; empty → staff.
  static Future<({bool isManagerLevel, List<int> lowerStaffIds})>
      resolveManagerLevel(Map<String, dynamic> user) async {
    // Desk staff are always normal staff — skip hierarchy lookup.
    if (isAtDeskStaff(user)) {
      return (isManagerLevel: false, lowerStaffIds: <int>[]);
    }

    final memberId =
        (user['member_id'] ?? user['staff_member_id'])?.toString().trim() ?? '';
    if (memberId.isEmpty) {
      return (isManagerLevel: false, lowerStaffIds: <int>[]);
    }

    final entries = hierarchyEntriesFrom(user['hierarchy']);
    if (entries.isEmpty) {
      return (isManagerLevel: false, lowerStaffIds: <int>[]);
    }

    final int? selfId = _staffRecordId(user);
    final Set<int> lowerStaffIds = {};
    bool foundAny = false;

    for (final entry in entries) {
      final hierarchyId = _parseInt(entry['id']);
      if (hierarchyId == null) continue;

      try {
        final response = await findStaffByHigherLevelParentId(
          memberId: memberId,
          hierarchyId: hierarchyId,
        );

        if (response.statusCode != 200 && response.statusCode != 201) {
          continue;
        }

        final data = jsonDecode(response.body);
        if (data is! Map || data['success'] != 1 || data['result'] == null) {
          continue;
        }

        final List<dynamic> staffList = data['result']['data'] ?? [];
        if (staffList.isEmpty &&
            _resultCount(Map<String, dynamic>.from(data)) == 0) {
          continue;
        }

        foundAny = true;
        for (final staff in staffList) {
          final staffId = _staffRecordId(staff);
          if (staffId == null) continue;
          if (selfId != null && staffId == selfId) continue;
          lowerStaffIds.add(staffId);
        }
      } catch (_) {
        continue;
      }
    }

    return (
      isManagerLevel: foundAny,
      lowerStaffIds: lowerStaffIds.toList(),
    );
  }

  /// @deprecated Prefer [resolveManagerLevel].
  static Future<http.Response> getLowerStaff(
    String memberId,
    List<int> hierarchyIds,
    List<String> departments,
  ) async {
    return await http.post(
      Uri.parse(
          "${PrimaryConfigData.domainName}:${ApiEndPoints.getlowerStaff}"),
      body: jsonEncode({
        "domain_name": PrimaryConfigData.domainName,
        "user_id": PrimaryConfigData.userId,
        "extras": {
          "find": {
            "member_id": memberId,
            "hierarchy.parentId": _normalizeFindFilterValue(hierarchyIds),
            "hierarchy.department": _normalizeFindFilterValue(departments)
          }
        }
      }),
      headers: {
        'Content-Type': 'application/json; charset=UTF-8',
      },
    );
  }
}
