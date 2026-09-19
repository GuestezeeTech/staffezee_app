import 'package:flutter/foundation.dart';
import 'package:guestezee_staffs_app/Services/local_storage_service.dart';
import 'package:guestezee_staffs_app/Services/task_service.dart';

/// High Priority button badge for managers only.
///
/// An Escalated notification is high priority when its task id is NOT in the
/// manager home list (escalations sent FROM the logged-in manager upward).
/// If the task id is in that list, it belongs on the home tab – no badge.
class HighPriorityBadgeService {
  HighPriorityBadgeService._();

  static final ValueNotifier<int> count = ValueNotifier<int>(0);

  /// Increment to tell [EscalatedTasksPage] to reload its home task list.
  static final ValueNotifier<int> homeListRefreshSignal = ValueNotifier<int>(0);

  static Future<void> init() async {
    await LocalStorageService.init();
    count.value = LocalStorageService.getUnreadHighPriorityEscalationCount();
  }

  /// Called when an Escalated push arrives (manager only).
  /// Refreshes escalated-from task ids; shows badge only if [taskId] is NOT
  /// in that home list.
  static Future<void> recordEscalationNotification({required int taskId}) async {
    await LocalStorageService.init();
    if (!LocalStorageService.isManagerLevel) return;

    final fromTaskIds = await TaskService.fetchManagerEscalatedFromTaskIds();
    homeListRefreshSignal.value++;

    if (fromTaskIds.contains(taskId)) {
      debugPrint(
          '🔔 Task $taskId is in manager home (escalated-from) list – not high priority, skip badge');
      return;
    }

    debugPrint(
        '🔔 Task $taskId is NOT in manager home list – high priority badge');

    final ids = LocalStorageService.getUnreadHighPriorityTaskIds();
    if (ids.contains(taskId)) return;

    ids.add(taskId);
    await LocalStorageService.saveUnreadHighPriorityTaskIds(ids);
    count.value = ids.length;
  }

  static Future<void> clear() async {
    await LocalStorageService.saveUnreadHighPriorityTaskIds([]);
    count.value = 0;
  }

  static void reset() {
    count.value = 0;
  }
}
