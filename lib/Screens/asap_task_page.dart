import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:guestezee_staffs_app/const.dart';
import 'package:guestezee_staffs_app/Custom%20Widgets/fnb_order_details.dart';
import 'package:guestezee_staffs_app/Custom%20Widgets/service_task_icon.dart';
import 'package:guestezee_staffs_app/Custom%20Widgets/task_special_request.dart';
import 'package:guestezee_staffs_app/Screens/track_task_page.dart';
import 'package:guestezee_staffs_app/Services/customer_service.dart';
import 'package:guestezee_staffs_app/Services/local_storage_service.dart';
import 'package:guestezee_staffs_app/Services/network_error_message.dart';
import 'package:guestezee_staffs_app/Services/staff_service.dart';
import 'package:guestezee_staffs_app/Services/task_service.dart';

/// Desk-only ASAP / Assigned board filtered by hotel room range + staff departments.
class AsapTaskPage extends StatefulWidget {
  const AsapTaskPage({super.key});

  @override
  State<AsapTaskPage> createState() => _AsapTaskPageState();
}

class _AsapTaskPageState extends State<AsapTaskPage>
    with WidgetsBindingObserver {
  List<Map<String, dynamic>> tasks = [];
  bool isLoading = true;
  String? errorMessage;

  Timer? _loopTimer;
  bool _refreshInFlight = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadTasks();
    _startLoop();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopLoop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _loadTasks(showLoading: false);
      _startLoop();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _stopLoop();
    }
  }

  void _startLoop() {
    _stopLoop();
    // Loop: staff getall → customer getall → task getall while ASAP tab is visible.
    _loopTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!mounted) return;
      _loadTasks(showLoading: false);
    });
  }

  void _stopLoop() {
    _loopTimer?.cancel();
    _loopTimer = null;
  }

  List<String> _departmentsFromUser(Map<String, dynamic>? user) {
    final entries = StaffService.hierarchyEntriesFrom(user?['hierarchy']);
    final Set<String> departments = {};
    for (final entry in entries) {
      final dept = entry['department']?.toString().trim() ?? '';
      if (dept.isNotEmpty) departments.add(dept);
    }
    return departments.toList();
  }

  Future<void> _loadTasks({bool showLoading = true}) async {
    if (!mounted) return;
    if (_refreshInFlight && !showLoading) return;
    _refreshInFlight = true;

    if (showLoading) {
      setState(() {
        isLoading = true;
        errorMessage = null;
      });
    }

    try {
      await LocalStorageService.init();
      final cachedUser = LocalStorageService.user;
      final empNo =
          (cachedUser?['staff_employee_number'] ?? '').toString().trim();
      if (empNo.isEmpty) {
        setState(() {
          errorMessage = 'Staff employee number not found';
          isLoading = false;
        });
        return;
      }

      // 1) Staff getall — fresh at_desk + hierarchy departments
      final staffResp = await StaffService.findStaffByEmployeeNumber(empNo);
      if (staffResp.statusCode != 200 && staffResp.statusCode != 201) {
        setState(() {
          errorMessage = 'Unable to load staff';
          isLoading = false;
        });
        return;
      }

      final staffBody = jsonDecode(staffResp.body);
      final List staffList =
          (staffBody is Map && staffBody['result']?['data'] is List)
              ? List.from(staffBody['result']['data'] as List)
              : <dynamic>[];
      if (staffList.isEmpty) {
        setState(() {
          errorMessage = 'Staff not found';
          isLoading = false;
          tasks = [];
        });
        return;
      }

      final staff = Map<String, dynamic>.from(staffList.first as Map);
      await LocalStorageService.mergeLoggedInUser(staff);
      StaffService.notifyRoleChanged();
      if (!StaffService.isAtDeskStaff(staff)) {
        if (mounted && Navigator.canPop(context)) {
          Navigator.pop(context);
        }
        return;
      }

      final memberId = (staff['member_id'] ?? staff['staff_member_id'] ?? '')
          .toString()
          .trim();
      if (memberId.isEmpty) {
        setState(() {
          errorMessage = 'Member ID not found';
          isLoading = false;
        });
        return;
      }

      final departments = _departmentsFromUser(staff);
      if (departments.isEmpty) {
        setState(() {
          errorMessage = 'No department found on staff hierarchy';
          isLoading = false;
        });
        return;
      }

      // 2) Customer getall — hotel room_range → room_no list
      final customerResp =
          await CustomerService.getCustomerByMemberId(memberId);
      if (customerResp.statusCode != 200 && customerResp.statusCode != 201) {
        setState(() {
          errorMessage = 'Unable to load hotel room settings';
          isLoading = false;
        });
        return;
      }

      final customerBody =
          jsonDecode(customerResp.body) as Map<String, dynamic>;
      final roomNos = CustomerService.parseRoomNumbers(customerBody);
      if (roomNos.isEmpty) {
        setState(() {
          errorMessage = 'No room range configured for this hotel';
          isLoading = false;
          tasks = [];
        });
        return;
      }

      // 3) Task getall — ASAP + Assigned for those rooms / departments
      final response = await TaskService.getDeskAsapAssignedTasks(
        memberId: memberId,
        roomNos: roomNos,
        departments: departments,
      );

      if (!mounted) return;

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        if (data['success'] == 1 && data['result'] != null) {
          final List<dynamic> taskList = data['result']['data'] ?? [];
          setState(() {
            tasks = taskList
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
            isLoading = false;
            errorMessage = null;
          });
        } else {
          setState(() {
            errorMessage =
                data['message']?.toString() ?? 'Failed to load tasks';
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
    } finally {
      _refreshInFlight = false;
    }
  }

  void _openTask(int index) {
    final taskId = tasks[index]['id'];
    final id = taskId is int ? taskId : int.tryParse(taskId?.toString() ?? '');
    if (id == null) return;
    _stopLoop();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => TrackTaskPage(taskId: id)),
    ).then((_) {
      if (!mounted) return;
      _loadTasks(showLoading: false);
      _startLoop();
    });
  }

  bool _isTaskEscalated(Map<String, dynamic> task) {
    final status = task['status']?.toString().toUpperCase() ?? '';
    if (status == 'ESCALATED') return true;
    final timeline = task['time_line'];
    if (timeline is! List || timeline.isEmpty) return false;
    final last = timeline.last;
    if (last is! Map) return false;
    return (last['status']?.toString() ?? '') == 'Escalated';
  }

  String _formatAmPm(String rawTime) {
    final time = rawTime.trim();
    if (time.isEmpty) return 'N/A';

    final lower = time.toLowerCase();
    if (lower.contains('am') || lower.contains('pm')) {
      return time;
    }

    try {
      final parts = time.split(':');
      if (parts.length < 2) return time;
      final hour = int.parse(parts[0]);
      final minute = parts[1].padLeft(2, '0');
      final secondPart = parts.length > 2 ? parts[2] : '00';
      final second = int.tryParse(secondPart.split(RegExp(r'\D')).first) ?? 0;
      final period = hour >= 12 ? 'pm' : 'am';
      final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
      if (second > 0) {
        return '$displayHour:${minute.padLeft(2, '0')} $period';
      }
      return '$displayHour:${minute.padLeft(2, '0')} $period';
    } catch (_) {
      return time;
    }
  }

  String _displayTime(Map<String, dynamic> task) {
    final orderTime = task['order_time']?.toString().trim() ?? '';
    if (orderTime.isNotEmpty) return _formatAmPm(orderTime);

    final timeline = task['time_line'];
    if (timeline is List) {
      for (var i = timeline.length - 1; i >= 0; i--) {
        final entry = timeline[i];
        if (entry is! Map) continue;
        final status = entry['status']?.toString() ?? '';
        if (status == 'ASAP' || status == 'Assigned' || status == 'Escalated') {
          final time = entry['time']?.toString().trim() ?? '';
          if (time.isNotEmpty) return _formatAmPm(time);
        }
      }
    }
    return 'N/A';
  }

  Color _statusColor(String? status) {
    switch ((status ?? '').trim().toUpperCase()) {
      case 'ASAP':
        return const Color(0xffC58827);
      case 'ASSIGNED':
        return Theme.of(context).colorScheme.primary;
      case 'ESCALATED':
        return Colors.red;
      case 'PROCESSING':
        return Colors.blueGrey;
      default:
        return Colors.grey;
    }
  }

  void _showTaskDetailsModal(BuildContext context, int index) {
    final task = tasks[index];
    final escalated = _isTaskEscalated(task);
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
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Theme.of(context).colorScheme.primary,
                          Theme.of(context).colorScheme.secondary,
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
                  Flexible(
                    fit: FlexFit.loose,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              ServiceTaskIcon(task: task, size: 48),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  task['service']?['service_name']
                                          ?.toString() ??
                                      'Service',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (escalated) ...[
                            const SizedBox(height: 8),
                            Container(
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
                          const SizedBox(height: 12),
                          _buildInfoRow(
                              'Guest', task['guest_name']?.toString() ?? 'N/A'),
                          _buildInfoRow(
                            'Staff',
                            task['assigned_staff_name']?.toString() ??
                                'Unassigned',
                          ),
                          _buildInfoRow(
                              'Room', task['room_no']?.toString() ?? 'N/A'),
                          _buildInfoRow(
                              'Status', task['status']?.toString() ?? 'N/A'),
                          _buildInfoRow('Time', _displayTime(task)),
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
      padding: const EdgeInsets.symmetric(vertical: 6),
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
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    return Scaffold(
      body: Column(
        children: [
          Container(
            width: screenWidth,
            height: MediaQuery.of(context).size.height * 0.25,
            color: const Color(0xffE9CD3A),
            child: Stack(
              children: [
                appBarContainer(context, showBackButton: true),
                Positioned(
                  bottom: 10,
                  left: 0,
                  right: 0,
                  child: Row(
                    children: [
                      const Expanded(
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
                      const Expanded(
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
                      const Expanded(
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
                ? const Center(child: CircularProgressIndicator())
                : errorMessage != null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.error_outline,
                                size: 64, color: Colors.grey),
                            SizedBox(
                                height:
                                    MediaQuery.of(context).size.height * 0.02),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 32),
                              child: Text(
                                errorMessage!,
                                style: TextStyle(
                                  fontSize:
                                      MediaQuery.of(context).size.width * 0.04,
                                  color: Colors.grey,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            SizedBox(
                                height:
                                    MediaQuery.of(context).size.height * 0.02),
                            ElevatedButton(
                              onPressed: () => _loadTasks(showLoading: true),
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      )
                    : tasks.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.inbox_outlined,
                                    size: 64, color: Colors.grey),
                                SizedBox(
                                    height: MediaQuery.of(context).size.height *
                                        0.02),
                                Text(
                                  'No ASAP / Assigned tasks',
                                  style: TextStyle(
                                    fontSize:
                                        MediaQuery.of(context).size.width *
                                            0.04,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: () => _loadTasks(showLoading: false),
                            child: ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: tasks.length,
                              itemBuilder: (context, index) {
                                final task = tasks[index];
                                final escalated = _isTaskEscalated(task);
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 16),
                                  child: GestureDetector(
                                    onTap: () => _openTask(index),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                          colors: escalated
                                              ? [
                                                  Colors.red.shade100,
                                                  Colors.red.shade50
                                                ]
                                              : [Colors.white, Colors.white],
                                        ),
                                        borderRadius: BorderRadius.circular(10),
                                        border: escalated
                                            ? Border.all(
                                                color: Colors.red, width: 2)
                                            : null,
                                      ),
                                      padding: const EdgeInsets.all(1),
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        child: Column(
                                          children: [
                                            SizedBox(
                                              height: 70,
                                              child: Row(
                                                children: [
                                                  Expanded(
                                                    flex: 2,
                                                    child: Text(
                                                      task['room_no']
                                                              ?.toString() ??
                                                          'N/A',
                                                      textAlign:
                                                          TextAlign.center,
                                                    ),
                                                  ),
                                                  Container(
                                                    margin: const EdgeInsets
                                                        .symmetric(
                                                        vertical: 16),
                                                    height: double.infinity,
                                                    width: 1,
                                                    color:
                                                        const Color(0xffE7E7E7),
                                                  ),
                                                  Expanded(
                                                    flex: 3,
                                                    child: Text(
                                                      task['service']?[
                                                                  'service_name']
                                                              ?.toString() ??
                                                          'Service',
                                                      textAlign:
                                                          TextAlign.center,
                                                    ),
                                                  ),
                                                  Container(
                                                    margin: const EdgeInsets
                                                        .symmetric(
                                                        vertical: 16),
                                                    height: double.infinity,
                                                    width: 1,
                                                    color:
                                                        const Color(0xffE7E7E7),
                                                  ),
                                                  Expanded(
                                                    flex: 2,
                                                    child: Text(
                                                      _displayTime(task),
                                                      textAlign:
                                                          TextAlign.center,
                                                      style: const TextStyle(
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
                                              margin:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 16),
                                              height: 1,
                                              width: screenWidth,
                                              color: const Color(0xffE7E7E7),
                                            ),
                                            Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 16,
                                                      vertical: 16),
                                              child: Row(
                                                children: [
                                                  Expanded(
                                                    child: SizedBox(
                                                      height: 45,
                                                      child: OutlinedButton(
                                                        style: OutlinedButton
                                                            .styleFrom(
                                                          foregroundColor:
                                                              Theme.of(context)
                                                                  .colorScheme
                                                                  .primary,
                                                          side: BorderSide(
                                                            color: Theme.of(
                                                                    context)
                                                                .colorScheme
                                                                .primary,
                                                          ),
                                                          shape:
                                                              RoundedRectangleBorder(
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        5),
                                                          ),
                                                        ),
                                                        onPressed: () {
                                                          _showTaskDetailsModal(
                                                              context, index);
                                                        },
                                                        child: const Row(
                                                          mainAxisAlignment:
                                                              MainAxisAlignment
                                                                  .center,
                                                          children: [
                                                            Text(
                                                              'View',
                                                              style: TextStyle(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                              ),
                                                            ),
                                                            SizedBox(width: 8),
                                                            Icon(
                                                              Icons
                                                                  .visibility_outlined,
                                                              size: 20,
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 16),
                                                  Expanded(
                                                    child: Container(
                                                      height: 45,
                                                      alignment:
                                                          Alignment.center,
                                                      decoration: BoxDecoration(
                                                        color: _statusColor(
                                                            task['status']
                                                                ?.toString()),
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(5),
                                                      ),
                                                      child: Text(
                                                        task['status']
                                                                ?.toString() ??
                                                            'N/A',
                                                        textAlign:
                                                            TextAlign.center,
                                                        style: const TextStyle(
                                                          color: Colors.white,
                                                          fontWeight:
                                                              FontWeight.w600,
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
                                  ),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}
