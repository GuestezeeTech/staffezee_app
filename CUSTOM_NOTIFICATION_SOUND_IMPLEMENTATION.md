# Custom Notification Sound Implementation

## Overview
This implementation adds custom notification sounds to Firebase Cloud Messaging (FCM) notifications in the Guesteezee Staff App. The app will now play a custom alarm sound whenever a notification is received, providing immediate audio feedback to users across all app states (foreground, background, and terminated).

## Features Implemented

### 1. Audio Service (`lib/Services/audio_service.dart`)
- **Custom Sound Playback**: Plays the custom alarm.mp3 sound for notifications
- **Multi-State Support**: Handles audio playback for foreground, background, and terminated states
- **Audio Context Configuration**: Optimized for notification sounds with proper audio focus
- **Error Handling**: Graceful fallback if audio playback fails
- **Resource Management**: Proper initialization and disposal of audio resources

### 2. Android Raw Resources
- **Custom Sound File**: `alarm.mp3` placed in `android/app/src/main/res/raw/`
- **Notification Channel**: Updated to use custom sound for system notifications
- **Local Notifications**: Configured to use custom sound for local notifications

### 3. Integration with Firebase Notifications
The audio service is integrated into the existing `PushNotificationService` at multiple points:

- **Foreground Notifications**: Plays custom sound when FCM message is received while app is open
- **Background Notifications**: Plays custom sound when notification is tapped
- **Terminated State**: Plays custom sound when app is launched from notification
- **Local Notifications**: Uses custom sound for local notification display

## Dependencies Added
- `audioplayers: ^6.1.0` - Handles audio playback functionality

## File Structure
```
android/app/src/main/res/raw/
├── alarm.mp3                    # Custom notification sound

lib/Services/
├── audio_service.dart           # Audio playback service
└── push_notification_service.dart # Updated with audio integration

assets/audio/
└── alarm.mp3                   # Source audio file
```

## Implementation Details

### Audio Service Features
- **Initialization**: Sets up audio context for optimal notification sound playback
- **State-Specific Methods**: 
  - `playForegroundNotificationSound()` - For foreground notifications
  - `playBackgroundNotificationSound()` - For background notifications  
  - `playTerminatedNotificationSound()` - For terminated state notifications
- **Audio Context**: Configured for notification sounds with proper focus management
- **Error Handling**: Fallback mechanisms if custom sound fails to play

### Notification Channel Updates
- **Channel ID**: Updated to `alarm_channel` to match FCM response
- **Custom Sound**: Uses `UriAndroidNotificationSound('alarm')` for system notifications
- **Local Notifications**: Uses `RawResourceAndroidNotificationSound('alarm')` for local notifications
- **Sound Priority**: Maintains high priority for notification sounds
- **Vibration Pattern**: Uses `Int64List.fromList([0, 1000, 500, 1000])` for custom vibration pattern
- **Conditional Playback**: Only plays custom sound when `sound: "alarm"` is specified in the notification

### Integration Points
1. **Foreground Handler**: Plays sound + shows local notification with vibration (FCM doesn't show system notification in foreground)
2. **Background Handler**: Plays sound when notification tapped in background
3. **Terminated Handler**: Plays sound when app launched from terminated state
4. **Background Message Handler**: Plays sound + shows local notification with vibration when FCM message received in background/terminated state
5. **Pending Notifications**: Plays sound for delayed notification processing
6. **System Notifications**: FCM handles notification display in background/terminated states with vibration

### Background Message Handler (`lib/Services/background_message_handler.dart`)
- **Isolate Execution**: Runs in separate isolate for background/terminated state
- **Custom Sound Detection**: Checks both `data.sound` and `notification.android.sound` fields
- **Audio Playback**: Plays custom alarm sound using AudioPlayer in background
- **Local Notification**: Shows notification with custom sound channel
- **Resource Management**: Properly disposes audio player after playback

## Usage

### Automatic Sound Playback
Custom notification sound is automatically played when:
1. Firebase notification is received in foreground
2. User taps on a notification (background or local)
3. App is launched from terminated state via notification
4. Pending notifications are processed after app activation

### FCM Payload Support
The implementation supports the FCM payload structure based on the actual response:
```json
{
  "data": {
    "sound": "alarm",
    "click_action": "FLUTTER_NOTIFICATION_CLICK",
    "message": "{\"order_id\": 21}"
  },
  "notification": {
    "title": "Escalated",
    "body": "pls check",
    "android": {
      "channelId": "alarm_channel",
      "sound": "alarm"
    }
  }
}
```

The implementation checks for custom sound in both:
- `data.sound` field
- `notification.android.sound` field

Only plays custom sound when either field contains "alarm".

## Permissions
- Android: `VIBRATE` permission (already present in AndroidManifest.xml)
- Audio playback permissions are handled automatically by the audioplayers package

## Testing
To test the custom notification sound:

1. **Foreground Testing**: Send FCM notification while app is open
2. **Background Testing**: Send FCM notification, tap it when app is in background
3. **Terminated Testing**: Send FCM notification, tap it when app is completely closed
4. **Local Notification Testing**: Trigger local notification display

## Troubleshooting

### Common Issues
1. **Sound Not Playing**: Check if alarm.mp3 exists in `android/app/src/main/res/raw/`
2. **Audio Context Errors**: Ensure proper audio permissions are granted
3. **File Not Found**: Verify the audio file is properly copied to the raw folder

### Debug Information
The implementation includes comprehensive logging:
- Audio service initialization status
- Sound playback attempts and results
- Error messages for troubleshooting

## Future Enhancements
- Multiple notification sound options
- User-configurable notification sounds
- Volume control for notification sounds
- Sound duration customization
