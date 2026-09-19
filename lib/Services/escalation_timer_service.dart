import 'package:guestezee_staffs_app/Services/local_storage_service.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Service to handle escalation time calculations for tasks
class EscalationTimerService {
  /// Get the staff's escalation time from local storage (in minutes)
  /// DEPRECATED: Use getEscalationTimeForTask() for department-specific times
  static int? getStaffEscalationTime() {
    try {
      final user = LocalStorageService.user;
      if (user == null) return null;

      final hierarchy = user['hierarchy'];
      if (hierarchy is Map) {
        final escalationTime = hierarchy['escalationTime'];
        if (escalationTime is int) {
          return escalationTime;
        } else if (escalationTime != null) {
          return int.tryParse(escalationTime.toString());
        }
      }
      return null;
    } catch (e) {
      print('Error getting staff escalation time: $e');
      return null;
    }
  }

  /// Get escalation time for a specific task based on its department/category
  /// Returns the escalation time in minutes, or null if not found
  static int? getEscalationTimeForTask(Map<String, dynamic> task) {
    try {
      // Extract department from task's service category
      final String? taskDepartment = task['service']?['category']?.toString();

      if (taskDepartment == null || taskDepartment.isEmpty) {
        print('⚠️ Task ${task['id']} has no service category, using fallback');
        return getStaffEscalationTime(); // Fallback to legacy method
      }

      // Get department-specific escalation time from local storage
      final int? escalationTime =
          LocalStorageService.getEscalationTimeForDepartment(taskDepartment);

      if (escalationTime != null) {
        print(
            '✅ Found escalation time for $taskDepartment: $escalationTime minutes');
        return escalationTime;
      } else {
        print(
            '⚠️ No escalation time found for department: $taskDepartment, using fallback');
        return getStaffEscalationTime(); // Fallback to legacy method
      }
    } catch (e) {
      print('❌ Error getting escalation time for task: $e');
      return getStaffEscalationTime(); // Fallback to legacy method
    }
  }

  /// Get escalation time directly from the task's time_bound_value
  /// Returns the escalation time in minutes, or null if not found
  static int? getEscalationTimeFromTask(Map<String, dynamic> task) {
    try {
      final service = task['service'];
      if (service != null && service['time_bound_value'] != null) {
        final value = service['time_bound_value'];
        if (value is int) {
          return value;
        } else {
          return int.tryParse(value.toString());
        }
      }
      return null;
    } catch (e) {
      print('❌ Error getting escalation time from task field: $e');
      return null;
    }
  }

  /// Calculate the remaining escalation time for a task
  ///
  /// Returns null if calculation fails or if task is not assigned yet
  /// Returns Duration with remaining time (can be negative if already escalated)
  static Duration? calculateRemainingEscalationTime(Map<String, dynamic> task) {
    try {
      final String status = task['status']?.toString().toUpperCase() ?? '';
      int? escalationMinutes;
      DateTime? startTime;

      if (status == 'PROCESSING') {
        // For Processing status, use service time_bound_value (as requested)
        escalationMinutes = getEscalationTimeFromTask(task);

        // Fallback to department-specific time if task doesn't have it
        if (escalationMinutes == null) {
          escalationMinutes = getEscalationTimeForTask(task);
        }

        // START TIME: For Processing, use the 'Processing' timeline entry
        startTime = _getTaskStatusTime(task, 'Processing');
        
        // Fallback to assignment time if 'Processing' timestamp isn't in timeline yet
        startTime ??= _getTaskAssignmentTime(task);
      } else {
        // For Assigned (accepting the task) or other statuses, use department time (as requested)
        escalationMinutes = getEscalationTimeForTask(task);
        
        // START TIME: For non-processing statuses, use 'Assigned' time
        startTime = _getTaskAssignmentTime(task);
      }

      if (escalationMinutes == null) {
        print('⚠️ Escalation time not found for task ${task['id']}');
        return null;
      }

      if (startTime == null) {
        print('⚠️ Start time not found for task ${task['id']} (status: $status)');
        return null;
      }

      // Calculate elapsed time since the relevant start point
      final DateTime now = DateTime.now();
      final Duration elapsed = now.difference(startTime);

      // Calculate remaining time
      final Duration totalEscalationTime = Duration(minutes: escalationMinutes);
      final Duration remaining = totalEscalationTime - elapsed;

      final String? dept = task['service']?['category']?.toString();
      print(
          '⏱️ Task ${task['id']} ($dept): Escalation in $escalationMinutes min, Start: $startTime, Elapsed: ${elapsed.inMinutes} min, Remaining: ${remaining.inMinutes} min');

      return remaining;
    } catch (e) {
      print('❌ Error calculating escalation time: $e');
      return null;
    }
  }

  /// Get a specific status time from the task's timeline
  /// Returns null if not found or invalid
  static DateTime? _getTaskStatusTime(Map<String, dynamic> task, String targetStatus) {
    try {
      final dynamic timelineData = task['time_line'];
      if (timelineData is! List) return null;
      final List<dynamic> timeline = timelineData;
      if (timeline.isEmpty) return null;

      // Find the MOST RECENT entry matching the target status
      DateTime? lastStatusTime;

      for (final entry in timeline) {
        if (entry is! Map) continue;
        final String status = entry['status']?.toString() ?? '';
        if (status.toUpperCase() == targetStatus.toUpperCase()) {
          final String? dateStr = entry['date']?.toString();
          final String? timeStr = entry['time']?.toString();

          if (dateStr != null && timeStr != null) {
            final DateTime? statusTime = _parseDateTime(dateStr, timeStr);
            if (statusTime != null) {
              if (lastStatusTime == null || statusTime.isAfter(lastStatusTime)) {
                lastStatusTime = statusTime;
              }
            }
          }
        }
      }
      return lastStatusTime;
    } catch (e) {
      print('Error getting status time for $targetStatus: $e');
      return null;
    }
  }

  /// Get the assignment time from task's timeline
  /// Returns null if not found or invalid
  /// Handles multiple assignments by finding the most recent one
  static DateTime? _getTaskAssignmentTime(Map<String, dynamic> task) {
    return _getTaskStatusTime(task, 'Assigned');
  }

  /// Parse date and time strings to DateTime
  /// Expected formats: date: "2025-10-09", time: "19:05:57"
  static DateTime? _parseDateTime(String dateStr, String timeStr) {
    try {
      // Combine date and time strings
      final String dateTimeStr = '$dateStr $timeStr';

      // Try parsing ISO format first
      try {
        return DateTime.parse(dateTimeStr);
      } catch (_) {}

      // Try manual parsing: "2025-10-09 19:05:57"
      final List<String> dateParts = dateStr.split('-');
      final List<String> timeParts = timeStr.split(':');

      if (dateParts.length == 3 && timeParts.length >= 2) {
        final int year = int.parse(dateParts[0]);
        final int month = int.parse(dateParts[1]);
        final int day = int.parse(dateParts[2]);
        final int hour = int.parse(timeParts[0]);
        final int minute = int.parse(timeParts[1]);
        final int second = timeParts.length >= 3 ? int.parse(timeParts[2]) : 0;

        return DateTime(year, month, day, hour, minute, second);
      }

      return null;
    } catch (e) {
      print('Error parsing datetime: $e');
      return null;
    }
  }

  /// Check if a task has been escalated based on remaining time
  static bool isTaskEscalated(Map<String, dynamic> task) {
    // First check if the API itself says it's escalated
    final String currentStatus = task['status']?.toString() ?? '';
    if (currentStatus == 'Escalated') {
      return true;
    }

    // Check timeline for escalation status
    final List<dynamic>? timeline = task['time_line'] as List<dynamic>?;
    if (timeline != null && timeline.isNotEmpty) {
      final String lastStatus = timeline.last['status']?.toString() ?? '';
      if (lastStatus == 'Escalated') {
        return true;
      }
    }

    // Check if remaining time is negative (past escalation time)
    final Duration? remaining = calculateRemainingEscalationTime(task);
    if (remaining != null && remaining.isNegative) {
      return true;
    }

    return false;
  }

  /// Format duration as minutes / hrs (e.g. "45 min", "1 hr 20 min").
  static String formatDuration(Duration duration) {
    if (duration.isNegative || duration.inSeconds <= 0) {
      return '0 min';
    }

    // Round up partial minutes so 1–59s still shows as 1 min (not 0 min)
    final int totalMinutes = (duration.inSeconds + 59) ~/ 60;
    final int hours = totalMinutes ~/ 60;
    final int minutes = totalMinutes % 60;

    if (hours > 0 && minutes > 0) {
      final hrLabel = hours == 1 ? 'hr' : 'hrs';
      return '$hours $hrLabel $minutes min';
    }
    if (hours > 0) {
      return hours == 1 ? '1 hr' : '$hours hrs';
    }
    return minutes == 1 ? '1 min' : '$minutes min';
  }

  /// Initialize escalation timers for a list of tasks
  /// Returns a list of Durations for each task
  /// Each task gets its department-specific escalation time
  static List<Duration> initializeTaskTimers(List<Map<String, dynamic>> tasks) {
    return tasks.map((task) {
      final String status = task['status']?.toString().toUpperCase() ?? '';
      // Already escalated → no countdown (avoids restarting the 1‑min default)
      if (status == 'ESCALATED') {
        return Duration.zero;
      }

      final Duration? calculated = calculateRemainingEscalationTime(task);
      if (calculated == null) {
        // Fallback: Try to get task-specific escalation time
        final int? taskEscalationMinutes = getEscalationTimeForTask(task);
        if (taskEscalationMinutes != null && taskEscalationMinutes > 0) {
          return Duration(minutes: taskEscalationMinutes);
        }

        // No data → default 1 minute
        return const Duration(minutes: 1);
      }

      // Expired / over limit → stop at zero (do not keep counting or reset)
      if (calculated.isNegative || calculated.inSeconds <= 0) {
        return Duration.zero;
      }

      return calculated;
    }).toList();
  }

  /// Save escalation time to local storage (called during login)
  static Future<void> saveStaffEscalationTime(int escalationTimeMinutes) async {
    try {
      await LocalStorageService.init();
      await Hive.box('authBox')
          .put('staff_escalation_time', escalationTimeMinutes);
    } catch (e) {
      print('Error saving staff escalation time: $e');
    }
  }

  /// Get saved escalation time from local storage (fallback method)
  static int? getSavedEscalationTime() {
    try {
      final value = Hive.box('authBox').get('staff_escalation_time');
      if (value is int) {
        return value;
      } else if (value != null) {
        return int.tryParse(value.toString());
      }
      return null;
    } catch (e) {
      print('Error getting saved escalation time: $e');
      return null;
    }
  }
}
