import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:guestezee_staffs_app/const.dart';
import 'package:guestezee_staffs_app/Services/task_service.dart';
import 'package:guestezee_staffs_app/Services/local_storage_service.dart';
import 'package:guestezee_staffs_app/Services/network_error_message.dart';
import 'package:guestezee_staffs_app/Custom%20Widgets/fnb_order_details.dart';
import 'package:guestezee_staffs_app/Custom%20Widgets/service_task_icon.dart';
import 'package:guestezee_staffs_app/Custom%20Widgets/task_special_request.dart';
import 'package:hive_flutter/hive_flutter.dart';

class CancelledTaskPage extends StatefulWidget {
  const CancelledTaskPage({super.key});

  @override
  State<CancelledTaskPage> createState() => _CancelledTaskPageState();
}
// ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPKMMizf6jtwyKrxbMxpA8A/UXBRiCx2MDg6l8r9KLDV techteam@hospitalitynews.in
// ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAa0Z3GX47KD+boojy9pUcOsJjKFFMw7pkwCs99Zk2SE info.hospitalitynews@gmail.com

class _CancelledTaskPageState extends State<CancelledTaskPage> {
  // API data
  List<Map<String, dynamic>> tasks = [];
  bool isLoading = true;
  String? errorMessage;
  @override
  void initState() {
    super.initState();
    _loadCancelledTasks();
  }

  Future<void> _loadCancelledTasks() async {
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

      final response = await TaskService.getCancelledTasks(
          memberId.toString(), assignedStaffId);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        if (data['success'] == 1 && data['result'] != null) {
          final List<dynamic> taskList = data['result']['data'] ?? [];
          setState(() {
            tasks = taskList.cast<Map<String, dynamic>>();
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

  void _showTaskDetailsModal(BuildContext context, int index) {
    final task = tasks[index];
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
                      color: Colors.red,
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(16)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Cancelled Task Details',
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
                                  color: Colors.red.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Center(
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxWidth:
                                          MediaQuery.of(context).size.width *
                                              0.4,
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
                                    TaskSpecialRequest.inlineSubtitle(task),
                                    SizedBox(height: 8),
                                    Container(
                                      padding: EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.red,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        'CANCELLED',
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

                          // Show cancel reason if available
                          if (task['cancel_remark'] != null &&
                              task['cancel_remark'].toString().isNotEmpty) ...[
                            SizedBox(height: 16),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Cancellation Reason',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.red,
                                  ),
                                ),
                                SizedBox(height: 8),
                                Container(
                                  padding: EdgeInsets.all(12),
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    color: Colors.red.shade50,
                                    border:
                                        Border.all(color: Colors.red.shade200),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    task['cancel_remark']?.toString() ?? '',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.red.shade900,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ]
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
                appBarContainer(context, showBackButton: true),
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
                              onPressed: _loadCancelledTasks,
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
                                Icon(Icons.cancel_outlined,
                                    size: 64, color: Colors.grey),
                                SizedBox(height: 16),
                                Text(
                                  'No tasks cancelled yet',
                                  style: TextStyle(
                                      fontSize: 16, color: Colors.grey),
                                ),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _loadCancelledTasks,
                            child: ListView.builder(
                              padding: EdgeInsets.all(16),
                              itemCount: tasks.length,
                              itemBuilder: (context, index) => Padding(
                                padding: const EdgeInsets.only(bottom: 16.0),
                                child: Container(
                                  padding: EdgeInsets.all(1),
                                  decoration: BoxDecoration(
                                      borderRadius:
                                          BorderRadius.all(Radius.circular(10)),
                                      gradient: LinearGradient(
                                          colors: [Colors.white, Colors.white],
                                          end: Alignment.bottomCenter,
                                          begin: Alignment.topCenter)),
                                  child: Container(
                                    decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.all(
                                            Radius.circular(10))),
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
                                                                BorderRadius
                                                                    .all(Radius
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
                                                            SizedBox(width: 8),
                                                            Icon(
                                                              Icons
                                                                  .visibility_outlined,
                                                              color:
                                                                  Colors.green,
                                                              size: 20,
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
          ),
        ],
      ),
    );
  }
}
