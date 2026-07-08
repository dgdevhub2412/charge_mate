import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static const String _keyTargetLevel = 'target_level';
  static const String _keyAlarmEnabled = 'alarm_enabled';
  static const String _keyVibrationEnabled = 'vibration_enabled';
  static const String _keyAlarmDuration = 'alarm_duration';
  static const String _keyCustomAudioPath = 'custom_audio_path';

  static SharedPreferences? _prefs;

  // Initialize SharedPreferences
  static Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  // Reload SharedPreferences from disk (for isolate syncing)
  static Future<void> reload() async {
    await _prefs?.reload();
  }

  // Target Level (1% to 100%)
  static int getTargetLevel() {
    return _prefs?.getInt(_keyTargetLevel) ?? 80;
  }

  static Future<bool> setTargetLevel(int value) async {
    return await _prefs?.setInt(_keyTargetLevel, value) ?? false;
  }

  // Alarm Enabled Status
  static bool isAlarmEnabled() {
    return _prefs?.getBool(_keyAlarmEnabled) ?? true;
  }

  static Future<bool> setAlarmEnabled(bool value) async {
    return await _prefs?.setBool(_keyAlarmEnabled, value) ?? false;
  }

  // Vibration Enabled Status
  static bool isVibrationEnabled() {
    return _prefs?.getBool(_keyVibrationEnabled) ?? true;
  }

  static Future<bool> setVibrationEnabled(bool value) async {
    return await _prefs?.setBool(_keyVibrationEnabled, value) ?? false;
  }

  // Alarm Duration (in seconds)
  static int getAlarmDuration() {
    return _prefs?.getInt(_keyAlarmDuration) ?? 60; // 60 seconds default
  }

  static Future<bool> setAlarmDuration(int value) async {
    return await _prefs?.setInt(_keyAlarmDuration, value) ?? false;
  }

  // Custom Audio File Path
  static String? getCustomAudioPath() {
    return _prefs?.getString(_keyCustomAudioPath);
  }

  static Future<bool> setCustomAudioPath(String? value) async {
    if (value == null) {
      return await _prefs?.remove(_keyCustomAudioPath) ?? false;
    }
    return await _prefs?.setString(_keyCustomAudioPath, value) ?? false;
  }

  // Custom Audio Title
  static const String _keyCustomAudioTitle = 'custom_audio_title';

  static String? getCustomAudioTitle() {
    return _prefs?.getString(_keyCustomAudioTitle);
  }

  static Future<bool> setCustomAudioTitle(String? value) async {
    if (value == null) {
      return await _prefs?.remove(_keyCustomAudioTitle) ?? false;
    }
    return await _prefs?.setString(_keyCustomAudioTitle, value) ?? false;
  }
}
