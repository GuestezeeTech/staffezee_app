import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/widgets.dart';

/// Service to manage continuous sound loops for multiple tasks
class ContinuousSoundService with WidgetsBindingObserver {
  static final Map<int, AudioPlayer> _taskSoundPlayers = {};
  static final Map<int, Timer> _taskSoundTimers = {};
  static final Map<int, bool> _taskSoundPlaying = {};

  // Global static variable for cross-isolate communication (backup method)
  static final Set<int> _stoppedTasks = <int>{};

  // Singleton instance for lifecycle management
  static ContinuousSoundService? _instance;

  static ContinuousSoundService get instance {
    _instance ??= ContinuousSoundService._();
    return _instance!;
  }

  ContinuousSoundService._() {
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        // App going to background - preserve player references
        print('🔊 App going to background, players: ${_taskSoundPlayers.keys}');
        break;

      case AppLifecycleState.resumed:
        // App coming back - validate player states
        _validatePlayers();
        break;

      case AppLifecycleState.detached:
        _cleanupAllPlayers();
        break;

      case AppLifecycleState.hidden:
        // App is hidden - preserve player references
        print('🔊 App hidden, players: ${_taskSoundPlayers.keys}');
        break;
    }
  }

  void _validatePlayers() {
    print('🔊 Validating players after app resume');
    final invalidPlayers = <int>[];

    _taskSoundPlayers.forEach((taskId, player) {
      try {
        // Check if player is still valid by trying a safe operation
        final state = player.state;
        print('🔊 Player for task $taskId is valid: $state');
      } catch (e) {
        // Player is invalid, mark for removal
        print('🔊 Player for task $taskId is invalid: $e');
        invalidPlayers.add(taskId);
      }
    });

    // Remove invalid players
    for (final taskId in invalidPlayers) {
      _taskSoundPlayers.remove(taskId);
      _taskSoundPlaying[taskId] = false;
      _taskSoundTimers[taskId]?.cancel();
      _taskSoundTimers.remove(taskId);
      print('🧹 Removed invalid player for task $taskId');
    }
  }

  void _cleanupAllPlayers() {
    print('🔊 Cleaning up all players');
    _taskSoundPlayers.clear();
    _taskSoundPlaying.clear();
    for (var timer in _taskSoundTimers.values) {
      timer.cancel();
    }
    _taskSoundTimers.clear();
  }

  void disposeInstance() {
    WidgetsBinding.instance.removeObserver(this);
    _cleanupAllPlayers();
  }

  /// Start continuous sound for a specific task (only for Assigned status)
  static Future<void> startTaskSound(int taskId) async {
    // Audio playback is now handled by AlarmService for both platforms.
    // We keep this method for backward compatibility, but it no longer
    // starts its own MediaPlayer loop to avoid double audio.
    print(
        '🔊 ContinuousSoundService.startTaskSound($taskId) is now a no-op; AlarmService manages alarms.');
    return;
  }

  /// Check if task should have continuous sound (only for Assigned status)
  static bool shouldPlayContinuousSound(String? taskStatus) {
    if (taskStatus == null) return false;
    final String status = taskStatus.toUpperCase();
    return status == 'ASSIGNED';
  }

  /// Mark a task as stopped using file-based communication (for cross-isolate communication)
  static Future<void> markTaskAsStopped(int taskId) async {
    try {
      // Add to global set (primary method)
      _stoppedTasks.add(taskId);
      print('🔊 Added task $taskId to global stopped set: $_stoppedTasks');

      // Also try file-based method with multiple attempts
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/sound_stopped_$taskId.txt');
      final timestamp = DateTime.now().millisecondsSinceEpoch;

      // Try multiple times to write the file
      bool writeSuccess = false;
      for (int attempt = 0; attempt < 3; attempt++) {
        try {
          await file.writeAsString('$timestamp');

          // Verify immediately
          if (await file.exists()) {
            final content = await file.readAsString();
            if (content == '$timestamp') {
              writeSuccess = true;
              break;
            }
          }

          if (attempt < 2) {
            await Future.delayed(Duration(milliseconds: 100));
          }
        } catch (e) {
          print('❌ Write attempt ${attempt + 1} failed: $e');
          if (attempt < 2) {
            await Future.delayed(Duration(milliseconds: 100));
          }
        }
      }

      print('🔊 Marked task $taskId as stopped in file at ${DateTime.now()}');
      print('🔊 File path: ${file.path}');
      print('🔊 File write success: $writeSuccess');

      if (writeSuccess) {
        final content = await file.readAsString();
        print('🔊 File content after write: $content');
      }
    } catch (e) {
      print('❌ Error marking task as stopped: $e');
    }
  }

  /// Check if a task is marked as stopped using file-based communication
  static Future<bool> isTaskMarkedAsStopped(int taskId) async {
    try {
      // Check global set first (backup method)
      final inGlobalSet = _stoppedTasks.contains(taskId);
      print('🔊 Checking global set for task $taskId: $inGlobalSet');
      print('🔊 Global stopped tasks: $_stoppedTasks');

      // Also check file-based method
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/sound_stopped_$taskId.txt');
      print('🔊 Checking file for task $taskId: ${file.path}');

      // Try multiple times to check file existence and read content
      bool exists = false;
      String fileContent = '';

      for (int i = 0; i < 5; i++) {
        try {
          exists = await file.exists();
          if (exists) {
            fileContent = await file.readAsString();
            print('🔊 File exists: $exists, content: $fileContent');

            // Parse timestamp to check if it's recent (within last 5 minutes)
            final int timestamp = int.tryParse(fileContent) ?? 0;
            final int now = DateTime.now().millisecondsSinceEpoch;
            final int fiveMinutesAgo = now - (5 * 60 * 1000);

            if (timestamp > fiveMinutesAgo) {
              print('🔊 File timestamp is recent, task is stopped');
              break;
            } else {
              print('🔊 File timestamp too old, ignoring');
              // Clean up old file
              await file.delete();
              exists = false;
              fileContent = '';
            }
          } else {
            print('🔊 File does not exist (attempt ${i + 1})');
          }
        } catch (e) {
          print('❌ Error checking file (attempt ${i + 1}): $e');
          exists = false;
          fileContent = '';
        }

        if (i < 4) {
          await Future.delayed(Duration(milliseconds: 50));
        }
      }

      // Return true if either method indicates the task is stopped
      final isStopped = inGlobalSet || exists;
      print(
          '🔊 Task $taskId marked as stopped: $isStopped (global: $inGlobalSet, file: $exists)');
      return isStopped;
    } catch (e) {
      print('❌ Error checking if task is stopped: $e');
      return false;
    }
  }

  /// Get the timestamp when a task was marked as stopped
  static Future<int> getStopTimestamp(int taskId) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/sound_stopped_$taskId.txt');
      if (await file.exists()) {
        final content = await file.readAsString();
        return int.tryParse(content) ?? 0;
      }
      return 0;
    } catch (e) {
      print('❌ Error getting stop timestamp: $e');
      return 0;
    }
  }

  /// Clear stopped marker for a specific task (for reassignment)
  static Future<void> _clearStoppedMarkerForTask(int taskId) async {
    try {
      // Remove from global set
      _stoppedTasks.remove(taskId);
      print('🔊 Removed task $taskId from global stopped set');

      // Delete the file marker
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/sound_stopped_$taskId.txt');
      if (await file.exists()) {
        await file.delete();
        print('🔊 Deleted stopped marker file for task $taskId');
      }
    } catch (e) {
      print('❌ Error clearing stopped marker for task $taskId: $e');
    }
  }

  /// Clear stopped task markers from files
  static Future<void> clearStoppedTaskMarkers() async {
    try {
      // Clear global set
      _stoppedTasks.clear();
      print('🔊 Cleared global stopped tasks set: $_stoppedTasks');

      // Clear files
      final directory = await getApplicationDocumentsDirectory();
      final files = directory
          .listSync()
          .where((file) =>
              file.path.contains('sound_stopped_') &&
              file.path.endsWith('.txt'))
          .toList();

      for (FileSystemEntity file in files) {
        if (file is File) {
          try {
            if (await file.exists()) await file.delete();
          } catch (_) {
            // File may already be deleted (e.g. by another isolate); ignore
          }
        }
      }
      print('🔊 Cleared stopped task markers from files');
    } catch (e) {
      print('❌ Error clearing stopped task markers: $e');
    }
  }

  /// Debug method to check file state
  static Future<void> debugFileState() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final files = directory
          .listSync()
          .where((file) =>
              file.path.contains('sound_stopped_') &&
              file.path.endsWith('.txt'))
          .toList();

      print('🔊 File state:');
      for (FileSystemEntity file in files) {
        if (file is File) {
          final content = await file.readAsString();
          print('🔊   ${file.path}: $content');
        }
      }
    } catch (e) {
      print('❌ Error debugging files: $e');
    }
  }

  /// Safe stop method that handles player disposal errors gracefully
  static Future<void> safeStopSound(int taskId) async {
    try {
      print('🔊 Attempting to stop sound for task $taskId');

      // IMMEDIATELY set playing state to false to prevent new loops
      _taskSoundPlaying[taskId] = false;
      print('🔊 Set playing state to false for task $taskId');

      // Mark as stopped (both global set and file)
      await markTaskAsStopped(taskId);

      // Cancel any timers
      _taskSoundTimers[taskId]?.cancel();
      _taskSoundTimers.remove(taskId);
      print('🔊 Cancelled timer for task $taskId');

      // Try to stop player if it exists
      final AudioPlayer? player = _taskSoundPlayers[taskId];
      if (player != null) {
        try {
          await player.stop().timeout(Duration(seconds: 1));
          await player.dispose().timeout(Duration(seconds: 1));
          print('🔊 Disposed player for task $taskId');
        } catch (e) {
          // Ignore player errors, already marked as stopped
          print('ℹ️ Player cleanup failed (expected if disposed): $e');
        }
        _taskSoundPlayers.remove(taskId);
      }

      // Remove from playing state map
      _taskSoundPlaying.remove(taskId);

      print('✅ Sound stopped successfully for task $taskId');
    } catch (e) {
      print('⚠️ Error in safeStopSound for task $taskId: $e');
      // Still remove from map to prevent repeated errors
      _taskSoundPlaying[taskId] = false;
      _taskSoundTimers[taskId]?.cancel();
      _taskSoundTimers.remove(taskId);
      _taskSoundPlayers.remove(taskId);
      _taskSoundPlaying.remove(taskId);
    }
  }

  /// Stop continuous sound for a specific task
  static Future<void> stopTaskSound(int taskId) async {
    await safeStopSound(taskId);
  }

  /// Stop sound for multiple tasks
  static Future<void> stopMultipleTaskSounds(List<int> taskIds) async {
    for (int taskId in taskIds) {
      await stopTaskSound(taskId);
    }
  }

  /// Stop all playing sounds
  static Future<void> stopAllSounds() async {
    print('🔊 Stopping all continuous sounds');

    final List<int> taskIds = _taskSoundPlaying.keys.toList();
    for (int taskId in taskIds) {
      await stopTaskSound(taskId);
    }
  }

  /// Force stop all sounds immediately (for debugging)
  static Future<void> forceStopAllSounds() async {
    print('🔊 Force stopping all continuous sounds');
    print('🔊 Current playing tasks: ${_taskSoundPlaying.keys.toList()}');
    print('🔊 Current timers: ${_taskSoundTimers.keys.toList()}');

    // Set all playing states to false FIRST
    for (var key in _taskSoundPlaying.keys.toList()) {
      print('🔊 Setting playing state to false for task $key');
      _taskSoundPlaying[key] = false;
    }

    // Cancel all timers
    for (var entry in _taskSoundTimers.entries) {
      print('🔊 Cancelling timer for task ${entry.key}');
      entry.value.cancel();
    }
    _taskSoundTimers.clear();

    // Dispose all players
    for (var entry in _taskSoundPlayers.entries) {
      print('🔊 Disposing player for task ${entry.key}');
      entry.value.stop();
      entry.value.dispose();
    }
    _taskSoundPlayers.clear();

    // Clear all playing states
    _taskSoundPlaying.clear();

    // Clear SharedPreferences markers
    await clearStoppedTaskMarkers();

    print('🔊 Force stop completed');
    print(
        '🔊 Final state - playing: ${_taskSoundPlaying.length}, timers: ${_taskSoundTimers.length}, players: ${_taskSoundPlayers.length}');
  }

  /// Force stop all sounds in background isolate
  static void forceStopAllSoundsInBackground() {
    print('🔊 Force stopping all continuous sounds in background isolate');
    print(
        '🔊 Background - Current playing tasks: ${_taskSoundPlaying.keys.toList()}');
    print('🔊 Background - Current timers: ${_taskSoundTimers.keys.toList()}');

    // Set all playing states to false FIRST
    for (var key in _taskSoundPlaying.keys.toList()) {
      print('🔊 Background - Setting playing state to false for task $key');
      _taskSoundPlaying[key] = false;
    }

    // Cancel all timers
    for (var entry in _taskSoundTimers.entries) {
      print('🔊 Background - Cancelling timer for task ${entry.key}');
      entry.value.cancel();
    }
    _taskSoundTimers.clear();

    // Dispose all players
    for (var entry in _taskSoundPlayers.entries) {
      print('🔊 Background - Disposing player for task ${entry.key}');
      entry.value.stop();
      entry.value.dispose();
    }
    _taskSoundPlayers.clear();

    // Clear all playing states
    _taskSoundPlaying.clear();

    // Clear SharedPreferences markers
    clearStoppedTaskMarkers();

    print('🔊 Background - Force stop completed');
    print(
        '🔊 Background - Final state - playing: ${_taskSoundPlaying.length}, timers: ${_taskSoundTimers.length}, players: ${_taskSoundPlayers.length}');
  }

  /// Check if sound is playing for a specific task
  static bool isSoundPlaying(int taskId) {
    return _taskSoundPlaying[taskId] == true;
  }

  /// Get list of tasks currently playing sounds
  static List<int> getPlayingTasks() {
    return _taskSoundPlaying.entries
        .where((entry) => entry.value == true)
        .map((entry) => entry.key)
        .toList();
  }

  /// Play sound loop for a specific task
  static Future<void> _playSoundLoop(int taskId) async {
    final AudioPlayer? player = _taskSoundPlayers[taskId];
    if (player == null) return;

    // Check if sound should still be playing for this task
    if (_taskSoundPlaying[taskId] != true) {
      print('🔊 Sound no longer playing for task $taskId, stopping loop');
      return;
    }

    // Check if task is marked as stopped in file (cross-isolate communication)
    print('🔊 Initial check - Checking file for task $taskId...');
    final bool isMarkedAsStopped = await isTaskMarkedAsStopped(taskId);
    print(
        '🔊 Initial check - Task $taskId marked as stopped: $isMarkedAsStopped');
    if (isMarkedAsStopped) {
      final int stopTimestamp = await getStopTimestamp(taskId);
      print(
          '🔊 Task $taskId marked as stopped in file at ${DateTime.fromMillisecondsSinceEpoch(stopTimestamp)}, stopping sound loop');
      await stopTaskSound(taskId);
      return;
    }

    try {
      print('🔊 Starting sound playback for task $taskId');

      // Stop any currently playing sound first
      await player.stop();

      // Play the sound
      await player.play(AssetSource('audio/alarm.mp3'));
      print('🔊 Sound played for task $taskId');

      // Cancel any existing timer for this task
      _taskSoundTimers[taskId]?.cancel();

      // Set up timer to replay after sound duration (assuming 2 seconds for alarm.mp3)
      _taskSoundTimers[taskId] = Timer(Duration(seconds: 1), () async {
        print(
            '🔊 Timer fired for task $taskId, checking if should continue...');
        print(
            '🔊 Current playing state for task $taskId: ${_taskSoundPlaying[taskId]}');

        // Check if task is marked as stopped in file (cross-isolate communication)
        print('🔊 Checking file for task $taskId...');
        final bool isMarkedAsStopped = await isTaskMarkedAsStopped(taskId);
        print('🔊 Task $taskId marked as stopped: $isMarkedAsStopped');
        if (isMarkedAsStopped) {
          final int stopTimestamp = await getStopTimestamp(taskId);
          print(
              '🔊 Task $taskId marked as stopped in file at ${DateTime.fromMillisecondsSinceEpoch(stopTimestamp)}, ending loop');
          await stopTaskSound(taskId);
          return;
        }

        // Check if sound should still be playing for this task
        if (_taskSoundPlaying.containsKey(taskId) &&
            _taskSoundPlaying[taskId] == true) {
          // Double-check that task is not marked as stopped before continuing
          final bool isStillMarkedAsStopped =
              await isTaskMarkedAsStopped(taskId);
          if (isStillMarkedAsStopped) {
            print(
                '🔊 Task $taskId was marked as stopped during timer, ending loop');
            await stopTaskSound(taskId);
            return;
          }

          // Additional check: if global set contains this task, stop immediately
          if (_stoppedTasks.contains(taskId)) {
            print(
                '🔊 Task $taskId found in global stopped set, ending loop immediately');
            await stopTaskSound(taskId);
            return;
          }

          print('🔊 Continuing sound loop for task $taskId - no gap');
          _playSoundLoop(taskId); // Recursive call to continue loop
        } else {
          print(
              '🔊 Sound stopped for task $taskId, ending loop (not in map or false)');
        }
      });
    } catch (e) {
      print('❌ Error playing sound loop for task $taskId: $e');
      // Stop the sound if there's an error
      await stopTaskSound(taskId);
    }
  }
}
