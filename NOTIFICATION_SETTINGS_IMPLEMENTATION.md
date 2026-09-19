# Notification Settings Implementation

## Overview
This implementation adds a notification settings tab to the profile/settings screen that allows users to check and manage their notification permissions. The feature provides a user-friendly way to enable notifications or navigate to device settings if permissions are denied.

## Features Implemented

### 1. Notification Settings Service (`lib/Services/notification_settings_service.dart`)
- **Permission Checking**: Checks both Firebase messaging and Android runtime notification permissions
- **Smart Detection**: Automatically detects if notifications are enabled or disabled
- **App Settings Navigation**: Opens device settings when permissions are denied
- **User-Friendly Dialogs**: Shows appropriate messages based on permission status

### 2. Settings Screen Integration
- **New Tab**: Added "Notifications" tab to the settings screen
- **Icon**: Uses `pro2.png` icon for the notification settings
- **Position**: Placed between "Profile" and "Terms and Conditions"

## User Experience Flow

### When Notifications Are Enabled:
1. User taps "Notifications" in settings
2. App shows green snackbar: "App notifications are already turned on"
3. User sees confirmation that notifications are working

### When Notifications Are Disabled:
1. User taps "Notifications" in settings
2. App shows dialog with:
   - Orange notification-off icon
   - Title: "Enable Notifications"
   - Explanation text about receiving task updates
   - "Cancel" and "Settings" buttons
3. If user taps "Settings", app opens device settings page
4. User can manually enable notifications in device settings

## Technical Implementation

### Permission Checking Logic:
```dart
// Checks both Firebase and Android runtime permissions
bool firebaseGranted = settings.authorizationStatus == AuthorizationStatus.authorized;
bool androidGranted = androidStatus == PermissionStatus.granted;
return firebaseGranted && (androidGranted || androidStatus == PermissionStatus.denied);
```

### Key Methods:
- `areNotificationsEnabled()`: Main permission check
- `showNotificationSettingsDialog()`: Shows appropriate UI based on permission status
- `openDeviceSettings()`: Opens device settings page
- `getPermissionStatus()`: Debug information about permission states

## UI Components

### Snackbar (Notifications Enabled):
- Green background
- Notification icon
- Message: "App notifications are already turned on"
- 3-second duration

### Dialog (Notifications Disabled):
- Clean white background with rounded corners
- Orange notification-off icon (48px)
- Clear title and explanation text
- Two buttons: Cancel (outlined) and Settings (filled)
- Responsive design using MediaQuery

## Cross-Platform Support

### Android:
- Checks both Firebase messaging permissions and Android 13+ runtime permissions
- Opens Android app settings when needed
- Handles permission states properly

### iOS:
- Checks Firebase messaging permissions (iOS handles runtime permissions automatically)
- Opens iOS app settings when needed
- Compatible with iOS permission system

## Integration Points

### Settings Screen Updates:
- Added "Notifications" to the settings list
- Updated array indices for other settings items
- Added async handling for notification dialog
- Maintains existing UI patterns and styling

### Error Handling:
- Graceful handling of permission check failures
- Context safety checks to prevent BuildContext issues
- Fallback behavior if settings can't be opened

## Testing Instructions

1. **Test with Notifications Enabled**:
   - Enable notifications in device settings
   - Open app and go to Settings > Notifications
   - Should show green snackbar

2. **Test with Notifications Disabled**:
   - Disable notifications in device settings
   - Open app and go to Settings > Notifications
   - Should show dialog with "Settings" button
   - Tapping "Settings" should open device settings

3. **Test Permission Flow**:
   - Use device settings to toggle notifications
   - Verify app correctly detects permission changes
   - Test both enabling and disabling notifications

## Console Output
The implementation includes detailed logging:
- `📱 Firebase permission: [status]` - Firebase permission status
- `📱 Android runtime permission: [status]` - Android runtime permission status
- `📱 Opened app settings` - When settings are opened
- `❌ Error [details]` - Error messages for debugging

## Future Enhancements
- Custom notification preferences (sound, vibration patterns)
- Notification scheduling (quiet hours)
- Different notification types for different task priorities
- Push notification history/log
