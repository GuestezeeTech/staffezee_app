import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:guestezee_staffs_app/Config/api_end_points.dart';
import 'package:guestezee_staffs_app/Config/primary_config.dart';
import 'package:guestezee_staffs_app/Custom Widgets/hotel_name_header.dart';
import 'package:guestezee_staffs_app/Custom%20Widgets/navigation_page.dart';
import 'package:guestezee_staffs_app/Screens/login_page.dart';
import 'package:guestezee_staffs_app/Services/local_storage_service.dart';
import 'package:guestezee_staffs_app/Services/staff_service.dart';
import 'package:guestezee_staffs_app/Services/staff_presence_service.dart';
import 'package:guestezee_staffs_app/Screens/registration_page.dart';
import 'package:guestezee_staffs_app/Services/notification_settings_service.dart';
import 'package:guestezee_staffs_app/Services/push_notification_service.dart';
import 'package:guestezee_staffs_app/Screens/static_content_page.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shimmer/shimmer.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool showProfilePage = false;
  bool showMyRatings = false;
  bool aboutUs = false;
  List<bool> toggleStates = [false, false, false, false, false, true, false];
  bool _availability = true;
  bool _availabilityLoading = false;
  bool _isUploadingProfileImage = false;
  Map<String, dynamic>? _staffData;
  String _hotelName = '';
  bool _hotelNameLoading = false;

  bool isAnySectionVisible = false;
  bool isSettingsListVisible = true;
  Map keysValues = {
    'text': [
      'Profile',
      'Notifications',
      // 'Rating', // Commented out ratings section as it uses static values
      'Terms and Conditions',
      'Privacy Policy',
      'About us',
      'Logout'
    ],
    'imageText': [
      'pro1',
      'pro2', // Using pro2 for notifications
      // 'pro2', // Commented out ratings icon as it uses static values
      'pro3',
      'pro4',
      'pro5',
      'pro6',
    ]
  };

  List<String> keys = [
    'Reporting Manager',
    'Phone Number',
    'Email Id',
    'Employee ID'
  ];

  List<bool> bools = [true, true, true, false];
  String thatText = '';

  Map<String, dynamic>? _normalizeUser(dynamic rawUser) {
    if (rawUser is Map) {
      return rawUser.map((key, value) => MapEntry(key.toString(), value));
    }
    return null;
  }

  dynamic _getStaffIdentifier(dynamic rawUser) {
    final user = _normalizeUser(rawUser);
    if (user == null) return null;
    final dynamic idValue = user['id'];
    if (idValue is int) return idValue;
    final int? parsedId = int.tryParse(idValue?.toString() ?? '');
    if (parsedId != null) return parsedId;

    final String legacy = _getLegacyEmployeeNumber(user);
    return legacy.isNotEmpty ? legacy : null;
  }

  String _getLegacyEmployeeNumber(dynamic rawUser) {
    final user = _normalizeUser(rawUser);
    return (user?['staff_employee_number'] ?? user?['staff_member_id'] ?? '')
        .toString();
  }

  ImageProvider? _resolveProfileImageProvider(String imageValue) {
    final String trimmed = imageValue.trim();
    if (trimmed.isEmpty) return null;

    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return NetworkImage(trimmed);
    }

    if (trimmed.startsWith('data:image')) {
      try {
        final int commaIndex = trimmed.indexOf(',');
        if (commaIndex == -1) return null;
        final String encoded = trimmed.substring(commaIndex + 1);
        final bytes = base64Decode(encoded);
        return MemoryImage(bytes);
      } catch (_) {
        return null;
      }
    }

    return null;
  }

  Future<void> _pickAndUploadProfileImage() async {
    if (_isUploadingProfileImage) return;

    final dynamic currentUser = _staffData ?? LocalStorageService.user;
    final dynamic staffIdentifier = _getStaffIdentifier(currentUser);
    if (staffIdentifier == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Staff details not found.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final picked = await FilePicker.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: false,
    );
    if (picked == null ||
        picked.files.isEmpty ||
        picked.files.single.path == null) {
      return;
    }

    final String filePath = picked.files.single.path!;
    final String normalizedPath = filePath.toLowerCase();
    final bool isAllowed = normalizedPath.endsWith('.jpg') ||
        normalizedPath.endsWith('.jpeg') ||
        normalizedPath.endsWith('.png') ||
        normalizedPath.endsWith('.heif') ||
        normalizedPath.endsWith('.heic');
    if (!isAllowed) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Only JPG, JPEG, PNG, HEIF, and HEIC images are allowed.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isUploadingProfileImage = true;
    });

    try {
      final localFile = File(filePath);
      final String? uploadedUrl = await _uploadImageToAWS(localFile);
      if (uploadedUrl == null || uploadedUrl.trim().isEmpty) {
        throw Exception('Image upload failed');
      }

      final updateRes = await StaffService.updateStaffProfileImage(
        staffIdentifier,
        uploadedUrl,
      );
      final Map<String, dynamic> parsed = updateRes.body.isNotEmpty
          ? (jsonDecode(updateRes.body) as Map<String, dynamic>)
          : <String, dynamic>{};
      final bool isSuccess = parsed['success'] == 1 &&
          (parsed['status_code'] == 200 || parsed['status_code'] == 201);
      if (!isSuccess) {
        throw Exception(parsed['message'] ?? 'Failed to update profile image');
      }

      await LocalStorageService.init();
      final storedUser = Hive.box('authBox').get('user');
      if (storedUser is Map) {
        final updatedUser = Map<String, dynamic>.from(storedUser);
        updatedUser['profile_image'] = uploadedUrl;
        await Hive.box('authBox').put('user', updatedUser);
      }

      if (!mounted) return;
      setState(() {
        _staffData = {
          ...?_staffData,
          'profile_image': uploadedUrl,
        };
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile image updated successfully'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile image update failed!'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingProfileImage = false;
        });
      }
    }
  }

  Future<void> _showProfileImageDialog(ImageProvider imageProvider) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: Stack(
            children: [
              Container(
                width: double.infinity,
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(dialogContext).size.height * 0.75,
                ),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image(
                    image: imageProvider,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(dialogContext),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showProfileImageOptionsBottomSheet() async {
    if (!mounted || _isUploadingProfileImage) return;

    final user = LocalStorageService.user;
    final String profileImageValue =
        (_staffData?['profile_image'] ?? user?['profile_image'] ?? '')
            .toString();
    final ImageProvider? profileImageProvider =
        _resolveProfileImageProvider(profileImageValue);

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (profileImageProvider != null)
                  ListTile(
                    leading: const Icon(Icons.visibility_outlined),
                    title: const Text('View profile image'),
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      await _showProfileImageDialog(profileImageProvider);
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.image_outlined),
                  title: const Text('Upload profile image'),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    await _pickAndUploadProfileImage();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.close),
                  title: const Text('Cancel'),
                  onTap: () => Navigator.pop(sheetContext),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<String?> _uploadImageToAWS(File imageFile) async {
    final uri = Uri.parse(
      "${PrimaryConfigData.domainName}:${ApiEndPoints.imageupload}",
    );

    final request = http.MultipartRequest('POST', uri)
      ..headers.addAll({
        'Accept': 'application/json,text/plain,*/*',
        'domain_name': PrimaryConfigData.domainName,
        'source': 'Product',
      })
      ..files.add(
        await http.MultipartFile.fromPath(
          'upload',
          imageFile.path,
          filename: imageFile.path.split('/').last,
          contentType: _getMediaType(imageFile.path),
        ),
      );

    final response = await request.send();

    if (response.statusCode == 200 || response.statusCode == 201) {
      final body = await response.stream.bytesToString();
      final imageUrl = _extractImageUrl(body);
      if (imageUrl == null || imageUrl.isEmpty) {
        return null;
      }
      return imageUrl;
    }
    return null;
  }

  MediaType _getMediaType(String filePath) {
    final extension = filePath.split('.').last.toLowerCase();
    switch (extension) {
      case 'jpeg':
        return MediaType('image', 'jpeg');
      case 'png':
        return MediaType('image', 'png');
      case 'gif':
        return MediaType('image', 'gif');
      case 'jpg':
        return MediaType('image', 'jpg');
      case 'heif':
        return MediaType('image', 'heif');
      case 'heic':
        return MediaType('image', 'heic');
      default:
        return MediaType('application', 'octet-stream');
    }
  }

  String? _extractImageUrl(String body) {
    try {
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final data = decoded['result']?['data'];
      if (data is List && data.isNotEmpty) {
        final first = data.first;
        if (first is Map) {
          final location = first['location']?.toString();
          if (location != null && location.trim().isNotEmpty) {
            return location.trim();
          }
        }
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  void updateVisibilityFlags() {
    isAnySectionVisible = showProfilePage || showMyRatings || aboutUs;
    isSettingsListVisible = !isAnySectionVisible;
  }

  void handleItemTap(int index) async {
    double screenWidth = MediaQuery.of(context).size.width;

    setState(() {
      showProfilePage = false;
      showMyRatings = false;
      aboutUs = false;

      if (index == 0) {
        showProfilePage = true;
      } else if (index == 1) {
        // Handle notification settings - will be handled after setState
        return; // Exit early to handle notification settings separately
      }
      // Commented out ratings navigation as it uses static values
      // else if (index == 2) {
      //   showMyRatings = true;
      // }
      else if (index == 2) {
        // Terms and Conditions - navigate to static content page
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => StaticContentPage(
              title: 'Terms and Conditions',
              isPrivacyPolicy: false,
            ),
          ),
        );
        return; // Exit early to prevent setState
      } else if (index == 3) {
        // Privacy Policy - navigate to static content page
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => StaticContentPage(
              title: 'Privacy Policy',
              isPrivacyPolicy: true,
            ),
          ),
        );
        return; // Exit early to prevent setState
      } else if (index == 4) {
        // About Us - navigate to static content page
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => StaticContentPage(
              title: 'About Us',
              isAboutUs: true,
            ),
          ),
        );
        return; // Exit early to prevent setState
      } else if (index == 6) {
        // Logout is now at index 6
        showDialog(
            context: context,
            builder: (BuildContext dialogRootContext) {
              bool isLoggingOut = false;
              return StatefulBuilder(
                  builder: (context, setDialogState) => AlertDialog(
                        contentPadding: EdgeInsets.all(5),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        backgroundColor: Colors.white,
                        content: Container(
                          padding: EdgeInsets.all(16),
                          width: screenWidth,
                          decoration: BoxDecoration(
                            color: Colors.white,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            spacing: 15,
                            children: [
                              Image.asset(
                                'assets/images/logout.png',
                                scale: 4,
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Text(
                                    'Are you sure you need to ',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize:
                                            MediaQuery.of(context).size.width *
                                                0.04),
                                  ),
                                  Text(
                                    'Logout',
                                    style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                        fontSize:
                                            MediaQuery.of(context).size.width *
                                                0.04,
                                        fontWeight: FontWeight.w600),
                                  )
                                ],
                              ),
                              Row(
                                children: [
                                  Expanded(
                                    child: Container(
                                      height:
                                          MediaQuery.of(context).size.height *
                                              0.056,
                                      width: double.infinity,
                                      decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(5),
                                          border: Border.all(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .primary)),
                                      child: ElevatedButton(
                                          style: TextButton.styleFrom(
                                              backgroundColor: Colors.white,
                                              foregroundColor: Theme.of(context)
                                                  .colorScheme
                                                  .primary),
                                          onPressed: () {
                                            Navigator.pop(context);
                                          },
                                          child: Text(
                                            'Cancel',
                                            style: TextStyle(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .primary,
                                                fontWeight: FontWeight.w600),
                                          )),
                                    ),
                                  ),
                                  SizedBox(
                                      width: MediaQuery.of(context).size.width *
                                          0.025),
                                  Expanded(
                                    child: Container(
                                      height:
                                          MediaQuery.of(context).size.height *
                                              0.056,
                                      width: double.infinity,
                                      child: ElevatedButton(
                                          onPressed: isLoggingOut
                                              ? null
                                              : () async {
                                                  setDialogState(() =>
                                                      isLoggingOut = true);
                                                  try {
                                                    // Remove FCM token on logout
                                                    await LocalStorageService
                                                        .init();
                                                    final user =
                                                        Hive.box('authBox')
                                                            .get('user');
                                                    final String empNo =
                                                        _getLegacyEmployeeNumber(
                                                            user);
                                                    final dynamic
                                                        staffIdentifier =
                                                        _getStaffIdentifier(
                                                            user);
                                                    final dynamic
                                                        identifierForUpdate =
                                                        staffIdentifier ??
                                                            empNo;

                                                    if (empNo.isNotEmpty ||
                                                        identifierForUpdate !=
                                                            null) {
                                                      // Get current device FCM token
                                                      final currentFcmToken =
                                                          await PushNotificationService
                                                              .getDeviceToken();

                                                      if (currentFcmToken !=
                                                          null) {
                                                        try {
                                                          // Get staff details to check existing FCM tokens
                                                          final staffResponse =
                                                              await StaffService
                                                                  .findStaffByEmployeeNumber(
                                                                      empNo);

                                                          if (staffResponse
                                                                      .statusCode ==
                                                                  200 ||
                                                              staffResponse
                                                                      .statusCode ==
                                                                  201) {
                                                            final staffData =
                                                                jsonDecode(
                                                                    staffResponse
                                                                        .body);
                                                            if (staffData[
                                                                        'success'] ==
                                                                    1 &&
                                                                staffData[
                                                                        'result'] !=
                                                                    null &&
                                                                staffData['result']
                                                                        [
                                                                        'data'] !=
                                                                    null) {
                                                              final List<
                                                                      dynamic>
                                                                  staffList =
                                                                  staffData['result']
                                                                          [
                                                                          'data'] ??
                                                                      [];
                                                              if (staffList
                                                                  .isNotEmpty) {
                                                                final staff =
                                                                    staffList[0]
                                                                        as Map<
                                                                            String,
                                                                            dynamic>;
                                                                final existingFcmTokens =
                                                                    staff[
                                                                        'fcm_token'];

                                                                List<String>
                                                                    fcmTokensList =
                                                                    [];
                                                                if (existingFcmTokens
                                                                    is List) {
                                                                  fcmTokensList = existingFcmTokens
                                                                      .map((e) =>
                                                                          e.toString())
                                                                      .toList();
                                                                } else if (existingFcmTokens
                                                                    is String) {
                                                                  fcmTokensList =
                                                                      [
                                                                    existingFcmTokens
                                                                  ];
                                                                }

                                                                // Remove this device's token (if present)
                                                                if (fcmTokensList
                                                                    .contains(
                                                                        currentFcmToken)) {
                                                                  fcmTokensList
                                                                      .remove(
                                                                          currentFcmToken);
                                                                  print(
                                                                      '🔄 Removing FCM token on logout: $currentFcmToken');
                                                                } else {
                                                                  print(
                                                                      '⚠️ FCM token not found in array.');
                                                                }

                                                                // After removal: if no tokens left, mark
                                                                // unavailable. If other devices remain,
                                                                // verify at least one is reachable (app
                                                                // installed) before keeping is_available.
                                                                if (fcmTokensList
                                                                    .isEmpty) {
                                                                  print(
                                                                      '📱 No FCM tokens left. Sending empty array + is_available false.');
                                                                  await StaffService
                                                                      .updateStaffAvailabilityWithFcmToken(
                                                                          identifierForUpdate,
                                                                          false,
                                                                          []);
                                                                } else {
                                                                  // Presence feature ("ref"): validate remaining
                                                                  // tokens + prune invalid ones. If disabled,
                                                                  // fall back to the old behaviour.
                                                                  final handled =
                                                                      await StaffPresenceService
                                                                          .onLogout(
                                                                    staffIdentifier:
                                                                        identifierForUpdate,
                                                                    tokens:
                                                                        fcmTokensList,
                                                                  );
                                                                  if (!handled) {
                                                                    // Old setup: tokens remain → keep
                                                                    // is_available untouched, only remove
                                                                    // this device's token.
                                                                    await StaffService.updateStaffFcmToken(
                                                                        identifierForUpdate,
                                                                        fcmTokensList);
                                                                  }
                                                                }

                                                                // Best-effort only; ignore response
                                                              } else {
                                                                // No staff data found, just update availability
                                                                await StaffService
                                                                    .updateStaffAvailability(
                                                                        identifierForUpdate,
                                                                        false);

                                                                // Best-effort only; ignore response
                                                              }
                                                            } else {
                                                              // API call failed, just update availability
                                                              await StaffService
                                                                  .updateStaffAvailability(
                                                                      identifierForUpdate,
                                                                      false);

                                                              // Best-effort only; ignore response
                                                            }
                                                          } else {
                                                            // API call failed, just update availability (best-effort)
                                                            await StaffService
                                                                .updateStaffAvailability(
                                                                    identifierForUpdate,
                                                                    false);
                                                          }
                                                        } catch (e) {
                                                          // Error in FCM removal, fallback to just update availability
                                                          print(
                                                              '❌ Error removing FCM token: $e');
                                                          await StaffService
                                                              .updateStaffAvailability(
                                                                  identifierForUpdate ??
                                                                      empNo,
                                                                  false);

                                                          // Best-effort only; ignore response
                                                        }
                                                      } else {
                                                        // No FCM token available.
                                                        // This is common on simulators or when push isn't configured.
                                                        // IMPORTANT: Never block logout because FCM is missing.
                                                        print(
                                                            '⚠️ No FCM token available. Skipping FCM cleanup and proceeding with logout.');

                                                        // Best-effort availability update; failures are only logged.
                                                        try {
                                                          await StaffService
                                                              .updateStaffAvailability(
                                                                  identifierForUpdate ??
                                                                      empNo,
                                                                  false);
                                                        } catch (e) {
                                                          print(
                                                              '⚠️ Error updating availability without FCM: $e');
                                                        }
                                                      }
                                                    } else {
                                                      // No employee number or staff identifier available.
                                                      // We can't update availability on the server, but
                                                      // the user should still be able to logout locally.
                                                      print(
                                                          '⚠️ No staff identifier/empNo found. Skipping API update and proceeding with local logout.');
                                                    }

                                                    // Always proceed with logout (do not block on FCM/server issues)
                                                    await PushNotificationService
                                                        .onUserLoggedOut();
                                                    await LocalStorageService
                                                        .logout();

                                                    // Close the dialog first
                                                    if (mounted)
                                                      Navigator.pop(context);

                                                    // Navigate to login page
                                                    if (!mounted) return;
                                                    Navigator.of(context)
                                                        .pushAndRemoveUntil(
                                                      MaterialPageRoute(
                                                        builder: (_) =>
                                                            LoginPage(),
                                                      ),
                                                      (route) => false,
                                                    );
                                                  } catch (e) {
                                                    print('❌ Logout error: $e');

                                                    // Close the dialog first
                                                    if (mounted)
                                                      Navigator.pop(context);

                                                    // Show error message and stay on page
                                                    if (mounted) {
                                                      ScaffoldMessenger.of(
                                                              context)
                                                          .showSnackBar(
                                                        SnackBar(
                                                          content: Text(
                                                              'Logout failed due to error. Please try again.'),
                                                          backgroundColor:
                                                              Colors.red,
                                                          duration: Duration(
                                                              seconds: 3),
                                                        ),
                                                      );
                                                    }
                                                  }
                                                },
                                          child: isLoggingOut
                                              ? const SizedBox(
                                                  height: 20,
                                                  width: 20,
                                                  child:
                                                      CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                    valueColor:
                                                        AlwaysStoppedAnimation<
                                                                Color>(
                                                            Colors.white),
                                                  ),
                                                )
                                              : Text(
                                                  'Confirm',
                                                  style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.w600),
                                                )),
                                    ),
                                  )
                                ],
                              )
                            ],
                          ),
                        ),
                      ));
            });
      }
      updateVisibilityFlags();
    });

    // Handle notification settings after setState
    if (index == 1) {
      await NotificationSettingsService.showNotificationSettingsDialog(context);
    }
  }

  bool showAnyDetailPage() {
    return showProfilePage || showMyRatings || aboutUs;
  }

  String getCurrentPageTitle() {
    if (showProfilePage) return "Profile";
    if (showMyRatings) return "My Ratings";
    if (aboutUs) return "About Us";
    return "Settings";
  }

  @override
  void initState() {
    super.initState();
    // Initialize availability toggle state from local storage (default true)
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await LocalStorageService.init();
      final stored = LocalStorageService.getValue('user_is_available');
      final bool initialAvail = (stored is bool) ? stored : true;
      setState(() {
        // 'My Availability' presumed at index 5
        if (toggleStates.length > 5) {
          toggleStates[5] = initialAvail;
        }
        _availability = initialAvail;
      });

      // Fetch latest availability from API using employee id
      await _fetchAvailabilityFromApi();
      await _fetchHotelNameFromCustomerApi();
    });
  }

  String _resolveCustomerMemberId() {
    final user = LocalStorageService.user;
    final fromStaff =
        _staffData?['member_id'] ?? _staffData?['staff_member_id'];
    final fromUser = user?['member_id'] ?? user?['staff_member_id'];
    return (fromStaff ?? fromUser ?? '').toString().trim();
  }

  Future<void> _fetchHotelNameFromCustomerApi() async {
    final memberId = _resolveCustomerMemberId();
    if (memberId.isEmpty) return;

    if (mounted) {
      setState(() => _hotelNameLoading = true);
    }

    try {
      final hotelName = await LocalStorageService.fetchHotelNameFromCustomerApi(
        memberIdOverride: memberId,
      );
      if (!mounted) return;
      if (hotelName != null && hotelName.isNotEmpty) {
        setState(() => _hotelName = hotelName);
      }
    } finally {
      if (mounted) {
        setState(() => _hotelNameLoading = false);
      }
    }
  }

  String get _displayHotelName {
    if (_hotelName.isNotEmpty) return _hotelName;
    return LocalStorageService.hotelName;
  }

  Future<void> _fetchAvailabilityFromApi() async {
    setState(() => _availabilityLoading = true);
    try {
      final user = LocalStorageService.user;
      final empNo =
          (user?['staff_employee_number'] ?? user?['staff_member_id'] ?? '')
              .toString();
      if (empNo.isEmpty) {
        setState(() => _availabilityLoading = false);
        return;
      }
      final resp = await StaffService.findStaffByEmployeeNumber(empNo);
      if (resp.statusCode == 200 || resp.statusCode == 201) {
        final data = resp.body;
        final map = data.isNotEmpty
            ? (jsonDecode(data) as Map<String, dynamic>)
            : <String, dynamic>{};
        final list = (map['result']?['data'] is List)
            ? map['result']['data'] as List
            : const [];
        if (list.isNotEmpty) {
          final rec = Map<String, dynamic>.from(list.first as Map);
          _staffData = rec;
          final apiValue = (rec['is_available'] ?? rec['is_avaliable']);
          final bool avail = apiValue is bool ? apiValue : true;
          await LocalStorageService.init();
          Hive.box('authBox').put('user_is_available', avail);
          setState(() {
            _availability = avail;
            if (toggleStates.length > 5) toggleStates[5] = avail;
          });
          await _fetchHotelNameFromCustomerApi();
        }
      }
    } catch (_) {
      // ignore
    } finally {
      if (mounted) setState(() => _availabilityLoading = false);
    }
  }

  Widget _buildShimmerToggle(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final toggleWidth = screenWidth * 0.12; // 45px equivalent
    final toggleHeight = screenWidth * 0.05; // 20px equivalent

    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: Container(
        width: toggleWidth,
        height: toggleHeight,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(toggleHeight / 2),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;

    return WillPopScope(
      onWillPop: () async {
        if (isAnySectionVisible) {
          setState(() {
            showProfilePage = false;
            showMyRatings = false;
            aboutUs = false;
            updateVisibilityFlags();
          });
          return false;
        } else {
          if (Navigator.canPop(context)) {
            Navigator.pop(context);
          } else {
            Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                    builder: (BuildContext context) => NavigationPage()));
          }
          return false;
        }
      },
      child: Scaffold(
        body: Column(
          children: [
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(bottom: Radius.circular(25)),
              child: Container(
                color: Colors.white,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return Stack(
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.18,
                          width: screenWidth,
                          child: Image.asset(
                            'assets/images/appbarpic.png',
                            width: screenWidth,
                            fit: BoxFit.fill,
                          ),
                        ),
                        Positioned.fill(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16.0, vertical: 20),
                            child: Align(
                              alignment: Alignment.bottomCenter,
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  !isAnySectionVisible
                                      ? Row(
                                          children: [
                                            GestureDetector(
                                              onTap: () {
                                                if (!mounted) return;
                                                Navigator.pop(context);
                                              },
                                              child: const Icon(
                                                  Icons
                                                      .keyboard_arrow_left_outlined,
                                                  size: 40,
                                                  color: Colors.white),
                                            ),
                                            SizedBox(
                                                width: MediaQuery.of(context)
                                                        .size
                                                        .width *
                                                    0.02),
                                            Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  (LocalStorageService.user?[
                                                              'full_name'] ??
                                                          '')
                                                      .toString(),
                                                  style: TextStyle(
                                                    fontSize:
                                                        MediaQuery.of(context)
                                                                .size
                                                                .width *
                                                            0.05,
                                                    fontWeight: FontWeight.w600,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                                Text(
                                                  LocalStorageService
                                                      .allDepartments,
                                                  style: TextStyle(
                                                    fontSize:
                                                        MediaQuery.of(context)
                                                                .size
                                                                .width *
                                                            0.03,
                                                    fontWeight: FontWeight.w500,
                                                    color: Colors.white70,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        )
                                      : Row(
                                          children: [
                                            GestureDetector(
                                              onTap: () {
                                                setState(() {
                                                  showProfilePage = false;
                                                  showMyRatings = false;
                                                  aboutUs = false;
                                                  updateVisibilityFlags();
                                                });
                                              },
                                              child: const Icon(
                                                  Icons
                                                      .keyboard_arrow_left_outlined,
                                                  size: 40,
                                                  color: Colors.white),
                                            ),
                                            SizedBox(
                                                width: MediaQuery.of(context)
                                                        .size
                                                        .width *
                                                    0.02),
                                            Text(
                                              getCurrentPageTitle(),
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: MediaQuery.of(context)
                                                        .size
                                                        .width *
                                                    0.045,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                  hotelNameHeader(
                                    context: context,
                                    name: _displayHotelName,
                                    loadingPlaceholder: _hotelNameLoading
                                        ? Shimmer.fromColors(
                                            baseColor:
                                                Colors.white.withOpacity(0.3),
                                            highlightColor:
                                                Colors.white.withOpacity(0.6),
                                            child: Container(
                                              height: 16,
                                              width: MediaQuery.of(context)
                                                      .size
                                                      .width *
                                                  0.25,
                                              decoration: BoxDecoration(
                                                color: Colors.white,
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                            ),
                                          )
                                        : null,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding:
                      EdgeInsets.only(top: aboutUs || showMyRatings ? 0 : 16.0),
                  child: showProfilePage
                      ? buildProfilePage()
                      : // Commented out ratings page as it uses static values
                      // showMyRatings
                      //     ? ratingsPage()
                      //     :
                      aboutUs
                          ? Center(child: Text('About Us Content'))
                          : Column(
                              children: [
                                // Profile
                                listItem(
                                    context,
                                    keysValues['text'][0],
                                    keysValues['imageText'][0],
                                    true,
                                    () => handleItemTap(0),
                                    toggleStates[0], (value) {
                                  setState(() {
                                    toggleStates[0] = value;
                                  });
                                }, false),
                                // Notifications
                                listItem(
                                    context,
                                    keysValues['text'][1],
                                    keysValues['imageText'][1],
                                    true,
                                    () => handleItemTap(1),
                                    toggleStates[1], (value) {
                                  setState(() {
                                    toggleStates[1] = value;
                                  });
                                }, false),
                                // Terms and Conditions
                                listItem(
                                    context,
                                    keysValues['text'][2],
                                    keysValues['imageText'][2],
                                    true,
                                    () => handleItemTap(2),
                                    toggleStates[2], (value) {
                                  setState(() {
                                    toggleStates[2] = value;
                                  });
                                }, false),
                                // Privacy Policy
                                listItem(
                                    context,
                                    keysValues['text'][3],
                                    keysValues['imageText'][3],
                                    true,
                                    () => handleItemTap(3),
                                    toggleStates[3], (value) {
                                  setState(() {
                                    toggleStates[3] = value;
                                  });
                                }, false),
                                // About us
                                listItem(
                                    context,
                                    keysValues['text'][4],
                                    keysValues['imageText'][4],
                                    true,
                                    () => handleItemTap(4),
                                    toggleStates[4], (value) {
                                  setState(() {
                                    toggleStates[4] = value;
                                  });
                                }, false),
                                // My Availability (custom row)
                                _availabilityRow(context, screenWidth),
                                // Logout
                                listItem(
                                    context,
                                    keysValues['text'][5],
                                    keysValues['imageText'][5],
                                    false,
                                    () => handleItemTap(6),
                                    toggleStates[6], (value) {
                                  setState(() {
                                    toggleStates[6] = value;
                                  });
                                }, true),
                              ],
                            ),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _availabilityRow(BuildContext context, double screenWidth) {
    return Column(
      children: [
        Container(
          color: Colors.transparent,
          height: MediaQuery.of(context).size.height * 0.087,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      height: MediaQuery.of(context).size.height *
                          0.037, // 30px equivalent
                      child: Image.asset('assets/images/pro6.png'),
                    ),
                    SizedBox(width: screenWidth * 0.025), // 10px equivalent
                    Text(
                      'My Availability',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: screenWidth * 0.04, // 16px equivalent
                      ),
                    ),
                  ],
                ),
                _availabilityLoading
                    ? _buildShimmerToggle(context)
                    : AvailabilityToggle(initialValue: _availability),
              ],
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          height: 1,
          width: screenWidth,
          color: const Color(0xffE7E7E7),
        )
      ],
    );
  }

  // Commented out ratings section as it uses static values
  // Widget ratingsPage() {
  //   final roomNos = contents['roomNo'];
  //   final reqMaterials = contents['reqmaterial'];
  //   final ratings = contents['ratings'];

  //   final int lenRoom = roomNos is List ? roomNos.length : 0;
  //   final int lenMat = reqMaterials is List ? reqMaterials.length : 0;
  //   final int lenRate = ratings is List ? ratings.length : 0;
  //   final int itemCount = [lenRoom, lenMat, lenRate]
  //       .where((e) => e > 0)
  //       .fold<int>(lenRoom, (prev, e) => prev < e ? prev : e);

  //   return Padding(
  //     padding: const EdgeInsets.all(16.0),
  //     child: Column(
  //       children: List.generate(itemCount, (index) {
  //         final room = (roomNos is List ? roomNos[index] : '').toString();
  //         final material = (reqMaterials is List ? reqMaterials[index] : '').toString();
  //         final rate = (ratings is List ? ratings[index] : '').toString();
  //         return Padding(
  //           padding: const EdgeInsets.only(bottom: 16.0),
  //           child: Container(
  //             decoration: BoxDecoration(
  //               color: Colors.white,
  //               borderRadius: BorderRadius.circular(10),
  //             ),
  //             height: MediaQuery.of(context).size.height * 0.087,
  //             child: Row(
  //               mainAxisAlignment: MainAxisAlignment.spaceBetween,
  //               children: [
  //                 Expanded(
  //                   flex: 2,
  //                   child: Text(
  //                     room,
  //                     textAlign: TextAlign.center,
  //                   ),
  //                 ),
  //                 verticalDivider(),
  //                 Expanded(
  //                   flex: 3,
  //                   child: Text(
  //                     material,
  //                     textAlign: TextAlign.center,
  //                   ),
  //                 ),
  //                 verticalDivider(),
  //                 Expanded(
  //                   flex: 2,
  //                   child: Row(
  //                     mainAxisAlignment: MainAxisAlignment.center,
  //                     children: [
  //                       Text(
  //                         rate,
  //                         style: const TextStyle(fontWeight: FontWeight.bold),
  //                         textAlign: TextAlign.center,
  //                       ),
  //                       const Icon(
  //                         Icons.star_outlined,
  //                         color: Color(0xffFECA57),
  //                       )
  //                     ],
  //                   ),
  //                 ),
  //               ],
  //             ),
  //           ),
  //         );
  //       }),
  //     ),
  //   );
  // }

  Widget verticalDivider() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      height: double.infinity,
      width: 1,
      color: const Color(0xffE7E7E7),
    );
  }

  Widget buildProfilePage() {
    double screenWidth = MediaQuery.of(context).size.width;
    final user = LocalStorageService.user;
    final String fullName =
        (_staffData?['full_name'] ?? user?['full_name'] ?? '').toString();

    // Handle hierarchy as array - get all departments
    String dept = '';
    if (_staffData != null) {
      final staffHierarchy = _staffData!['hierarchy'];
      if (staffHierarchy is List && staffHierarchy.isNotEmpty) {
        // Get all unique departments
        final departments = staffHierarchy
            .map((h) => h['department']?.toString() ?? '')
            .where((d) => d.isNotEmpty)
            .toSet()
            .toList();
        dept = departments.join(', ');
      } else if (staffHierarchy is Map) {
        dept = (staffHierarchy['department'] ?? '').toString();
      }
    }
    if (dept.isEmpty) {
      dept = LocalStorageService.allDepartments;
    }

    // Handle higher_level_hierarchy as array - get designation from first entry
    String reportingManager = '';
    if (_staffData != null) {
      final higherOfficer = _staffData!['higher_level_officer'];
      if (higherOfficer is List && higherOfficer.isNotEmpty) {
        reportingManager = (higherOfficer[0]['name'] ?? '').toString();
      } else if (higherOfficer is Map) {
        reportingManager = (higherOfficer['name'] ?? '').toString();
      }

      if (reportingManager.isEmpty) {
        final higherHierarchy = _staffData!['higher_level_hierarchy'];
        if (higherHierarchy is List && higherHierarchy.isNotEmpty) {
          reportingManager =
              (higherHierarchy[0]['designation'] ?? '').toString();
        } else if (higherHierarchy is Map) {
          reportingManager = (higherHierarchy['designation'] ?? '').toString();
        }
      }
    }
    if (reportingManager.isEmpty) {
      final userHigherOfficer = user?['higher_level_officer'];
      if (userHigherOfficer is List && userHigherOfficer.isNotEmpty) {
        reportingManager = (userHigherOfficer[0]['name'] ?? '').toString();
      } else if (userHigherOfficer is Map) {
        reportingManager = (userHigherOfficer['name'] ?? '').toString();
      }

      if (reportingManager.isEmpty) {
        final userHigherHierarchy = user?['higher_level_hierarchy'];
        if (userHigherHierarchy is List && userHigherHierarchy.isNotEmpty) {
          reportingManager =
              (userHigherHierarchy[0]['designation'] ?? '').toString();
        } else if (userHigherHierarchy is Map) {
          reportingManager =
              (userHigherHierarchy['designation'] ?? '').toString();
        }
      }
    }
    final String phone =
        (_staffData?['phone_number'] ?? user?['phone_number'] ?? '').toString();
    final String email =
        (_staffData?['email'] ?? user?['email'] ?? '').toString();
    final String empId = (_staffData?['staff_employee_number'] ??
            _staffData?['staff_member_id'] ??
            user?['staff_employee_number'] ??
            user?['staff_member_id'] ??
            '')
        .toString();
    final String profileImageValue =
        (_staffData?['profile_image'] ?? user?['profile_image'] ?? '')
            .toString();
    final ImageProvider? profileImageProvider =
        _resolveProfileImageProvider(profileImageValue);
    final double avatarRadius = MediaQuery.of(context).size.width * 0.125;

    return Column(spacing: 1, children: [
      GestureDetector(
        onTap: _isUploadingProfileImage
            ? null
            : _showProfileImageOptionsBottomSheet,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            CircleAvatar(
              maxRadius: avatarRadius,
              backgroundImage: profileImageProvider,
              child: profileImageProvider == null
                  ? const Icon(
                      Icons.person,
                      size: 35,
                      color: Colors.white,
                    )
                  : null,
            ),
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                height: 30,
                width: 30,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: _isUploadingProfileImage
                    ? const Padding(
                        padding: EdgeInsets.all(6),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Icon(
                        Icons.camera_alt,
                        color: Colors.white,
                        size: 16,
                      ),
              ),
            ),
          ],
        ),
      ),
      SizedBox(width: MediaQuery.of(context).size.width * 0.025),
      Text(
        fullName,
        style: TextStyle(
          fontSize: MediaQuery.of(context).size.width * 0.055,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
      Text(
        dept,
        style: TextStyle(
          fontSize: MediaQuery.of(context).size.width * 0.035,
          fontWeight: FontWeight.w500,
          color: Color(0xff757575),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 20),
        child: Container(
            decoration: BoxDecoration(
                borderRadius: BorderRadius.all(
                  Radius.circular(10),
                ),
                color: Colors.white),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: () {
                  final List<String> dynamicValues = [
                    reportingManager,
                    phone,
                    email,
                    empId,
                  ];
                  return List.generate(
                      keys.length,
                      (index) => Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(
                                    right: 16, top: 16, left: 16.0),
                                child: Text(
                                  keys[index],
                                  style: TextStyle(
                                      fontWeight: FontWeight.w200,
                                      fontSize:
                                          MediaQuery.of(context).size.width *
                                              0.035),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(
                                    right: 16, top: 16, bottom: 10, left: 16.0),
                                child: Text(
                                  (index < dynamicValues.length
                                      ? dynamicValues[index]
                                      : ''),
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize:
                                          MediaQuery.of(context).size.width *
                                              0.04),
                                ),
                              ),
                              bools[index]
                                  ? Container(
                                      height: 1,
                                      width: screenWidth,
                                      color: const Color(0xffE7E7E7),
                                    )
                                  : const SizedBox(
                                      height: 5,
                                    )
                            ],
                          ));
                }())),
      ),
    ]);
  }
}

Widget listItem(
    BuildContext context,
    String text,
    String imageText,
    bool iconNeed,
    VoidCallback onTap,
    bool isSwitched,
    Function(bool) onSwitchChanged,
    bool logOut) {
  double screenWidth = MediaQuery.of(context).size.width;

  return Column(
    children: [
      GestureDetector(
        onTap: onTap,
        child: Container(
          color: Colors.transparent,
          height: MediaQuery.of(context).size.height * 0.087,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                        height: MediaQuery.of(context).size.height * 0.037,
                        child: Image.asset('assets/images/$imageText.png')),
                    SizedBox(width: MediaQuery.of(context).size.width * 0.025),
                    Text(
                      text,
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: MediaQuery.of(context).size.width * 0.04),
                    ),
                  ],
                ),
                iconNeed
                    ? Icon(Icons.keyboard_arrow_right_rounded)
                    : !logOut
                        ? AvailabilityToggle(
                            initialValue: isSwitched,
                          )
                        : SizedBox.shrink(),
              ],
            ),
          ),
        ),
      ),
      Container(
        margin: EdgeInsets.symmetric(horizontal: 16),
        height: 1,
        width: screenWidth,
        color: Color(0xffE7E7E7),
      )
    ],
  );
}

class BigThumbToggle extends StatefulWidget {
  final bool initialValue;
  final ValueChanged<bool> onChanged;

  const BigThumbToggle({
    Key? key,
    this.initialValue = false,
    required this.onChanged,
  }) : super(key: key);

  @override
  _BigThumbToggleState createState() => _BigThumbToggleState();
}

class _BigThumbToggleState extends State<BigThumbToggle>
    with SingleTickerProviderStateMixin {
  late bool _value;
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _value = widget.initialValue;
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);

    if (_value) _ctrl.value = 1.0;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _value = !_value);
    widget.onChanged(_value);
    if (_value) {
      _ctrl.forward();
    } else {
      _ctrl.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final double trackWidth = screenWidth * 0.12; // 45px equivalent
    final double trackHeight = screenWidth * 0.05; // 20px equivalent
    final double thumbSize = screenWidth * 0.08; // 30px equivalent

    return GestureDetector(
      onTap: _toggle,
      child: Padding(
        padding: EdgeInsets.only(right: screenWidth * 0.02), // 8px equivalent
        child: SizedBox(
          width: trackWidth,
          height: trackHeight,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              AnimatedBuilder(
                animation: _anim,
                builder: (_, __) {
                  final Color borderBegin = Color(0xffFF0000);
                  final Color borderEnd = Colors.green;
                  final Color fillBegin = Color(0xffFFC1C1);
                  final Color fillEnd = Color(0xffEEFFE3);
                  final borderColor =
                      Color.lerp(borderBegin, borderEnd, _anim.value)!;
                  final fillColor =
                      Color.lerp(fillBegin, fillEnd, _anim.value)!;
                  return Container(
                    width: trackWidth,
                    height: trackHeight,
                    decoration: BoxDecoration(
                      color: fillColor,
                      borderRadius: BorderRadius.circular(trackHeight / 2),
                      border: Border.all(
                          color: borderColor,
                          width: MediaQuery.of(context).size.width * 0.005),
                    ),
                  );
                },
              ),
              AnimatedPositioned(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                left: _value ? trackWidth - thumbSize + 5 : -5,
                top: (trackHeight - thumbSize) / 2,
                child: Container(
                  width: thumbSize,
                  height: thumbSize,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.15),
                        blurRadius: 7,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AvailabilityToggle extends StatefulWidget {
  final bool initialValue;
  const AvailabilityToggle({Key? key, this.initialValue = true})
      : super(key: key);

  @override
  State<AvailabilityToggle> createState() => _AvailabilityToggleState();
}

class _AvailabilityToggleState extends State<AvailabilityToggle>
    with SingleTickerProviderStateMixin {
  late bool _value;
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _value = widget.initialValue;
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 200));
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
    if (_value) _ctrl.value = 1.0;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    setState(() => _value = !_value);
    if (_value) {
      _ctrl.forward();
    } else {
      _ctrl.reverse();
    }

    // Persist locally
    await LocalStorageService.init();
    final user = LocalStorageService.user;
    final dynamic staffIdValue = user?['id'];
    final int? staffDbId = staffIdValue is int
        ? staffIdValue
        : int.tryParse(staffIdValue?.toString() ?? '');
    final String legacyEmpNo =
        (user?['staff_employee_number'] ?? user?['staff_member_id'] ?? '')
            .toString();
    final dynamic staffIdentifier =
        staffDbId ?? (legacyEmpNo.isNotEmpty ? legacyEmpNo : null);

    if (staffIdentifier != null) {
      // Update API
      await StaffService.updateStaffAvailability(staffIdentifier, _value);
      Hive.box('authBox').put('user_is_available', _value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final double trackWidth = screenWidth * 0.12; // 45px equivalent
    final double trackHeight = screenWidth * 0.05; // 20px equivalent
    final double thumbSize = screenWidth * 0.08; // 30px equivalent

    return GestureDetector(
      onTap: _toggle,
      child: Padding(
        padding: EdgeInsets.only(right: screenWidth * 0.02), // 8px equivalent
        child: SizedBox(
          width: trackWidth,
          height: trackHeight,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              AnimatedBuilder(
                animation: _anim,
                builder: (_, __) {
                  final Color borderBegin = Color(0xffFF0000);
                  final Color borderEnd = Colors.green;
                  final Color fillBegin = Color(0xffFFC1C1);
                  final Color fillEnd = Color(0xffEEFFE3);
                  final borderColor =
                      Color.lerp(borderBegin, borderEnd, _anim.value)!;
                  final fillColor =
                      Color.lerp(fillBegin, fillEnd, _anim.value)!;
                  return Container(
                    width: trackWidth,
                    height: trackHeight,
                    decoration: BoxDecoration(
                      color: fillColor,
                      borderRadius: BorderRadius.circular(trackHeight / 2),
                      border: Border.all(
                          color: borderColor,
                          width: MediaQuery.of(context).size.width * 0.005),
                    ),
                  );
                },
              ),
              AnimatedPositioned(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                left: _value ? trackWidth - thumbSize + 5 : -5,
                top: (trackHeight - thumbSize) / 2,
                child: Container(
                  width: thumbSize,
                  height: thumbSize,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.15),
                        blurRadius: 7,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
