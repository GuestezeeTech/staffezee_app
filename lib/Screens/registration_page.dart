import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:guestezee_staffs_app/Screens/login_page.dart';
import 'package:guestezee_staffs_app/Screens/static_content_page.dart';
import 'package:guestezee_staffs_app/app_theme.dart';
import 'package:guestezee_staffs_app/Services/hotel_status_service.dart';
import 'package:guestezee_staffs_app/Services/staff_service.dart';
import 'package:pinput/pinput.dart';

class RegistrationPage extends StatefulWidget {
  const RegistrationPage({
    super.key,
    this.employeeId,
    this.isForgotPin = false,
  });

  final String? employeeId;

  /// When true, reuses register flow for PIN reset with forgot-PIN labels.
  final bool isForgotPin;

  @override
  State<RegistrationPage> createState() => _RegistrationPageState();
}

class _RegistrationPageState extends State<RegistrationPage> {
  final TextEditingController _employeeIdController = TextEditingController();
  final TextEditingController _pinController = TextEditingController();
  final TextEditingController _confirmPinController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();
  final FocusNode _otpFocusNode = FocusNode();

  bool _isLoading = false;
  bool _showPinError = false;
  bool _startIdValidate = false;
  bool _disableButton = true;
  String? _staffPhoneNumber;
  String? _staffEmail;
  String? _staffEmployeeNumber;
  String? _otpReferenceId;
  void Function(String? message)? _setOtpError;

  bool get _isForgotPin => widget.isForgotPin;

  String get _headerTitle => _isForgotPin ? 'Forgot PIN' : 'Welcome Back!!';

  String get _headerSubtitle => _isForgotPin
      ? 'Enter Employee ID to reset your PIN'
      : 'New User Generate Pin to Access your ID';

  String get _primaryButtonLabel => _isForgotPin ? 'Send OTP' : 'Generate Pin';

  String get _pinModalTitle => _isForgotPin ? 'Set New PIN' : 'Create Pin';

  String get _pinSubmitLabel => _isForgotPin ? 'Update PIN' : 'Create Pin';

  String get _pinSuccessMessage => _isForgotPin
      ? 'PIN updated successfully! Please login.'
      : 'Pin created successfully! Please login.';

  @override
  void initState() {
    super.initState();
    if (widget.employeeId != null && widget.employeeId!.isNotEmpty) {
      _employeeIdController.text = widget.employeeId!.toUpperCase();
      _startIdValidate = true;
    }
    // On web, disable the browser's context menu since this example uses a custom
    // Flutter-rendered context menu.
    if (kIsWeb) {
      BrowserContextMenu.disableContextMenu();
    }
  }

  @override
  void dispose() {
    if (kIsWeb) {
      BrowserContextMenu.enableContextMenu();
    }
    _employeeIdController.dispose();
    _pinController.dispose();
    _confirmPinController.dispose();
    _otpController.dispose();
    _otpFocusNode.dispose();
    super.dispose();
  }

  PinTheme _defaultPinTheme(BuildContext context) => PinTheme(
        width: MediaQuery.of(context).size.width * 0.1125,
        height: MediaQuery.of(context).size.width * 0.1125,
        textStyle: TextStyle(
          fontSize: MediaQuery.of(context).size.width * 0.05,
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
        decoration: BoxDecoration(
          border:
              const Border.fromBorderSide(BorderSide(color: Color(0xff6C7278))),
          borderRadius: BorderRadius.circular(10),
        ),
      );

  PinTheme _focusedPinTheme(BuildContext context) =>
      _defaultPinTheme(context).copyDecorationWith(
        border: Border.all(color: Theme.of(context).colorScheme.secondary),
        borderRadius: BorderRadius.circular(8),
      );

  PinTheme _submittedPinTheme(BuildContext context) =>
      _defaultPinTheme(context).copyWith(
        decoration: _defaultPinTheme(context).decoration!.copyWith(
              color: const Color.fromARGB(255, 238, 236, 235),
            ),
      );

  void _getOtp(String otp) {
    if (otp.length == 5) {
      setState(() {
        _disableButton = false;
      });
    } else {
      setState(() {
        _disableButton = true;
      });
    }
  }

  int? _parseMobileNumber(String? phone) {
    if (phone == null || phone.trim().isEmpty) return null;
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return null;
    return int.tryParse(digits);
  }

  /// Same gates as login: staff is_active + customer getall hotel_enabled.
  /// Returns false when blocked (modal already shown).
  Future<bool> _assertStaffAndHotelAccess(Map<String, dynamic> staff) async {
    if (!HotelStatusService.isActiveForUser(staff)) {
      HotelStatusService.showInactiveLoginBlock();
      FocusScope.of(context).unfocus();
      if (mounted) setState(() {});
      return false;
    }

    final memberId = (staff['member_id'] ?? staff['staff_member_id'] ?? '')
        .toString()
        .trim();
    final hotelOk = await HotelStatusService.checkCustomerHotelAccess(
      memberId,
      applyToSession: false,
    );
    if (!hotelOk) {
      HotelStatusService.showLoginBlock();
      FocusScope.of(context).unfocus();
      if (mounted) setState(() {});
      return false;
    }

    return true;
  }

  Future<void> _handleGeneratePin() async {
    if (_employeeIdController.text.isEmpty) {
      setState(() {
        _startIdValidate = true;
      });
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // First, get all staff to find the employee
      final response = await StaffService.findStaffByEmployeeNumber(
          _employeeIdController.text.trim().toUpperCase());

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);

        // Check if the response has the expected structure
        if (data.containsKey('success') && data['success'] == 1) {
          // Check if data array is not empty
          if (data.containsKey('result') &&
              data['result'] != null &&
              data['result'].containsKey('data') &&
              data['result']['data'] != null &&
              data['result']['data'] is List &&
              data['result']['data'].isNotEmpty) {
            final rawStaff = data['result']['data'][0];
            if (rawStaff is! Map) {
              _showSnackBar(
                  'Invalid credentials. Employee ID not found.', Colors.red);
              return;
            }
            final staffData = Map<String, dynamic>.from(rawStaff);

            // Lock with modal if inactive staff or hotel disabled / no customer.
            final accessOk = await _assertStaffAndHotelAccess(staffData);
            if (!accessOk) return;

            setState(() {
              _staffPhoneNumber = staffData['phone_number']?.toString();
              _staffEmail = staffData['email']?.toString();
              _staffEmployeeNumber = staffData['staff_employee_number'];
            });

            // Check if staff already has pin
            final hasPin = staffData['pin'] != null &&
                staffData['pin'].toString().trim().isNotEmpty;

            if (_isForgotPin) {
              // Forgot PIN: must already have a PIN; then OTP → set new PIN.
              if (!hasPin) {
                _showSnackBar(
                  'No PIN found. Please register first.',
                  Colors.orange,
                );
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => RegistrationPage(
                      employeeId:
                          _employeeIdController.text.trim().toUpperCase(),
                    ),
                  ),
                );
              } else {
                await _generateOtp();
              }
            } else if (hasPin) {
              // Register: already has pin → login
              _showSnackBar(
                  'You already have an account. Please login.', Colors.blue);
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                    builder: (context) => LoginPage(
                        employeeId:
                            _employeeIdController.text.trim().toUpperCase())),
              );
            } else {
              // Register: no pin → OTP
              await _generateOtp();
            }
          } else {
            // No records found - invalid credentials
            _showSnackBar(
                'Invalid credentials. Employee ID not found.', Colors.red);
          }
        } else {
          // API returned success: 0 or other error
          _showSnackBar(
              'Invalid credentials. Employee ID not found.', Colors.red);
        }
      } else {
        _showSnackBar(
            'Error connecting to server. Please try again.', Colors.red);
      }
    } catch (e) {
      _showSnackBar('An error occurred. Please try again.', Colors.red);
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _generateOtp() async {
    final email = _staffEmail?.trim();
    final mobile = _parseMobileNumber(_staffPhoneNumber);

    if (email == null || email.isEmpty) {
      _showSnackBar(
          'Registered email not found for this employee.', Colors.red);
      return;
    }
    if (mobile == null) {
      _showSnackBar(
          'Registered phone number not found for this employee.', Colors.red);
      return;
    }

    try {
      final response = await StaffService.sendOtp(
        recipientEmail: email,
        recipientMobile: mobile,
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);

        if (data['success'] == 1) {
          final refId = data['reference_id']?.toString();
          if (refId == null || refId.isEmpty) {
            _showSnackBar('OTP sent but reference id missing.', Colors.red);
            return;
          }
          setState(() {
            _otpReferenceId = refId;
          });
          _showOtpModal();
        } else {
          final message = data['message']?.toString() ??
              'Failed to send OTP. Please try again.';
          _showSnackBar(message, Colors.red);
        }
      } else {
        _showSnackBar('Error sending OTP. Please try again.', Colors.red);
      }
    } catch (e) {
      _showSnackBar('Error sending OTP. Please try again.', Colors.red);
    }
  }

  Future<void> _verifyOtpAndCreatePassword(String otp) async {
    final referenceId = _otpReferenceId;
    if (referenceId == null || referenceId.isEmpty) {
      _showSnackBar(
          'OTP session expired. Please request OTP again.', Colors.red);
      return;
    }

    try {
      final response = await StaffService.verifyOtp(
        referenceId: referenceId,
        otpCode: otp,
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);

        if (data['success'] == 1) {
          _showSnackBar('OTP verified successfully!', Colors.green);
          _showPasswordModal();
        } else {
          final String message = (data is Map && data['message'] is String)
              ? data['message']
              : 'Incorrect OTP. Please try again.';
          // Show both snackbar and inline error for better UX
          _showSnackBar(message, Colors.red);
          if (_setOtpError != null) {
            _setOtpError!(message);
          }
          // Let user re-enter: clear and refocus OTP field
          _otpController.clear();
          _getOtp('');
          _otpFocusNode.requestFocus();
        }
      } else {
        _showSnackBar('Error verifying OTP. Please try again.', Colors.red);
      }
    } catch (e) {
      _showSnackBar('Error verifying OTP. Please try again.', Colors.red);
    }
  }

  Future<void> _updateStaffPin(String pin) async {
    if (_staffEmployeeNumber == null) return;

    try {
      // Re-check staff active + hotel before saving PIN.
      final staffResponse = await StaffService.findStaffByEmployeeNumber(
        _staffEmployeeNumber!.toString(),
      );
      if (staffResponse.statusCode == 200 || staffResponse.statusCode == 201) {
        final body = jsonDecode(staffResponse.body);

        final list = body is Map ? (body['result']?['data'] ?? []) : [];

        if (list is List && list.isNotEmpty && list.first is Map) {
          final staff = Map<String, dynamic>.from(list.first as Map);

          final accessOk = await _assertStaffAndHotelAccess(staff);

          if (!accessOk) {
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            }
            return;
          }
        }
      }

      final response =
          await StaffService.updateStaffPin(_staffEmployeeNumber!, pin);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);

        if (data['success'] == 1) {
          if (Navigator.canPop(context)) {
            Navigator.pop(context);
          }
          _clearPinForm();
          _showSnackBar(_pinSuccessMessage, Colors.green);
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
                builder: (context) =>
                    LoginPage(
                        employeeId:
                            _employeeIdController.text.trim().toUpperCase())),
          );
        } else {
          _showSnackBar(
            _isForgotPin
                ? 'Failed to update PIN. Please try again.'
                : 'Failed to create pin. Please try again.',
            Colors.red,
          );
        }
      } else {
        _showSnackBar(
          _isForgotPin
              ? 'Error updating PIN. Please try again.'
              : 'Error creating pin. Please try again.',
          Colors.red,
        );
      }
    } catch (e) {
      _showSnackBar(
        _isForgotPin
            ? 'Error updating PIN. Please try again.'
            : 'Error creating pin. Please try again.',
        Colors.red,
      );
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _clearPinForm() {
    _pinController.clear();
    _confirmPinController.clear();
    _showPinError = false;
  }

  void _clearOtpForm() {
    _otpController.clear();
    _disableButton = true;
    _setOtpError = null;
  }

  void _showOtpModal() {
    _clearOtpForm();
    showModalBottomSheet(
      backgroundColor: AppTheme.colorScheme.surface,
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            String? modalError;
            // expose setter so async verifier can update inline error
            _setOtpError = (String? msg) {
              setModalState(() {
                modalError = msg;
              });
            };
            return SafeArea(
              child: Stack(
                children: [
                  Padding(
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.of(context).viewInsets.bottom,
                    ),
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Center(
                              child: SizedBox(
                                height:
                                    MediaQuery.of(context).size.height * .09,
                                width: MediaQuery.of(context).size.height * .09,
                                child:
                                    Image.asset('assets/images/otpphone.png'),
                              ),
                            ),
                            Center(
                              child: Text(
                                'Enter OTP',
                                style: TextStyle(
                                  color: Colors.black,
                                  fontSize: MediaQuery.of(context).size.width *
                                      0.0625,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            SizedBox(
                                height: MediaQuery.of(context).size.height *
                                    0.0125),
                            const Text(
                              'OTP sent to your registered email and phone number',
                              style: TextStyle(color: Color(0xff6C7278)),
                            ),
                            SizedBox(
                                height:
                                    MediaQuery.of(context).size.height * 0.025),
                            Directionality(
                              textDirection: TextDirection.ltr,
                              child: Pinput(
                                controller: _otpController,
                                focusNode: _otpFocusNode,
                                length: 5,
                                defaultPinTheme: _defaultPinTheme(context),
                                focusedPinTheme: _focusedPinTheme(context),
                                submittedPinTheme: _submittedPinTheme(context),
                                showCursor: true,
                                hapticFeedbackType:
                                    HapticFeedbackType.lightImpact,
                                onCompleted: (pin) {
                                  _verifyOtpAndCreatePassword(pin);
                                },
                                onChanged: (value) {
                                  _getOtp(value);
                                },
                              ),
                            ),
                            if (modalError != null) ...[
                              SizedBox(
                                  height: MediaQuery.of(context).size.height *
                                      0.01),
                              Text(
                                modalError!,
                                style: TextStyle(
                                    color: Colors.red,
                                    fontSize:
                                        MediaQuery.of(context).size.width *
                                            0.03),
                              ),
                            ],
                            SizedBox(
                                height:
                                    MediaQuery.of(context).size.height * 0.025),
                            SizedBox(
                              width: double.infinity,
                              height:
                                  MediaQuery.of(context).size.height * 0.062,
                              child: ElevatedButton(
                                onPressed: _disableButton
                                    ? null
                                    : () {
                                        _verifyOtpAndCreatePassword(
                                            _otpController.text);
                                      },
                                child: const Text('Verify OTP'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 8,
                    top: 8,
                    child: IconButton(
                      onPressed: () {
                        Navigator.pop(context);
                      },
                      icon: const Icon(
                        Icons.cancel,
                        color: Color(0xffB9B9B9),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      if (!mounted) return;
      setState(_clearOtpForm);
    });
  }

  void _showPasswordModal() {
    Navigator.pop(context); // Close OTP modal first
    _clearPinForm();

    showModalBottomSheet(
      backgroundColor: AppTheme.colorScheme.surface,
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Stack(
                children: [
                  Padding(
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.of(context).viewInsets.bottom,
                    ),
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Center(
                              child: SizedBox(
                                height:
                                    MediaQuery.of(context).size.height * .09,
                                width: MediaQuery.of(context).size.height * .09,
                                child:
                                    Image.asset('assets/images/otpphone.png'),
                              ),
                            ),
                            Center(
                              child: Text(
                                _pinModalTitle,
                                style: TextStyle(
                                  color: Colors.black,
                                  fontSize: MediaQuery.of(context).size.width *
                                      0.0625,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                _isForgotPin ? 'Enter New Pin' : 'Enter Pin',
                                style: const TextStyle(
                                  color: Color(0xff6C7278),
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Pinput(
                              controller: _pinController,
                              length: 4,
                              defaultPinTheme: _defaultPinTheme(context),
                              focusedPinTheme: _focusedPinTheme(context),
                              submittedPinTheme: _submittedPinTheme(context),
                              showCursor: true,
                              forceErrorState: _showPinError,
                            ),
                            const SizedBox(height: 6),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                _isForgotPin
                                    ? 'Confirm New Pin'
                                    : 'Confirm Pin',
                                style: const TextStyle(
                                  color: Color(0xff6C7278),
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Pinput(
                              controller: _confirmPinController,
                              length: 4,
                              defaultPinTheme: _defaultPinTheme(context),
                              focusedPinTheme: _focusedPinTheme(context),
                              submittedPinTheme: _submittedPinTheme(context),
                              showCursor: true,
                              errorText:
                                  _showPinError ? 'Pins do not match' : null,
                              forceErrorState: _showPinError,
                            ),
                            _showPinError
                                ? const SizedBox(height: 10)
                                : SizedBox(
                                    height: MediaQuery.of(context).size.height *
                                        0.025),
                            SizedBox(
                              width: double.infinity,
                              height:
                                  MediaQuery.of(context).size.height * 0.062,
                              child: ElevatedButton(
                                onPressed: () {
                                  final pin = _pinController.text;
                                  final confirmPin = _confirmPinController.text;

                                  if (pin.length < 4 ||
                                      confirmPin.length < 4 ||
                                      pin != confirmPin) {
                                    setModalState(() => _showPinError = true);
                                  } else {
                                    setModalState(() => _showPinError = false);
                                    _updateStaffPin(pin);
                                  }
                                },
                                child: Text(_pinSubmitLabel),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 8,
                    top: 8,
                    child: IconButton(
                      onPressed: () {
                        Navigator.pop(context);
                      },
                      icon: const Icon(
                        Icons.cancel,
                        color: Color(0xffB9B9B9),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      if (!mounted) return;
      setState(_clearPinForm);
    });
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
                    borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(25)),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    spacing: 10,
                    children: [
                      const SizedBox(height: 10),
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
                        _headerTitle,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 30,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        _headerSubtitle,
                        textAlign: TextAlign.center,
                        style: AppTheme.extraLightText,
                      )
                    ],
                  ),
                ),
                Padding(
                  padding:
                      const EdgeInsets.only(right: 16.0, left: 16, top: 16),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      SizedBox(
                        height: screenHeight * .3,
                        child: Image.asset('assets/images/otplogo.png'),
                      ),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          "Employee ID",
                          style: TextStyle(color: Color(0xff6C7278)),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.only(top: screenHeight * 0.01),
                        child: TextField(
                          keyboardType: TextInputType.text,
                          textCapitalization: TextCapitalization.characters,
                          inputFormatters: [
                            TextInputFormatter.withFunction(
                              (oldValue, newValue) => newValue.copyWith(
                                text: newValue.text.toUpperCase(),
                              ),
                            ),
                          ],
                          maxLength: 25,
                          controller: _employeeIdController,
                          decoration: InputDecoration(
                            counterText: ' ',
                            errorBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(
                                color: (_startIdValidate) &&
                                        _employeeIdController.text.isEmpty
                                    ? Colors.red
                                    : const Color(0xff6C7278),
                              ),
                            ),
                            focusedErrorBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(
                                color: _employeeIdController.text.isEmpty
                                    ? Colors.red
                                    : const Color(0xff6C7278),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide:
                                  const BorderSide(color: Color(0xff6C7278)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide:
                                  const BorderSide(color: Color(0xff6C7278)),
                            ),
                            errorText: _startIdValidate
                                ? _employeeIdController.text.isEmpty
                                    ? "Employee ID is required"
                                    : null
                                : null,
                          ),
                          onChanged: (value) {
                            setState(() {
                              _startIdValidate = true;
                            });
                          },
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.only(top: screenHeight * 0.01),
                        child: Container(
                          height: MediaQuery.of(context).size.height * 0.062,
                          width: screenWidth,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _handleGeneratePin,
                            child: _isLoading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                          Colors.white),
                                    ),
                                  )
                                : Text(_primaryButtonLabel),
                          ),
                        ),
                      ),
                      SizedBox(
                          height: MediaQuery.of(context).size.height * 0.025),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _isForgotPin
                                ? 'Remember your PIN? '
                                : 'Already have an account? ',
                            style: const TextStyle(color: Color(0xff6C7278)),
                          ),
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(
                                    builder: (context) => const LoginPage()),
                              );
                            },
                            child: Text(
                              'Login',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.secondary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      // if (!_isForgotPin) ...[
                      //   SizedBox(
                      //       height: MediaQuery.of(context).size.height * 0.015),
                      //   Row(
                      //     mainAxisAlignment: MainAxisAlignment.center,
                      //     children: [
                      //       const Text(
                      //         'Forgot PIN? ',
                      //         style: TextStyle(color: Color(0xff6C7278)),
                      //       ),
                      //       GestureDetector(
                      //         behavior: HitTestBehavior.opaque,
                      //         onTap: () {
                      //           Navigator.pushReplacement(
                      //             context,
                      //             MaterialPageRoute(
                      //               builder: (context) => RegistrationPage(
                      //                 employeeId:
                      //                     _employeeIdController.text.trim(),
                      //                 isForgotPin: true,
                      //               ),
                      //             ),
                      //           );
                      //         },
                      //         child: Text(
                      //           'Reset here',
                      //           style: TextStyle(
                      //             color:
                      //                 Theme.of(context).colorScheme.secondary,
                      //             fontWeight: FontWeight.bold,
                      //           ),
                      //         ),
                      //       ),
                      //     ],
                      //   ),
                      // ],
                      SizedBox(
                          height: MediaQuery.of(context).size.height * 0.025),
                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) => StaticContentPage(
                                      title: 'Privacy Policy',
                                      isPrivacyPolicy: true)));
                        },
                        child: Text('Privacy Policy'),
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
}
