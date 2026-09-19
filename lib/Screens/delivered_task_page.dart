import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:guestezee_staffs_app/const.dart';
import 'package:guestezee_staffs_app/Services/task_service.dart';
import 'package:guestezee_staffs_app/Services/local_storage_service.dart';
import 'package:guestezee_staffs_app/Services/network_error_message.dart';
import 'package:guestezee_staffs_app/Custom%20Widgets/fnb_order_details.dart';
import 'package:guestezee_staffs_app/Custom%20Widgets/task_special_request.dart';
import 'package:guestezee_staffs_app/Custom%20Widgets/desk_task_floating_actions.dart';
import 'package:hive_flutter/hive_flutter.dart';

class DeliveredTaskPage extends StatefulWidget {
  const DeliveredTaskPage({super.key});

  @override
  State<DeliveredTaskPage> createState() => _DeliveredTaskPageState();
}

class _DeliveredTaskPageState extends State<DeliveredTaskPage> {
  TextEditingController fromController = TextEditingController();
  TextEditingController toController = TextEditingController();
  int slots = -1;
  bool? errorFromdate;
  bool? errorToDate;
  List<String> stringList = ['3 Min', '10 Min', 'above 10 Min'];

  // API data
  List<Map<String, dynamic>> tasks = [];
  bool isLoading = true;
  String? errorMessage;
  Map<int, Map<String, dynamic>> taskRatings =
      {}; // Map of task_id to rating data (rating, feedback_text)
  @override
  void initState() {
    super.initState();
    _loadDeliveredTasks();

    fromController.addListener(() {
      String text = fromController.text.replaceAll('/', '');
      String newText = '';
      errorFromdate = false;

      if (text.length >= 2) {
        String dayStr = text.substring(0, 2);
        int? date = int.tryParse(dayStr);
        newText += dayStr;

        if (text.length >= 4) {
          String monthStr = text.substring(2, 4);
          newText += '/$monthStr';

          if (date == null || date < 1 || date > 31) {
            setState(() {
              errorFromdate = true;
            });
          }

          if (text.length > 4) {
            String yearStr = text.substring(4, text.length.clamp(4, 8));
            newText += '/$yearStr';
          }
        } else if (text.length > 2) {
          newText += '/${text.substring(2)}';
        }
      } else {
        newText = text;
      }

      fromController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: newText.length),
      );
    });
    toController.addListener(() {
      String text = toController.text.replaceAll('/', '');
      String newText = '';
      errorToDate = false;

      if (text.length >= 2) {
        String dayStr = text.substring(0, 2);
        int? date = int.tryParse(dayStr);
        newText += dayStr;

        if (text.length >= 4) {
          String monthStr = text.substring(2, 4);
          newText += '/$monthStr';

          if (date == null || date < 1 || date > 31) {
            setState(() {
              errorToDate = true;
            });
          }

          if (text.length > 4) {
            String yearStr = text.substring(4, text.length.clamp(4, 8));
            newText += '/$yearStr';
          }
        } else if (text.length > 2) {
          newText += '/${text.substring(2)}';
        }
      } else {
        newText = text;
      }

      toController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: newText.length),
      );
    });
  }

  Future<void> _loadDeliveredTasks() async {
    try {
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

      final response = await TaskService.getDeliveredTasks(
          memberId.toString(), assignedStaffId);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        if (data['success'] == 1 && data['result'] != null) {
          final List<dynamic> taskList = data['result']['data'] ?? [];
          setState(() {
            tasks = taskList.cast<Map<String, dynamic>>();
          });

          // Fetch ratings for all delivered tasks
          if (tasks.isNotEmpty) {
            await _loadRatings(memberId.toString());
          }

          setState(() {
            isLoading = false;
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
      setState(() {
        errorMessage = NetworkErrorMessage.forTaskLoad(e);
        isLoading = false;
      });
    }
  }

  Future<void> _loadRatings(String memberId) async {
    try {
      // Extract task IDs from delivered tasks
      List<int> taskIds = tasks
          .map((task) => task['id'] as int?)
          .where((id) => id != null)
          .cast<int>()
          .toList();

      if (taskIds.isEmpty) return;

      final response = await TaskService.getRatingsForTasks(taskIds, memberId);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        if (data['success'] == 1 && data['result'] != null) {
          final List<dynamic> ratingsList = data['result']['data'] ?? [];

          // Map ratings by task_id - store rating and feedback data
          Map<int, Map<String, dynamic>> ratingsMap = {};
          for (var rating in ratingsList) {
            if (rating is Map<String, dynamic>) {
              final taskId = rating['task_id'] as int?;
              if (taskId != null) {
                ratingsMap[taskId] = {
                  'rating': rating['rating'] ?? 0,
                  'feedback_text': rating['feedback_text'] ?? '',
                };
              }
            }
          }

          setState(() {
            taskRatings = ratingsMap;
          });
        }
      }
    } catch (e) {
      // Silently fail - ratings are not critical
      print('Error loading ratings: $e');
    }
  }

  String? _formatOrderTime(String? time, String? date) {
    if (time == null || date == null) return null;

    try {
      // Parse the time string (format: "18:02:44")
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

  String? _formatDeliveredTime(List<dynamic>? timeline) {
    if (timeline == null) return null;

    try {
      // Find the "Delivered" status in the timeline
      for (var entry in timeline) {
        if (entry is Map<String, dynamic> && entry['status'] == 'Delivered') {
          final time = entry['time']?.toString();
          final date = entry['date']?.toString();
          if (time != null && date != null) {
            return _formatOrderTime(time, date);
          }
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  void _showTaskDetailsModal(BuildContext context, int index) {
    final task = tasks[index];
    final taskId = task['id'] as int?;
    final ratingData = taskId != null ? taskRatings[taskId] : null;
    final rating = ratingData?['rating'] ?? 0;
    final feedbackText =
        ratingData?['ai_feedback'] ?? ratingData?['feedback_text'] ?? '';
    final isOnTime = task['timely_delivered'] ?? true;
    final hasRatingData =
        ratingData != null && (rating > 0 || feedbackText.isNotEmpty);

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
                      color: Colors.green,
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(16)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Delivered Task Details',
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
                          onPressed: () => Navigator.pop(dialogContext),
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
                                  color: Colors.green.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Center(
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxWidth:
                                          MediaQuery.of(context).size.width *
                                              0.4,
                                    ),
                                    child: Text(
                                      LocalStorageService.hotelName,
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
                                    TaskSpecialRequest.inlineSubtitle(task),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 12),
                          _buildInfoRow(
                              'Task id', task['id']?.toString() ?? 'N/A'),
                          _buildInfoRow(
                              'Guest', task['guest_name']?.toString() ?? 'N/A'),
                          _buildInfoRow('Staff',
                              task['assigned_staff_name']?.toString() ?? 'N/A'),
                          _buildInfoRow(
                              'Room', task['room_no']?.toString() ?? 'N/A'),

                          SizedBox(height: 8),
                          MenuOrderFoodSection(task: task),

                          TaskSpecialRequest.section(task),

                          SizedBox(height: 16),
                          Divider(),
                          SizedBox(height: 8),
                          // Task delivery info
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _buildStatusCard(
                                  'Status', 'Delivered', '', Colors.green),
                              _buildStatusCard(
                                  'Order Time',
                                  _formatOrderTime(task['order_time'],
                                          task['order_date']) ??
                                      'N/A',
                                  '',
                                  null),
                              _buildStatusCard(
                                  'Delivered',
                                  _formatDeliveredTime(task['time_line']) ??
                                      'N/A',
                                  '',
                                  Colors.green),
                            ],
                          ),
                          SizedBox(height: 12),
                          // On-time delivery indicator
                          Container(
                            padding: EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: isOnTime
                                  ? Colors.green.shade50
                                  : Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isOnTime
                                    ? Colors.green.shade200
                                    : Colors.orange.shade200,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  isOnTime
                                      ? Icons.check_circle
                                      : Icons.schedule,
                                  color:
                                      isOnTime ? Colors.green : Colors.orange,
                                  size: 20,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  isOnTime
                                      ? 'Delivered On Time'
                                      : 'Delayed Delivery',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: isOnTime
                                        ? Colors.green.shade700
                                        : Colors.orange.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (hasRatingData) ...[
                            SizedBox(height: 16),
                            Divider(),
                            SizedBox(height: 8),
                            // Rating Section
                            Text(
                              'Guest Rating',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey[800],
                              ),
                            ),
                            SizedBox(height: 12),
                            Row(
                              children: [
                                ...List.generate(5, (starIndex) {
                                  return Icon(
                                    starIndex < rating
                                        ? Icons.star
                                        : Icons.star_border,
                                    color: Color(0xffFECA57),
                                    size: 28,
                                  );
                                }),
                                SizedBox(width: 8),
                                Text(
                                  '$rating/5',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey[700],
                                  ),
                                ),
                              ],
                            ),
                            if (feedbackText.isNotEmpty) ...[
                              SizedBox(height: 12),
                              Text(
                                'Feedback',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey[700],
                                ),
                              ),
                              SizedBox(height: 8),
                              Container(
                                padding: EdgeInsets.all(12),
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  color: Colors.grey[50],
                                  border: Border.all(color: Color(0xffE7E7E7)),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  feedbackText,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ),
                            ],
                          ],
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

  Widget _buildStatusCard(
      String label, String value, String subtitle, Color? color) {
    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
          SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: color ?? Colors.black,
            ),
          ),
          if (subtitle.isNotEmpty)
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[500],
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
      // floatingActionButton: FloatingActionButton(
      //   elevation: 1,
      //   onPressed: () {
      //     showModalBottomSheet(
      //         // shape: RoundedRectangleBorder(
      //         //     borderRadius: BorderRadius.circular(15)),
      //         backgroundColor: AppTheme.colorScheme.surface,
      //         isScrollControlled: true,
      //         context: context,
      //         builder: (context) {
      //           return StatefulBuilder(
      //               builder: (context, setModelState) => Padding(
      //                     padding: EdgeInsets.all(16),
      //                     child: AnimatedPadding(
      //                       padding: EdgeInsets.only(
      //                         bottom: MediaQuery.of(context).viewInsets.bottom,
      //                       ),
      //                       duration: const Duration(milliseconds: 100),
      //                       curve: Curves.decelerate,
      //                       child: SingleChildScrollView(
      //                         child: Column(
      //                           mainAxisSize: MainAxisSize.min,
      //                           crossAxisAlignment: CrossAxisAlignment.start,
      //                           children: [
      //                             Row(
      //                               mainAxisAlignment:
      //                                   MainAxisAlignment.spaceBetween,
      //                               children: [
      //                                 Text(
      //                                   'Filter and Sort',
      //                                   style: TextStyle(
      //                                     fontSize: 24,
      //                                     fontWeight: FontWeight.bold,
      //                                   ),
      //                                 ),
      //                                 IconButton(
      //                                     onPressed: () {
      //                                       Navigator.pop(context);
      //                                       errorFromdate = false;
      //                                       errorToDate = false;
      //                                       fromController.clear();
      //                                       toController.clear();
      //                                       if (slots >= 0) {
      //                                         print(stringList[slots]);
      //                                         slots = -1;
      //                                       }
      //                                     },
      //                                     icon: Icon(
      //                                       Icons.cancel,
      //                                       color: Color(0xffB9B9B9),
      //                                     ))
      //                               ],
      //                             ),
      //                             Text('Delivery Time'),
      //                             SizedBox(height: 16),
      //                             Row(
      //                               spacing: 10,
      //                               children: List.generate(
      //                                   stringList.length,
      //                                   (index) => GestureDetector(
      //                                         onTap: () {
      //                                           setModelState(() {
      //                                             if (slots == index) {
      //                                               slots = -1;
      //                                             } else {
      //                                               slots = index;
      //                                             }
      //                                           });
      //                                         },
      //                                         child: Container(
      //                                           constraints: BoxConstraints(
      //                                               minWidth: 80,
      //                                               minHeight: 40),
      //                                           decoration: BoxDecoration(
      //                                               border: Border.all(
      //                                                   color: slots == index
      //                                                       ? Colors.transparent
      //                                                       : Theme.of(context)
      //                                                           .colorScheme
      //                                                           .primary),
      //                                               color: slots == index
      //                                                   ? Color(0xff32BA7C)
      //                                                   : Colors.transparent,
      //                                               borderRadius:
      //                                                   BorderRadius.all(
      //                                                       Radius.circular(
      //                                                           6))),
      //                                           child: Center(
      //                                               child: Padding(
      //                                             padding: const EdgeInsets
      //                                                 .symmetric(
      //                                                 horizontal: 16.0),
      //                                             child: Text(
      //                                               stringList[index],
      //                                               style: TextStyle(
      //                                                   color: slots == index
      //                                                       ? Colors.white
      //                                                       : Theme.of(context)
      //                                                           .colorScheme
      //                                                           .primary),
      //                                             ),
      //                                           )),
      //                                         ),
      //                                       )),
      //                             ),
      //                             SizedBox(height: 16),
      //                             Container(
      //                               height: 100,
      //                               child: Row(
      //                                 children: [
      //                                   Expanded(
      //                                     child: Column(
      //                                       crossAxisAlignment:
      //                                           CrossAxisAlignment.start,
      //                                       children: [
      //                                         Text('From Date'),
      //                                         SizedBox(height: 8),
      //                                         SizedBox(
      //                                           // height: 50,
      //                                           child: TextField(
      //                                             controller: fromController,
      //                                             keyboardType:
      //                                                 TextInputType.number,
      //                                             inputFormatters: [
      //                                               FilteringTextInputFormatter
      //                                                   .digitsOnly,
      //                                               LengthLimitingTextInputFormatter(
      //                                                   8),
      //                                             ],
      //                                             decoration: InputDecoration(
      //                                               errorText:
      //                                                   errorFromdate == true
      //                                                       ? 'Invalid date'
      //                                                       : null,
      //                                               suffixIcon: IconButton(
      //                                                 onPressed: () {},
      //                                                 icon: Icon(Icons
      //                                                     .edit_calendar_outlined),
      //                                               ),
      //                                               counterText: '',
      //                                               border:
      //                                                   OutlineInputBorder(),
      //                                               isDense: true,
      //                                             ),
      //                                           ),
      //                                         ),
      //                                       ],
      //                                     ),
      //                                   ),
      //                                   SizedBox(width: 16),
      //                                   Expanded(
      //                                     child: Column(
      //                                       crossAxisAlignment:
      //                                           CrossAxisAlignment.start,
      //                                       children: [
      //                                         Text('To Date'),
      //                                         SizedBox(height: 8),
      //                                         SizedBox(
      //                                           // height: 50,
      //                                           child: TextField(
      //                                             controller: toController,
      //                                             keyboardType:
      //                                                 TextInputType.number,
      //                                             inputFormatters: [
      //                                               FilteringTextInputFormatter
      //                                                   .digitsOnly,
      //                                               LengthLimitingTextInputFormatter(
      //                                                   8),
      //                                             ],
      //                                             decoration: InputDecoration(
      //                                               errorText:
      //                                                   errorToDate == true
      //                                                       ? 'Invalid date'
      //                                                       : null,
      //                                               suffixIcon: IconButton(
      //                                                 onPressed: () {},
      //                                                 icon: Icon(Icons
      //                                                     .edit_calendar_outlined),
      //                                               ),
      //                                               counterText: '',
      //                                               border:
      //                                                   OutlineInputBorder(),
      //                                               isDense: true,
      //                                             ),
      //                                           ),
      //                                         ),
      //                                       ],
      //                                     ),
      //                                   ),
      //                                 ],
      //                               ),
      //                             ),
      //                             Container(
      //                               height: 45,
      //                               width: screenWidth,
      //                               child: ElevatedButton(
      //                                 onPressed: slots == -1
      //                                     ? () {
      //                                         String fromDate = fromController
      //                                             .text
      //                                             .replaceAll('/', '');
      //                                         String toDate = toController.text
      //                                             .replaceAll('/', '');
      //                                         bool valid = true;

      //                                         if (fromDate.length >= 4) {
      //                                           int? fromDay = int.tryParse(
      //                                               fromDate.substring(0, 2));
      //                                           int? fromMonth = int.tryParse(
      //                                               fromDate.substring(2, 4));

      //                                           if (fromDay == null ||
      //                                               fromDay < 1 ||
      //                                               fromDay > 31 ||
      //                                               fromMonth == null ||
      //                                               fromMonth < 1 ||
      //                                               fromMonth > 12) {
      //                                             valid = false;
      //                                           }
      //                                         } else {
      //                                           valid = false;
      //                                         }

      //                                         bool toDateValid = true;
      //                                         if (toDate.length >= 4) {
      //                                           int? toDay = int.tryParse(
      //                                               toDate.substring(0, 2));
      //                                           int? toMonth = int.tryParse(
      //                                               toDate.substring(2, 4));

      //                                           if (toDay == null ||
      //                                               toDay < 1 ||
      //                                               toDay > 31 ||
      //                                               toMonth == null ||
      //                                               toMonth < 1 ||
      //                                               toMonth > 12) {
      //                                             toDateValid = false;
      //                                           }
      //                                         } else {
      //                                           toDateValid = false;
      //                                         }
      //                                         setModelState(() {
      //                                           errorFromdate = !valid;
      //                                           errorToDate = !toDateValid;
      //                                         });

      //                                         if (valid && toDateValid) {
      //                                           Navigator.pop(context);
      //                                         }
      //                                       }
      //                                     : () {
      //                                         slots = -1;
      //                                         Navigator.pop(context);
      //                                       },
      //                                 child: Text('Apply Filter'),
      //                               ),
      //                             )
      //                           ],
      //                         ),
      //                       ),
      //                     ),
      //                   ));
      //         });
      //   },
      //   backgroundColor: Colors.white,
      //   child: Container(
      //       height: 30, child: Image.asset('assets/images/filtericon.png')),
      // ),
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
                            SizedBox(height: 16),
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
                            SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: _loadDeliveredTasks,
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
                                SizedBox(height: 16),
                                Text(
                                  'No completed tasks found',
                                  style: TextStyle(
                                      fontSize: 16, color: Colors.grey),
                                ),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _loadDeliveredTasks,
                            child: ListView.builder(
                              padding: EdgeInsets.all(16),
                              itemCount: tasks.length,
                              itemBuilder: (context, index) => Padding(
                                padding: const EdgeInsets.only(bottom: 16.0),
                                child: Container(
                                  decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius:
                                          BorderRadius.all(Radius.circular(10)),
                                      border: Border.all(
                                          color: Colors.grey.shade200)),
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
                                              child: Padding(
                                                padding: EdgeInsets.symmetric(
                                                    horizontal: 12.0,
                                                    vertical: 14),
                                                child: GestureDetector(
                                                  onTap: () {
                                                    _showTaskDetailsModal(
                                                        context, index);
                                                  },
                                                  child: Container(
                                                      decoration: BoxDecoration(
                                                          borderRadius:
                                                              BorderRadius.all(
                                                                  Radius
                                                                      .circular(
                                                                          5)),
                                                          border: Border.all(
                                                              color: Colors
                                                                  .green)),
                                                      width: double.infinity,
                                                      height: double.infinity,
                                                      child: Row(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .center,
                                                        mainAxisAlignment:
                                                            MainAxisAlignment
                                                                .center,
                                                        children: [
                                                          Text(
                                                            'View',
                                                            style: TextStyle(
                                                                color: Colors
                                                                    .green,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600),
                                                          ),
                                                          SizedBox(width: 4),
                                                          Icon(
                                                            Icons
                                                                .visibility_outlined,
                                                            color: Colors.green,
                                                            size: 18,
                                                          )
                                                        ],
                                                      )),
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
                          ),
          ),
        ],
      ),
      floatingActionButton: const DeskTaskFloatingActions(),
    );
  }
}
