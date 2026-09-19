import 'package:flutter/foundation.dart';
import 'package:guestezee_staffs_app/Services/local_storage_service.dart';
import 'package:guestezee_staffs_app/Services/task_service.dart';

/// Signals screens to reload tasks after the session monitor polls task/getall.
class TaskRefreshService {
  TaskRefreshService._();

  static final ValueNotifier<int> refreshSignal = ValueNotifier<int>(0);

  /// Best-effort task/getall poll for the logged-in staff.
  static Future<void> poll() async {
    if (!LocalStorageService.isLoggedIn) return;

    try {
      await LocalStorageService.init();
      final user = LocalStorageService.user;
      final memberId = (user?['member_id'] ?? user?['staff_member_id'] ?? '')
          .toString()
          .trim();
      final int? staffId = user?['id'] is int
          ? user!['id'] as int
          : int.tryParse(user?['id']?.toString() ?? '');

      if (memberId.isEmpty || staffId == null) return;

      await TaskService.getAssignedTasks(memberId, staffId);
      refreshSignal.value++;
    } catch (e) {
      debugPrint('⚠️ TaskRefreshService poll failed: $e');
    }
  }
}
