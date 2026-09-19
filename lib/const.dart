import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:guestezee_staffs_app/Config/api_end_points.dart';
import 'package:guestezee_staffs_app/Config/primary_config.dart';
import 'package:guestezee_staffs_app/Custom Widgets/hotel_name_header.dart';
import 'package:guestezee_staffs_app/Screens/login_page.dart';
import 'package:guestezee_staffs_app/Screens/settings_page.dart'
    show SettingsPage;
import 'package:guestezee_staffs_app/Services/local_storage_service.dart';
import 'package:guestezee_staffs_app/Services/notification_settings_service.dart';
import 'package:guestezee_staffs_app/Services/push_notification_service.dart';
import 'package:guestezee_staffs_app/Services/staff_service.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

ImageProvider? _resolveProfileImageProvider(dynamic rawValue) {
  final String value = (rawValue ?? '').toString().trim();
  if (value.isEmpty) return null;

  if (value.startsWith('http://') || value.startsWith('https://')) {
    return NetworkImage(value);
  }

  if (value.startsWith('data:image')) {
    try {
      final int commaIndex = value.indexOf(',');
      if (commaIndex == -1) return null;
      final String encoded = value.substring(commaIndex + 1);
      return MemoryImage(base64Decode(encoded));
    } catch (_) {
      return null;
    }
  }

  return null;
}

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

  final String legacy =
      (user['staff_employee_number'] ?? user['staff_member_id'] ?? '')
          .toString();
  return legacy.isNotEmpty ? legacy : null;
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
    return _extractImageUrl(body);
  }
  return null;
}

Widget appBarContainer(
  BuildContext context, {
  bool manager = false,
  bool showBackButton = false,
  String? hotelName,
}) {
  final String displayHotelName = (hotelName != null && hotelName.isNotEmpty)
      ? hotelName
      : LocalStorageService.hotelName;
  double screenWidth = MediaQuery.of(context).size.width;
  final profileImageProvider = _resolveProfileImageProvider(
    LocalStorageService.user?['profile_image'],
  );

  Future<void> handleNotificationButtonTap() async {
    try {
      bool areNotificationsEnabled =
          await NotificationSettingsService.areNotificationsEnabled();

      if (areNotificationsEnabled) {
        // Show snackbar if notifications are already enabled
        if (context.mounted) {
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
        if (context.mounted) {
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
      if (context.mounted) {
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

  Future<void> handleLogout() async {
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

        if (context.mounted) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const LoginPage()),
            (route) => false,
          );
        }
      } catch (e) {
        print('❌ Logout error: $e');

        // Show error message and stay on page
        if (context.mounted) {
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

  Future<void> pickAndUploadManagerProfileImage() async {
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
      if (!context.mounted) return;
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

    if (!context.mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final uploadedUrl = await _uploadImageToAWS(File(filePath));
      if (uploadedUrl == null || uploadedUrl.trim().isEmpty) {
        throw Exception('Image upload failed');
      }

      await LocalStorageService.init();
      final dynamic user = Hive.box('authBox').get('user');
      final dynamic staffIdentifier = _getStaffIdentifier(user);
      if (staffIdentifier == null) {
        throw Exception('Staff identifier not found');
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

      final storedUser = Hive.box('authBox').get('user');
      if (storedUser is Map) {
        final updatedUser = Map<String, dynamic>.from(storedUser);
        updatedUser['profile_image'] = uploadedUrl;
        await Hive.box('authBox').put('user', updatedUser);
      }

      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile image updated successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
      if (context is Element) {
        context.markNeedsBuild();
      }
    } catch (_) {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile image update failed!'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> showManagerImageUploadPopup() async {
    if (!context.mounted) return;
    final latestUser = _normalizeUser(Hive.box('authBox').get('user')) ??
        _normalizeUser(LocalStorageService.user);
    final ImageProvider? latestProfileImageProvider =
        _resolveProfileImageProvider(latestUser?['profile_image']);

    Future<void> showManagerProfileImageDialog() async {
      if (!context.mounted || latestProfileImageProvider == null) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 24,
            ),
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
                      image: latestProfileImageProvider,
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
                if (latestProfileImageProvider != null)
                  ListTile(
                    leading: const Icon(Icons.visibility_outlined),
                    title: const Text('View profile image'),
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      await showManagerProfileImageDialog();
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.upload),
                  title: const Text('Upload profile image'),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    await pickAndUploadManagerProfileImage();
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

  return ClipRRect(
    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(25)),
    child: Container(
      color: Colors.white,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: [
              SizedBox(
                height: 145,
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
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                            GestureDetector(
                              onTap: () {
                                if (showBackButton) {
                                  if (Navigator.canPop(context)) {
                                    Navigator.pop(context);
                                  }
                                  return;
                                }
                                if (manager == true) {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          const SettingsPage(),
                                    ),
                                  );
                                  return;
                                }
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const SettingsPage(),
                                  ),
                                );
                              },
                              child: showBackButton
                                  ? const CircleAvatar(
                                      maxRadius: 30,
                                      backgroundColor: Colors.white24,
                                      child: Icon(
                                        Icons.keyboard_arrow_left_outlined,
                                        size: 35,
                                        color: Colors.white,
                                      ),
                                    )
                                  : CircleAvatar(
                                      maxRadius: 30,
                                      backgroundColor: Colors.white24,
                                      backgroundImage: profileImageProvider,
                                      child: profileImageProvider == null
                                          ? const Icon(
                                              Icons.person,
                                              size: 35,
                                              color: Colors.white,
                                            )
                                          : null,
                                    ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  if (manager == true) {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            const SettingsPage(),
                                      ),
                                    );
                                    return;
                                  }
                                  Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                          builder: (context) =>
                                              const SettingsPage()));
                                },
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      LocalStorageService.user?['full_name'] ??
                                          '',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                      ),
                                    ),
                                    Text(
                                      LocalStorageService
                                              .hierarchyDesignationDepartmentDisplay
                                              .isNotEmpty
                                          ? LocalStorageService
                                              .hierarchyDesignationDepartmentDisplay
                                          : LocalStorageService.allDepartments,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.white70,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                          ),
                        ),
                        manager == true
                            ? IconButton(
                                icon: Icon(Icons.notifications_outlined,
                                    color: Colors.white),
                                onPressed: handleNotificationButtonTap,
                                tooltip: 'Notification Settings',
                              )
                            : hotelNameHeader(
                                context: context,
                                name: displayHotelName,
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
  );
}
