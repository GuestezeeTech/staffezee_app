import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:guestezee_staffs_app/Services/task_service.dart';
import 'package:guestezee_staffs_app/Services/local_storage_service.dart';
import 'package:guestezee_staffs_app/Services/network_error_message.dart';
import 'package:guestezee_staffs_app/Custom Widgets/task_special_request.dart';
import 'package:guestezee_staffs_app/Custom Widgets/fnb_order_details.dart';
import 'package:guestezee_staffs_app/Custom Widgets/task_card_type.dart';
import 'package:guestezee_staffs_app/Screens/track_task_page.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class HighPriorityTasksPage extends StatefulWidget {
  const HighPriorityTasksPage({super.key});

  @override
  State<HighPriorityTasksPage> createState() => _HighPriorityTasksPageState();
}

class _HighPriorityTasksPageState extends State<HighPriorityTasksPage> {
  List<Map<String, dynamic>> highPriorityTasks = [];
  bool isLoading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    _loadHighPriorityTasks(showLoading: true);
  }

  Future<void> _loadHighPriorityTasks({bool showLoading = false}) async {
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
      final userId = user?['id'];

      if (memberId == null) {
        if (mounted) {
          setState(() {
            errorMessage = 'Member ID not found';
            isLoading = false;
          });
        }
        return;
      }

      if (userId == null) {
        if (mounted) {
          setState(() {
            errorMessage = 'User ID not found';
            isLoading = false;
          });
        }
        return;
      }

      // Call API with: member_id, escalated_to_id, status: "Escalated"
      final response = await TaskService.getHighPriorityEscalatedTasks(
        memberId: memberId.toString(),
        escalatedToId: userId is int ? userId : int.parse(userId.toString()),
      );

      if (!mounted) return;

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        if (data['success'] == 1 && data['result'] != null) {
          final List rawTasks = data['result']['data'] ?? [];
          final tasks =
              rawTasks.map((e) => Map<String, dynamic>.from(e)).toList();

          setState(() {
            highPriorityTasks = tasks;
            isLoading = false;
            errorMessage = null;
          });
          print('✅ High Priority Tasks loaded: ${tasks.length}');
        } else {
          setState(() {
            highPriorityTasks = [];
            isLoading = false;
            errorMessage = null;
          });
        }
      } else {
        setState(() {
          errorMessage = 'Error loading tasks';
          isLoading = false;
        });
      }
    } catch (e) {
      print('❌ Error loading high priority tasks: $e');
      if (mounted) {
        setState(() {
          errorMessage = NetworkErrorMessage.forTaskLoad(e);
          isLoading = false;
        });
      }
    }
  }

  String? _formatOrderTime(String? time, String? date) {
    if (time == null || date == null) return null;
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

  void _showTaskDetailsModal(BuildContext context, Map<String, dynamic> task) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 420,
              maxHeight: MediaQuery.of(context).size.height * 0.85,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Container(
                    padding: EdgeInsets.fromLTRB(16, 12, 8, 12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade600,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(16),
                        topRight: Radius.circular(16),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.priority_high,
                            color: Colors.white, size: 28),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'High Priority Task Details',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
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
                  // Content
                  Flexible(
                    fit: FlexFit.loose,
                    child: SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(16, 12, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildInfoRow(
                            icon: Icons.tag,
                            label: 'Task ID',
                            value: task['id']?.toString() ?? 'N/A',
                          ),
                          SizedBox(height: 12),
                          // Room and Guest Info
                          _buildInfoRow(
                            icon: Icons.room_service,
                            label: 'Room Number',
                            value: task['room_no']?.toString() ?? 'N/A',
                          ),
                          SizedBox(height: 12),
                          _buildInfoRow(
                            icon: Icons.person,
                            label: 'Guest Name',
                            value: task['guest_name']?.toString() ?? 'N/A',
                          ),
                          SizedBox(height: 12),
                          _buildInfoRow(
                            icon: Icons.phone,
                            label: 'Phone Number',
                            value: task['phone_number']?.toString() ?? 'N/A',
                          ),
                          Divider(height: 24),
                          // Service Info
                          _buildInfoRow(
                            icon: Icons.dining,
                            label: 'Service',
                            value:
                                task['service']?['service_name']?.toString() ??
                                    'N/A',
                          ),
                          SizedBox(height: 12),
                          _buildInfoRow(
                            icon: Icons.label_outline,
                            label: 'Type',
                            value: TaskCardType.isMenuOrderingTask(task)
                                ? 'Menu Ordering'
                                : (TaskCardType.serviceBelongsTo(task) ??
                                    task['service']?['category']?.toString() ??
                                    'N/A'),
                          ),
                          MenuOrderFoodSection(task: task),
                          TaskSpecialRequest.section(task,
                              withTopSpacing: true),
                          Divider(height: 24),
                          // Time Info
                          _buildInfoRow(
                            icon: Icons.access_time,
                            label: 'Order Time',
                            value: _formatOrderTime(
                                    task['order_time'], task['order_date']) ??
                                'N/A',
                          ),
                          SizedBox(height: 12),
                          _buildInfoRow(
                            icon: Icons.calendar_today,
                            label: 'Order Date',
                            value: task['order_date']?.toString() ?? 'N/A',
                          ),
                          SizedBox(height: 12),
                          _buildInfoRow(
                            icon: Icons.info_outline,
                            label: 'Status',
                            value: task['status']?.toString() ?? 'N/A',
                            valueColor: Colors.red.shade600,
                          ),
                          // Timeline
                          // if (task['time_line'] != null &&
                          //     task['time_line'] is List &&
                          //     (task['time_line'] as List).isNotEmpty) ...[
                          //   Divider(height: 24),
                          //   Text(
                          //     'Timeline:',
                          //     style: TextStyle(
                          //       fontWeight: FontWeight.bold,
                          //       fontSize: 16,
                          //       color: Colors.grey[800],
                          //     ),
                          //   ),
                          //   SizedBox(height: 12),
                          //   ...(task['time_line'] as List).map((timeline) {
                          //     return Padding(
                          //       padding: const EdgeInsets.only(bottom: 12),
                          //       child: Container(
                          //         padding: EdgeInsets.all(12),
                          //         decoration: BoxDecoration(
                          //           color: Colors.grey[50],
                          //           borderRadius: BorderRadius.circular(8),
                          //           border: Border.all(color: Colors.grey[300]!),
                          //         ),
                          //         child: Column(
                          //           crossAxisAlignment: CrossAxisAlignment.start,
                          //           children: [
                          //             Row(
                          //               children: [
                          //                 Icon(Icons.circle,
                          //                     size: 8, color: Colors.red),
                          //                 SizedBox(width: 8),
                          //                 Text(
                          //                   timeline['status']?.toString() ??
                          //                       'Status',
                          //                   style: TextStyle(
                          //                     fontWeight: FontWeight.bold,
                          //                     fontSize: 14,
                          //                   ),
                          //                 ),
                          //               ],
                          //             ),
                          //             SizedBox(height: 4),
                          //             Row(
                          //               children: [
                          //                 Icon(Icons.access_time,
                          //                     size: 14, color: Colors.grey),
                          //                 SizedBox(width: 4),
                          //                 Text(
                          //                   '${timeline['date']} ${timeline['time']}',
                          //                   style: TextStyle(
                          //                     fontSize: 12,
                          //                     color: Colors.grey[600],
                          //                   ),
                          //                 ),
                          //               ],
                          //             ),
                          //             if (timeline['escalated_from_name'] !=
                          //                 null) ...[
                          //               SizedBox(height: 4),
                          //               Text(
                          //                 'From: ${timeline['escalated_from_name']}',
                          //                 style: TextStyle(
                          //                   fontSize: 12,
                          //                   color: Colors.grey[600],
                          //                 ),
                          //               ),
                          //             ],
                          //             if (timeline['escalated_to_name'] !=
                          //                 null) ...[
                          //               Text(
                          //                 'To: ${timeline['escalated_to_name']}',
                          //                 style: TextStyle(
                          //                   fontSize: 12,
                          //                   color: Colors.grey[600],
                          //                 ),
                          //               ),
                          //             ],
                          //             if (timeline['remark'] != null &&
                          //                 timeline['remark']
                          //                     .toString()
                          //                     .isNotEmpty) ...[
                          //               SizedBox(height: 4),
                          //               Text(
                          //                 'Remark: ${timeline['remark']}',
                          //                 style: TextStyle(
                          //                   fontSize: 12,
                          //                   color: Colors.orange[700],
                          //                   fontStyle: FontStyle.italic,
                          //                 ),
                          //               ),
                          //             ],
                          //           ],
                          //         ),
                          //       ),
                          //     );
                          //   }).toList(),
                          // ],
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

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
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
                  color: valueColor ?? Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showNotifyFrontDeskDialog(BuildContext context) {
    // Front desk contact number - you can make this configurable
    const String frontDeskNumber = '+1234567890'; // Replace with actual number

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade100,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.phone,
                    size: 48,
                    color: Colors.orange.shade700,
                  ),
                ),
                SizedBox(height: 20),
                Text(
                  'Notify Front Desk',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 12),
                Text(
                  'Call the front desk to urgently address this high priority task',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
                SizedBox(height: 20),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.phone, color: Colors.grey[700], size: 20),
                      SizedBox(width: 8),
                      Text(
                        frontDeskNumber,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          padding: EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text('Cancel'),
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          Navigator.pop(context);
                          final uri = Uri.parse('tel:$frontDeskNumber');
                          try {
                            await launchUrl(
                              uri,
                              mode: LaunchMode.externalApplication,
                            );
                          } catch (e) {
                            print('❌ Error launching phone dialer: $e');
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Unable to open phone dialer'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          padding: EdgeInsets.symmetric(vertical: 14),
                          backgroundColor: Colors.orange.shade600,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.phone, size: 18),
                            SizedBox(width: 8),
                            Text(
                              'Call Now',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      appBar: AppBar(
        title: const Text('High Priority Tasks'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, size: 64, color: Colors.grey),
                      SizedBox(
                          height: MediaQuery.of(context).size.height * 0.02),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 32),
                        child: Text(
                          errorMessage!,
                          style: TextStyle(
                              fontSize:
                                  MediaQuery.of(context).size.width * 0.04,
                              color: Colors.grey),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      SizedBox(
                          height: MediaQuery.of(context).size.height * 0.02),
                      ElevatedButton(
                        onPressed: () {
                          _loadHighPriorityTasks(showLoading: true);
                        },
                        child: Text('Retry'),
                      ),
                    ],
                  ),
                )
              : highPriorityTasks.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.inbox_outlined,
                              size: 64, color: Colors.grey),
                          SizedBox(height: 16),
                          Text(
                            'No high priority tasks',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: () =>
                          _loadHighPriorityTasks(showLoading: false),
                      child: ListView.builder(
                        padding: EdgeInsets.all(16),
                        itemCount: highPriorityTasks.length,
                        itemBuilder: (context, index) {
                          final task = highPriorityTasks[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 16),
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
                                border: Border.all(color: Colors.red, width: 2),
                              ),
                              padding: EdgeInsets.all(1),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Column(
                                  children: [
                                    // Header Row
                                    Container(
                                      height: 70,
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            flex: 2,
                                            child: Text(
                                              task['room_no']?.toString() ??
                                                  'N/A',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16,
                                              ),
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
                                              task['service']?['service_name']
                                                      ?.toString() ??
                                                  'Service',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(fontSize: 14),
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
                                              _formatOrderTime(
                                                      task['order_time'],
                                                      task['order_date']) ??
                                                  'N/A',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: Colors.black,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      margin:
                                          EdgeInsets.symmetric(horizontal: 16),
                                      height: 1,
                                      width: screenWidth,
                                      color: Color(0xffE7E7E7),
                                    ),
                                    // Guest Name & Notify Front Desk
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12.0, vertical: 8.0),
                                      child: Row(
                                        children: [
                                          Icon(Icons.person,
                                              size: 18, color: Colors.grey),
                                          SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              task['guest_name']?.toString() ??
                                                  'Guest',
                                              style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                          SizedBox(width: 8),
                                          Container(
                                            decoration: BoxDecoration(
                                              color: Colors.orange.shade50,
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Material(
                                              color: Colors.transparent,
                                              child: InkWell(
                                                onTap: () =>
                                                    _showNotifyFrontDeskDialog(
                                                        context),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                child: Padding(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 12,
                                                      vertical: 8),
                                                  child: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      Icon(Icons.phone,
                                                          size: 16,
                                                          color: Colors
                                                              .orange.shade700),
                                                      SizedBox(width: 6),
                                                      Text(
                                                        'Notify',
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          color: Colors
                                                              .orange.shade700,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    // Action Buttons
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16.0, vertical: 16),
                                      child: Row(
                                        spacing: 16,
                                        children: [
                                          Expanded(
                                            child: Container(
                                              height: 45,
                                              child: ElevatedButton(
                                                style: TextButton.styleFrom(
                                                  backgroundColor: Colors.white,
                                                  foregroundColor:
                                                      Theme.of(context)
                                                          .colorScheme
                                                          .primary,
                                                ),
                                                onPressed: () {
                                                  _showTaskDetailsModal(
                                                      context, task);
                                                },
                                                child: Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  children: [
                                                    Text(
                                                      'View',
                                                      style: TextStyle(
                                                          fontWeight:
                                                              FontWeight.w600),
                                                    ),
                                                    SizedBox(width: 8),
                                                    Icon(
                                                        Icons
                                                            .visibility_outlined,
                                                        size: 20),
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
                                                      Colors.blue.shade600,
                                                ),
                                                onPressed: () {
                                                  Navigator.push(
                                                    context,
                                                    MaterialPageRoute(
                                                      builder: (context) =>
                                                          TrackTaskPage(
                                                        taskId: task['id'],
                                                      ),
                                                    ),
                                                  );
                                                },
                                                child: Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  children: [
                                                    Icon(Icons.timeline,
                                                        size: 18,
                                                        color: Colors.white),
                                                    SizedBox(width: 8),
                                                    FittedBox(
                                                      fit: BoxFit.scaleDown,
                                                      child: Text(
                                                        'Track Task',
                                                        style: TextStyle(
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          color: Colors.white,
                                                        ),
                                                        softWrap: false,
                                                        overflow: TextOverflow
                                                            .visible,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
