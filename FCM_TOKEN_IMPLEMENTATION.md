# FCM Token Management Implementation

## Overview
This document describes the FCM token management implementation during staff login and home screen initialization, which ensures proper token tracking across multiple devices for the same staff member.

## Implementation Details

### Flow Description

#### 1. Login Flow (Token Management)

When a staff member logs in successfully, the app performs the following FCM token management:

1. **Get Current Device Token**: Retrieves the FCM token from the current device using Firebase Cloud Messaging.

2. **Fetch Staff Details**: Makes an API call to get the staff member's current data, including any existing `fcm_token` array.

3. **Check Token Existence**:
   - **If `fcm_token` key doesn't exist**: 
     - Creates a new array with the current device token
     - Updates the API with this new array
     - Saves the token to local storage (for testing only)
   
   - **If `fcm_token` key exists**:
     - Retrieves the existing array of tokens
     - Compares the current device token with the API array
     - **If token exists in array**: No update needed (just updates availability)
     - **If token doesn't exist in array**: Appends the new token to the array, updates API and saves to local storage

4. **Update API**: Sends the `fcm_token` array along with `is_available: true` to the backend.

5. **Persist Locally**: Saves the current device token to local storage (for testing purposes only).

#### 2. Home Screen Initialization

Both entry-level staff (HomeScreen) and higher-level staff (EscalatedTasksPage) initialize FCM token in their `initState`:

1. **Get Device Token**: Calls `PushNotificationService.getDeviceToken()`
2. **Save to Local Storage**: Saves the token for testing purposes only
3. **Non-blocking**: Runs asynchronously without blocking UI initialization

## Files Modified

### 1. `lib/Services/staff_service.dart`
Added two new methods:

#### `updateStaffAvailabilityWithFcmToken()`
```dart
static Future<http.Response> updateStaffAvailabilityWithFcmToken(
  String employeeNumber, 
  bool isAvailable, 
  List<String> fcmTokens
)
```
Updates both availability and FCM token array in a single API call.

#### `getStaffById()`
```dart
static Future<http.Response> getStaffById(String staffId)
```
Fetches staff details by ID to check existing FCM token array.

### 2. `lib/Screens/login_page.dart`

#### Modified `_login()` method
- Replaced direct FCM token saving with the new token management logic
- Calls `_updateAvailabilityWithFcmToken()` instead of simple availability update

#### Added `_updateAvailabilityWithFcmToken()` method
```dart
Future<void> _updateAvailabilityWithFcmToken(
  String employeeNumber, 
  String staffId, 
  String currentFcmToken
)
```
Implements the complete FCM token management logic with the following features:
- Fetches current staff data
- Checks if `fcm_token` key exists
- Compares current device token directly with API array (no local storage comparison)
- Updates API with appropriate token array
- Handles all error cases with fallback to simple availability update

### 3. `lib/Screens/home_screen.dart` (Entry-Level Staff)

#### Added `_initializeFcmToken()` method
```dart
Future<void> _initializeFcmToken()
```
- Called in `initState`
- Gets current device FCM token
- Saves to local storage for testing purposes only
- Non-blocking async operation

### 4. `lib/Screens/escalated_tasks_page.dart` (Higher-Level Staff)

#### Added `_initializeFcmToken()` method
```dart
Future<void> _initializeFcmToken()
```
- Called in `initState`
- Gets current device FCM token
- Saves to local storage for testing purposes only
- Non-blocking async operation

## API Payload Structure

### Update Staff with FCM Token
```json
{
  "domain_name": "...",
  "user_id": "...",
  "extras": {
    "find": {
      "staff_employee_number": "EMP123"
    }
  },
  "payload": {
    "staff_updation": {
      "is_available": true,
      "fcm_token": ["token1", "token2", "token3"]
    }
  }
}
```

## Benefits

1. **Multi-Device Support**: Staff can login from multiple devices and receive notifications on all logged-in devices.

2. **No Duplicate Tokens**: The logic prevents adding the same token multiple times.

3. **Efficient Updates**: Only updates the API when necessary (when token is new or changed).

4. **Robust Error Handling**: Gracefully falls back to basic availability update if any FCM-related operations fail.

5. **Local Storage Sync**: Keeps local storage in sync with backend for quick token comparisons.

## Error Handling

The implementation includes comprehensive error handling:
- Network failures during staff data fetch
- Missing or invalid staff data
- FCM token retrieval failures
- API update failures

In all error cases, the system falls back to updating only the availability status without FCM token changes, ensuring the login process is never blocked.

## Testing Scenarios

1. **First Login (No existing token)**: Should create new array with current token
2. **Same Device Login**: Should detect existing token and skip update
3. **Different Device Login**: Should append new token to existing array
4. **Token Changed on Same Device**: Should append new token
5. **API Failure**: Should still update availability successfully

## Local Storage

FCM token is stored in Hive's `authBox` under the key `fcm_token` **for testing purposes only**. The app doesn't actually need the FCM token stored locally for normal operation, as:

1. **Push notifications are automatically received** by the device via Firebase
2. **Token comparison is done with API data**, not local storage
3. **Local storage is only used for debugging and testing** notification functionality

The token is refreshed in both home screens (entry-level and higher-level staff) during `initState` to ensure the latest token is available for testing.

