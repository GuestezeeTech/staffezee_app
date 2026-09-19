import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:guestezee_staffs_app/Custom%20Widgets/navigation_page.dart';
import 'package:guestezee_staffs_app/Screens/escalated_tasks_page.dart';
import 'package:guestezee_staffs_app/Screens/registration_page.dart';
import 'package:guestezee_staffs_app/Screens/static_content_page.dart';
import 'package:guestezee_staffs_app/Services/staff_service.dart';
import 'package:guestezee_staffs_app/Services/staff_presence_service.dart';
import 'dart:convert';
import 'package:guestezee_staffs_app/Services/local_storage_service.dart';
import 'package:guestezee_staffs_app/Services/escalation_timer_service.dart';
import 'package:guestezee_staffs_app/Services/hotel_status_service.dart';
import 'package:guestezee_staffs_app/Services/push_notification_service.dart';
import 'package:guestezee_staffs_app/app_theme.dart';
import 'package:hive/hive.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, this.employeeId});
  final String? employeeId;
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _startIdValidate = false;
  bool _startValidate = false;
  bool _startPinValidate = false;
  bool _isLoggingIn = false;
  final TextEditingController _idController = TextEditingController();
  final TextEditingController _pinController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Auto-fill employee ID if provided from registration
    if (widget.employeeId != null && widget.employeeId!.isNotEmpty) {
      _idController.text = widget.employeeId!.toUpperCase();
      // Set validation state to true since field is pre-filled
      _startIdValidate = true;
    }
    getToken();
  }

  Future<void> getToken() async {
    print('object');
    final currentFcmToken = await PushNotificationService.getDeviceToken();
    print(currentFcmToken);
  }

  @override
  Widget build(BuildContext context) {
    double screenHeight = MediaQuery.of(context).size.height;
    double screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      bottomNavigationBar: Container(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 7.0, top: 7),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Powered by '),
                  Text(
                    'GuestEzee',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.secondary),
                  ),
                ],
              ),
              SizedBox(height: MediaQuery.of(context).size.height * 0.01),
            ],
          ),
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              children: [
                Container(
                  height: screenHeight * .3,
                  width: screenWidth,
                  decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      borderRadius:
                          BorderRadius.vertical(bottom: Radius.circular(25))),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    spacing: 10,
                    children: [
                      SizedBox(
                        height: 10,
                      ),
                      ClipRRect(
                        borderRadius:
                            const BorderRadius.all(Radius.circular(10)),
                        child: SizedBox(
                          height: screenHeight * .09,
                          width: screenHeight * .09,
                          child: Image.asset('assets/images/staff_logo.png'),
                        ),
                      ),
                      Text(
                        'Login',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: MediaQuery.of(context).size.width * 0.075,
                            fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Enter your Employee code to login',
                        style: AppTheme.extraLightText,
                      )
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text("Employee ID",
                            style: TextStyle(
                                color: Color(0xff6C7278),
                                fontSize:
                                    MediaQuery.of(context).size.width * 0.035)),
                      ),
                      SizedBox(height: screenHeight * 0.01),
                      TextField(
                        keyboardType: TextInputType.name,
                        textCapitalization: TextCapitalization.characters,
                        inputFormatters: [
                          TextInputFormatter.withFunction(
                            (oldValue, newValue) => newValue.copyWith(
                              text: newValue.text.toUpperCase(),
                            ),
                          ),
                        ],
                        maxLength: 25,
                        controller: _idController,
                        decoration: InputDecoration(
                          counterText: ' ',
                          errorBorder: _errorBorder(_startIdValidate),
                          focusedErrorBorder: _errorBorder(_startIdValidate),
                          focusedBorder: _normalBorder(),
                          enabledBorder: _normalBorder(),
                          errorText: (_startValidate || _startIdValidate) &&
                                  _idController.text.isEmpty
                              ? "Employee ID is required"
                              : null,
                        ),
                        onChanged: (_) {
                          setState(() {
                            _startIdValidate = true;
                          });
                        },
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text("Pin Number",
                            style: TextStyle(
                                color: Color(0xff6C7278),
                                fontSize:
                                    MediaQuery.of(context).size.width * 0.035)),
                      ),
                      SizedBox(height: screenHeight * 0.01),
                      TextField(
                        keyboardType: TextInputType.number,
                        maxLength: 4,
                        controller: _pinController,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                        obscureText: true,
                        decoration: InputDecoration(
                          counterText: ' ',
                          errorBorder: _errorBorder(_startPinValidate),
                          focusedErrorBorder: _errorBorder(_startPinValidate),
                          focusedBorder: _normalBorder(),
                          enabledBorder: _normalBorder(),
                          errorText: (_startValidate || _startPinValidate) &&
                                  _pinController.text.isEmpty
                              ? "Pin Number is required"
                              : (_startValidate || _startPinValidate) &&
                                      _pinController.text.isNotEmpty &&
                                      _pinController.text.length != 4
                                  ? "Pin Number must be 4 digits"
                                  : null,
                        ),
                        onChanged: (_) {
                          setState(() {
                            _startPinValidate = true;
                          });
                        },
                      ),
                      SizedBox(
                          height: MediaQuery.of(context).size.height * 0.015),
                      SizedBox(
                        width: double.infinity,
                        height: MediaQuery.of(context).size.height * 0.062,
                        child: ElevatedButton(
                          onPressed: _isLoggingIn ? null : _handleLogin,
                          child: _isLoggingIn
                              ? const SizedBox(
                                  height: 22,
                                  width: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white),
                                  ),
                                )
                              : const Text("Login"),
                        ),
                      ),
                      SizedBox(
                          height: MediaQuery.of(context).size.height * 0.015),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            'New user? ',
                            style: TextStyle(color: Color(0xff6C7278)),
                          ),
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      const RegistrationPage(),
                                ),
                              );
                            },
                            child: Text(
                              'Register',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.secondary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(
                          height: MediaQuery.of(context).size.height * 0.012),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            'Forgot PIN? ',
                            style: TextStyle(color: Color(0xff6C7278)),
                          ),
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => RegistrationPage(
                                    employeeId:
                                        _idController.text.trim().toUpperCase(),
                                    isForgotPin: true,
                                  ),
                                ),
                              );
                            },
                            child: Text(
                              'Reset',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.secondary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(
                        height: MediaQuery.of(context).size.height * 0.28,
                        child: Image.asset('assets/images/loginpicture.png'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  InputBorder _normalBorder() => OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Color(0xff6C7278)),
      );

  InputBorder _errorBorder(bool showError) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide:
            BorderSide(color: showError ? Colors.red : Color(0xff6C7278)),
      );

  void _handleLogin() {
    setState(() {
      _startValidate = true;
    });
    if (_idController.text.isEmpty ||
        _pinController.text.isEmpty ||
        _pinController.text.length != 4) {
      return;
    }

    setState(() => _isLoggingIn = true);
    _login();
  }

  Future<void> _login() async {
    final employeeId = _idController.text.trim().toUpperCase();
    final pin = _pinController.text.trim();

    try {
      // 1) Pre-check staff by employee number on EVERY login attempt.
      final staffResp =
          await StaffService.findStaffByEmployeeNumber(employeeId);
      if (staffResp.statusCode != 200 && staffResp.statusCode != 201) {
        _showError('Unable to validate staff. Please try again.');
        return;
      }

      final staffData = jsonDecode(staffResp.body);
      final List<dynamic> staffList =
          (staffData is Map && staffData['result']?['data'] is List)
              ? List<dynamic>.from(staffData['result']['data'] as List)
              : <dynamic>[];

      if (staffList.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No staff found. Please register.')),
          );
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => RegistrationPage(employeeId: employeeId),
            ),
          );
        }
        return;
      }

      final staff = Map<String, dynamic>.from(staffList.first as Map);
      final hasPin =
          staff['pin'] != null && staff['pin'].toString().trim().isNotEmpty;
      if (!hasPin) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please set your PIN first.')),
          );
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => RegistrationPage(employeeId: employeeId),
            ),
          );
        }
        return;
      }

      if (!HotelStatusService.isActiveForUser(staff)) {
        HotelStatusService.showInactiveLoginBlock();
        FocusScope.of(context).unfocus();
        if (mounted) setState(() {});
        return;
      }

      // Hotel gate from customer getall only (do not mutate overlay until fail).
      final memberIdForHotel =
          (staff['member_id'] ?? staff['staff_member_id'] ?? '')
              .toString()
              .trim();
      final hotelOk = await HotelStatusService.checkCustomerHotelAccess(
        memberIdForHotel,
        applyToSession: false,
      );
      if (!hotelOk) {
        HotelStatusService.showLoginBlock();
        FocusScope.of(context).unfocus();
        if (mounted) setState(() {});
        return;
      }

      // 2) Staff exists + has pin -> perform login.
      final resp = await StaffService.loginStaff(
        employeeId: employeeId,
        pin: pin,
      );

      // Explicit invalid-password path requested by user.
      if (resp.statusCode == 500) {
        _showError('Invalid PIN. Please try again.');
        return;
      }

      if (resp.statusCode == 200 || resp.statusCode == 201) {
        final data = jsonDecode(resp.body);
        if (data['success'] == 1 && data['user'] != null) {
          final user = Map<String, dynamic>.from(data['user']);

          if (!HotelStatusService.isActiveForUser(user)) {
            HotelStatusService.showInactiveLoginBlock();
            FocusScope.of(context).unfocus();
            if (mounted) setState(() {});
            return;
          }

          // Re-check customer hotel access after login (empty data = blocked).
          final memberId =
              (user['member_id'] ?? user['staff_member_id'] ?? '')
                  .toString()
                  .trim();
          final hotelOkAfterLogin =
              await HotelStatusService.checkCustomerHotelAccess(
            memberId,
            applyToSession: false,
          );
          if (!hotelOkAfterLogin) {
            HotelStatusService.showLoginBlock();
            FocusScope.of(context).unfocus();
            if (mounted) setState(() {});
            return;
          }

          await LocalStorageService.saveLoginResponse(
            Map<String, dynamic>.from(data),
          );
          await LocalStorageService.setLoginState(true);
          await LocalStorageService.setRememberMe(true);

          await HotelStatusService.updateStaffActiveFromUser(user);
          // Apply hotel enabled only from customer getall (already verified).
          await HotelStatusService.checkCustomerHotelAccess(memberId);
          HotelStatusService.startPolling();
          await HotelStatusService.refreshNow();

          final hierarchy = user['hierarchy'];
          final Map<String, int> departmentEscalationTimes = {};

          if (hierarchy is List && hierarchy.isNotEmpty) {
            for (final hierarchyEntry in hierarchy) {
              if (hierarchyEntry is Map) {
                final String? department =
                    hierarchyEntry['department']?.toString();
                final dynamic escalationTime = hierarchyEntry['escalationTime'];

                if (department != null && department.isNotEmpty) {
                  int? timeInMinutes;
                  if (escalationTime is int) {
                    timeInMinutes = escalationTime;
                  } else if (escalationTime != null) {
                    timeInMinutes = int.tryParse(escalationTime.toString());
                  }

                  if (timeInMinutes != null) {
                    departmentEscalationTimes[department] = timeInMinutes;
                    print(
                        '💾 Saved escalation time for $department: $timeInMinutes minutes');
                  }
                }
              }
            }
          } else if (hierarchy is Map && hierarchy['escalationTime'] != null) {
            final String? department = hierarchy['department']?.toString();
            final escalationTime = hierarchy['escalationTime'];
            int? timeInMinutes;

            if (escalationTime is int) {
              timeInMinutes = escalationTime;
            } else {
              timeInMinutes = int.tryParse(escalationTime.toString());
            }

            if (department != null && timeInMinutes != null) {
              departmentEscalationTimes[department] = timeInMinutes;
              print(
                  '💾 Saved escalation time for $department: $timeInMinutes minutes (legacy format)');
            }
          }

          if (departmentEscalationTimes.isNotEmpty) {
            await LocalStorageService.saveDepartmentEscalationTimes(
                departmentEscalationTimes);
            print(
                '✅ Saved all department escalation times: $departmentEscalationTimes');
            final firstTime = departmentEscalationTimes.values.first;
            await EscalationTimerService.saveStaffEscalationTime(firstTime);
          }

          final dynamic staffIdValue = user['id'];
          final int? staffDbId = staffIdValue is int
              ? staffIdValue
              : int.tryParse(staffIdValue?.toString() ?? '');
          final String legacyEmployeeNumber =
              (user['staff_employee_number'] ?? user['staff_member_id'] ?? '')
                  .toString();
          final dynamic staffIdentifier = staffDbId ??
              (legacyEmployeeNumber.isNotEmpty ? legacyEmployeeNumber : null);

          if (staffIdentifier != null) {
            final currentFcmToken =
                await PushNotificationService.getDeviceToken();

            if (currentFcmToken != null) {
              final existingFcmTokens = user['fcm_token'];
              if (existingFcmTokens == null) {
                await StaffService.updateStaffAvailabilityWithFcmToken(
                    staffIdentifier, true, [currentFcmToken]);
              } else {
                List<String> fcmTokensList = [];

                if (existingFcmTokens is List) {
                  if (existingFcmTokens.isEmpty) {
                    await StaffService.updateStaffAvailabilityWithFcmToken(
                        staffIdentifier, true, [currentFcmToken]);
                  } else {
                    fcmTokensList =
                        existingFcmTokens.map((e) => e.toString()).toList();
                    if (fcmTokensList.contains(currentFcmToken)) {
                      await StaffService.updateStaffAvailability(
                          staffIdentifier, true);
                    } else {
                      fcmTokensList.add(currentFcmToken);
                      await StaffService.updateStaffAvailabilityWithFcmToken(
                          staffIdentifier, true, fcmTokensList);
                    }
                  }
                } else if (existingFcmTokens is String) {
                  fcmTokensList = [existingFcmTokens];
                  if (fcmTokensList.contains(currentFcmToken)) {
                    await StaffService.updateStaffAvailability(
                        staffIdentifier, true);
                  } else {
                    fcmTokensList.add(currentFcmToken);
                    await StaffService.updateStaffAvailabilityWithFcmToken(
                        staffIdentifier, true, fcmTokensList);
                  }
                }
              }
            } else {
              await StaffService.updateStaffAvailability(staffIdentifier, true);
            }

            await LocalStorageService.init();
            Hive.box('authBox').put('user_is_available', true);

            final existingTokens = user['fcm_token'];
            final otherTokens = <String>[];
            if (existingTokens is List) {
              otherTokens.addAll(existingTokens
                  .map((e) => e.toString())
                  .where((t) => t.isNotEmpty && t != currentFcmToken));
            } else if (existingTokens is String &&
                existingTokens.isNotEmpty &&
                existingTokens != currentFcmToken) {
              otherTokens.add(existingTokens);
            }
            StaffPresenceService.onLogin(
                staffIdentifier: staffIdentifier, tokens: otherTokens);
          }

          bool isHigherLevelOfficer = false;
          List<int> lowerStaffIds = [];

          try {
            final level = await StaffService.resolveManagerLevel(
              Map<String, dynamic>.from(user),
            );
            isHigherLevelOfficer = level.isManagerLevel;
            lowerStaffIds = level.lowerStaffIds;
            await LocalStorageService.saveLowerStaffIds(lowerStaffIds);
            await LocalStorageService.saveIsManagerLevel(isHigherLevelOfficer);
          } catch (e) {
            print('❌ Error resolving manager level: $e');
          }

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  duration: Duration(seconds: 1),
                  content: Text('Login successful.'),
                  backgroundColor: Colors.green),
            );
          }

          if (isHigherLevelOfficer) {
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (_) => const EscalatedTasksPage()),
              (route) => false,
            );
          } else {
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(
                  builder: (_) => const NavigationPage(initialIndex: 0)),
              (route) => false,
            );
          }

          PushNotificationService.handlePostLoginNavigation();
        } else {
          _showError('Invalid credentials');
        }
      } else {
        _showError('Invalid credentials. Please try again.');
      }
    } catch (_) {
      _showError('Login Failed. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoggingIn = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 1),
        backgroundColor: Colors.red));
  }
}
