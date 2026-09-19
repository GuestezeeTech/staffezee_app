import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:guestezee_staffs_app/Services/task_service.dart';
import 'package:guestezee_staffs_app/Services/staff_service.dart';
import 'package:guestezee_staffs_app/Services/local_storage_service.dart';
import 'package:guestezee_staffs_app/Services/network_error_message.dart';
import 'package:guestezee_staffs_app/Services/escalation_timer_service.dart';
import 'package:guestezee_staffs_app/Services/continuous_sound_service.dart';
import 'package:guestezee_staffs_app/Services/Notifictaion%20service/alarm_service.dart';
import 'package:guestezee_staffs_app/Custom Widgets/task_transition_loader.dart';
import 'package:guestezee_staffs_app/Custom Widgets/fnb_order_details.dart';
import 'package:guestezee_staffs_app/Custom Widgets/task_card_type.dart';
import 'package:guestezee_staffs_app/Custom Widgets/task_special_request.dart';
import 'package:guestezee_staffs_app/Custom Widgets/navigation_page.dart';
import 'package:hive_flutter/hive_flutter.dart';

class TrackTaskPage extends StatefulWidget {
  final int taskId;

  const TrackTaskPage({
    super.key,
    required this.taskId,
  });

  @override
  State<TrackTaskPage> createState() => _TrackTaskPageState();
}

class _TrackTaskPageState extends State<TrackTaskPage>
    with WidgetsBindingObserver {
  Map<String, dynamic>? task;
  bool isLoading = true;
  String? errorMessage;

  // Timer variables for assigned tasks
  Duration? escalationTimer;
  Timer? countTimer;
  bool showAcceptButton = true;

  // Refresh while this screen is visible
  Timer? _visibilityRefreshTimer;
  bool _refreshInFlight = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadTaskDetails();
    _startVisibilityRefresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopVisibilityRefresh();
    countTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _loadTaskDetails(showLoading: false);
      _startVisibilityRefresh();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _stopVisibilityRefresh();
    }
  }

  void _startVisibilityRefresh() {
    _stopVisibilityRefresh();
    _visibilityRefreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!mounted) return;
      _loadTaskDetails(showLoading: false);
    });
  }

  void _stopVisibilityRefresh() {
    _visibilityRefreshTimer?.cancel();
    _visibilityRefreshTimer = null;
  }

  Future<void> _loadTaskDetails({bool showLoading = true}) async {
    if (!mounted) return;
    if (_refreshInFlight && !showLoading) return;
    _refreshInFlight = true;

    if (showLoading) {
      setState(() {
        isLoading = true;
        errorMessage = null;
      });
    } else if (errorMessage != null) {
      setState(() => errorMessage = null);
    }

    try {
      await LocalStorageService.init();
      final user = Hive.box('authBox').get('user');
      final memberId = user?['member_id'] ?? user?['staff_member_id'];

      if (memberId == null) {
        setState(() {
          errorMessage = 'Member ID not found';
          isLoading = false;
        });
        return;
      }

      // Fetch task details by task ID
      final response = await TaskService.getTaskById(
        memberId: memberId.toString(),
        taskId: widget.taskId,
      );

      if (!mounted) return;

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);

        if (data['success'] == 1 && data['result'] != null) {
          final resultData = data['result']['data'];

          // The API returns an array in result.data, we need the first item
          if (resultData is List && resultData.isNotEmpty) {
            final firstItem = resultData[0];
            if (firstItem is Map) {
              setState(() {
                task = Map<String, dynamic>.from(firstItem);
                isLoading = false;
                errorMessage = null;
              });

              // Initialize escalation timer for assigned tasks
              _initializeEscalationTimer();

              // Stop sound if task is escalated
              _stopSoundIfEscalated();

              // Start continuous sound if task is assigned (in case it came from background)
              _startContinuousSoundIfAssigned();

              print('✅ Task details loaded for ID: ${widget.taskId}');
              if (task != null && task!['time_line'] != null) {
                print(
                    '📋 Task timeline entries: ${(task!['time_line'] as List).length}');
              }
            } else {
              setState(() {
                errorMessage = 'Invalid task data format';
                isLoading = false;
              });
              print('⚠️ Task data is not a Map: ${firstItem.runtimeType}');
            }
          } else {
            setState(() {
              errorMessage = 'Task not found';
              isLoading = false;
            });
            print('⚠️ No task data in response');
          }
        } else {
          setState(() {
            errorMessage = 'Task not found';
            isLoading = false;
          });
          print('⚠️ API returned success: ${data['success']}');
        }
      } else {
        setState(() {
          errorMessage = 'Error connecting to server';
          isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          errorMessage = NetworkErrorMessage.forTaskDetails(e);
          isLoading = false;
        });
      }
    } finally {
      _refreshInFlight = false;
    }
  }

  bool _canShowAcceptButton() {
    if (task == null) return false;
    // Desk / manager see Assign (or nothing) — floor staff accept Assigned tasks.
    if (!StaffService.canAcceptAssignedTasks(LocalStorageService.user)) {
      return false;
    }
    final status = task!['status']?.toString().trim().toUpperCase() ?? '';
    return status == 'ASSIGNED';
  }

  void _initializeEscalationTimer() {
    if (task == null) return;

    if (!_canShowAcceptButton()) {
      countTimer?.cancel();
      setState(() {
        showAcceptButton = false;
        escalationTimer = null;
      });
      return;
    }

    final Duration? remainingTime =
        EscalationTimerService.calculateRemainingEscalationTime(task!);

    setState(() {
      showAcceptButton = true;
      if (remainingTime != null && remainingTime.inSeconds > 0) {
        escalationTimer = remainingTime;
      } else {
        escalationTimer = null;
      }
    });

    if (escalationTimer != null) {
      _startCountdownTimer();
    } else {
      countTimer?.cancel();
    }
  }

  void _startCountdownTimer() {
    // Cancel any existing timer
    countTimer?.cancel();

    countTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (escalationTimer != null) {
        setState(() {
          if (escalationTimer!.inSeconds <= 0) {
            // Keep Accept visible until the task status is no longer Assigned.
            escalationTimer = null;
            timer.cancel();
            _handleTimerExpiry();
          } else {
            escalationTimer = escalationTimer! - Duration(seconds: 1);
          }
        });
      }
    });
  }

  void _handleTimerExpiry() async {
    // Wait 5 seconds after timer expires
    await Future.delayed(Duration(seconds: 5));

    if (!mounted) return;

    // Reload task data to check if status changed to escalated
    await _loadTaskDetails(showLoading: false);
  }

  Future<void> _stopSoundIfEscalated() async {
    if (task == null) return;

    final String currentStatus =
        task!['status']?.toString().toUpperCase() ?? '';
    // Stop sound/alarm if task is not in Assigned status
    if (currentStatus != 'ASSIGNED') {
      print(
          '🔊 Stopping sound/alarm for task ${widget.taskId} (status: $currentStatus)');
      ContinuousSoundService.stopTaskSound(widget.taskId);
      await AlarmService.stopAlarmForTask(widget.taskId);
    }
  }

  void _startContinuousSoundIfAssigned() {
    // Desk staff assign tasks — no accept alarm for them.
    if (!StaffService.canAcceptAssignedTasks(LocalStorageService.user)) return;

    // Check if the current task's status is ASSIGNED and start continuous sound
    // Only on Android; on iOS, AlarmService handles the continuous alarm.
    if (task != null && Platform.isAndroid) {
      final String currentStatus =
          task!['status']?.toString().toUpperCase() ?? '';
      if (currentStatus == 'ASSIGNED') {
        // Check if sound is already playing for this task
        if (!ContinuousSoundService.isSoundPlaying(widget.taskId)) {
          print(
              '🔊 Task ${widget.taskId} is ASSIGNED, starting continuous sound');
          ContinuousSoundService.startTaskSound(widget.taskId);
        }
      }
    }
  }

  String _formatTimer(Duration d) {
    if (d.isNegative || d.inSeconds <= 0) {
      return '00:00';
    }

    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return '${twoDigits(d.inMinutes.remainder(60))}:${twoDigits(d.inSeconds.remainder(60))}';
  }

  bool _hasTimelineText(dynamic value) {
    if (value == null) return false;
    final text = value.toString().trim();
    return text.isNotEmpty && text.toLowerCase() != 'null';
  }

  String? _timelineStatus(Map<String, dynamic> event) {
    final status = event['status']?.toString().trim();
    if (status == null || status.isEmpty || status.toLowerCase() == 'null') {
      return null;
    }
    return status;
  }

  bool _isDisplayableTimelineEvent(Map<String, dynamic> event) {
    return _timelineStatus(event) != null ||
        _hasTimelineText(event['assigned_staff_name']) ||
        _hasTimelineText(event['escalated_from_name']) ||
        _hasTimelineText(event['escalated_to_name']) ||
        _hasTimelineText(event['remark']) ||
        _hasTimelineText(event['feedback']);
  }

  List<Map<String, dynamic>> _visibleTimelineEntries(List timeline) {
    return timeline
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .where(_isDisplayableTimelineEvent)
        .toList();
  }

  String _formatTime(String? time) {
    if (time == null) return 'N/A';
    try {
      final timeParts = time.split(':');
      if (timeParts.length < 2) return time;
      int hour = int.parse(timeParts[0]);
      final minute = timeParts[1];
      final period = hour >= 12 ? 'PM' : 'AM';
      hour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
      return '$hour:$minute $period';
    } catch (e) {
      return time;
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toUpperCase()) {
      case 'ASAP':
        return Colors.orange;
      case 'ASSIGNED':
        return Colors.blue;
      case 'PROCESSING':
        return Colors.purple;
      case 'ESCALATED':
        return Colors.red;
      case 'DELIVERED':
      case 'COMPLETED':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status.toUpperCase()) {
      case 'ASAP':
        return Icons.flash_on;
      case 'ASSIGNED':
        return Icons.person_add;
      case 'PROCESSING':
        return Icons.pending_actions;
      case 'ESCALATED':
        return Icons.arrow_upward;
      case 'DELIVERED':
      case 'COMPLETED':
        return Icons.check_circle;
      default:
        return Icons.info;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Track Task #${widget.taskId}'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        // actions: [
        //   IconButton(
        //     icon: Icon(Icons.refresh),
        //     onPressed: _loadTaskDetails,
        //   ),
        // ],
      ),
      body: isLoading
          ? Center(child: CircularProgressIndicator())
          : errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, size: 64, color: Colors.red),
                      SizedBox(height: 16),
                      Text(
                        errorMessage!,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 16, color: Colors.grey[700]),
                      ),
                      SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: _loadTaskDetails,
                        child: Text('Retry'),
                      ),
                    ],
                  ),
                )
              : task == null
                  ? Center(child: Text('No task data available'))
                  : RefreshIndicator(
                      onRefresh: _loadTaskDetails,
                      child: SingleChildScrollView(
                        physics: AlwaysScrollableScrollPhysics(),
                        padding: EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Task Info Card
                            Card(
                              color: Colors.white,
                              elevation: 4,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Padding(
                                padding: EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary
                                                .withOpacity(0.1),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: Icon(
                                            Icons.room_service,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary,
                                          ),
                                        ),
                                        SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Room ${task!['room_no'] ?? 'N/A'}',
                                                style: TextStyle(
                                                  fontSize: 20,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              Text(
                                                task!['guest_name']
                                                        ?.toString() ??
                                                    'Guest',
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  color: Colors.grey[600],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Container(
                                          padding: EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: _getStatusColor(
                                                task!['status'] ?? ''),
                                            borderRadius:
                                                BorderRadius.circular(20),
                                          ),
                                          child: Text(
                                            task!['status']?.toString() ??
                                                'N/A',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    Divider(height: 24),
                                    _buildInfoRow(
                                      icon: Icons.dining,
                                      label: 'Service',
                                      value: task!['service']?['service_name']
                                              ?.toString() ??
                                          'N/A',
                                    ),
                                    SizedBox(height: 12),
                                    _buildInfoRow(
                                      icon: Icons.category,
                                      label: 'Type',
                                      value: TaskCardType.serviceBelongsTo(
                                              task!) ??
                                          task!['service']?['category']
                                              ?.toString() ??
                                          'N/A',
                                    ),
                                    SizedBox(height: 12),
                                    _buildInfoRow(
                                      icon: Icons.access_time,
                                      label: 'Order Time',
                                      value:
                                          '${_formatTime(task!['order_time'])} on ${task!['order_date'] ?? 'N/A'}',
                                    ),
                                    MenuOrderFoodSection(task: task!),
                                    if (TaskSpecialRequest.text(task) !=
                                        null) ...[
                                      SizedBox(height: 12),
                                      _buildInfoRow(
                                        icon: Icons.note_alt_outlined,
                                        label: 'Special Request',
                                        value: TaskSpecialRequest.text(task)!,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                            // Desk: desktop-only checkout tasks → web label (no Assign)
                            if (_shouldShowDesktopHandleLabel()) ...[
                              SizedBox(height: 16),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 14),
                                decoration: BoxDecoration(
                                  color: Colors.orange.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                  border:
                                      Border.all(color: Colors.orange.shade300),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      Icons.desktop_windows_outlined,
                                      color: Colors.orange.shade800,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        'Please handle this task on the desktop. Checkout tasks cannot be assigned from the mobile app.',
                                        style: TextStyle(
                                          fontSize: 14,
                                          height: 1.35,
                                          color: Colors.orange.shade900,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            // Desk: Assign if unassigned, or Escalated (re-assign)
                            if (_canShowDeskAssignButton()) ...[
                              SizedBox(height: 16),
                              SizedBox(
                                width: double.infinity,
                                height: 50,
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor:
                                        Theme.of(context).colorScheme.secondary,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  onPressed: _openDeskAssignSheet,
                                  child: const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.person_add_alt_1, size: 20),
                                      SizedBox(width: 8),
                                      Text(
                                        'Assign',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                            // Accept: floor staff, Assigned — independent of desk Assign / timer.
                            if (_canShowAcceptButton() && showAcceptButton) ...[
                              SizedBox(height: 16),
                              Container(
                                width: double.infinity,
                                height: 50,
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor:
                                        Theme.of(context).colorScheme.primary,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  onPressed: () async {
                                    // Show loader immediately (only if not already showing)
                                    if (!TaskTransitionLoaderController
                                        .isShowing) {
                                      TaskTransitionLoaderController.show(
                                        context: context,
                                        message: 'Accepting task...',
                                      );
                                    }

                                    try {
                                      final user =
                                          Hive.box('authBox').get('user');
                                      final int? staffId = (user?['id'] is int)
                                          ? user['id'] as int
                                          : int.tryParse(
                                              user?['id']?.toString() ?? '');
                                      final String? staffName =
                                          user?['full_name']?.toString();

                                      // Get guest_id and staff_desk_id from task
                                      final int? guestId = task!['guest_id']
                                              is int
                                          ? task!['guest_id'] as int
                                          : int.tryParse(
                                              task!['guest_id']?.toString() ??
                                                  '');
                                      final String? staffDeskId =
                                          task!['staff_desk_id']?.toString();

                                      final resp =
                                          await TaskService.updateTaskStatus(
                                        taskId: widget.taskId,
                                        service: task?['service'] ?? {},
                                        status: 'Processing',
                                        assignedStaffId: staffId,
                                        assignedStaffName: staffName,
                                        guestId: guestId,
                                        staffDeskId: staffDeskId,
                                        department: task?['service']
                                                ?['category']
                                            ?.toString(),
                                      );

                                      // Hide loader
                                      TaskTransitionLoaderController.hide();

                                      if (resp.statusCode == 200 ||
                                          resp.statusCode == 201) {
                                        final body = jsonDecode(resp.body);
                                        if (body['success'] == 1) {
                                          // Stop continuous sound for this specific task only
                                          await ContinuousSoundService
                                              .stopTaskSound(widget.taskId);
                                          await AlarmService.stopAlarmForTask(
                                              widget.taskId);

                                          // Assigned notification stayed in the
                                          // tray until now – clear it on accept.
                                          await AlarmService
                                              .clearTaskStatusNotifications(
                                                  widget.taskId);

                                          // Refresh task from server and update UI
                                          await _loadTaskDetails(
                                              showLoading: false);
                                        } else {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                  body['message']?.toString() ??
                                                      'Failed to accept task'),
                                            ),
                                          );
                                        }
                                      } else {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                            content: Text(
                                                'Error connecting to server'),
                                          ),
                                        );
                                      }
                                    } catch (e) {
                                      // Hide loader on error
                                      TaskTransitionLoaderController.hide();

                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text('Error: $e'),
                                        ),
                                      );
                                    }
                                  },
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.check_circle_outline,
                                          size: 20),
                                      SizedBox(width: 8),
                                      Text(
                                        escalationTimer != null &&
                                                !escalationTimer!.isNegative
                                            ? 'Accept Task (${_formatTimer(escalationTimer!)})'
                                            : 'Accept Task',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                            SizedBox(height: 24),
                            // Timeline Section
                            Text(
                              'Task Timeline',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: 16),
                            if (task!['time_line'] != null &&
                                task!['time_line'] is List &&
                                (task!['time_line'] as List).isNotEmpty)
                              _buildTimeline(task!['time_line'] as List)
                            else
                              Center(
                                child: Padding(
                                  padding: EdgeInsets.all(24),
                                  child: Text(
                                    'No timeline available',
                                    style: TextStyle(color: Colors.grey),
                                  ),
                                ),
                              ),
                            SizedBox(height: 24),
                          ],
                        ),
                      ),
                    ),
    );
  }

  bool _shouldShowDesktopHandleLabel() {
    if (task == null) return false;
    if (!StaffService.isAtDeskStaff(LocalStorageService.user)) return false;
    return TaskCardType.isDesktopHandledTask(task!);
  }

  bool _canShowDeskAssignButton() {
    if (task == null) return false;

    final user = LocalStorageService.user;
    if (!StaffService.isAtDeskStaff(user)) return false;

    // Checkout / Late Checkout → desktop only, never assign on mobile.
    if (TaskCardType.isDesktopHandledTask(task!)) return false;

    final status = task!['status']?.toString().trim().toUpperCase() ?? '';

    // Escalated → desk can (re)assign even if assigned_staff_id exists.
    if (status == 'ESCALATED') return true;

    // No assigned_staff_id key / null / empty → needs assign (e.g. ASAP).
    if (!task!.containsKey('assigned_staff_id')) return true;
    final assigned = task!['assigned_staff_id'];
    if (assigned == null) return true;
    if (assigned.toString().trim().isEmpty) return true;

    return false;
  }

  Future<void> _openDeskAssignSheet() async {
    if (task == null) return;

    await LocalStorageService.init();
    final user = LocalStorageService.user;
    final memberId = (user?['member_id'] ?? user?['staff_member_id'] ?? '')
        .toString()
        .trim();
    final int? deskStaffId = user?['id'] is int
        ? user!['id'] as int
        : int.tryParse(user?['id']?.toString() ?? '');
    final department =
        (task!['department'] ?? task!['service']?['category'] ?? '')
            .toString()
            .trim();

    if (memberId.isEmpty || deskStaffId == null || department.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to load staff for assignment')),
      );
      return;
    }

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return _DeskAssignSheet(
          task: Map<String, dynamic>.from(task!),
          memberId: memberId,
          deskStaffId: deskStaffId,
          deskStaffName: user?['full_name']?.toString() ?? 'Self',
          deskStaffEmployeeNumber:
              (user?['staff_employee_number'] ?? '').toString(),
          department: department,
          onAssigned: () {
            if (!mounted) return;
            _loadTaskDetails(showLoading: false);
          },
        );
      },
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Colors.grey[600]),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
              SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTimeline(List timeline) {
    final entries = _visibleTimelineEntries(timeline);
    if (entries.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No timeline available',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: NeverScrollableScrollPhysics(),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final Map<String, dynamic> event = entries[index];
        final isFirst = index == 0;
        final isLast = index == entries.length - 1;
        final status = _timelineStatus(event) ?? 'Update';
        final assignedStaffName = event['assigned_staff_name'];
        final escalatedFromName = event['escalated_from_name'];
        final escalatedToName = event['escalated_to_name'];
        final remark = event['remark'];

        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Timeline indicator
              Column(
                children: [
                  if (!isFirst)
                    Container(
                      width: 2,
                      height: 20,
                      color: Colors.grey[300],
                    ),
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _getStatusColor(status),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: [
                        BoxShadow(
                          color: _getStatusColor(status).withOpacity(0.3),
                          blurRadius: 8,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Icon(
                      _getStatusIcon(status),
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  if (!isLast)
                    Expanded(
                      child: Container(
                        width: 2,
                        color: Colors.grey[300],
                      ),
                    ),
                ],
              ),
              SizedBox(width: 16),
              // Timeline content
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(bottom: isLast ? 0 : 24),
                  child: Card(
                    color: Colors.white,
                    elevation: 2,
                    margin: EdgeInsets.only(top: 0),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: _getStatusColor(status).withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  status.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: _getStatusColor(status),
                                  ),
                                ),
                              ),
                              Icon(
                                Icons.schedule,
                                size: 14,
                                color: Colors.grey[600],
                              ),
                              SizedBox(width: 4),
                              Text(
                                _formatTime(event['time']?.toString()),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          if (_hasTimelineText(event['date'])) ...[
                            SizedBox(height: 4),
                            Text(
                              event['date'].toString().trim(),
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[500],
                              ),
                            ),
                          ],
                          if (_hasTimelineText(assignedStaffName)) ...[
                            SizedBox(height: 8),
                            Row(
                              children: [
                                Icon(Icons.person,
                                    size: 14, color: Colors.blue),
                                SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    'Assigned to: ${assignedStaffName.toString().trim()}',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.blue[700],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          if (_hasTimelineText(escalatedFromName) ||
                              _hasTimelineText(escalatedToName)) ...[
                            SizedBox(height: 8),
                            Container(
                              padding: EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.red[50],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (_hasTimelineText(escalatedFromName))
                                    Row(
                                      children: [
                                        Icon(Icons.arrow_upward,
                                            size: 14, color: Colors.red),
                                        SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            'From: ${escalatedFromName.toString().trim()}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.red[800],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  if (_hasTimelineText(escalatedToName))
                                    Row(
                                      children: [
                                        Icon(Icons.arrow_forward,
                                            size: 14, color: Colors.red),
                                        SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            'To: ${escalatedToName.toString().trim()}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.red[800],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                            ),
                          ],
                          if (_hasTimelineText(remark)) ...[
                            SizedBox(height: 8),
                            Container(
                              padding: EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.orange[50],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.comment,
                                      size: 14, color: Colors.orange),
                                  SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      remark.toString().trim(),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.orange[900],
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DeskAssignSheet extends StatefulWidget {
  final Map<String, dynamic> task;
  final String memberId;
  final int deskStaffId;
  final String deskStaffName;
  final String deskStaffEmployeeNumber;
  final String department;
  final VoidCallback onAssigned;

  const _DeskAssignSheet({
    required this.task,
    required this.memberId,
    required this.deskStaffId,
    required this.deskStaffName,
    required this.deskStaffEmployeeNumber,
    required this.department,
    required this.onAssigned,
  });

  @override
  State<_DeskAssignSheet> createState() => _DeskAssignSheetState();
}

class _DeskAssignSheetState extends State<_DeskAssignSheet> {
  bool _loading = true;
  bool _assigning = false;
  String? _error;
  List<Map<String, dynamic>> _options = [];
  int? _selectedStaffId;
  bool _selectedIsSelf = false;

  @override
  void initState() {
    super.initState();
    _loadStaff();
  }

  int? _staffId(Map<String, dynamic> staff) {
    final id = staff['id'];
    if (id is int) return id;
    return int.tryParse(id?.toString() ?? '');
  }

  Future<void> _loadStaff() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final response = await StaffService.findStaffForTaskAllocation(
        memberId: widget.memberId,
        deskStaffId: widget.deskStaffId,
        department: widget.department,
      );

      if (response.statusCode != 200 && response.statusCode != 201) {
        setState(() {
          _loading = false;
          _error = 'Unable to load available staff';
        });
        return;
      }

      final data = jsonDecode(response.body);
      final List raw = (data is Map && data['result']?['data'] is List)
          ? List.from(data['result']['data'] as List)
          : <dynamic>[];

      final List<Map<String, dynamic>> staffList = raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      final others = staffList.where((s) {
        final id = _staffId(s);
        return id != null && id != widget.deskStaffId;
      }).toList();

      final List<Map<String, dynamic>> options = [];
      if (others.isEmpty) {
        // API returned only self / empty → offer self assign.
        options.add({
          'id': widget.deskStaffId,
          'full_name': widget.deskStaffName,
          'staff_employee_number': widget.deskStaffEmployeeNumber,
          '_is_self': true,
        });
      } else {
        for (final s in others) {
          options.add({...s, '_is_self': false});
        }
      }

      setState(() {
        _options = options;
        _loading = false;
        if (_options.length == 1) {
          _selectedStaffId = _staffId(_options.first);
          _selectedIsSelf = _options.first['_is_self'] == true;
        }
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Unable to load available staff';
      });
    }
  }

  Future<void> _assignDuty() async {
    if (_selectedStaffId == null || _assigning) return;

    Map<String, dynamic>? selected;
    for (final s in _options) {
      if (_staffId(s) == _selectedStaffId) {
        selected = s;
        break;
      }
    }
    if (selected == null) return;

    setState(() => _assigning = true);

    try {
      final name =
          (selected['full_name'] ?? selected['name'] ?? 'Staff').toString();
      final empNo = (selected['staff_employee_number'] ?? '').toString();

      final response = await TaskService.assignTaskFromDesk(
        task: widget.task,
        assignedStaffId: _selectedStaffId!,
        assignedStaffName: name,
        assignedStaffEmployeeNumber: empNo,
        deskStaffId: widget.deskStaffId,
        isSelfAssigned: _selectedIsSelf,
        department: widget.department,
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final body = jsonDecode(response.body);
        if (body is Map && body['success'] == 1) {
          final taskId = widget.task['id'] is int
              ? widget.task['id'] as int
              : int.tryParse(widget.task['id']?.toString() ?? '') ?? 0;

          await ContinuousSoundService.stopTaskSound(taskId);
          await AlarmService.stopAlarmForTask(taskId);
          await AlarmService.clearTaskStatusNotifications(taskId);

          if (mounted) Navigator.of(context).pop();
          widget.onAssigned();
          return;
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                body is Map
                    ? (body['message']?.toString() ?? 'Failed to assign task')
                    : 'Failed to assign task',
              ),
            ),
          );
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error connecting to server')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _assigning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final theme = Theme.of(context);

    return ClipRRect(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.55,
        color: Colors.white,
        child: Padding(
          padding: EdgeInsets.only(bottom: bottom),
          child: SafeArea(
            bottom: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 12),
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Text(
                    'Assign duty',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null
                          ? Center(child: Text(_error!))
                          : ListView.separated(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              itemCount: _options.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final staff = _options[index];
                                final id = _staffId(staff);
                                final isSelf = staff['_is_self'] == true;
                                final title = isSelf
                                    ? 'Self assign'
                                    : (staff['full_name'] ??
                                            staff['name'] ??
                                            'Staff')
                                        .toString();
                                final subtitle = isSelf
                                    ? widget.deskStaffName
                                    : (staff['staff_employee_number'] ?? '')
                                        .toString();
                                final selected =
                                    id != null && id == _selectedStaffId;

                                return ListTile(
                                  leading: Icon(
                                    isSelf
                                        ? Icons.person_outline
                                        : Icons.badge_outlined,
                                    color: theme.colorScheme.primary,
                                  ),
                                  title: Text(title),
                                  subtitle:
                                      subtitle.isEmpty ? null : Text(subtitle),
                                  trailing: selected
                                      ? Icon(Icons.check_circle,
                                          color: theme.colorScheme.primary)
                                      : const Icon(Icons.radio_button_unchecked,
                                          color: Colors.grey),
                                  onTap: id == null
                                      ? null
                                      : () {
                                          setState(() {
                                            _selectedStaffId = id;
                                            _selectedIsSelf = isSelf;
                                          });
                                        },
                                );
                              },
                            ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: (_selectedStaffId == null || _assigning)
                          ? null
                          : _assignDuty,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.colorScheme.primary,
                        foregroundColor: Colors.white,
                      ),
                      child: _assigning
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Text(
                              'Assign duty',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
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
