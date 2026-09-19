import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:guestezee_staffs_app/app_theme.dart';
import 'package:guestezee_staffs_app/const.dart';
import 'package:guestezee_staffs_app/Services/task_service.dart';
import 'package:guestezee_staffs_app/Services/task_refresh_service.dart';
import 'package:guestezee_staffs_app/Services/local_storage_service.dart';
import 'package:guestezee_staffs_app/Services/staff_service.dart';
import 'package:guestezee_staffs_app/Services/network_error_message.dart';
import 'package:guestezee_staffs_app/Services/escalation_timer_service.dart';
import 'package:guestezee_staffs_app/Services/continuous_sound_service.dart';
import 'package:guestezee_staffs_app/Services/Notifictaion%20service/alarm_service.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:guestezee_staffs_app/Custom Widgets/navigation_page.dart';
import 'package:guestezee_staffs_app/Custom Widgets/fnb_order_details.dart';
import 'package:guestezee_staffs_app/Custom Widgets/task_special_request.dart';
import 'package:guestezee_staffs_app/Custom Widgets/task_transition_loader.dart';
import 'package:guestezee_staffs_app/Screens/track_task_page.dart';
import 'package:guestezee_staffs_app/Custom Widgets/desk_task_floating_actions.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  // API data
  List<Map<String, dynamic>> tasks = [];
  bool isLoading = true;
  String? errorMessage;

  // Timer and UI state
  List<bool> start = [];
  List<Duration> timers = [];
  List<Timer> countTimers = [];
  List<Duration> timerForAccept = [];
  List<Timer> countTimerForAccept = [];
  List<DateTime> dateTime = [];
  List<bool> turnTimerRed = [];
  List<bool> didNotAccept = [];
  List<bool> acceptButton = [];

  bool get _canAcceptAssigned =>
      StaffService.canAcceptAssignedTasks(LocalStorageService.user);

  // Live update timer
  Timer? _liveUpdateTimer;

  String _hotelName = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    TaskRefreshService.refreshSignal.addListener(_onTaskRefreshPoll);
    _loadAssignedTasks(showLoading: true);
    _fetchHotelNameFromCustomerApi();
    _startLiveUpdates();
  }

  void _onTaskRefreshPoll() {
    if (mounted) _loadAssignedTasks(showLoading: false);
  }

  Future<void> _fetchHotelNameFromCustomerApi() async {
    try {
      await LocalStorageService.init();
      final hotelName =
          await LocalStorageService.fetchHotelNameFromCustomerApi();
      if (!mounted) return;
      if (hotelName != null && hotelName.isNotEmpty) {
        setState(() => _hotelName = hotelName);
      }
    } catch (_) {}
  }

  String get _displayHotelName {
    if (_hotelName.isNotEmpty) return _hotelName;
    return LocalStorageService.hotelName;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _stopLiveUpdates();
    } else if (state == AppLifecycleState.resumed && mounted) {
      _loadAssignedTasks(showLoading: false);
      _startLiveUpdates();

      // Removed: forceStopAllSounds() - sound should persist until Accept

      // On Android, start continuous sound for any pending Assigned tasks
      // (on iOS, AlarmService handles continuous alarm instead).
      if (Platform.isAndroid) {
        _startContinuousSoundForAssignedTasks();

        // Also check for any tasks that might have been assigned while app was in background
        // This ensures continuous sound starts even if notification came while app was backgrounded
        _checkAndStartContinuousSoundForBackgroundTasks();
      }
    }
  }

  Future<void> _loadAssignedTasks({bool showLoading = false}) async {
    if (!mounted) return;

    if (showLoading) {
      setState(() {
        isLoading = true;
        errorMessage = null;
      });
    } else {
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

      final response = await TaskService.getAssignedTasks(
          memberId.toString(), assignedStaffId);

      if (!mounted) return;

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        if (data['success'] == 1 && data['result'] != null) {
          final List<dynamic> taskList = data['result']['data'] ?? [];
          final List<Map<String, dynamic>> normalized =
              taskList.cast<Map<String, dynamic>>().where((t) {
            final String current = t['status']?.toString() ?? '';
            if (current == 'Escalated') {
              final String? base = _lastNonEscalationStatusOf(t);
              return base == 'Assigned';
            }
            return true;
          }).toList();
          setState(() {
            tasks = normalized;
            _initializeTaskStates();
            isLoading = false;
            errorMessage = null;
          });

          // Stop sounds for escalated tasks
          _stopSoundsForEscalatedTasks();

          // Start continuous sound for assigned tasks only on Android.
          if (Platform.isAndroid) {
            _startContinuousSoundForAssignedTasks();
          }
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
    dateTime = List.generate(itemCount, (_) => DateTime.now());
    start = List.generate(itemCount, (_) => false);
    turnTimerRed = List.generate(itemCount, (_) => false);
    didNotAccept = List.generate(itemCount, (_) => false);
    acceptButton = List.generate(itemCount, (_) => true);

    timerForAccept = EscalationTimerService.initializeTaskTimers(tasks);
    timers = List.generate(itemCount, (i) => timerForAccept[i]);

    for (int i = 0; i < tasks.length; i++) {
      if (_isTaskEscalated(i)) {
        turnTimerRed[i] = true;
      }
    }

    for (var timer in countTimerForAccept) {
      timer.cancel();
    }
    countTimerForAccept.clear();

    for (var timer in countTimers) {
      timer.cancel();
    }
    countTimers.clear();

    for (int i = 0; i < timerForAccept.length; i++) {
      countTimerForAccept.add(Timer.periodic(Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }

        if (timerForAccept[i].inSeconds <= 0) {
          setState(() {
            turnTimerRed[i] = true;
          });
          timer.cancel();
        } else {
          setState(() {
            timerForAccept[i] = timerForAccept[i] - Duration(seconds: 1);
          });
        }
      }));
    }
  }

  bool _isTaskEscalated(int index) {
    if (index >= tasks.length) return false;

    final task = tasks[index];
    final timeline = task['time_line'] as List<dynamic>?;
    if (timeline == null || timeline.isEmpty) return false;
    final String lastStatus = timeline.last['status']?.toString() ?? '';
    if (lastStatus != 'Escalated') return false;
    final String? base = _lastNonEscalationStatusOf(task);
    return base == 'Assigned';
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

  String? _getAssignedTime(Map<String, dynamic> task) {
    final List<dynamic>? timeline = task['time_line'] as List<dynamic>?;
    if (timeline == null || timeline.isEmpty) return null;

    String? lastAssignedTime;
    DateTime? lastAssignedDateTime;

    for (final entry in timeline) {
      final String status = entry['status']?.toString() ?? '';
      if (status == 'Assigned') {
        final String? time = entry['time']?.toString();
        final String? date = entry['date']?.toString();

        if (time != null && date != null) {
          try {
            final timeParts = time.split(':');
            if (timeParts.length >= 2) {
              final hour = int.parse(timeParts[0]);
              final minute = timeParts[1];
              final period = hour >= 12 ? 'pm' : 'am';
              final displayHour =
                  hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);

              final String formattedTime = '${displayHour}:${minute}${period}';

              final DateTime assignmentDateTime = DateTime.parse('$date $time');

              if (lastAssignedDateTime == null ||
                  assignmentDateTime.isAfter(lastAssignedDateTime)) {
                lastAssignedTime = formattedTime;
                lastAssignedDateTime = assignmentDateTime;
              }
            }
          } catch (e) {
            return null;
          }
        }
      }
    }
    return lastAssignedTime;
  }

  void startTimer(int index) {
    if (start[index]) return;

    setState(() {
      start[index] = true;
    });

    countTimers.add(Timer.periodic(Duration(seconds: 1), (timer) {
      if (timers[index].inSeconds <= 1) {
        timer.cancel();
        setState(() {
          // Timer completed
        });
      } else {
        setState(() {
          timers[index] = timers[index] - Duration(seconds: 1);
        });
      }
    }));
  }

  Future<void> _stopSoundsForEscalatedTasks() async {
    // Get list of currently playing tasks
    final List<int> playingTasks = ContinuousSoundService.getPlayingTasks();

    // Check which tasks are now escalated and stop their sounds
    for (int taskId in playingTasks) {
      // Find the task in our current tasks list
      final task = tasks.firstWhere(
        (t) => t['id'] == taskId,
        orElse: () => <String, dynamic>{},
      );

      // If task is escalated or not assigned, stop its sound
      if (task.isNotEmpty) {
        final String currentStatus =
            task['status']?.toString().toUpperCase() ?? '';
        if (currentStatus == 'ESCALATED' ||
            currentStatus == 'PROCESSING' ||
            currentStatus == 'COMPLETED') {
          print(
              '🔊 Stopping sound/alarm for task $taskId (status: $currentStatus)');
          ContinuousSoundService.stopTaskSound(taskId);
          await AlarmService.stopAlarmForTask(taskId);
        }
      }
    }
  }

  void _startContinuousSoundForAssignedTasks() {
    print('🔊 Starting continuous sound for assigned tasks');

    // Check if we have any assigned tasks
    if (tasks.isNotEmpty) {
      for (var task in tasks) {
        final String status = task['status']?.toString().toUpperCase() ?? '';
        final int? taskId = task['id'];

        if (status == 'ASSIGNED' && taskId != null) {
          print('🔊 Starting continuous sound for assigned task $taskId');
          ContinuousSoundService.startTaskSound(taskId);
        }
      }
    } else {
      print('🔊 No tasks loaded yet, will start sounds after tasks are loaded');
    }
  }

  void _checkAndStartContinuousSoundForBackgroundTasks() {
    print('🔊 Checking for background tasks that need continuous sound');

    // This method will be called when app becomes active
    // It will check if there are any assigned tasks that need continuous sound
    // The _loadAssignedTasks method will be called first, so tasks should be loaded
    if (tasks.isNotEmpty) {
      for (var task in tasks) {
        final String status = task['status']?.toString().toUpperCase() ?? '';
        final int? taskId = task['id'];

        if (status == 'ASSIGNED' && taskId != null) {
          // Check if sound is already playing for this task
          if (!ContinuousSoundService.isSoundPlaying(taskId)) {
            print(
                '🔊 Starting continuous sound for background assigned task $taskId');
            ContinuousSoundService.startTaskSound(taskId);
          }
        }
      }
    }
  }

  void _startLiveUpdates() {
    _stopLiveUpdates();

    print('🔄 HomeScreen: Starting live updates timer');
    _liveUpdateTimer = Timer.periodic(Duration(seconds: 10), (timer) {
      if (mounted) {
        print('⏰ HomeScreen: 10-second timer fired - reloading assigned tasks');
        _loadAssignedTasks(showLoading: false);
      } else {
        timer.cancel();
      }
    });
  }

  void _stopLiveUpdates() {
    if (_liveUpdateTimer != null) {
      print('🛑 HomeScreen: Stopping live updates timer');
    }
    _liveUpdateTimer?.cancel();
    _liveUpdateTimer = null;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    TaskRefreshService.refreshSignal.removeListener(_onTaskRefreshPoll);
    _stopLiveUpdates();
    for (var timer in countTimers) {
      timer.cancel();
    }
    for (var timer in countTimerForAccept) {
      timer.cancel();
    }
    // Clean up any remaining loader
    TaskTransitionLoaderController.hide();
    super.dispose();
  }

  String formatTimer(Duration d) {
    if (d.isNegative || d.inSeconds <= 0) {
      return '00:00';
    }

    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return '${twoDigits(d.inMinutes.remainder(60))}:${twoDigits(d.inSeconds.remainder(60))}';
  }

  void _showTaskDetailsModal(BuildContext context, int index) {
    final task = tasks[index];
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 420,
              maxHeight: MediaQuery.of(context).size.height * 0.85,
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
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
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
                                    child: Text(
                                      _displayHotelName,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                      ),
                                    ),
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
                          MenuOrderFoodSection(task: task),
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
    );
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
      // floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      // floatingActionButton: SafeArea(
      //   top: false,
      //   child: Row(
      //     mainAxisAlignment: MainAxisAlignment.center,
      //     children: [
      //       FloatingActionButton.extended(
      //         onPressed: () {
      //           print('🔊 Testing continuous sound...');
      //           ContinuousSoundService.testContinuousSound();
      //         },
      //         backgroundColor: Colors.blue,
      //         icon: Icon(Icons.volume_up, color: Colors.white, size: 20),
      //         label: Text(
      //           'Test Sound',
      //           style:
      //               TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
      //         ),
      //       ),
      //       SizedBox(width: 10),
      //       FloatingActionButton.extended(
      //         onPressed: () {
      //           print('🔊 Stopping all sounds...');
      //           ContinuousSoundService.stopAllSounds();
      //         },
      //         backgroundColor: Colors.red,
      //         icon: Icon(Icons.volume_off, color: Colors.white, size: 20),
      //         label: Text(
      //           'Stop Sound',
      //           style:
      //               TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
      //         ),
      //       ),
      //     ],
      //   ),
      // ),
      body: Column(
        children: [
          Container(
            width: screenWidth,
            height: MediaQuery.of(context).size.height * 0.25,
            color: Color(0xffE9CD3A),
            child: Stack(
              children: [
                appBarContainer(
                  context,
                  hotelName: _displayHotelName,
                ),
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
                                _loadAssignedTasks(showLoading: true);
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
                                  'No assigned tasks found',
                                  style: TextStyle(
                                      fontSize:
                                          MediaQuery.of(context).size.width *
                                              0.04,
                                      color: Colors.grey),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
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
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: _isTaskEscalated(index)
                                          ? [
                                              Colors.red.shade100,
                                              Colors.red.shade50
                                            ]
                                          : [Colors.white, Colors.white],
                                    ),
                                    borderRadius: BorderRadius.circular(10),
                                    border: _isTaskEscalated(index)
                                        ? Border.all(
                                            color: Colors.red, width: 2)
                                        : null,
                                  ),
                                  padding: EdgeInsets.all(1),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Column(
                                      children: [
                                        Container(
                                          height: 70,
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Expanded(
                                                flex: 2,
                                                child: Text(
                                                  tasks[index]['room_no']
                                                          ?.toString() ??
                                                      'N/A',
                                                  textAlign: TextAlign.center,
                                                ),
                                              ),
                                              Container(
                                                margin: EdgeInsets.symmetric(
                                                    vertical: 16),
                                                height: double.infinity,
                                                width: 1,
                                                color: Color(0xffE7E7E7),
                                              ),
                                              Expanded(
                                                flex: 3,
                                                child: Text(
                                                  tasks[index]['service']
                                                              ?['service_name']
                                                          ?.toString() ??
                                                      'Service',
                                                  textAlign: TextAlign.center,
                                                ),
                                              ),
                                              Container(
                                                margin: EdgeInsets.symmetric(
                                                    vertical: 16),
                                                height: double.infinity,
                                                width: 1,
                                                color: Color(0xffE7E7E7),
                                              ),
                                              Expanded(
                                                flex: 2,
                                                child: Text(
                                                  start[index]
                                                      ? DateFormat('hh:mm a')
                                                          .format(
                                                              dateTime[index])
                                                      : didNotAccept[index]
                                                          ? DateFormat(
                                                                  'hh:mm a')
                                                              .format(dateTime[
                                                                  index])
                                                          : _getAssignedTime(
                                                                  tasks[
                                                                      index]) ??
                                                              'N/A',
                                                  textAlign: TextAlign.center,
                                                  style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: Colors.black),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Container(
                                          margin: EdgeInsets.symmetric(
                                              horizontal: 16),
                                          height: 1,
                                          width: screenWidth,
                                          color: Color(0xffE7E7E7),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 16.0, vertical: 16),
                                          child: Row(
                                            spacing: 16,
                                            children: [
                                              Expanded(
                                                child: Container(
                                                  height: 45,
                                                  decoration: BoxDecoration(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            5),
                                                    border: Border.all(
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .primary,
                                                    ),
                                                  ),
                                                  width: double.infinity,
                                                  child: ElevatedButton(
                                                    style: TextButton.styleFrom(
                                                      backgroundColor:
                                                          Colors.white,
                                                      foregroundColor:
                                                          Theme.of(context)
                                                              .colorScheme
                                                              .primary,
                                                    ),
                                                    onPressed: () {
                                                      _showTaskDetailsModal(
                                                          context, index);
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
                                                                FontWeight.w600,
                                                          ),
                                                        ),
                                                        SizedBox(width: 8),
                                                        Icon(
                                                          Icons
                                                              .visibility_outlined,
                                                          size: 20,
                                                        )
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              Expanded(
                                                child: Container(
                                                  height: 45,
                                                  width: double.infinity,
                                                  child: ElevatedButton(
                                                    style: TextButton.styleFrom(
                                                      backgroundColor:
                                                          _isTaskEscalated(
                                                                  index)
                                                              ? Color(
                                                                  0xffA7A7A7)
                                                              : start[index]
                                                                  ? Color(
                                                                      0xffC58827)
                                                                  : Theme.of(
                                                                          context)
                                                                      .colorScheme
                                                                      .primary,
                                                    ),
                                                    onPressed:
                                                        _isTaskEscalated(
                                                                    index) ||
                                                                !_canAcceptAssigned
                                                            ? null
                                                            : acceptButton[
                                                                    index]
                                                                ? () async {
                                                                    final taskId =
                                                                        tasks[index]
                                                                            [
                                                                            'id'];
                                                                    if (taskId
                                                                        is! int) {
                                                                      ScaffoldMessenger.of(
                                                                              context)
                                                                          .showSnackBar(
                                                                        SnackBar(
                                                                            content:
                                                                                Text('Invalid task id')),
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
                                                                            'Accepting task...',
                                                                      );
                                                                    }

                                                                    setState(
                                                                        () {
                                                                      acceptButton[
                                                                              index] =
                                                                          false;
                                                                    });

                                                                    try {
                                                                      final user =
                                                                          Hive.box('authBox')
                                                                              .get('user');
                                                                      final int?
                                                                          staffId =
                                                                          (user?['id'] is int)
                                                                              ? user['id'] as int
                                                                              : int.tryParse(user?['id']?.toString() ?? '');
                                                                      final String?
                                                                          staffName =
                                                                          user?['full_name']
                                                                              ?.toString();

                                                                      // Get guest_id and staff_desk_id from task
                                                                      final int?
                                                                          guestId =
                                                                          tasks[index]['guest_id'] is int
                                                                              ? tasks[index]['guest_id'] as int
                                                                              : int.tryParse(tasks[index]['guest_id']?.toString() ?? '');
                                                                      final String?
                                                                          staffDeskId =
                                                                          tasks[index]['staff_desk_id']
                                                                              ?.toString();

                                                                      final resp =
                                                                          await TaskService
                                                                              .updateTaskStatus(
                                                                        service:
                                                                            tasks[index]['service'] ??
                                                                                {},
                                                                        taskId:
                                                                            taskId,
                                                                        status:
                                                                            'Processing',
                                                                        assignedStaffId:
                                                                            staffId,
                                                                        assignedStaffName:
                                                                            staffName,
                                                                        guestId:
                                                                            guestId,
                                                                        staffDeskId:
                                                                            staffDeskId,
                                                                        department:
                                                                            tasks[index]['service']?['category']?.toString(),
                                                                      );

                                                                      // Hide loader
                                                                      TaskTransitionLoaderController
                                                                          .hide();

                                                                      if (resp.statusCode ==
                                                                              200 ||
                                                                          resp.statusCode ==
                                                                              201) {
                                                                        final body =
                                                                            jsonDecode(resp.body);
                                                                        if (body['success'] ==
                                                                            1) {
                                                                          // Stop continuous sound for this specific task only
                                                                          await ContinuousSoundService.stopTaskSound(
                                                                              taskId);
                                                                          await AlarmService.stopAlarmForTask(
                                                                              taskId);

                                                                          Navigator.of(context)
                                                                              .pushAndRemoveUntil(
                                                                            MaterialPageRoute(builder: (_) => const NavigationPage(initialIndex: 1)),
                                                                            (route) =>
                                                                                false,
                                                                          );
                                                                        } else {
                                                                          ScaffoldMessenger.of(context)
                                                                              .showSnackBar(
                                                                            SnackBar(content: Text(body['message']?.toString() ?? 'Failed to accept task')),
                                                                          );
                                                                          setState(
                                                                              () {
                                                                            acceptButton[index] =
                                                                                true;
                                                                          });
                                                                        }
                                                                      } else {
                                                                        ScaffoldMessenger.of(context)
                                                                            .showSnackBar(
                                                                          SnackBar(
                                                                              content: Text('Error connecting to server')),
                                                                        );
                                                                        setState(
                                                                            () {
                                                                          acceptButton[index] =
                                                                              true;
                                                                        });
                                                                      }
                                                                    } catch (e) {
                                                                      // Hide loader on error
                                                                      TaskTransitionLoaderController
                                                                          .hide();

                                                                      ScaffoldMessenger.of(
                                                                              context)
                                                                          .showSnackBar(
                                                                        SnackBar(
                                                                            content:
                                                                                Text('Error: $e')),
                                                                      );
                                                                      setState(
                                                                          () {
                                                                        acceptButton[index] =
                                                                            true;
                                                                      });
                                                                    }
                                                                  }
                                                                : () {
                                                                    showModalBottomSheet(
                                                                      backgroundColor: AppTheme
                                                                          .colorScheme
                                                                          .surface,
                                                                      isScrollControlled:
                                                                          true,
                                                                      context:
                                                                          context,
                                                                      builder:
                                                                          (BuildContext
                                                                              context) {
                                                                        return StatefulBuilder(
                                                                          builder:
                                                                              (context, setModalState) {
                                                                            return Padding(
                                                                              padding: EdgeInsets.only(
                                                                                bottom: MediaQuery.of(context).viewInsets.bottom,
                                                                              ),
                                                                              child: Container(
                                                                                width: screenWidth,
                                                                                child: Padding(
                                                                                  padding: const EdgeInsets.symmetric(
                                                                                    vertical: 32,
                                                                                    horizontal: 16,
                                                                                  ),
                                                                                  child: Column(
                                                                                    mainAxisSize: MainAxisSize.min,
                                                                                    children: [
                                                                                      Image.asset(
                                                                                        'assets/images/otpphone.png',
                                                                                        scale: 2,
                                                                                      ),
                                                                                      Text(
                                                                                        'Make Sure you completed\nyour Task',
                                                                                        textAlign: TextAlign.center,
                                                                                        style: TextStyle(
                                                                                          fontSize: 24,
                                                                                          fontWeight: FontWeight.bold,
                                                                                        ),
                                                                                      ),
                                                                                      SizedBox(height: 24),
                                                                                      Container(
                                                                                        width: screenWidth,
                                                                                        height: 45,
                                                                                        child: ElevatedButton(
                                                                                          onPressed: () {
                                                                                            Navigator.pop(context);
                                                                                          },
                                                                                          child: Text('Yes'),
                                                                                        ),
                                                                                      ),
                                                                                      SizedBox(height: 12),
                                                                                      Container(
                                                                                        width: screenWidth,
                                                                                        height: 45,
                                                                                        decoration: BoxDecoration(
                                                                                          borderRadius: BorderRadius.all(Radius.circular(5)),
                                                                                          border: Border.all(color: Theme.of(context).colorScheme.primary),
                                                                                        ),
                                                                                        child: ElevatedButton(
                                                                                          style: TextButton.styleFrom(
                                                                                            backgroundColor: AppTheme.colorScheme.surface,
                                                                                            foregroundColor: Theme.of(context).colorScheme.primary,
                                                                                          ),
                                                                                          onPressed: () {
                                                                                            Navigator.pop(context);
                                                                                          },
                                                                                          child: Text('No'),
                                                                                        ),
                                                                                      )
                                                                                    ],
                                                                                  ),
                                                                                ),
                                                                              ),
                                                                            );
                                                                          },
                                                                        );
                                                                      },
                                                                    );
                                                                  },
                                                    child: FittedBox(
                                                      fit: BoxFit.scaleDown,
                                                      child: Text(
                                                        _isTaskEscalated(index)
                                                            ? 'Escalated'
                                                            : !_canAcceptAssigned
                                                                ? (tasks[index]['status']
                                                                        ?.toString() ??
                                                                    'Assigned')
                                                                : start[index]
                                                                    ? formatTimer(
                                                                        timers[
                                                                            index])
                                                                    : 'Accept (${formatTimer(timerForAccept[index])})',
                                                        style: TextStyle(
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          color:
                                                              _isTaskEscalated(
                                                                      index)
                                                                  ? Colors.white
                                                                  : null,
                                                        ),
                                                        softWrap: false,
                                                        overflow: TextOverflow
                                                            .visible,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        )
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
          ),
        ],
      ),
      floatingActionButton: const DeskTaskFloatingActions(),
    );
  }
}
