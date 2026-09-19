import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:guestezee_staffs_app/Services/task_service.dart';
import 'package:guestezee_staffs_app/Services/local_storage_service.dart';
import 'package:guestezee_staffs_app/Services/network_error_message.dart';
import 'package:guestezee_staffs_app/Services/staff_service.dart';
import 'package:guestezee_staffs_app/const.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:guestezee_staffs_app/Custom Widgets/fnb_order_details.dart';
import 'package:guestezee_staffs_app/Custom Widgets/task_special_request.dart';
import 'package:guestezee_staffs_app/Screens/login_page.dart';
import 'package:guestezee_staffs_app/Screens/high_priority_tasks_page.dart';
import 'package:guestezee_staffs_app/Screens/settings_page.dart';
import 'package:guestezee_staffs_app/Services/notification_settings_service.dart';
import 'package:guestezee_staffs_app/Screens/track_task_page.dart';
import 'package:guestezee_staffs_app/Services/push_notification_service.dart';
import 'package:guestezee_staffs_app/Services/high_priority_badge_service.dart';
import 'package:guestezee_staffs_app/Services/task_refresh_service.dart';
import 'package:guestezee_staffs_app/Services/manager_level_service.dart';

class EscalatedTasksPage extends StatefulWidget {
  const EscalatedTasksPage({super.key});

  @override
  State<EscalatedTasksPage> createState() => _EscalatedTasksPageState();
}

class _EscalatedTasksPageState extends State<EscalatedTasksPage>
    with WidgetsBindingObserver {
  // API data
  List<Map<String, dynamic>> normalTasks = [];
  bool isLoading = true;
  String? errorMessage;

  // Live update timer
  Timer? _liveUpdateTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HighPriorityBadgeService.init();
    HighPriorityBadgeService.homeListRefreshSignal
        .addListener(_onHomeListRefreshSignal);
    TaskRefreshService.refreshSignal.addListener(_onTaskRefreshPoll);
    ManagerLevelService.refreshFromServer();
    _loadEscalatedTasks(showLoading: true);
    _startLiveUpdates();
  }

  void _onHomeListRefreshSignal() {
    if (!mounted) return;
    _loadEscalatedTasks(showLoading: false);
  }

  void _onTaskRefreshPoll() {
    if (!mounted) return;
    _loadEscalatedTasks(showLoading: false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _stopLiveUpdates();
    } else if (state == AppLifecycleState.resumed) {
      ManagerLevelService.refreshFromServer();
      _loadEscalatedTasks(showLoading: false);
      _startLiveUpdates();
    }
  }

  Future<void> _loadEscalatedTasks({bool showLoading = false}) async {
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
      final int? staffId = (user?['id'] is int)
          ? user['id'] as int
          : int.tryParse(user?['id']?.toString() ?? '');

      if (memberId == null) {
        if (mounted) {
          setState(() {
            errorMessage = 'Member ID not found';
            isLoading = false;
          });
        }
        return;
      }

      if (staffId == null) {
        if (mounted) {
          setState(() {
            errorMessage = 'Staff ID not found';
            isLoading = false;
          });
        }
        return;
      }

      // ═══════════════════════════════════════════════════════════════
      // NORMAL ESCALATED TASKS (Escalated FROM this manager to higher level)
      // ═══════════════════════════════════════════════════════════════
      // Filter: escalated_from_id = logged-in staff id
      List<Map<String, dynamic>> fetchedNormalTasks = [];
      try {
        final normalResponse = await TaskService.getNormalEscalatedTasks(
          memberId: memberId.toString(),
          escalatedFromId: staffId,
        );

        if (normalResponse.statusCode == 200 ||
            normalResponse.statusCode == 201) {
          final data = jsonDecode(normalResponse.body);
          if (data['success'] == 1 && data['result'] != null) {
            final List rawTasks = data['result']['data'] ?? [];
            fetchedNormalTasks =
                rawTasks.map((e) => Map<String, dynamic>.from(e)).toList();
            print(
                '✅ Normal Escalated Tasks loaded: ${fetchedNormalTasks.length}');
          }
        }
      } catch (e) {
        print('❌ Error loading normal escalated tasks: $e');
      }

      if (!mounted) return;

      setState(() {
        normalTasks = fetchedNormalTasks;
        isLoading = false;
        errorMessage = null;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        errorMessage = NetworkErrorMessage.forTaskLoad(e);
        isLoading = false;
      });
    }
  }

  void _startLiveUpdates() {
    _stopLiveUpdates();

    print('🔄 EscalatedTasksPage: Starting live updates timer');
    _liveUpdateTimer = Timer.periodic(Duration(seconds: 10), (timer) {
      if (mounted) {
        print(
            '⏰ EscalatedTasksPage: 10-second timer fired - reloading escalated tasks');
        // Only reload tasks, not lower staff (lower staff IDs don't change frequently)
        _loadEscalatedTasks(showLoading: false);
      } else {
        print('❌ EscalatedTasksPage: Widget not mounted, cancelling timer');
        timer.cancel();
      }
    });
  }

  void _stopLiveUpdates() {
    if (_liveUpdateTimer != null) {
      print('🛑 EscalatedTasksPage: Stopping live updates timer');
    }
    _liveUpdateTimer?.cancel();
    _liveUpdateTimer = null;
  }

  @override
  void dispose() {
    HighPriorityBadgeService.homeListRefreshSignal
        .removeListener(_onHomeListRefreshSignal);
    TaskRefreshService.refreshSignal.removeListener(_onTaskRefreshPoll);
    WidgetsBinding.instance.removeObserver(this);
    _stopLiveUpdates();
    super.dispose();
  }

  String? _formatOrderTime(String? time, String? date) {
    if (time == null || date == null) return null;

    try {
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

  void _showTaskDetailsModal(BuildContext context, int index) {
    final task = normalTasks[index];
    final screenSize = MediaQuery.of(context).size;
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 420,
              maxHeight: MediaQuery.of(dialogContext).size.height * 0.85,
            ),
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
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
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Theme.of(dialogContext).colorScheme.primary,
                          Theme.of(dialogContext).colorScheme.secondary,
                        ],
                      ),
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(16)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Task Details',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          onPressed: () => Navigator.pop(dialogContext),
                        ),
                      ],
                    ),
                  ),
                  // Content
                  Flexible(
                    fit: FlexFit.loose,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                height: 56,
                                width: 56,
                                decoration: BoxDecoration(
                                  color: Theme.of(dialogContext)
                                      .colorScheme
                                      .primary
                                      .withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Center(
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxWidth: screenSize.width * 0.4,
                                    ),
                                    child: Text(
                                      LocalStorageService.hotelName,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Theme.of(dialogContext)
                                            .colorScheme
                                            .primary,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      task['service']?['service_name']
                                              ?.toString() ??
                                          'Service',
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Container(
                                      margin: const EdgeInsets.only(top: 8),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.red,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text(
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
                          const SizedBox(height: 12),
                          _buildInfoRow(
                              'Guest', task['guest_name']?.toString() ?? 'N/A'),
                          _buildInfoRow(
                              'Staff',
                              task['assigned_staff_name']?.toString() ??
                                  'Escalated - Not Assigned'),
                          _buildInfoRow(
                              'Room', task['room_no']?.toString() ?? 'N/A'),
                          const SizedBox(height: 8),
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

  Future<void> _handleLogout() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        contentPadding: const EdgeInsets.only(
          bottom: 10,
          right: 18,
          left: 18,
          top: 18,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        backgroundColor: Colors.white,
        title: Text('Logout'),
        content: Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Logout', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (shouldLogout == true) {
      try {
        // Get current FCM token and remove it on logout
        await LocalStorageService.init();
        final dynamic rawUser = Hive.box('authBox').get('user');
        print(
            'All FCM tokens removed. Sending empty array ${rawUser.toString()}');
        final Map<String, dynamic>? user = rawUser is Map
            ? rawUser.map((key, value) => MapEntry(key.toString(), value))
            : null;
        final String empNo =
            (user?['staff_employee_number'] ?? user?['staff_member_id'] ?? '')
                .toString();
        final dynamic staffIdValue = user?['id'];
        final int? staffDbId = staffIdValue is int
            ? staffIdValue
            : int.tryParse(staffIdValue?.toString() ?? '');
        final dynamic identifierForUpdate =
            staffDbId ?? (empNo.isNotEmpty ? empNo : null);

        if (identifierForUpdate != null && empNo.isNotEmpty) {
          // Get current device FCM token
          final currentFcmToken =
              await PushNotificationService.getDeviceToken();

          if (currentFcmToken != null) {
            try {
              // Get staff details to check existing FCM tokens
              final staffResponse =
                  await StaffService.findStaffByEmployeeNumber(empNo);

              if (staffResponse.statusCode == 200 ||
                  staffResponse.statusCode == 201) {
                final staffData = jsonDecode(staffResponse.body);
                if (staffData['success'] == 1 &&
                    staffData['result'] != null &&
                    staffData['result']['data'] != null) {
                  final List<dynamic> staffList =
                      staffData['result']['data'] ?? [];
                  if (staffList.isNotEmpty) {
                    final staff = staffList[0] as Map<String, dynamic>;
                    final existingFcmTokens = staff['fcm_token'];

                    List<String> fcmTokensList = [];
                    if (existingFcmTokens is List) {
                      fcmTokensList =
                          existingFcmTokens.map((e) => e.toString()).toList();
                    } else if (existingFcmTokens is String) {
                      fcmTokensList = [existingFcmTokens];
                    }

                    // Check if current token exists in the array
                    if (fcmTokensList.contains(currentFcmToken)) {
                      // Remove the current token
                      fcmTokensList.remove(currentFcmToken);
                      print(
                          '🔄 Removing FCM token on logout: $currentFcmToken');

                      // If array is now empty, send empty array
                      // Otherwise, send updated array without the current token
                      var updateResponse;
                      if (fcmTokensList.isEmpty) {
                        print(
                            '📱 All FCM tokens removed. Sending empty array. ${identifierForUpdate.toString()}');
                        updateResponse = await StaffService
                            .updateStaffAvailabilityWithFcmToken(
                                identifierForUpdate, false, []);
                      } else {
                        print('✅ FCM tokens remaining: $fcmTokensList');
                        updateResponse = await StaffService
                            .updateStaffAvailabilityWithFcmToken(
                                identifierForUpdate, false, fcmTokensList);
                      }

                      // Check if update was successful
                      if (updateResponse.statusCode == 200 ||
                          updateResponse.statusCode == 201) {
                        // success flag ignored; logout always proceeds
                      }
                    } else {
                      // Token doesn't exist in array, just update availability
                      print(
                          '⚠️ FCM token not found in array. Updating only is_available.');
                      await StaffService.updateStaffAvailability(
                          identifierForUpdate, false);
                    }
                  } else {
                    // No staff data found, just update availability
                    await StaffService.updateStaffAvailability(
                        identifierForUpdate, false);
                  }
                } else {
                  // API call failed, just update availability
                  await StaffService.updateStaffAvailability(
                      identifierForUpdate, false);
                }
              } else {
                // API call failed, just update availability
                await StaffService.updateStaffAvailability(
                    identifierForUpdate, false);
              }
            } catch (e) {
              // Error in FCM removal, fallback to just update availability
              print('❌ Error removing FCM token: $e');
              await StaffService.updateStaffAvailability(
                  identifierForUpdate, false);
            }
          } else {
            // No FCM token available, just update availability
            print('⚠️ No FCM token available. Updating only is_available.');
            await StaffService.updateStaffAvailability(
                identifierForUpdate, false);
          }
        } else if (identifierForUpdate != null) {
          await StaffService.updateStaffAvailability(
              identifierForUpdate, false);
        }

        // Business rule: never block logout from this screen.
        // Always proceed with local logout, FCM / server updates are best-effort only.
        await PushNotificationService.onUserLoggedOut();
        await LocalStorageService.logout();

        if (mounted) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const LoginPage()),
            (route) => false,
          );
        }
      } catch (e) {
        print('❌ Logout error: $e');

        // Show error message and stay on page
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Logout failed due to error. Please try again.'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    }
  }

  Future<void> _showHighPriorityModal() async {
    await HighPriorityBadgeService.clear();
    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const HighPriorityTasksPage(),
      ),
    );
  }

  Future<void> _handleNotificationButtonTap() async {
    try {
      bool areNotificationsEnabled =
          await NotificationSettingsService.areNotificationsEnabled();

      if (areNotificationsEnabled) {
        // Show snackbar if notifications are already enabled
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.notifications_active, color: Colors.white),
                  SizedBox(width: 8),
                  Text('Notifications are already enabled'),
                ],
              ),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
            ),
          );
        }
      } else {
        // Navigate to settings page for notification settings
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const SettingsPage(),
            ),
          );
        }
      }
    } catch (e) {
      print('❌ Error handling notification button: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Unable to check notification settings. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _navigateToTrackTask(int taskId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TrackTaskPage(taskId: taskId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      body: Column(
        children: [
          // Profile Section
          // Container(
          //   width: screenWidth,
          //   padding: EdgeInsets.only(
          //       top: MediaQuery.of(context).padding.top + 16,
          //       bottom: 16,
          //       left: 16,
          //       right: 16),
          //   decoration: BoxDecoration(
          //     gradient: LinearGradient(
          //       colors: [
          //         Theme.of(context).colorScheme.primary,
          //         Theme.of(context).colorScheme.secondary,
          //       ],
          //       begin: Alignment.topLeft,
          //       end: Alignment.bottomRight,
          //     ),
          //   ),
          //   child: FutureBuilder(
          //     future: LocalStorageService.init(),
          //     builder: (context, snapshot) {
          //       final user = Hive.box('authBox').get('user');
          //       final String staffName =
          //           user?['full_name']?.toString() ?? 'Staff';
          //       final String designation =
          //           LocalStorageService.designation.isNotEmpty
          //               ? LocalStorageService.designation
          //               : 'Staff';
          //       final String hierarchyDisplay =
          //           LocalStorageService.hierarchyDesignationDepartmentDisplay;

          //       return Row(
          //         children: [
          //           CircleAvatar(
          //             radius: 30,
          //             backgroundColor: Colors.white,
          //             child: Icon(Icons.person,
          //                 size: 35,
          //                 color: Theme.of(context).colorScheme.primary),
          //           ),
          //           SizedBox(width: 16),
          //           Expanded(
          //             child: Column(
          //               crossAxisAlignment: CrossAxisAlignment.start,
          //               children: [
          //                 Text(
          //                   staffName,
          //                   style: TextStyle(
          //                     color: Colors.white,
          //                     fontSize: 18,
          //                     fontWeight: FontWeight.bold,
          //                   ),
          //                 ),
          //                 SizedBox(height: 4),
          //                 Text(
          //                   hierarchyDisplay.isNotEmpty
          //                       ? hierarchyDisplay
          //                       : designation,
          //                   style: TextStyle(
          //                     color: Colors.white.withOpacity(0.9),
          //                     fontSize: 14,
          //                   ),
          //                 ),
          //               ],
          //             ),
          //           ),
          //           IconButton(
          //             icon: Icon(Icons.notifications_outlined,
          //                 color: Colors.white),
          //             onPressed: _handleNotificationButtonTap,
          //             tooltip: 'Notification Settings',
          //           ),
          //           SizedBox(width: 8),
          //           IconButton(
          //             icon: Icon(Icons.logout, color: Colors.white),
          //             onPressed: _handleLogout,
          //           ),
          //         ],
          //       );
          //     },
          //   ),
          // ),
          Container(
            width: screenWidth,
            height: MediaQuery.of(context).size.height * 0.25,
            color: Color(0xffE9CD3A),
            child: Stack(
              children: [
                appBarContainer(context, manager: true),
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
                                _loadEscalatedTasks(showLoading: true);
                                _startLiveUpdates();
                              },
                              child: Text('Retry'),
                            ),
                          ],
                        ),
                      )
                    : normalTasks.isEmpty
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
                                  'No escalated tasks found',
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
                            onRefresh: () =>
                                _loadEscalatedTasks(showLoading: false),
                            child: ListView.builder(
                              padding: EdgeInsets.all(16),
                              itemCount: normalTasks.length,
                              itemBuilder: (context, index) => Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: () => _navigateToTrackTask(
                                        normalTasks[index]['id']),
                                    borderRadius: BorderRadius.circular(10),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                          colors: [
                                            Colors.red.shade100,
                                            Colors.red.shade50
                                          ],
                                        ),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                            color: Colors.red, width: 2),
                                      ),
                                      padding: EdgeInsets.all(1),
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        child: Column(
                                          children: [
                                            Container(
                                              height: 70,
                                              child: Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment
                                                        .spaceBetween,
                                                children: [
                                                  Expanded(
                                                    flex: 2,
                                                    child: Text(
                                                      normalTasks[index]
                                                                  ['room_no']
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
                                                    width: 1,
                                                    color: Color(0xffE7E7E7),
                                                  ),
                                                  Expanded(
                                                    flex: 3,
                                                    child: Text(
                                                      normalTasks[index][
                                                                      'service']
                                                                  ?[
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
                                                    width: 1,
                                                    color: Color(0xffE7E7E7),
                                                  ),
                                                  Expanded(
                                                    flex: 2,
                                                    child: Text(
                                                      _formatOrderTime(
                                                              normalTasks[index]
                                                                  [
                                                                  'order_time'],
                                                              normalTasks[index]
                                                                  [
                                                                  'order_date']) ??
                                                          'N/A',
                                                      textAlign:
                                                          TextAlign.center,
                                                      style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color: Colors.black,
                                                      ),
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
                                                                      size: 20),
                                                                ],
                                                              )))),
                                                  Expanded(
                                                      child: Container(
                                                          height: 45,
                                                          width:
                                                              double.infinity,
                                                          child: ElevatedButton(
                                                              style: TextButton
                                                                  .styleFrom(
                                                                backgroundColor:
                                                                    Colors.blue
                                                                        .shade600,
                                                              ),
                                                              onPressed: () =>
                                                                  _navigateToTrackTask(
                                                                      normalTasks[
                                                                              index]
                                                                          [
                                                                          'id']),
                                                              child: Row(
                                                                mainAxisAlignment:
                                                                    MainAxisAlignment
                                                                        .center,
                                                                children: [
                                                                  Icon(
                                                                      Icons
                                                                          .timeline,
                                                                      size: 18,
                                                                      color: Colors
                                                                          .white),
                                                                  SizedBox(
                                                                      width: 8),
                                                                  FittedBox(
                                                                    fit: BoxFit
                                                                        .scaleDown,
                                                                    child: Text(
                                                                      'Track Task',
                                                                      style:
                                                                          TextStyle(
                                                                        fontWeight:
                                                                            FontWeight.w600,
                                                                        color: Colors
                                                                            .white,
                                                                      ),
                                                                      softWrap:
                                                                          false,
                                                                      overflow:
                                                                          TextOverflow
                                                                              .visible,
                                                                    ),
                                                                  ),
                                                                ],
                                                              ))))
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
                          ),
          )
        ],
      ),
      floatingActionButton: Container(
        margin: EdgeInsets.only(bottom: 16, right: 8),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Material(
              elevation: 6,
              borderRadius: BorderRadius.circular(12),
              color: Colors.orange,
              child: InkWell(
                onTap: _showHighPriorityModal,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.priority_high,
                        color: Colors.white,
                        size: 24,
                      ),
                      SizedBox(width: 10),
                      Text(
                        'High Priority',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Unread escalation badge (notification-style, not in-page task count)
            ValueListenableBuilder<int>(
              valueListenable: HighPriorityBadgeService.count,
              builder: (context, badgeCount, _) {
                if (badgeCount <= 0) return const SizedBox.shrink();
                return Positioned(
                  top: -8,
                  right: -8,
                  child: Container(
                    padding: EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    constraints: BoxConstraints(
                      minWidth: 24,
                      minHeight: 24,
                    ),
                    child: Center(
                      child: Text(
                        badgeCount > 99 ? '99+' : badgeCount.toString(),
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }
}
