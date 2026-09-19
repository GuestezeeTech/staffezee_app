import 'package:audioplayers/audioplayers.dart';
import 'dart:io';

class AudioService {
  static final AudioPlayer _audioPlayer = AudioPlayer();
  static bool _isInitialized = false;

  /// Initialize the audio service
  static Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // For emulators and devices with audio context issues, skip audio context setup
      // and just initialize the basic audio player
      print(
          "🔊 Initializing audio service (basic mode for emulator compatibility)");

      _isInitialized = true;
      print("🔊 Audio service initialized successfully");
    } catch (e) {
      print("❌ Error initializing audio service: $e");
      // Still mark as initialized to prevent repeated attempts
      _isInitialized = true;
    }
  }

  /// Play custom notification sound
  static Future<void> playNotificationSound() async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      // Stop any currently playing audio
      await _audioPlayer.stop();

      // Play the custom alarm sound
      await _audioPlayer.play(AssetSource('audio/alarm.mp3'));

      print("🔊 Playing custom notification sound");
    } catch (e) {
      print("❌ Error playing notification sound: $e");

      // Check if running on emulator
      bool isEmulator = Platform.isAndroid &&
          (Platform.environment['ANDROID_EMULATOR'] == '1' ||
              Platform.environment['ANDROID_SERIAL']?.contains('emulator') ==
                  true);

      if (isEmulator) {
        print("🔇 Running on emulator - audio playback may be limited");
      } else if (e.toString().contains('AudioContext') ||
          e.toString().contains('assertion')) {
        print("🔇 Audio context error - this may be due to device limitations");
      } else {
        // Fallback: try to play system notification sound
        try {
          await _audioPlayer.play(AssetSource('audio/alarm.mp3'));
        } catch (fallbackError) {
          print("❌ Fallback audio play failed: $fallbackError");
        }
      }
    }
  }

  /// Play custom notification sound for foreground state
  static Future<void> playForegroundNotificationSound() async {
    print("🔊 Playing foreground notification sound");
    await playNotificationSound();
  }

  /// Play custom notification sound for background state
  static Future<void> playBackgroundNotificationSound() async {
    print("🔊 Playing background notification sound");
    await playNotificationSound();
  }

  /// Play custom notification sound for terminated state
  static Future<void> playTerminatedNotificationSound() async {
    print("🔊 Playing terminated notification sound");
    await playNotificationSound();
  }

  /// Stop any currently playing audio
  static Future<void> stopAudio() async {
    try {
      await _audioPlayer.stop();
      print("🔇 Stopped audio playback");
    } catch (e) {
      print("❌ Error stopping audio: $e");
    }
  }

  /// Dispose of the audio player
  static Future<void> dispose() async {
    try {
      await _audioPlayer.dispose();
      _isInitialized = false;
      print("🧹 Audio service disposed");
    } catch (e) {
      print("❌ Error disposing audio service: $e");
    }
  }

  /// Check if audio is currently playing
  static bool get isPlaying => _audioPlayer.state == PlayerState.playing;

  /// Get current audio player state
  static PlayerState get playerState => _audioPlayer.state;
}
