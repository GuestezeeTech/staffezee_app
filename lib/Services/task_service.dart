import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:guestezee_staffs_app/Config/api_end_points.dart';
import 'package:guestezee_staffs_app/Config/primary_config.dart';
import 'package:guestezee_staffs_app/Services/local_storage_service.dart';

class TaskService {
  static int? _toInt(dynamic value) {
    if (value is int) return value;
    if (value == null) return null;
    return int.tryParse(value.toString());
  }

  /// Get all tasks with filters
  static Future<http.Response> getAllTasks({
    String? status,
    List<String>? roomNo,
    String? memberId,
    List<int>? assignedStaffId,
    bool pagination = false,
    bool sorting = true,
    Map<String, int>? sortingDetails,
  }) async {
    Map<String, dynamic> findCriteria = {};

    if (status != null) findCriteria['status'] = status;
    if (roomNo != null) findCriteria['room_no'] = roomNo;
    if (memberId != null) findCriteria['member_id'] = memberId;
    if (assignedStaffId != null) {
      findCriteria['assigned_staff_id'] = assignedStaffId;
    }

    Map<String, dynamic> requestBody = {
      "domain_name": PrimaryConfigData.domainName,
      "user_id": PrimaryConfigData.userId,
      "extras": {
        "find": findCriteria,
        "pagination": pagination,
        "sorting": sorting,
        if (sortingDetails != null) "sortingDetails": sortingDetails,
      }
    };

    return await http.post(
      Uri.parse("${PrimaryConfigData.domainName}:${ApiEndPoints.getallTasks}"),
      body: jsonEncode(requestBody),
      headers: <String, String>{
        'Content-Type': 'application/json; charset=UTF-8',
      },
    );
  }

  /// Update a task's status by id
  static Future<http.Response> updateTaskStatus({
    required int taskId,
    required String status,
    required Map<String, dynamic> service,
    int? assignedStaffId,
    String? assignedStaffName,
    DateTime? dateTime,
    int? guestId,
    dynamic staffDeskId,
    String? department,
  }) async {
    final Map<String, dynamic> updateTask = {"status": status};

    if (assignedStaffId != null) {
      updateTask["assigned_staff_id"] = assignedStaffId;
    }

    if (assignedStaffName != null) {
      updateTask["assigned_staff_name"] = assignedStaffName;
    }

    if (dateTime != null) {
      updateTask["delivered_time"] = dateTime.toIso8601String();
    }

    if (guestId != null) {
      updateTask["guest_id"] = guestId;
    }

    final int? parsedStaffDeskId = _toInt(staffDeskId);
    if (parsedStaffDeskId != null) {
      updateTask["staff_desk_id"] = parsedStaffDeskId;
    }

    if (department != null && department.isNotEmpty) {
      updateTask["department"] = department;
    }

    // ADD SERVICE MAP
    if (service.isNotEmpty) {
      updateTask["service"] = service;
    }

    final Map<String, dynamic> body = {
      "domain_name": PrimaryConfigData.domainName,
      "user_id": PrimaryConfigData.userId,
      "payload": {"update_task": updateTask},
      "extras": {
        "find": {"id": taskId}
      }
    };

    return await http.post(
      Uri.parse("${PrimaryConfigData.domainName}:${ApiEndPoints.updateTasks}"),
      body: jsonEncode(body),
      headers: const {
        'Content-Type': 'application/json; charset=UTF-8',
      },
    );
  }

  static Future<http.Response> updateCompletedTaskStatus({
    required int taskId,
    required String status,
    int? assignedStaffId,
    String? assignedStaffName,
    int? guestId,
    dynamic staffDeskId,
    String? department,
  }) async {
    final Map<String, dynamic> updateTask = {"status": status};

    // Add assigned staff details if provided
    if (assignedStaffId != null) {
      updateTask["assigned_staff_id"] = assignedStaffId;
    }
    if (assignedStaffName != null) {
      updateTask["assigned_staff_name"] = assignedStaffName;
    }
    updateTask["completed_time"] = DateTime.now().toIso8601String();

    // Add guest_id and staff_desk_id if provided
    if (guestId != null) {
      updateTask["guest_id"] = guestId;
    }
    final int? parsedStaffDeskId = _toInt(staffDeskId);
    if (parsedStaffDeskId != null) {
      updateTask["staff_desk_id"] = parsedStaffDeskId;
    }
    if (department != null && department.isNotEmpty) {
      updateTask["department"] = department;
    }

    final Map<String, dynamic> body = {
      "domain_name": PrimaryConfigData.domainName,
      "user_id": PrimaryConfigData.userId,
      "payload": {"update_task": updateTask},
      "extras": {
        "find": {"id": taskId}
      }
    };

    return await http.post(
      Uri.parse("${PrimaryConfigData.domainName}:${ApiEndPoints.updateTasks}"),
      body: jsonEncode(body),
      headers: const {
        'Content-Type': 'application/json; charset=UTF-8',
      },
    );
  }

  static Future<http.Response> updateTaskCompletionTime({
    required int taskId,
    required Map<String, dynamic> task,
    required int completionTimeInMinutes,
  }) async {
    final rawService = task['service'];
    final service = Map<String, dynamic>.from(
      rawService is Map<String, dynamic>
          ? rawService
          : rawService is Map
              ? Map<String, dynamic>.from(rawService)
              : <String, dynamic>{},
    );
    service['time_bound_value'] = completionTimeInMinutes;

    if (task['service'] is Map<String, dynamic>) {
      (task['service'] as Map<String, dynamic>)['time_bound_value'] =
          completionTimeInMinutes;
    }

    final Map<String, dynamic> updateTask = {
      'status': task['status']?.toString() ?? 'Processing',
      'service': service,
    };

    final assignedStaffId = _toInt(task['assigned_staff_id']);
    if (assignedStaffId != null) {
      updateTask['assigned_staff_id'] = assignedStaffId;
    }

    if (task['assigned_staff_name'] != null) {
      updateTask['assigned_staff_name'] = task['assigned_staff_name'];
    }

    final guestId = _toInt(task['guest_id']);
    if (guestId != null) {
      updateTask['guest_id'] = guestId;
    }

    final staffDeskId = task['staff_desk_id'];
    if (staffDeskId != null && staffDeskId.toString().isNotEmpty) {
      updateTask['staff_desk_id'] = staffDeskId.toString();
    }

    final department = task['department']?.toString();
    if (department != null && department.isNotEmpty) {
      updateTask['department'] = department;
    }

    final Map<String, dynamic> body = {
      "domain_name": PrimaryConfigData.domainName,
      "user_id": PrimaryConfigData.userId,
      "payload": {"update_task": updateTask},
      "extras": {
        "find": {"id": taskId}
      }
    };

    return await http.post(
      Uri.parse("${PrimaryConfigData.domainName}:${ApiEndPoints.updateTasks}"),
      body: jsonEncode(body),
      headers: const {
        'Content-Type': 'application/json; charset=UTF-8',
      },
    );
  }

  /// Get delivered tasks specifically
  static Future<http.Response> getDeliveredTasks(
      String memberId, int assignedStaffId) async {
    return await http.post(
      Uri.parse("${PrimaryConfigData.domainName}:${ApiEndPoints.getallTasks}"),
      body: jsonEncode({
        "domain_name": PrimaryConfigData.domainName,
        "user_id": PrimaryConfigData.userId,
        "extras": {
          "find": {
            "status": "Delivered",
            "member_id": memberId,
            "assigned_staff_id": assignedStaffId
          },
          "pagination": false,
          "sorting": true,
          "sortingDetails": {"id": -1}
        }
      }),
      headers: <String, String>{
        'Content-Type': 'application/json; charset=UTF-8',
      },
    );
  }

  // /// Get escalated tasks for a specific staff (using current_escalated_id)
  // static Future<http.Response> getEscalatedTasksForStaff(
  //     String memberId, int staffId) async {
  //   return await http.post(
  //     Uri.parse("${PrimaryConfigData.domainName}:${ApiEndPoints.getallTasks}"),
  //     body: jsonEncode({
  //       "domain_name": PrimaryConfigData.domainName,
  //       "user_id": PrimaryConfigData.userId,
  //       "extras": {
  //         "find": {
  //           "status": "Escalated",
  //           "member_id": memberId,
  //           "current_escalated_id": staffId
  //         },
  //         "pagination": false,
  //         "sorting": true,
  //         "sortingDetails": {"id": -1}
  //       }
  //     }),
  //     headers: <String, String>{
  //       'Content-Type': 'application/json; charset=UTF-8',
  //     },
  //   );
  // }

  /// Get ratings for task IDs
  static Future<http.Response> getRatingsForTasks(
      List<int> taskIds, String memberId) async {
    return await http.post(
      Uri.parse("${PrimaryConfigData.domainName}:${ApiEndPoints.getRatings}"),
      body: jsonEncode({
        "domain_name": PrimaryConfigData.domainName,
        "user_id": PrimaryConfigData.userId,
        "extras": {
          "find": {"task_id": taskIds, "member_id": memberId},
          "pagination": false,
          "sorting": true,
          "sortingDetails": {"id": -1}
        }
      }),
      headers: <String, String>{
        'Content-Type': 'application/json; charset=UTF-8',
      },
    );
  }

  /// Get completed tasks specifically
  static Future<http.Response> getCompletedTasks(
      String memberId, int assignedStaffId) async {
    return await http.post(
      Uri.parse("${PrimaryConfigData.domainName}:${ApiEndPoints.getallTasks}"),
      body: jsonEncode({
        "domain_name": PrimaryConfigData.domainName,
        "user_id": PrimaryConfigData.userId,
        "extras": {
          "find": {
            "status": "Completed",
            "member_id": memberId,
            "assigned_staff_id": assignedStaffId
          },
          "pagination": false,
          "sorting": true,
          "sortingDetails": {"id": -1}
        }
      }),
      headers: <String, String>{
        'Content-Type': 'application/json; charset=UTF-8',
      },
    );
  }

  /// Desk ASAP board: ASAP + Assigned tasks for hotel rooms + staff departments.
  static Future<http.Response> getDeskAsapAssignedTasks({
    required String memberId,
    required List<String> roomNos,
    required List<String> departments,
  }) async {
    return await http.post(
      Uri.parse("${PrimaryConfigData.domainName}:${ApiEndPoints.getallTasks}"),
      body: jsonEncode({
        "domain_name": PrimaryConfigData.domainName,
        "user_id": PrimaryConfigData.userId,
        "extras": {
          "find": {
            "status": ["ASAP", "Assigned", "Escalated"],
            "room_no": roomNos,
            "member_id": memberId,
            "service.category": departments,
          },
          "pagination": false,
          "sorting": true,
          "sortingDetails": {"id": -1}
        }
      }),
      headers: <String, String>{
        'Content-Type': 'application/json; charset=UTF-8',
      },
    );
  }

  /// Get cancelled tasks specifically
  static Future<http.Response> getCancelledTasks(
      String memberId, int assignedStaffId) async {
    return await http.post(
      Uri.parse("${PrimaryConfigData.domainName}:${ApiEndPoints.getallTasks}"),
      body: jsonEncode({
        "domain_name": PrimaryConfigData.domainName,
        "user_id": PrimaryConfigData.userId,
        "extras": {
          "find": {
            "status": "Cancelled",
            "member_id": memberId,
            "assigned_staff_id": assignedStaffId
          },
          "pagination": false,
          "sorting": true,
          "sortingDetails": {"id": -1}
        }
      }),
      headers: <String, String>{
        'Content-Type': 'application/json; charset=UTF-8',
      },
    );
  }

  /// Get assigned tasks (both Assigned and Escalated statuses)
  static Future<http.Response> getAssignedTasks(
      String memberId, int assignedStaffId) async {
    return await http.post(
      Uri.parse("${PrimaryConfigData.domainName}:${ApiEndPoints.getallTasks}"),
      body: jsonEncode({
        "domain_name": PrimaryConfigData.domainName,
        "user_id": PrimaryConfigData.userId,
        "extras": {
          "find": {
            "status": ["Assigned", "Escalated"],
            "member_id": memberId,
            "assigned_staff_id": assignedStaffId
          },
          "pagination": false,
          "sorting": true,
          "sortingDetails": {"id": -1}
        }
      }),
      headers: <String, String>{
        'Content-Type': 'application/json; charset=UTF-8',
      },
    );
  }

  /// Get processing tasks (both Processing and Escalated statuses)
  static Future<http.Response> getProcessingTasks(
      String memberId, int assignedStaffId) async {
    return await http.post(
      Uri.parse("${PrimaryConfigData.domainName}:${ApiEndPoints.getallTasks}"),
      body: jsonEncode({
        "domain_name": PrimaryConfigData.domainName,
        "user_id": PrimaryConfigData.userId,
        "extras": {
          "find": {
            "status": ["Processing", "Escalated"],
            "member_id": memberId,
            "assigned_staff_id": assignedStaffId
          },
          "pagination": false,
          "sorting": true,
          "sortingDetails": {"id": -1}
        }
      }),
      headers: <String, String>{
        'Content-Type': 'application/json; charset=UTF-8',
      },
    );
  }

  /// Get scheduled tasks
  static Future<http.Response> getScheduledTasks(
      String memberId, int assignedStaffId) async {
    return await http.post(
      Uri.parse("${PrimaryConfigData.domainName}:${ApiEndPoints.getallTasks}"),
      body: jsonEncode({
        "domain_name": PrimaryConfigData.domainName,
        "user_id": PrimaryConfigData.userId,
        "extras": {
          "find": {
            "status": "Scheduled",
            "member_id": memberId,
            "assigned_staff_id": assignedStaffId
          },
          "pagination": false,
          "sorting": true,
          "sortingDetails": {"id": -1}
        }
      }),
      headers: <String, String>{
        'Content-Type': 'application/json; charset=UTF-8',
      },
    );
  }

  /// Get high priority escalated tasks escalated TO the logged-in manager
  /// (escalated_to_id = logged in staff id).
  static Future<http.Response> getHighPriorityEscalatedTasks({
    required String memberId,
    required int escalatedToId,
  }) async {
    return await http.post(
      Uri.parse("${PrimaryConfigData.domainName}:${ApiEndPoints.getallTasks}"),
      body: jsonEncode({
        "domain_name": PrimaryConfigData.domainName,
        "user_id": PrimaryConfigData.userId,
        "extras": {
          "find": {
            "member_id": memberId,
            "status": "Escalated",
            "time_line.escalated_to_id": escalatedToId
          },
          "pagination": false,
          "sorting": true,
          "sortingDetails": {"id": -1}
        }
      }),
      headers: <String, String>{
        'Content-Type': 'application/json; charset=UTF-8',
      },
    );
  }

  /// Get escalated tasks sent FROM the logged-in manager to higher level
  /// (escalated_from_id = logged in staff id).
  static Future<http.Response> getNormalEscalatedTasks({
    required String memberId,
    required int escalatedFromId,
  }) async {
    return await http.post(
      Uri.parse("${PrimaryConfigData.domainName}:${ApiEndPoints.getallTasks}"),
      body: jsonEncode({
        "domain_name": PrimaryConfigData.domainName,
        "user_id": PrimaryConfigData.userId,
        "extras": {
          "find": {
            "member_id": memberId,
            "status": "Escalated",
            "time_line.escalated_from_id": escalatedFromId
          },
          "pagination": false,
          "sorting": true,
          "sortingDetails": {"id": -1}
        }
      }),
      headers: <String, String>{
        'Content-Type': 'application/json; charset=UTF-8',
      },
    );
  }

  /// Task IDs for escalations sent FROM the logged-in manager (home list).
  /// Used to decide whether an Escalated notification is high priority.
  static Future<List<int>> fetchManagerEscalatedFromTaskIds() async {
    await LocalStorageService.init();
    final user = LocalStorageService.user;
    final memberId = user?['member_id'] ?? user?['staff_member_id'];
    final staffId = _toInt(user?['id']);

    if (memberId == null || staffId == null) return [];

    try {
      final response = await getNormalEscalatedTasks(
        memberId: memberId.toString(),
        escalatedFromId: staffId,
      );
      if (response.statusCode != 200 && response.statusCode != 201) {
        return [];
      }
      final data = jsonDecode(response.body);
      if (data is! Map || data['success'] != 1 || data['result'] == null) {
        return [];
      }
      final List rawTasks = data['result']['data'] ?? [];
      return rawTasks
          .map((task) => _toInt((task as Map)['id']))
          .whereType<int>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  // Get task by ID (for tracking)
  static Future<http.Response> getTaskById({
    required String memberId,
    required int taskId,
  }) async {
    return await http.post(
      Uri.parse("${PrimaryConfigData.domainName}:${ApiEndPoints.getallTasks}"),
      body: jsonEncode({
        "domain_name": PrimaryConfigData.domainName,
        "user_id": PrimaryConfigData.userId,
        "extras": {
          "find": {"member_id": memberId, "id": taskId},
          "pagination": false
        }
      }),
      headers: <String, String>{
        'Content-Type': 'application/json; charset=UTF-8',
      },
    );
  }

  static const List<String> _selfAssignStripKeys = [
    '_id',
    'organization_id',
    'created_on',
    'modified_on',
  ];

  /// Desk assign:
  /// - Self → old payload: status [Processing], strip server-only keys
  /// - Other staff → current payload: full task, status [Assigned]
  static Future<http.Response> assignTaskFromDesk({
    required Map<String, dynamic> task,
    required int assignedStaffId,
    required String assignedStaffName,
    required String assignedStaffEmployeeNumber,
    required int deskStaffId,
    required bool isSelfAssigned,
    String? department,
  }) async {
    final int? taskId = _toInt(task['id']);
    if (taskId == null) {
      throw ArgumentError('Task id is required for assignment');
    }

    final dept = (department ??
            task['department']?.toString() ??
            task['service']?['category']?.toString() ??
            '')
        .trim();

    final Map<String, dynamic> updateTask = Map<String, dynamic>.from(task);

    if (isSelfAssigned) {
      // Old self-assign payload
      for (final key in _selfAssignStripKeys) {
        updateTask.remove(key);
      }
      updateTask['status'] = 'Processing';
      updateTask['is_self_assigned'] = true;
    } else {
      // Assign to another staff
      updateTask['status'] = 'Assigned';
      updateTask['is_self_assigned'] = false;
    }

    updateTask['at_desk'] = true;
    updateTask['assigned_staff_id'] = assignedStaffId;
    updateTask['assigned_staff_name'] = assignedStaffName;
    updateTask['assigned_staff_employee_number'] = assignedStaffEmployeeNumber;
    updateTask['staff_desk_id'] = deskStaffId;
    if (dept.isNotEmpty) {
      updateTask['department'] = dept;
    }

    final Map<String, dynamic> body = {
      "domain_name": PrimaryConfigData.domainName,
      "user_id": PrimaryConfigData.userId,
      "payload": {"update_task": updateTask},
      "extras": {
        "find": {"id": taskId}
      }
    };

    return await http.post(
      Uri.parse("${PrimaryConfigData.domainName}:${ApiEndPoints.updateTasks}"),
      body: jsonEncode(body),
      headers: const {
        'Content-Type': 'application/json; charset=UTF-8',
      },
    );
  }

  /// Centralized timer formatting for minutes and seconds
  static String formatTimerInMinutes(Duration d) {
    if (d.isNegative || d.inSeconds <= 0) {
      return '0 minutes';
    }

    final int totalMinutes = d.inMinutes;
    final int seconds = d.inSeconds % 60;

    if (totalMinutes == 0) {
      return '$seconds seconds';
    } else if (seconds == 0) {
      return totalMinutes == 1 ? '1 minute' : '$totalMinutes minutes';
    } else {
      return '$totalMinutes:$seconds minutes';
    }
  }
}
