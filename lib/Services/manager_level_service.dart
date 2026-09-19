import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:guestezee_staffs_app/Services/high_priority_badge_service.dart';
import 'package:guestezee_staffs_app/Services/local_storage_service.dart';
import 'package:guestezee_staffs_app/Services/staff_service.dart';

/// Keeps manager vs staff mode in sync with the server.
///
/// On cold start / app resume, re-checks via [StaffService.resolveManagerLevel]
/// (`at_desk` first, then `higher_level_hierarchy.parentId` = logged-in hierarchy id).
/// If the user was manager but is no longer, switches to staff mode via [onDemotedToStaff].
class ManagerLevelService {
  ManagerLevelService._();

  /// Called when cached manager level was true but the server says staff now.
  static Future<void> Function()? onDemotedToStaff;

  /// Called when staff becomes upper-layer manager (no Accept; manager home).
  static Future<void> Function()? onPromotedToManager;

  /// Re-fetch staff and resolve manager level from the service.
  /// Returns true when demoted from manager → staff.
  static Future<bool> refreshFromServer() async {
    if (!LocalStorageService.isLoggedIn) return false;

    try {
      await LocalStorageService.init();
      final user = LocalStorageService.user;
      final empNo =
          (user?['staff_employee_number'] ?? user?['staff_member_id'] ?? '')
              .toString()
              .trim();
      if (empNo.isEmpty) return false;

      final staffResp = await StaffService.findStaffByEmployeeNumber(empNo);
      if (staffResp.statusCode != 200 && staffResp.statusCode != 201) {
        return false;
      }

      final staffData = jsonDecode(staffResp.body);
      if (staffData is! Map ||
          staffData['success'] != 1 ||
          staffData['result']?['data'] is! List ||
          (staffData['result']['data'] as List).isEmpty) {
        return false;
      }

      final staff =
          Map<String, dynamic>.from(staffData['result']['data'].first as Map);
      return applyFromStaffRecord(staff);
    } catch (e) {
      debugPrint('⚠️ ManagerLevelService refresh failed: $e');
      return false;
    }
  }

  /// Persist latest staff getall, resolve desk/manager, update escalation times.
  /// Returns true when demoted from manager → staff.
  static Future<bool> applyFromStaffRecord(Map<String, dynamic> staff) async {
    await LocalStorageService.mergeLoggedInUser(staff);
    StaffService.notifyRoleChanged();

    final Map<String, int> departmentEscalationTimes = {};
    for (final entry in StaffService.hierarchyEntriesFrom(staff['hierarchy'])) {
      final department = entry['department']?.toString().trim() ?? '';
      if (department.isEmpty) continue;
      final raw = entry['escalationTime'];
      final minutes = raw is int ? raw : int.tryParse(raw?.toString() ?? '');
      if (minutes != null) {
        departmentEscalationTimes[department] = minutes;
      }
    }
    if (departmentEscalationTimes.isNotEmpty) {
      await LocalStorageService.saveDepartmentEscalationTimes(
          departmentEscalationTimes);
    }

    final level = await StaffService.resolveManagerLevel(staff);
    final wasManager = LocalStorageService.isManagerLevel;
    await LocalStorageService.saveLowerStaffIds(level.lowerStaffIds);
    await LocalStorageService.saveIsManagerLevel(level.isManagerLevel);

    if (wasManager && !level.isManagerLevel) {
      debugPrint(
          '👤 Manager level revoked by service – switching to staff mode');
      await HighPriorityBadgeService.clear();
      await onDemotedToStaff?.call();
      return true;
    }

    if (!wasManager && level.isManagerLevel) {
      debugPrint('👤 Manager level granted by service – switching to manager');
      await onPromotedToManager?.call();
    }

    return false;
  }
}
