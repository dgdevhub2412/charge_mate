import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:my_ringtone_player/my_ringtone_player.dart';
import 'storage_service.dart';

class AlarmService {
  static final AudioPlayer _audioPlayer = AudioPlayer();
  static VoidCallback? onStatusChanged;
  static bool _isPlaying = false;
  static Timer? _autoStopTimer;
  static bool isBackgroundIsolate = false; // Flag to indicate if running in background isolate

  static bool get isPlaying => _isPlaying;

  // Start the alarm and vibration asynchronously without blocking
  static Future<void> startAlarm() async {
    if (_isPlaying) return;
    _isPlaying = true;
    onStatusChanged?.call();

    // 1. Trigger Alarm Sound concurrently (no await)
    if (StorageService.isAlarmEnabled()) {
      _playAudioConcurrently();
    }

    // 2. Trigger Vibration concurrently (no await)
    if (StorageService.isVibrationEnabled()) {
      _startVibrationConcurrently();
    }

    // 3. Set Auto-stop timer
    final durationSeconds = StorageService.getAlarmDuration();
    _autoStopTimer?.cancel();
    _autoStopTimer = Timer(Duration(seconds: durationSeconds), () {
      stopAlarm();
    });
  }

  // Stop the alarm and vibration
  static Future<void> stopAlarm() async {
    if (!_isPlaying) return;
    _isPlaying = false;
    onStatusChanged?.call();

    _autoStopTimer?.cancel();
    _autoStopTimer = null;

    // Stop native custom system ringtone via our local plugin
    try {
      await MyRingtonePlayer.stop();
    } catch (e) {
      debugPrint('Error stopping custom native ringtone: $e');
    }

    // Stop flutter_ringtone_player
    try {
      await FlutterRingtonePlayer().stop();
    } catch (e) {
      debugPrint('Error stopping ringtone player: $e');
    }

    // Stop audioplayers sound
    try {
      await _audioPlayer.stop();
    } catch (e) {
      debugPrint('Error stopping audio player: $e');
    }

    // Stop physical vibration
    try {
      await Vibration.cancel();
    } catch (e) {
      debugPrint('Error stopping vibration: $e');
    }
  }

  // Test current configuration for 5 seconds
  static Future<void> testAlarm() async {
    await startAlarm();
    // Override auto-stop timer for test (stop after 5 seconds)
    _autoStopTimer?.cancel();
    _autoStopTimer = Timer(const Duration(seconds: 5), () {
      stopAlarm();
    });
  }

  // Play audio concurrently to prevent UI blocking
  static Future<void> _playAudioConcurrently() async {
    try {
      final customPath = StorageService.getCustomAudioPath();
      
      if (customPath != null && customPath.isNotEmpty) {
        if (customPath.startsWith('content://')) {
          // Play the selected custom system ringtone via our local plugin.
          // This works in both foreground and background service isolates!
          await MyRingtonePlayer.play(customPath);
        } else {
          // Play custom local file path
          await _audioPlayer.setReleaseMode(ReleaseMode.loop);
          await _audioPlayer.play(DeviceFileSource(customPath));
        }
      } else {
        // Default sound: Play default system alarm sound offline (loud, ignores silent mode).
        await FlutterRingtonePlayer().playAlarm(
          looping: true,
          asAlarm: true,
          volume: 1.0,
        );
      }
    } catch (e) {
      debugPrint('Error playing custom alarm: $e. Reverting to fallback.');
      try {
        // Fallback: play default alarm sound natively
        await FlutterRingtonePlayer().playAlarm(
          looping: true,
          asAlarm: true,
          volume: 1.0,
        );
      } catch (err) {
        debugPrint('Fallback alarm failed: $err');
      }
    }
  }

  // Start physical vibration concurrently to prevent UI blocking
  static Future<void> _startVibrationConcurrently() async {
    try {
      final hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator) {
        // Vibrate: vibrate 0.5s, rest 1s, vibrate 0.5s... repeat indefinitely (repeat: 0)
        await Vibration.vibrate(
          pattern: [500, 1000, 500, 1000],
          repeat: 0,
        );
      }
    } catch (e) {
      debugPrint('Error running vibration: $e');
    }
  }
}
