import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'alarm_service.dart';

class BatteryService {
  static final Battery _battery = Battery();
  static StreamSubscription<BatteryState>? _stateSubscription;
  static Timer? _pollingTimer;

  static int _currentLevel = 0;
  static BatteryState _currentState = BatteryState.unknown;
  static bool _isInitialized = false;

  // Stream controller to notify UI of status changes
  static final StreamController<BatteryStatus> _statusController = 
      StreamController<BatteryStatus>.broadcast();

  static Stream<BatteryStatus> get statusStream => _statusController.stream;
  static int get currentLevel => _currentLevel;
  static BatteryState get currentState => _currentState;

  // Initialize monitoring
  static Future<void> init() async {
    if (_isInitialized) return;
    _isInitialized = true;

    // Get initial state
    try {
      _currentLevel = await _battery.batteryLevel;
      _currentState = await _battery.batteryState;
    } catch (e) {
      debugPrint('Error getting initial battery status: $e');
    }

    // Bind AlarmService changes to notify listeners
    AlarmService.onStatusChanged = () {
      _notifyListeners();
    };

    _notifyListeners();

    // Listen to state changes
    _stateSubscription = _battery.onBatteryStateChanged.listen((BatteryState state) {
      _currentState = state;
      _handleStateChange(state);
    });

    // Start periodic level checking (every 10 seconds)
    _pollingTimer = Timer.periodic(const Duration(seconds: 10), (timer) async {
      await _checkBatteryLevel();
    });
  }

  // Handle battery state change (charging, discharging, full)
  static void _handleStateChange(BatteryState state) async {
    await _checkBatteryLevel();

    // If charger is unplugged (discharging), automatically stop the alarm in both isolates
    if (state == BatteryState.discharging) {
      await AlarmService.stopAlarm();
      // Send command to stop background service alarm
      FlutterForegroundTask.sendDataToTask('stopAlarm');
    }
  }

  // Check battery level and notify listeners
  static Future<void> _checkBatteryLevel() async {
    try {
      _currentLevel = await _battery.batteryLevel;
      
      // Update state in case it changed without notifying stream
      _currentState = await _battery.batteryState;

      _notifyListeners();

      // Note: We do NOT trigger AlarmService.startAlarm() in the main UI isolate here.
      // This is now exclusively handled by the background task service (BatteryMonitorTaskHandler)
      // to prevent dual-alarm conflicts.
    } catch (e) {
      debugPrint('Error checking battery level: $e');
    }
  }

  // Clean up
  static void dispose() {
    _stateSubscription?.cancel();
    _pollingTimer?.cancel();
    _statusController.close();
  }

  // Notify listeners with latest status
  static void _notifyListeners() {
    if (!_statusController.isClosed) {
      _statusController.add(BatteryStatus(
        level: _currentLevel,
        state: _currentState,
        isRinging: AlarmService.isPlaying,
      ));
    }
  }

  static const MethodChannel _batteryChannel = MethodChannel('charge_mate/battery');

  // Fetch native battery statistics (Current, Voltage, Temperature)
  static Future<Map<String, dynamic>?> getNativeBatteryStats() async {
    try {
      final Map<dynamic, dynamic>? stats = 
          await _batteryChannel.invokeMethod<Map<dynamic, dynamic>>('getBatteryStats');
      if (stats != null) {
        return Map<String, dynamic>.from(stats);
      }
    } catch (e) {
      debugPrint('Error getting native battery stats: $e');
    }
    return null;
  }
}

class BatteryStatus {
  final int level;
  final BatteryState state;
  final bool isRinging;

  BatteryStatus({
    required this.level,
    required this.state,
    required this.isRinging,
  });

  bool get isCharging => state == BatteryState.charging || state == BatteryState.full;
  
  String get stateString {
    switch (state) {
      case BatteryState.charging:
        return 'Charging';
      case BatteryState.discharging:
        return 'Discharging';
      case BatteryState.full:
        return 'Fully Charged';
      case BatteryState.unknown:
      default:
        return 'Unknown';
    }
  }
}
