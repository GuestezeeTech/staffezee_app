import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:guestezee_staffs_app/const.dart';
import 'package:guestezee_staffs_app/Services/task_service.dart';
import 'package:guestezee_staffs_app/Services/local_storage_service.dart';
import 'package:guestezee_staffs_app/Services/network_error_message.dart';
import 'package:guestezee_staffs_app/Services/escalation_timer_service.dart';
import 'package:guestezee_staffs_app/Custom%20Widgets/fnb_order_details.dart';
import 'package:guestezee_staffs_app/Custom%20Widgets/task_special_request.dart';
import 'package:guestezee_staffs_app/Custom%20Widgets/desk_task_floating_actions.dart';
import 'package:hive_flutter/hive_flutter.dart';

class ScheduledTaskPage extends ConsumerStatefulWidget {
  const ScheduledTaskPage({super.key});

  @override
  ConsumerState<ScheduledTaskPage> createState() => _ScheduledTaskPageState();
}

class _ScheduledTaskPageState extends ConsumerState<ScheduledTaskPage> {
  // API data
  List<Map<String, dynamic>> tasks = [];
  bool isLoading = true;
  String? errorMessage;

  // Timer and UI state
  List<Duration> timers = [];
  List<Timer> countTimer = [];
  List<bool> viewDropdown = [];

  // Live update timer for API polling
  Timer? _liveUpdateTimer;

  @override
  void initState() {
    super.initState();
    _loadScheduledTasks(showLoading: true);
    _startLiveUpdates();
  }

  Future<void> _loadScheduledTasks({bool showLoading = true}) async {
    try {
      if (showLoading) {
        setState(() {
          isLoading = true;
          errorMessage = null;
        });
      }

      await LocalStorageService.init();
      final user = Hive.box('authBox').get('user');
      final memberId = user?['member_id'] ?? user?['staff_member_id'];
      final int? assignedStaffId = (user?['id'] is int)
          ? user['id'] as int
          : int.tryParse(user?['id']?.toString() ?? '');

      if (memberId == null || assignedStaffId == null) {
        setState(() {
          errorMessage = 'Member ID or Staff ID not found';
          isLoading = false;
        });
        return;
      }

      final response = await TaskService.getScheduledTasks(
          memberId.toString(), assignedStaffId);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        if (data['success'] == 1 && data['result'] != null) {
          final List<dynamic> taskList = data['result']['data'] ?? [];
          if (mounted) {
            setState(() {
              tasks = taskList.cast<Map<String, dynamic>>();
              _initializeTaskStates();
              isLoading = false;
            });
          }
        } else {
          if (mounted) {
            setState(() {
              errorMessage = data['message'] ?? 'Failed to load tasks';
              isLoading = false;
            });
          }
        }
      } else {
        if (mounted) {
          setState(() {
            errorMessage = 'Error connecting to server';
            isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          errorMessage = NetworkErrorMessage.forTaskLoad(e);
          isLoading = false;
        });
      }
    }
  }

  void _initializeTaskStates() {
    int itemCount = tasks.length;
    viewDropdown = List.generate(itemCount, (_) => false);

    // Use escalation timer service to calculate initial timers for each task
    timers = EscalationTimerService.initializeTaskTimers(tasks);

    // Dispose old timers
    for (var timer in countTimer) {
      timer.cancel();
    }
    countTimer.clear();

    // Initialize timers
    for (int i = 0; i < timers.length; i++) {
      countTimer.add(Timer.periodic(Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }

        if (timers[i].inSeconds <= 0) {
          setState(() {
            // Timer has reached zero - task is escalated
            timer.cancel();
          });
        } else {
          setState(() {
            timers[i] = timers[i] - Duration(seconds: 1);
          });
        }
      }));
    }
  }

  // Start live API updates (polling every 10 seconds)
  void _startLiveUpdates() {
    _stopLiveUpdates();

    print('🔄 ScheduledTaskPage: Starting live updates timer');
    _liveUpdateTimer = Timer.periodic(Duration(seconds: 10), (timer) {
      if (mounted) {
        print(
            '⏰ ScheduledTaskPage: 10-second timer fired - reloading scheduled tasks');
        _loadScheduledTasks(showLoading: false);
      } else {
        timer.cancel();
      }
    });
  }

  // Stop live API updates
  void _stopLiveUpdates() {
    if (_liveUpdateTimer != null) {
      print('🛑 ScheduledTaskPage: Stopping live updates timer');
    }
    _liveUpdateTimer?.cancel();
    _liveUpdateTimer = null;
  }

  @override
  void dispose() {
    print('🗑️ ScheduledTaskPage: Disposing widget');
    _stopLiveUpdates(); // Stop API polling
    // Stop countdown timers
    for (final timer in countTimer) {
      timer.cancel();
    }
    super.dispose();
  }

  String formatTimer(Duration d) {
    // If negative or zero, show as 00:00
    if (d.isNegative || d.inSeconds <= 0) {
      return '00:00 m';
    }

    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return '${twoDigits(d.inHours.remainder(24))}:${twoDigits(d.inMinutes.remainder(60))} m';
  }

  String? _formatOrderTime(String? time, String? date) {
    if (time == null || date == null) return null;

    try {
      // Parse the time string (format: "10:52:30")
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

  String? _formatScheduledTime(String? time, String? date) {
    if (time == null || date == null) return null;

    try {
      // Parse the scheduled time string (format: "16:53:00")
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

  // Helper method to get the first timeline entry (requested time)
  String? _getRequestedTime(Map<String, dynamic> task) {
    final List<dynamic>? timeline = task['time_line'] as List<dynamic>?;
    if (timeline == null || timeline.isEmpty) return null;

    final firstEntry = timeline.first;
    final String? time = firstEntry['time']?.toString();
    final String? date = firstEntry['date']?.toString();

    return _formatOrderTime(time, date);
  }

  // Helper method to get the scheduled timeline entry (scheduled time)
  String? _getScheduledTime(Map<String, dynamic> task) {
    final List<dynamic>? timeline = task['time_line'] as List<dynamic>?;
    if (timeline == null || timeline.isEmpty) return null;

    // Find the scheduled entry in timeline (could be "Scheduled" or "ASAP")
    for (final entry in timeline) {
      final String status = entry['status']?.toString() ?? '';
      if (status == 'Scheduled' || status == 'ASAP') {
        final String? time = entry['time']?.toString();
        final String? date = entry['date']?.toString();
        return _formatOrderTime(time, date);
      }
    }
    // If no scheduled entry found, return the first entry
    final firstEntry = timeline.first;
    final String? time = firstEntry['time']?.toString();
    final String? date = firstEntry['date']?.toString();
    return _formatOrderTime(time, date);
  }

  @override
  Widget build(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;
    return Scaffold(
      body: Column(
        children: [
          appBarContainer(context),
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
                            Text(
                              errorMessage!,
                              style: TextStyle(
                                  fontSize:
                                      MediaQuery.of(context).size.width * 0.04,
                                  color: Colors.grey),
                              textAlign: TextAlign.center,
                            ),
                            SizedBox(
                                height:
                                    MediaQuery.of(context).size.height * 0.02),
                            ElevatedButton(
                              onPressed: _loadScheduledTasks,
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
                                Icon(Icons.schedule_outlined,
                                    size: 64, color: Colors.grey),
                                SizedBox(
                                    height: MediaQuery.of(context).size.height *
                                        0.02),
                                Text(
                                  'No scheduled tasks found',
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
                            onRefresh: _loadScheduledTasks,
                            child: ListView.builder(
                                padding: EdgeInsets.all(16),
                                itemCount: tasks.length,
                                itemBuilder: (context, index) => Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 16),
                                      child: Container(
                                        padding: EdgeInsets.all(1),
                                        decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(
                                                12), // More rounded corners
                                            gradient: LinearGradient(
                                                colors: viewDropdown[index]
                                                    ? [
                                                        Colors.blue.shade400,
                                                        Colors.blue.shade300
                                                      ]
                                                    : [
                                                        Colors.blue.shade50,
                                                        Colors.white
                                                      ], // Different color scheme
                                                begin: Alignment.topLeft,
                                                end: Alignment.bottomRight),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.blue
                                                    .withOpacity(0.1),
                                                spreadRadius: 1,
                                                blurRadius: 4,
                                                offset: Offset(0, 2),
                                              ),
                                            ]),
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
                                                            topLeft: Radius
                                                                .circular(10),
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
                                                            color:
                                                                Colors.black),
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
                                                            color:
                                                                Colors.black),
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
                                                            color:
                                                                Colors.black),
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
                                                        style: TextStyle(
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          color: Colors
                                                              .blue.shade700,
                                                        ),
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
                                                        tasks[index]['service']
                                                                    ?[
                                                                    'service_name']
                                                                ?.toString() ??
                                                            'Service',
                                                        textAlign:
                                                            TextAlign.center,
                                                        style: TextStyle(
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          color: Colors
                                                              .blue.shade700,
                                                        ),
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
                                                            'Scheduled',
                                                            style: TextStyle(
                                                              fontSize: MediaQuery.of(
                                                                          context)
                                                                      .size
                                                                      .width *
                                                                  0.03,
                                                              color: Colors
                                                                  .grey[600],
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w500,
                                                            ),
                                                          ),
                                                          Text(
                                                            formatTimer(
                                                                timers[index]),
                                                            textAlign: TextAlign
                                                                .center,
                                                            style: TextStyle(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                              color: Colors.blue
                                                                  .shade700,
                                                              fontSize: MediaQuery.of(
                                                                          context)
                                                                      .size
                                                                      .width *
                                                                  0.04,
                                                            ),
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
                                                        height: MediaQuery.of(
                                                                    context)
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
                                                                    fontSize: MediaQuery.of(context)
                                                                            .size
                                                                            .width *
                                                                        0.03),
                                                              ),
                                                              Text(
                                                                'Requested at ${_getRequestedTime(tasks[index]) ?? 'N/A'}',
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
                                                        height: MediaQuery.of(
                                                                    context)
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
                                                                'Delivery time',
                                                                style: TextStyle(
                                                                    fontSize: MediaQuery.of(context)
                                                                            .size
                                                                            .width *
                                                                        0.03),
                                                              ),
                                                              Text(
                                                                  'Scheduled at ${_getScheduledTime(tasks[index]) ?? 'N/A'}',
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
                                              AnimatedCrossFade(
                                                firstChild: SizedBox.shrink(),
                                                secondChild: Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                          left: 16.0,
                                                          right: 16,
                                                          top: 16),
                                                  child: Column(
                                                    children: [
                                                      Row(
                                                        children: [
                                                          Container(
                                                            height:
                                                                screenWidth / 5,
                                                            width:
                                                                screenWidth / 5,
                                                            decoration:
                                                                BoxDecoration(
                                                              color: Theme.of(
                                                                      context)
                                                                  .colorScheme
                                                                  .primary
                                                                  .withOpacity(
                                                                      0.1),
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                          12),
                                                            ),
                                                            child: Center(
                                                              child:
                                                                  ConstrainedBox(
                                                                constraints:
                                                                    BoxConstraints(
                                                                  maxWidth:
                                                                      screenWidth *
                                                                          0.35,
                                                                ),
                                                                child: Text(
                                                                  LocalStorageService
                                                                      .hotelName,
                                                                  maxLines: 2,
                                                                  overflow:
                                                                      TextOverflow
                                                                          .ellipsis,
                                                                  textAlign:
                                                                      TextAlign
                                                                          .center,
                                                                  style:
                                                                      TextStyle(
                                                                    color: Theme.of(
                                                                            context)
                                                                        .colorScheme
                                                                        .primary,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w700,
                                                                    fontSize:
                                                                        18,
                                                                  ),
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                          SizedBox(width: 15),
                                                          Column(
                                                            spacing: 6,
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment
                                                                    .start,
                                                            children: [
                                                              Text(
                                                                tasks[index]['service']
                                                                            ?[
                                                                            'service_name']
                                                                        ?.toString() ??
                                                                    'Service',
                                                                style: TextStyle(
                                                                    fontSize:
                                                                        20,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w600,
                                                                    color: Colors
                                                                        .blue
                                                                        .shade700),
                                                              ),
                                                              if (TaskSpecialRequest
                                                                      .text(tasks[
                                                                          index]) !=
                                                                  null)
                                                                Text(
                                                                  TaskSpecialRequest
                                                                      .text(tasks[
                                                                          index])!,
                                                                  style:
                                                                      TextStyle(
                                                                    color: Colors
                                                                            .grey[
                                                                        600],
                                                                  ),
                                                                ),
                                                              Text(
                                                                '   ',
                                                                style:
                                                                    TextStyle(
                                                                  fontSize: 15,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600,
                                                                  color: Colors
                                                                      .blue
                                                                      .shade600,
                                                                ),
                                                              ),
                                                              SizedBox(
                                                                  height: 8),
                                                              Container(
                                                                padding: EdgeInsets
                                                                    .symmetric(
                                                                        horizontal:
                                                                            12,
                                                                        vertical:
                                                                            6),
                                                                decoration:
                                                                    BoxDecoration(
                                                                  color: Colors
                                                                      .blue
                                                                      .shade100,
                                                                  borderRadius:
                                                                      BorderRadius
                                                                          .circular(
                                                                              20),
                                                                  border: Border.all(
                                                                      color: Colors
                                                                          .blue
                                                                          .shade300),
                                                                ),
                                                                child: Row(
                                                                  mainAxisSize:
                                                                      MainAxisSize
                                                                          .min,
                                                                  children: [
                                                                    Icon(
                                                                        Icons
                                                                            .schedule,
                                                                        size:
                                                                            16,
                                                                        color: Colors
                                                                            .blue
                                                                            .shade700),
                                                                    SizedBox(
                                                                        width:
                                                                            4),
                                                                    Text(
                                                                      'Scheduled for ${_formatScheduledTime(tasks[index]['scheduled_time'], tasks[index]['scheduled_date']) ?? 'N/A'}',
                                                                      style:
                                                                          TextStyle(
                                                                        fontSize:
                                                                            MediaQuery.of(context).size.width *
                                                                                0.03,
                                                                        fontWeight:
                                                                            FontWeight.w600,
                                                                        color: Colors
                                                                            .blue
                                                                            .shade700,
                                                                      ),
                                                                    ),
                                                                  ],
                                                                ),
                                                              ),
                                                              SizedBox(
                                                                  height: 4),
                                                              Text(
                                                                'Guest: ${tasks[index]['guest_name']?.toString() ?? 'N/A'}',
                                                                style:
                                                                    TextStyle(
                                                                  fontSize: MediaQuery.of(
                                                                              context)
                                                                          .size
                                                                          .width *
                                                                      0.03,
                                                                  color: Colors
                                                                          .grey[
                                                                      600],
                                                                ),
                                                              ),
                                                              Text(
                                                                'Ordered: ${_formatOrderTime(tasks[index]['order_time'], tasks[index]['order_date']) ?? 'N/A'}',
                                                                style:
                                                                    TextStyle(
                                                                  fontSize: MediaQuery.of(
                                                                              context)
                                                                          .size
                                                                          .width *
                                                                      0.03,
                                                                  color: Colors
                                                                          .grey[
                                                                      600],
                                                                ),
                                                              ),
                                                            ],
                                                          )
                                                        ],
                                                      ),
                                                      MenuOrderFoodSection(
                                                          task: tasks[index]),

                                                      TaskSpecialRequest
                                                          .section(
                                                              tasks[index]),
                                                    ],
                                                  ),
                                                ),
                                                crossFadeState: viewDropdown[
                                                        index]
                                                    ? CrossFadeState.showSecond
                                                    : CrossFadeState.showFirst,
                                                duration:
                                                    Duration(milliseconds: 300),
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
                                                                    color: Theme.of(context)
                                                                        .colorScheme
                                                                        .primary)),
                                                            width:
                                                                double.infinity,
                                                            child:
                                                                ElevatedButton(
                                                                    style: TextButton.styleFrom(
                                                                        backgroundColor:
                                                                            Colors
                                                                                .white,
                                                                        foregroundColor: Theme.of(context)
                                                                            .colorScheme
                                                                            .primary),
                                                                    onPressed:
                                                                        () {
                                                                      setState(
                                                                          () {
                                                                        viewDropdown[index] =
                                                                            !viewDropdown[index];
                                                                      });
                                                                    },
                                                                    child: Row(
                                                                      mainAxisAlignment:
                                                                          MainAxisAlignment
                                                                              .center,
                                                                      children: [
                                                                        Text(
                                                                          'View',
                                                                          style:
                                                                              TextStyle(fontWeight: FontWeight.w600),
                                                                        ),
                                                                        Icon(
                                                                          viewDropdown[index]
                                                                              ? Icons.keyboard_arrow_up
                                                                              : Icons.keyboard_arrow_down,
                                                                          size:
                                                                              25,
                                                                        )
                                                                      ],
                                                                    )))),
                                                    Expanded(
                                                        child: Container(
                                                            height: 45,
                                                            width:
                                                                double.infinity,
                                                            child:
                                                                ElevatedButton(
                                                                    style: TextButton.styleFrom(
                                                                        backgroundColor:
                                                                            Color(
                                                                                0xffA7A7A7)),
                                                                    onPressed:
                                                                        null,
                                                                    child: Text(
                                                                      'Accept Order',
                                                                      style: TextStyle(
                                                                          color: Colors
                                                                              .white,
                                                                          fontWeight:
                                                                              FontWeight.w600),
                                                                    ))))
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
        ],
      ),
      floatingActionButton: const DeskTaskFloatingActions(),
    );
  }
}
