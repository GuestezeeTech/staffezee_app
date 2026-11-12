import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:guestezee_staffs_app/const.dart';
import 'package:guestezee_staffs_app/Services/task_service.dart';
import 'package:guestezee_staffs_app/Services/local_storage_service.dart';
import 'package:guestezee_staffs_app/Services/network_error_message.dart';
import 'package:guestezee_staffs_app/Services/escalation_timer_service.dart';
import 'package:guestezee_staffs_app/Custom%20Widgets/navigation_page.dart';
import 'package:guestezee_staffs_app/Custom%20Widgets/fnb_order_details.dart';
import 'package:guestezee_staffs_app/Custom%20Widgets/service_task_icon.dart';
import 'package:guestezee_staffs_app/Custom%20Widgets/task_special_request.dart';
import 'package:guestezee_staffs_app/Custom%20Widgets/task_card_type.dart';
import 'package:guestezee_staffs_app/Custom%20Widgets/task_transition_loader.dart';
import 'package:guestezee_staffs_app/Screens/track_task_page.dart';
import 'package:guestezee_staffs_app/Custom%20Widgets/desk_task_floating_actions.dart';
import 'package:hive_flutter/hive_flutter.dart';

class ProcessingTaskPage extends ConsumerStatefulWidget {
  const ProcessingTaskPage({super.key});

  @override
  ConsumerState<ProcessingTaskPage> createState() => _ProcessingTaskPageState();
}

class _ProcessingTaskPageState extends ConsumerState<ProcessingTaskPage>
    with WidgetsBindingObserver {
  // API data
  List<Map<String, dynamic>> tasks = [];
  bool isLoading = true;
  String? errorMessage;

  // Timer and UI state
  List<Duration> timers = [];
  List<Timer> countTimer = [];

  // F&B time input controllers
  List<TextEditingController> completionTimeControllers = [];
  String? staffCategory;

  // Live update timer
  Timer? _liveUpdateTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadStaffCategory();
    _loadProcessingTasks(showLoading: true);
    _startLiveUpdates();
  }

  void _loadStaffCategory() async {
    await LocalStorageService.init();
    final user = Hive.box('authBox').get('user');
    setState(() {
      staffCategory = user?['category']?.toString();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      // App is going to background - stop polling
      _stopLiveUpdates();
    } else if (state == AppLifecycleState.resumed && mounted) {
      // App is coming back to foreground - resume polling
      _loadProcessingTasks(showLoading: false);
      _startLiveUpdates();
    }
  }

  Future<void> _loadProcessingTasks({bool showLoading = false}) async {
    if (!mounted) return;

    // Only show loading indicator on initial load or manual retry
    if (showLoading) {
      setState(() {
        isLoading = true;
        errorMessage = null; // Clear any previous errors
      });
    } else {
      // Silent background update - just clear error if any
      if (errorMessage != null) {
        setState(() {
          errorMessage = null;
        });
      }
    }

    try {
      await LocalStorageService.init();
      final user = Hive.box('authBox').get('user');
      final memberId = user?['member_id'] ?? user?['staff_member_id'];
      final int? assignedStaffId = (user?['id'] is int)
          ? user['id'] as int
          : int.tryParse(user?['id']?.toString() ?? '');

      if (memberId == null || assignedStaffId == null) {
        if (mounted) {
          setState(() {
            errorMessage = 'Member ID or Staff ID not found';
            isLoading = false;
          });
        }
        return;
      }

      final response = await TaskService.getProcessingTasks(
          memberId.toString(), assignedStaffId);

      if (!mounted) return;

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        if (data['success'] == 1 && data['result'] != null) {
          final List<dynamic> taskList = data['result']['data'] ?? [];
          // Keep escalated tasks only if their last non-escalation status is 'Processing'
          final List<Map<String, dynamic>> normalized =
              taskList.cast<Map<String, dynamic>>().where((t) {
            final String current = t['status']?.toString() ?? '';
            if (current == 'Escalated') {
              final String? base = _lastNonEscalationStatusOf(t);
              return base == 'Processing';
            }
            return true; // keep non-escalated as provided by API
          }).toList();
          setState(() {
            tasks = normalized;
            _initializeTaskStates();
            isLoading = false;
            errorMessage = null; // Clear error on success
          });
        } else {
          setState(() {
            errorMessage = data['message'] ?? 'Failed to load tasks';
            isLoading = false;
          });
        }
      } else {
        setState(() {
          errorMessage = 'Error connecting to server';
          isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        errorMessage = NetworkErrorMessage.forTaskLoad(e);
        isLoading = false;
      });
    }
  }

  void _initializeTaskStates() {
    int itemCount = tasks.length;

    // Use escalation timer service to calculate initial timers for each task
    timers = EscalationTimerService.initializeTaskTimers(tasks);

    // Dispose old controllers
    for (var controller in completionTimeControllers) {
      controller.dispose();
    }

    // Initialize F&B completion time controllers
    completionTimeControllers = List.generate(itemCount, (index) {
      // Pre-fill with existing time if available
      final existingTime = tasks[index]['actual_time_to_close_the_task'];
      return TextEditingController(
          text: existingTime != null ? existingTime.toString() : '');
    });

    // Dispose old timers
    for (var timer in countTimer) {
      timer.cancel();
    }
    countTimer.clear();

    // Initialize timers — skip countdown for escalated / already-expired tasks
    for (int i = 0; i < timers.length; i++) {
      if (_isTaskEscalated(i) || timers[i].inSeconds <= 0) {
        timers[i] = Duration.zero;
        continue;
      }

      countTimer.add(Timer.periodic(Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }

        // Stop if task escalated after a live refresh
        if (i < tasks.length && _isTaskEscalated(i)) {
          setState(() {
            timers[i] = Duration.zero;
          });
          timer.cancel();
          return;
        }

        if (timers[i].inSeconds <= 0) {
          setState(() {
            timers[i] = Duration.zero;
          });
          timer.cancel();
        } else {
          setState(() {
            timers[i] = timers[i] - Duration(seconds: 1);
          });
        }
      }));
    }
  }

  void _updateTaskTimeBoundLocally(int index, int timeInMinutes) {
    if (index < 0 || index >= tasks.length) return;

    final task = tasks[index];
    final service = task['service'];
    if (service is Map<String, dynamic>) {
      service['time_bound_value'] = timeInMinutes;
    } else if (service is Map) {
      service['time_bound_value'] = timeInMinutes;
    } else {
      task['service'] = <String, dynamic>{'time_bound_value': timeInMinutes};
    }

    final Duration? newRemaining =
        EscalationTimerService.calculateRemainingEscalationTime(task);

    setState(() {
      if (newRemaining != null && index < timers.length) {
        timers[index] = newRemaining.isNegative ? Duration.zero : newRemaining;
      }
      if (index < completionTimeControllers.length) {
        completionTimeControllers[index].text = timeInMinutes.toString();
      }
    });
  }

  void _startLiveUpdates() {
    // Cancel any existing timer first
    _stopLiveUpdates();

    print('🔄 ProcessingTaskPage: Starting live updates timer');
    _liveUpdateTimer = Timer.periodic(Duration(seconds: 10), (timer) {
      if (mounted) {
        print(
            '⏰ ProcessingTaskPage: 10-second timer fired - reloading processing tasks');
        _loadProcessingTasks(showLoading: false);
      } else {
        timer.cancel();
      }
    });
  }

  void _stopLiveUpdates() {
    if (_liveUpdateTimer != null) {
      print('🛑 ProcessingTaskPage: Stopping live updates timer');
    }
    _liveUpdateTimer?.cancel();
    _liveUpdateTimer = null;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopLiveUpdates();
    for (final timer in countTimer) {
      timer.cancel();
    }
    for (final controller in completionTimeControllers) {
      controller.dispose();
    }
    // Clean up any remaining loader
    TaskTransitionLoaderController.hide();
    super.dispose();
  }

  String formatTimer(Duration d) {
    if (d.isNegative || d.inSeconds <= 0) {
      return '0 min';
    }

    // Round up partial minutes so 1–59s still shows as 1 min (not 0 min)
    final int totalMinutes = (d.inSeconds + 59) ~/ 60;
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

  String formatTimerInMinutes(Duration d) {
    // If negative or zero, show as 0 minutes
    if (d.isNegative || d.inSeconds <= 0) {
      return '0 minutes';
    }

    final int totalMinutes = d.inMinutes;
    final int seconds = d.inSeconds % 60;

    if (totalMinutes == 0) {
      return '$seconds seconds';
    } else if (seconds == 0) {
      return '$totalMinutes minutes';
    } else {
      return '$totalMinutes:$seconds minutes';
    }
  }

  String? _formatOrderTime(String? time, String? date) {
    if (time == null || date == null) return null;

    try {
      // Parse the time string (format: "10:23:32")
      final timeParts = time.split(':');
      if (timeParts.length >= 2) {
        final hour = int.parse(timeParts[0]);
        final minute = timeParts[1];
        final period = hour >= 12 ? 'pm' : 'am';
        final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);

        return '${displayHour}:${minute}${period}';
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  bool _isTaskEscalated(int index) {
    if (index >= tasks.length) return false;

    final task = tasks[index];
    final String currentStatus = task['status']?.toString() ?? '';
    if (currentStatus == 'Escalated') {
      final String? base = _lastNonEscalationStatusOf(task);
      return base == null || base == 'Processing';
    }

    final timeline = task['time_line'] as List<dynamic>?;
    if (timeline == null || timeline.isEmpty) return false;
    final String lastStatus = timeline.last['status']?.toString() ?? '';
    if (lastStatus != 'Escalated') return false;
    // Handle multiple consecutive escalations by finding the last non-escalation status
    final String? base = _lastNonEscalationStatusOf(task);
    return base == 'Processing';
  }

  String? _lastNonEscalationStatusOf(Map<String, dynamic> task) {
    final List<dynamic>? timeline = task['time_line'] as List<dynamic>?;
    if (timeline == null || timeline.isEmpty) {
      return task['status']?.toString();
    }
    int i = timeline.length - 1;
    while (i >= 0) {
      final String value = timeline[i]['status']?.toString() ?? '';
      if (value != 'Escalated') {
        return value;
      }
      i--;
    }
    return null;
  }

  // Helper method to get the first timeline entry (requested time)
  String? _getRequestedTime(Map<String, dynamic> task) {
    final List<dynamic>? timeline = task['time_line'] as List<dynamic>?;
    if (timeline == null || timeline.isEmpty) return null;

    final firstEntry = timeline.first;
    final String? time = firstEntry['time']?.toString();
    final String? date = firstEntry['date']?.toString();

    return _formatOrderTime(time, date);
  }

  // Helper method to get the processing timeline entry (processing time)
  String? _getProcessingTime(Map<String, dynamic> task) {
    final List<dynamic>? timeline = task['time_line'] as List<dynamic>?;
    if (timeline == null || timeline.isEmpty) return null;

    // Find the processing entry in timeline
    for (final entry in timeline) {
      final String status = entry['status']?.toString() ?? '';
      if (status == 'Processing') {
        final String? time = entry['time']?.toString();
        final String? date = entry['date']?.toString();
        return _formatOrderTime(time, date);
      }
    }
    return null;
  }

  void _safeDisposeController(TextEditingController controller) {
    controller.dispose();
  }

  void _showTaskDetailsModal(BuildContext context, int index) {
    final task = tasks[index];
    final taskId = task['id'];

    // Create a local controller for this dialog that won't be disposed by parent refreshes
    final localCompletionTimeController = TextEditingController(
      text: task['service']['time_bound_value']?.toString() ?? '',
    );

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 420,
              maxHeight: MediaQuery.of(dialogContext).size.height * 0.85,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Container(
                    padding: EdgeInsets.fromLTRB(16, 12, 8, 12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Theme.of(context).colorScheme.primary,
                          Theme.of(context).colorScheme.secondary,
                        ],
                      ),
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(16)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Task Details',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.close, color: Colors.white),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          onPressed: () {
                            // Unfocus before closing
                            FocusScope.of(dialogContext).unfocus();
                            Navigator.pop(dialogContext);
                          },
                        ),
                      ],
                    ),
                  ),
                  // Content
                  Flexible(
                    fit: FlexFit.loose,
                    child: SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(16, 12, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                height: 56,
                                width: 56,
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Center(
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxWidth:
                                          MediaQuery.of(context).size.width * 0.4,
                                    ),
                                    child: ServiceTaskIcon(task: task),
                                  ),
                                ),
                              ),
                              SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      task['service']?['service_name']
                                              ?.toString() ??
                                          'Service',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    if (_isTaskEscalated(index))
                                      Container(
                                        margin: EdgeInsets.only(top: 8),
                                        padding: EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.red,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          'ESCALATED',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 12),
                          _buildInfoRow(
                              'Guest', task['guest_name']?.toString() ?? 'N/A'),
                          _buildInfoRow('Staff',
                              task['assigned_staff_name']?.toString() ?? 'N/A'),
                          _buildInfoRow(
                              'Room', task['room_no']?.toString() ?? 'N/A'),
                          SizedBox(height: 8),
                          if (TaskCardType.isMenuOrderingTask(task)) ...[
                          MenuOrderFoodSection(task: task),
                          // Completion Time Input (menu ordering / food tasks only)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(height: 20),
                              Text(
                                'Completion Time',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                              SizedBox(height: 12),
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.grey[50],
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary
                                        .withOpacity(0.3),
                                    width: 1.5,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller:
                                            localCompletionTimeController,
                                        keyboardType: TextInputType.number,
                                        decoration: InputDecoration(
                                          hintText: 'Enter time',
                                          hintStyle: TextStyle(
                                            color: Colors.grey[400],
                                            fontSize: 14,
                                          ),
                                          border: InputBorder.none,
                                          contentPadding: EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 12,
                                          ),
                                          suffixIcon: Padding(
                                            padding: const EdgeInsets.only(
                                                right: 12),
                                            child: Center(
                                              widthFactor: 1,
                                              child: Text(
                                                'minutes',
                                                style: TextStyle(
                                                  color: Colors.grey[600],
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      margin: EdgeInsets.only(right: 4),
                                      child: Material(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                        borderRadius: BorderRadius.circular(8),
                                        child: InkWell(
                                          onTap: () async {
                                            // Unfocus keyboard first
                                            FocusScope.of(dialogContext)
                                                .unfocus();

                                            // Wait for keyboard to dismiss and UI to settle
                                            await Future.delayed(
                                                Duration(milliseconds: 300));

                                            // Check if dialog is still mounted
                                            if (!dialogContext.mounted) return;

                                            // Get the time from local controller
                                            final timeText =
                                                localCompletionTimeController
                                                    .text
                                                    .trim();

                                            if (timeText.isEmpty) {
                                              if (context.mounted) {
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(
                                                  SnackBar(
                                                    content: Text(
                                                        'Please enter completion time'),
                                                    backgroundColor:
                                                        Colors.orange,
                                                  ),
                                                );
                                              }
                                              return;
                                            }

                                            final timeInMinutes =
                                                int.tryParse(timeText);
                                            if (timeInMinutes == null ||
                                                timeInMinutes <= 0) {
                                              if (context.mounted) {
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(
                                                  SnackBar(
                                                    content: Text(
                                                        'Please enter a valid number'),
                                                    backgroundColor: Colors.red,
                                                  ),
                                                );
                                              }
                                              return;
                                            }

                                            if (taskId is! int) {
                                              if (context.mounted) {
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(
                                                  SnackBar(
                                                      content: Text(
                                                          'Invalid task ID')),
                                                );
                                              }
                                              return;
                                            }

                                            // Update completion time using the local value
                                            try {
                                              final response = await TaskService
                                                  .updateTaskCompletionTime(
                                                taskId: taskId,
                                                completionTimeInMinutes:
                                                    timeInMinutes,
                                                task: task,
                                              );

                                              if (response.statusCode == 200 ||
                                                  response.statusCode == 201) {
                                                final body =
                                                    jsonDecode(response.body);
                                                if (body['success'] == 1) {
                                                  if (dialogContext.mounted) {
                                                    Navigator.pop(
                                                        dialogContext);
                                                  }

                                                  if (mounted) {
                                                    _updateTaskTimeBoundLocally(
                                                        index, timeInMinutes);
                                                  }

                                                  if (context.mounted) {
                                                    ScaffoldMessenger.of(
                                                            context)
                                                        .showSnackBar(
                                                      SnackBar(
                                                        content: Text(
                                                            'Completion time updated successfully'),
                                                        backgroundColor:
                                                            Colors.green,
                                                      ),
                                                    );
                                                  }
                                                } else {
                                                  if (context.mounted) {
                                                    ScaffoldMessenger.of(
                                                            context)
                                                        .showSnackBar(
                                                      SnackBar(
                                                        content: Text(body[
                                                                    'message']
                                                                ?.toString() ??
                                                            'Failed to update'),
                                                        backgroundColor:
                                                            Colors.red,
                                                      ),
                                                    );
                                                  }
                                                }
                                              } else {
                                                if (context.mounted) {
                                                  ScaffoldMessenger.of(context)
                                                      .showSnackBar(
                                                    SnackBar(
                                                      content: Text(
                                                          'Error connecting to server'),
                                                      backgroundColor:
                                                          Colors.red,
                                                    ),
                                                  );
                                                }
                                              }
                                            } catch (e) {
                                              if (context.mounted) {
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(
                                                  SnackBar(
                                                    content: Text('Error: $e'),
                                                    backgroundColor: Colors.red,
                                                  ),
                                                );
                                              }
                                            }
                                          },
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          child: Container(
                                            padding: EdgeInsets.symmetric(
                                              horizontal: 16,
                                              vertical: 12,
                                            ),
                                            child: Icon(
                                              Icons.check,
                                              color: Colors.white,
                                              size: 20,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                        TaskSpecialRequest.section(task),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            ),
          ),
        );
      },
    ).then((_) {
      Future.delayed(Duration(milliseconds: 100), () {
        _safeDisposeController(localCompletionTimeController);
      });
    });
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[600],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;
    return Scaffold(
      body: Column(
        children: [
          Container(
            width: screenWidth,
            height: MediaQuery.of(context).size.height * 0.25,
            color: Color(0xffE9CD3A),
            child: Stack(
              children: [
                appBarContainer(context),
                Positioned(
                  bottom: 10,
                  left: 0,
                  right: 0,
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: Text(
                          'Room no',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      Container(
                        height: MediaQuery.of(context).size.height * 0.031,
                        width: MediaQuery.of(context).size.width * 0.0025,
                        color: Colors.black,
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          'Service',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      Container(
                        height: MediaQuery.of(context).size.height * 0.031,
                        width: MediaQuery.of(context).size.width * 0.0025,
                        color: Colors.black,
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          'Time',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: isLoading
                ? Center(child: CircularProgressIndicator())
                : errorMessage != null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.error_outline,
                                size: 64, color: Colors.grey),
                            SizedBox(
                                height:
                                    MediaQuery.of(context).size.height * 0.02),
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 32),
                              child: Text(
                                errorMessage!,
                                style: TextStyle(
                                    fontSize:
                                        MediaQuery.of(context).size.width *
                                            0.04,
                                    color: Colors.grey),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            SizedBox(
                                height:
                                    MediaQuery.of(context).size.height * 0.02),
                            ElevatedButton(
                              onPressed: () {
                                _loadProcessingTasks(
                                    showLoading:
                                        true); // Show loading on manual retry
                                _startLiveUpdates();
                              },
                              child: Text('Retry'),
                            ),
                          ],
                        ),
                      )
                    : tasks.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.inbox_outlined,
                                    size: 64, color: Colors.grey),
                                SizedBox(
                                    height: MediaQuery.of(context).size.height *
                                        0.02),
                                Text(
                                  'No processing tasks found',
                                  style: TextStyle(
                                      fontSize:
                                          MediaQuery.of(context).size.width *
                                              0.04,
                                      color: Colors.grey),
                                ),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _loadProcessingTasks,
                            child: ListView.builder(
                              padding: EdgeInsets.all(16),
                              itemCount: tasks.length,
                              itemBuilder: (context, index) => Padding(
                                  padding: const EdgeInsets.only(bottom: 16),
                                  child: GestureDetector(
                                    onTap: () {
                                      // Navigate to track task page
                                      final taskId = tasks[index]['id'];
                                      if (taskId is int) {
                                        // Stop live updates before navigating
                                        _stopLiveUpdates();
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) =>
                                                TrackTaskPage(taskId: taskId),
                                          ),
                                        ).then((_) {
                                          // Resume live updates when returning
                                          if (mounted) {
                                            _startLiveUpdates();
                                          }
                                        });
                                      }
                                    },
                                    child: Container(
                                      padding: EdgeInsets.all(1),
                                      decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          gradient: LinearGradient(
                                              colors: _isTaskEscalated(index)
                                                  ? [
                                                      Colors.red.shade100,
                                                      Colors.red.shade50
                                                    ] // Red for escalated
                                                  : [
                                                      Colors.white,
                                                      Colors.white
                                                    ],
                                              begin: Alignment.topCenter,
                                              end: Alignment.bottomCenter),
                                          border: _isTaskEscalated(index)
                                              ? Border.all(
                                                  color: Colors.red,
                                                  width: MediaQuery.of(context)
                                                          .size
                                                          .width *
                                                      0.005)
                                              : null),
                                      child: Container(
                                        decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius: BorderRadius.all(
                                                Radius.circular(10))),
                                        child: Column(
                                          children: [
                                            Container(
                                              // padding: EdgeInsets.symmetric(horizontal: 40),
                                              height: MediaQuery.of(context)
                                                      .size
                                                      .height *
                                                  0.05,
                                              decoration: BoxDecoration(
                                                  color: Color(0xffE09273),
                                                  borderRadius:
                                                      BorderRadius.only(
                                                          topLeft:
                                                              Radius.circular(
                                                                  10),
                                                          topRight:
                                                              Radius.circular(
                                                                  10))),
                                              child: Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment
                                                        .spaceBetween,
                                                children: [
                                                  Expanded(
                                                    flex: 2,
                                                    child: Text(
                                                      'Room No',
                                                      style: TextStyle(
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          color: Colors.black),
                                                      textAlign:
                                                          TextAlign.center,
                                                    ),
                                                  ),
                                                  Expanded(
                                                    flex: 3,
                                                    child: Text(
                                                      'Service',
                                                      style: TextStyle(
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          color: Colors.black),
                                                      textAlign:
                                                          TextAlign.center,
                                                    ),
                                                  ),
                                                  Expanded(
                                                    flex: 2,
                                                    child: Text(
                                                      'Time',
                                                      style: TextStyle(
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          color: Colors.black),
                                                      textAlign:
                                                          TextAlign.center,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Container(
                                              color: Colors.white,
                                              height: MediaQuery.of(context)
                                                      .size
                                                      .height *
                                                  0.087,
                                              child: Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment
                                                        .spaceBetween,
                                                children: [
                                                  Expanded(
                                                    flex: 2,
                                                    child: Text(
                                                      tasks[index]['room_no']
                                                              ?.toString() ??
                                                          'N/A',
                                                      textAlign:
                                                          TextAlign.center,
                                                    ),
                                                  ),
                                                  Container(
                                                    margin:
                                                        EdgeInsets.symmetric(
                                                            vertical: 16),
                                                    height: double.infinity,
                                                    width:
                                                        MediaQuery.of(context)
                                                                .size
                                                                .width *
                                                            0.0025,
                                                    color: Color(0xffE7E7E7),
                                                  ),
                                                  Expanded(
                                                    flex: 3,
                                                    child: Text(
                                                      tasks[index]['service']?[
                                                                  'service_name']
                                                              ?.toString() ??
                                                          'Service',
                                                      textAlign:
                                                          TextAlign.center,
                                                    ),
                                                  ),
                                                  Container(
                                                    margin:
                                                        EdgeInsets.symmetric(
                                                            vertical: 16),
                                                    height: double.infinity,
                                                    width:
                                                        MediaQuery.of(context)
                                                                .size
                                                                .width *
                                                            0.0025,
                                                    color: Color(0xffE7E7E7),
                                                  ),
                                                  Expanded(
                                                    flex: 2,
                                                    child: Column(
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .center,
                                                      children: [
                                                        Text(
                                                          _formatOrderTime(
                                                                  tasks[index][
                                                                      'order_time'],
                                                                  tasks[index][
                                                                      'order_date']) ??
                                                              'N/A',
                                                          textAlign:
                                                              TextAlign.center,
                                                          style: TextStyle(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                              color: Colors.blue
                                                                  .shade700),
                                                        ),
                                                        SizedBox(height: 2),
                                                        Text(
                                                          formatTimer(
                                                              timers[index]),
                                                          textAlign:
                                                              TextAlign.center,
                                                          style: TextStyle(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                              color: Colors
                                                                  .red.shade600,
                                                              fontSize: MediaQuery.of(
                                                                          context)
                                                                      .size
                                                                      .width *
                                                                  0.025),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Container(
                                              margin: EdgeInsets.symmetric(
                                                  horizontal: 16),
                                              height: MediaQuery.of(context)
                                                      .size
                                                      .height *
                                                  0.001,
                                              width: screenWidth,
                                              color: Color(0xffE7E7E7),
                                            ),
                                            // Escalation Timer Section
                                            Container(
                                              margin: EdgeInsets.symmetric(
                                                  horizontal: 16, vertical: 8),
                                              padding: EdgeInsets.symmetric(
                                                  horizontal: 12, vertical: 8),
                                              decoration: BoxDecoration(
                                                color: _isTaskEscalated(index)
                                                    ? Colors.red.shade50
                                                    : Colors.orange.shade50,
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                border: Border.all(
                                                  color: _isTaskEscalated(index)
                                                      ? Colors.red.shade200
                                                      : Colors.orange.shade200,
                                                  width: 1,
                                                ),
                                              ),
                                              child: Column(
                                                children: [
                                                  Row(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .center,
                                                    children: [
                                                      Icon(
                                                        _isTaskEscalated(index)
                                                            ? Icons
                                                                .warning_amber
                                                            : Icons.timer,
                                                        color: _isTaskEscalated(
                                                                index)
                                                            ? Colors
                                                                .red.shade600
                                                            : Colors.orange
                                                                .shade600,
                                                        size: 18,
                                                      ),
                                                      SizedBox(width: 8),
                                                      Text(
                                                        _isTaskEscalated(index)
                                                            ? 'Escalated'
                                                            : 'Escalation Timer: ',
                                                        style: TextStyle(
                                                          fontSize: MediaQuery.of(
                                                                      context)
                                                                  .size
                                                                  .width *
                                                              0.032,
                                                          fontWeight:
                                                              FontWeight.w500,
                                                          color:
                                                              _isTaskEscalated(
                                                                      index)
                                                                  ? Colors.red
                                                                      .shade700
                                                                  : Colors
                                                                      .orange
                                                                      .shade700,
                                                        ),
                                                      ),
                                                      if (!_isTaskEscalated(
                                                          index))
                                                        Text(
                                                          TaskService
                                                              .formatTimerInMinutes(
                                                                  timers[
                                                                      index]),
                                                          style: TextStyle(
                                                            fontSize: MediaQuery.of(
                                                                        context)
                                                                    .size
                                                                    .width *
                                                                0.032,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                            color: Colors
                                                                .red.shade600,
                                                          ),
                                                        ),
                                                    ],
                                                  ),
                                                  if (_isTaskEscalated(
                                                      index)) ...[
                                                    SizedBox(height: 4),
                                                    Text(
                                                      'You can still complete the task',
                                                      textAlign:
                                                          TextAlign.center,
                                                      style: TextStyle(
                                                        fontSize: MediaQuery.of(
                                                                    context)
                                                                .size
                                                                .width *
                                                            0.028,
                                                        fontWeight:
                                                            FontWeight.w500,
                                                        color:
                                                            Colors.red.shade600,
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                            Container(
                                              height: MediaQuery.of(context)
                                                      .size
                                                      .height *
                                                  0.087,
                                              decoration: BoxDecoration(
                                                  color: Colors.white,
                                                  borderRadius:
                                                      BorderRadius.vertical(
                                                          bottom:
                                                              Radius.circular(
                                                                  10))),
                                              child: Row(
                                                children: [
                                                  Expanded(
                                                    child: Container(
                                                      height:
                                                          MediaQuery.of(context)
                                                                  .size
                                                                  .height *
                                                              0.075,
                                                      width: double.infinity,
                                                      child: Padding(
                                                        padding:
                                                            const EdgeInsets
                                                                .only(
                                                                left: 16.0),
                                                        child: Column(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          mainAxisAlignment:
                                                              MainAxisAlignment
                                                                  .center,
                                                          children: [
                                                            Text(
                                                              'Timeline',
                                                              style: TextStyle(
                                                                  fontSize: MediaQuery.of(
                                                                              context)
                                                                          .size
                                                                          .width *
                                                                      0.03),
                                                            ),
                                                            Text(
                                                              screenWidth > 600
                                                                  ? 'Requested at ${_getRequestedTime(tasks[index]) ?? 'N/A'}'
                                                                  : 'Requested at\n${_getRequestedTime(tasks[index]) ?? 'N/A'}',
                                                              style: TextStyle(
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600,
                                                                  color: Colors
                                                                      .black),
                                                            )
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  Container(
                                                    height:
                                                        MediaQuery.of(context)
                                                                .size
                                                                .height *
                                                            0.05,
                                                    width:
                                                        MediaQuery.of(context)
                                                                .size
                                                                .width *
                                                            0.0025,
                                                    color: Color(0xffE7E7E7),
                                                  ),
                                                  Expanded(
                                                    child: Container(
                                                      height:
                                                          MediaQuery.of(context)
                                                                  .size
                                                                  .height *
                                                              0.075,
                                                      width: double.infinity,
                                                      child: Padding(
                                                        padding:
                                                            const EdgeInsets
                                                                .only(
                                                                left: 16.0),
                                                        child: Column(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          mainAxisAlignment:
                                                              MainAxisAlignment
                                                                  .center,
                                                          children: [
                                                            Text(
                                                              'Processing Time ',
                                                              style: TextStyle(
                                                                  fontSize: MediaQuery.of(
                                                                              context)
                                                                          .size
                                                                          .width *
                                                                      0.03),
                                                            ),
                                                            Text(
                                                                screenWidth >
                                                                        600
                                                                    ? 'Processing at ${_getProcessingTime(tasks[index]) ?? 'N/A'}'
                                                                    : 'Processing at\n${_getProcessingTime(tasks[index]) ?? 'N/A'}',
                                                                style: TextStyle(
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w600))
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Container(
                                              margin: EdgeInsets.symmetric(
                                                  horizontal: 16),
                                              height: MediaQuery.of(context)
                                                      .size
                                                      .height *
                                                  0.001,
                                              width: screenWidth,
                                              color: Color(0xffE7E7E7),
                                            ),
                                            Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 16.0,
                                                      vertical: 16),
                                              child: Row(
                                                spacing: 16,
                                                children: [
                                                  Expanded(
                                                      child: Container(
                                                          height: 45,
                                                          decoration: BoxDecoration(
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                          5),
                                                              border: Border.all(
                                                                  color: Theme.of(
                                                                          context)
                                                                      .colorScheme
                                                                      .primary)),
                                                          width:
                                                              double.infinity,
                                                          child: ElevatedButton(
                                                              style: TextButton.styleFrom(
                                                                  backgroundColor:
                                                                      Colors
                                                                          .white,
                                                                  foregroundColor: Theme.of(
                                                                          context)
                                                                      .colorScheme
                                                                      .primary),
                                                              onPressed: () {
                                                                _showTaskDetailsModal(
                                                                    context,
                                                                    index);
                                                              },
                                                              child: Row(
                                                                mainAxisAlignment:
                                                                    MainAxisAlignment
                                                                        .center,
                                                                children: [
                                                                  Text(
                                                                    'View',
                                                                    style: TextStyle(
                                                                        fontWeight:
                                                                            FontWeight.w600),
                                                                  ),
                                                                  SizedBox(
                                                                      width: 8),
                                                                  Icon(
                                                                    Icons
                                                                        .visibility_outlined,
                                                                    size: 20,
                                                                  )
                                                                ],
                                                              )))),
                                                  Expanded(
                                                      child: Container(
                                                          height: 45,
                                                          width:
                                                              double.infinity,
                                                          child: ElevatedButton(
                                                            style:
                                                                ElevatedButton
                                                                    .styleFrom(
                                                              backgroundColor:
                                                                  Theme.of(
                                                                          context)
                                                                      .colorScheme
                                                                      .primary,
                                                              foregroundColor:
                                                                  Colors.white,
                                                              shape:
                                                                  RoundedRectangleBorder(
                                                                borderRadius:
                                                                    BorderRadius
                                                                        .circular(
                                                                            5),
                                                              ),
                                                            ),
                                                            onPressed:
                                                                () async {
                                                              final taskId =
                                                                  tasks[index]
                                                                      ['id'];
                                                              if (taskId
                                                                  is! int) {
                                                                ScaffoldMessenger.of(
                                                                        context)
                                                                    .showSnackBar(
                                                                  SnackBar(
                                                                      content: Text(
                                                                          'Invalid task ID')),
                                                                );
                                                                return;
                                                              }

                                                              // Show loader immediately (only if not already showing)
                                                              if (!TaskTransitionLoaderController
                                                                  .isShowing) {
                                                                TaskTransitionLoaderController
                                                                    .show(
                                                                  context:
                                                                      context,
                                                                  message:
                                                                      'Completing task...',
                                                                );
                                                              }

                                                              try {
                                                                // Get staff details from local storage
                                                                final user = Hive
                                                                        .box(
                                                                            'authBox')
                                                                    .get(
                                                                        'user');
                                                                final int? staffId = (user?[
                                                                            'id']
                                                                        is int)
                                                                    ? user['id']
                                                                        as int
                                                                    : int.tryParse(
                                                                        user?['id']?.toString() ??
                                                                            '');
                                                                final String?
                                                                    staffName =
                                                                    user?['full_name']
                                                                        ?.toString();

                                                                // Get guest_id and staff_desk_id from task
                                                                final int? guestId = tasks[
                                                                                index]
                                                                            [
                                                                            'guest_id']
                                                                        is int
                                                                    ? tasks[index]
                                                                            [
                                                                            'guest_id']
                                                                        as int
                                                                    : int.tryParse(
                                                                        tasks[index]['guest_id']?.toString() ??
                                                                            '');
                                                                final String?
                                                                    staffDeskId =
                                                                    tasks[index]
                                                                            [
                                                                            'staff_desk_id']
                                                                        ?.toString();

                                                                final response =
                                                                    await TaskService
                                                                        .updateCompletedTaskStatus(
                                                                  taskId:
                                                                      taskId,
                                                                  status:
                                                                      'Completed',
                                                                  assignedStaffId:
                                                                      staffId,
                                                                  assignedStaffName:
                                                                      staffName,
                                                                  guestId:
                                                                      guestId,
                                                                  staffDeskId:
                                                                      staffDeskId,
                                                                  department: tasks[index]
                                                                              [
                                                                              'service']
                                                                          ?[
                                                                          'category']
                                                                      ?.toString(),
                                                                );

                                                                // Hide loader
                                                                TaskTransitionLoaderController
                                                                    .hide();

                                                                if (response.statusCode ==
                                                                        200 ||
                                                                    response.statusCode ==
                                                                        201) {
                                                                  final body =
                                                                      jsonDecode(
                                                                          response
                                                                              .body);
                                                                  if (body[
                                                                          'success'] ==
                                                                      1) {
                                                                    // Navigate to Completed tab (index 3)
                                                                    Navigator.of(
                                                                            context)
                                                                        .pushAndRemoveUntil(
                                                                      MaterialPageRoute(
                                                                          builder: (_) =>
                                                                              const NavigationPage(initialIndex: 2)), // Completed (was 3 before Scheduled tab removed)
                                                                      (route) =>
                                                                          false,
                                                                    );
                                                                    // Show success message
                                                                    ScaffoldMessenger.of(
                                                                            context)
                                                                        .showSnackBar(
                                                                      SnackBar(
                                                                        content:
                                                                            Text('Task completed successfully'),
                                                                        backgroundColor:
                                                                            Colors.green,
                                                                      ),
                                                                    );
                                                                  } else {
                                                                    ScaffoldMessenger.of(
                                                                            context)
                                                                        .showSnackBar(
                                                                      SnackBar(
                                                                        content:
                                                                            Text(body['message']?.toString() ??
                                                                                'Failed to complete task'),
                                                                        backgroundColor:
                                                                            Colors.red,
                                                                      ),
                                                                    );
                                                                  }
                                                                } else {
                                                                  ScaffoldMessenger.of(
                                                                          context)
                                                                      .showSnackBar(
                                                                    SnackBar(
                                                                      content: Text(
                                                                          'Error connecting to server'),
                                                                      backgroundColor:
                                                                          Colors
                                                                              .red,
                                                                    ),
                                                                  );
                                                                }
                                                              } catch (e) {
                                                                // Hide loader on error
                                                                TaskTransitionLoaderController
                                                                    .hide();

                                                                ScaffoldMessenger.of(
                                                                        context)
                                                                    .showSnackBar(
                                                                  SnackBar(
                                                                    content: Text(
                                                                        'Error: $e'),
                                                                    backgroundColor:
                                                                        Colors
                                                                            .red,
                                                                  ),
                                                                );
                                                              }
                                                            },
                                                            child: FittedBox(
                                                              fit: BoxFit
                                                                  .scaleDown,
                                                              child: Row(
                                                                mainAxisAlignment:
                                                                    MainAxisAlignment
                                                                        .center,
                                                                children: [
                                                                  Icon(
                                                                      Icons
                                                                          .check_circle_outline,
                                                                      size: 20),
                                                                  SizedBox(
                                                                      width: 8),
                                                                  Text(
                                                                    'Complete Task',
                                                                    style:
                                                                        TextStyle(
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .w600,
                                                                      fontSize: MediaQuery.of(context)
                                                                              .size
                                                                              .width *
                                                                          0.035,
                                                                    ),
                                                                  ),
                                                                ],
                                                              ),
                                                            ),
                                                          )))
                                                ],
                                              ),
                                            )
                                          ],
                                        ),
                                      ),
                                    ),
                                  )),
                            ),
                          ),
          ),
        ],
      ),
      floatingActionButton: const DeskTaskFloatingActions(),
    );
  }
}
