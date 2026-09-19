import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:guestezee_staffs_app/Screens/login_page.dart';
import 'package:guestezee_staffs_app/app_theme.dart';
import 'package:pinput/pinput.dart';

class ForgotPinPage extends StatefulWidget {
  const ForgotPinPage({super.key});

  @override
  State<ForgotPinPage> createState() => _ForgotPinPageState();
}

class _ForgotPinPageState extends State<ForgotPinPage> {
  final TextEditingController _otpController = TextEditingController();
  final TextEditingController _pinController = TextEditingController();
  final TextEditingController _confirmPinController = TextEditingController();
  bool startValidate = false;
  bool startPhoneValidate = false;
  bool _showPinError = false;

  void _clearPinForm() {
    _pinController.clear();
    _confirmPinController.clear();
    _showPinError = false;
  }

  void _clearBottomSheetForm() {
    _otpController.clear();
    _clearPinForm();
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
    // OTP received, can be used for validation if needed
  }

  final TextEditingController phoneController = TextEditingController();
  @override
  Widget build(BuildContext context) {
    double screenHeight = MediaQuery.of(context).size.height;
    double screenWidth = MediaQuery.of(context).size.width;
    return Scaffold(
      bottomNavigationBar: Container(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 15.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Powered by '),
              Text(
                'GuestEzee',
                style:
                    TextStyle(color: Theme.of(context).colorScheme.secondary),
              )
            ],
          ),
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
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
                    height: MediaQuery.of(context).size.height * 0.0125,
                  ),
                  SizedBox(
                    height: screenHeight * .09,
                    width: screenHeight * .09,
                    child: Image.asset(
                      'assets/images/hotellogo.png',
                    ),
                  ),
                  Text(
                    'Forgot Pin',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: MediaQuery.of(context).size.width * 0.075,
                        fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Reset your Pin for Further Access',
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
                    child: Text("Phone Number",
                        style: TextStyle(
                            color: Color(0xff6C7278),
                            fontSize:
                                MediaQuery.of(context).size.width * 0.035)),
                  ),
                  SizedBox(height: screenHeight * 0.01),
                  TextField(
                    maxLength: 10,
                    controller: phoneController,
                    keyboardType: TextInputType.number,
                    onChanged: (_) {
                      setState(() {
                        startPhoneValidate = true;
                      });
                    },
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                        counterText: ' ',
                        enabledBorder: _normalBorder(),
                        focusedBorder: _normalBorder(),
                        errorText: (startPhoneValidate || startValidate)
                            ? phoneController.text.isEmpty
                                ? 'Phone Number is required'
                                : phoneController.text.length < 10
                                    ? 'Phone Number must be 10 digits'
                                    : null
                            : null,
                        focusedErrorBorder: _errorBorder(startPhoneValidate),
                        errorBorder: _errorBorder(startPhoneValidate)),
                  ),
                  Container(
                    width: screenWidth,
                    height: MediaQuery.of(context).size.height * 0.056,
                    child: ElevatedButton(
                        onPressed: () {
                          Timer? timer;
                          Duration duration = Duration(seconds: 30);
                          bool start = false;
                          bool resend = false;

                          String formatTimer(Duration d) {
                            String twoDigits(int i) =>
                                i.toString().padLeft(2, '0');
                            return '${twoDigits(d.inMinutes.remainder(60))}:${twoDigits(d.inSeconds.remainder(60))}';
                          }

                          void timerStart(StateSetter setModalState) {
                            if (timer != null && timer!.isActive) return;
                            setModalState(() {
                              start = true;
                              resend = false;
                              duration = Duration(seconds: 30);
                            });
                            timer =
                                Timer.periodic(Duration(seconds: 1), (Timer t) {
                              if (duration.inSeconds > 1) {
                                setModalState(() {
                                  duration -= Duration(seconds: 1);
                                });
                              } else {
                                setModalState(() {
                                  t.cancel();
                                  start = false;
                                  resend = true;
                                });
                              }
                            });
                          }

                          _clearBottomSheetForm();
                          showModalBottomSheet(
                            backgroundColor: AppTheme.colorScheme.surface,
                            context: context,
                            isScrollControlled: true,
                            builder: (context) {
                              return StatefulBuilder(
                                  builder: (context, setModalState) {
                                return Stack(children: [
                                  Padding(
                                    padding: EdgeInsets.only(
                                      bottom: MediaQuery.of(context)
                                          .viewInsets
                                          .bottom,
                                    ),
                                    child: SingleChildScrollView(
                                      child: Padding(
                                        padding: const EdgeInsets.all(16.0),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.center,
                                          children: [
                                            Center(
                                              child: SizedBox(
                                                height: screenHeight * .09,
                                                width: screenHeight * .09,
                                                child: Image.asset(
                                                    'assets/images/otpphone.png'),
                                              ),
                                            ),
                                            // const SizedBox(height: 10),
                                            const Center(
                                              child: Text(
                                                'Enter OTP',
                                                style: TextStyle(
                                                    color: Colors.black,
                                                    fontSize: 25,
                                                    fontWeight:
                                                        FontWeight.bold),
                                              ),
                                            ),
                                            const SizedBox(height: 10),
                                            Pinput(
                                              controller: _otpController,
                                              length: 5,
                                              defaultPinTheme:
                                                  _defaultPinTheme(context),
                                              focusedPinTheme:
                                                  _focusedPinTheme(context),
                                              submittedPinTheme:
                                                  _submittedPinTheme(context),
                                              showCursor: true,
                                              hapticFeedbackType:
                                                  HapticFeedbackType
                                                      .lightImpact,
                                              onCompleted: (pin) {
                                                _getOtp(pin);
                                              },
                                              onChanged: (value) {
                                                _getOtp(value);
                                              },
                                            ),
                                            const SizedBox(height: 10),
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              children: [
                                                Row(
                                                  children: [
                                                    Text(
                                                        'Didn’t Received OTP? ',
                                                        style: TextStyle(
                                                            color: Color(
                                                                0xff6C7278))),
                                                    GestureDetector(
                                                      onTap: () {
                                                        timerStart(
                                                            setModalState);
                                                      },
                                                      child: Text('Click Here',
                                                          style: TextStyle(
                                                            color: Theme.of(
                                                                    context)
                                                                .colorScheme
                                                                .secondary,
                                                          )),
                                                    )
                                                  ],
                                                ),
                                                start
                                                    ? Text(
                                                        formatTimer(duration),
                                                        style: TextStyle(
                                                            color: Theme.of(
                                                                    context)
                                                                .colorScheme
                                                                .primary,
                                                            fontWeight:
                                                                FontWeight
                                                                    .bold),
                                                      )
                                                    : resend
                                                        ? GestureDetector(
                                                            onTap: () {
                                                              setState(() {
                                                                timerStart(
                                                                    setModalState);
                                                              });
                                                            },
                                                            child: Text(
                                                                'Resend',
                                                                style: TextStyle(
                                                                    color: Theme.of(
                                                                            context)
                                                                        .colorScheme
                                                                        .primary,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .bold)))
                                                        : SizedBox.shrink()
                                              ],
                                            ),

                                            const SizedBox(height: 10),
                                            Center(
                                              child: SizedBox(
                                                height: screenHeight * .09,
                                                width: screenHeight * .09,
                                                child: Image.asset(
                                                    'assets/images/otpphone.png'),
                                              ),
                                            ),
                                            // const SizedBox(height: 10),
                                            const Center(
                                              child: Text(
                                                'Create New Pin',
                                                style: TextStyle(
                                                    color: Colors.black,
                                                    fontSize: 25,
                                                    fontWeight:
                                                        FontWeight.bold),
                                              ),
                                            ),
                                            const SizedBox(height: 16),
                                            Align(
                                              alignment: Alignment.centerLeft,
                                              child: Text('Enter Pin',
                                                  style: TextStyle(
                                                      color: Color(0xff6C7278),
                                                      fontSize: 12)),
                                            ),
                                            const SizedBox(height: 8),
                                            Pinput(
                                              controller: _pinController,
                                              length: 4,
                                              defaultPinTheme:
                                                  _defaultPinTheme(context),
                                              focusedPinTheme:
                                                  _focusedPinTheme(context),
                                              submittedPinTheme:
                                                  _submittedPinTheme(context),
                                              showCursor: true,
                                              forceErrorState: _showPinError,
                                            ),
                                            const SizedBox(height: 6),
                                            Align(
                                              alignment: Alignment.centerLeft,
                                              child: Text('Confirm Pin',
                                                  style: TextStyle(
                                                      color: Color(0xff6C7278),
                                                      fontSize: 12)),
                                            ),
                                            const SizedBox(height: 8),
                                            Pinput(
                                              controller: _confirmPinController,
                                              length: 4,
                                              defaultPinTheme:
                                                  _defaultPinTheme(context),
                                              focusedPinTheme:
                                                  _focusedPinTheme(context),
                                              submittedPinTheme:
                                                  _submittedPinTheme(context),
                                              showCursor: true,
                                              errorText: _showPinError
                                                  ? 'Pins do not match'
                                                  : null,
                                              forceErrorState: _showPinError,
                                            ),
                                            _showPinError
                                                ? SizedBox(height: 10)
                                                : SizedBox(height: 20),
                                            SizedBox(
                                              width: double.infinity,
                                              height: 50,
                                              child: ElevatedButton(
                                                onPressed: () {
                                                  // Navigator.of(context)
                                                  //     .push(
                                                  //   MaterialPageRoute(
                                                  //     builder: (BuildContext
                                                  //             context) =>
                                                  //         LoginPage(),
                                                  //   ),
                                                  // );
                                                  final pin =
                                                      _pinController.text;
                                                  final confirmPin =
                                                      _confirmPinController
                                                          .text;
                                                  if (pin.length < 4 ||
                                                      confirmPin.length < 4 ||
                                                      pin != confirmPin) {
                                                    setModalState(() =>
                                                        _showPinError = true);
                                                  } else {
                                                    setModalState(() =>
                                                        _showPinError = false);
                                                    Navigator.of(context).push(
                                                      MaterialPageRoute(
                                                        builder: (BuildContext
                                                                context) =>
                                                            LoginPage(),
                                                      ),
                                                    );
                                                  }
                                                },
                                                child: const Text('Confirm'),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                      right: 16,
                                      top: 16,
                                      child: IconButton(
                                          onPressed: () {
                                            Navigator.pop(context);
                                          },
                                          icon: Icon(
                                            Icons.cancel,
                                            color: Color(0xffB9B9B9),
                                          )))
                                ]);
                              });
                            },
                          ).whenComplete(() {
                            if (!mounted) return;
                            setState(_clearBottomSheetForm);
                          });
                        },
                        child: Text('Send OTP')),
                  )
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}

InputBorder _normalBorder() => OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: Color(0xff6C7278)),
    );

InputBorder _errorBorder(bool showError) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: showError ? Colors.red : Color(0xff6C7278)),
    );
