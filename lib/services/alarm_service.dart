import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';
import 'storage_service.dart';

class AlarmService {
  static final AudioPlayer _audioPlayer = AudioPlayer();
  static VoidCallback? onStatusChanged;
  static bool _isPlaying = false;
  static Timer? _autoStopTimer;

  static bool get isPlaying => _isPlaying;

  // Fallback alarm sound URL (from royalty-free public Google Actions sound library)
  static const String defaultAlarmUrl = 'https://actions.google.com/sounds/v1/alarms/digital_watch_alarm_long.ogg';
  static const MethodChannel _ringtoneChannel = MethodChannel('charge_mate/ringtone_picker');

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

    // Stop native system ringtone
    try {
      _ringtoneChannel.invokeMethod('stopRingtone');
    } catch (e) {
      debugPrint('Error stopping native ringtone: $e');
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
          // Play system ringtone natively
          await _ringtoneChannel.invokeMethod('playRingtone', {'uri': customPath});
        } else {
          // Play custom local file path
          await _audioPlayer.setReleaseMode(ReleaseMode.loop);
          await _audioPlayer.play(DeviceFileSource(customPath));
        }
      } else {
        // Play default public sound URL
        await _audioPlayer.setReleaseMode(ReleaseMode.loop);
        await _audioPlayer.play(UrlSource(defaultAlarmUrl));
      }
    } catch (e) {
      debugPrint('Error playing custom alarm: $e. Reverting to fallback.');
      try {
        await _audioPlayer.setReleaseMode(ReleaseMode.loop);
        await _audioPlayer.play(UrlSource(defaultAlarmUrl));
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
