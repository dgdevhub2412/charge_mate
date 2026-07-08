import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:battery_plus/battery_plus.dart';
import 'storage_service.dart';
import 'alarm_service.dart';

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(BatteryMonitorTaskHandler());
}

class BatteryMonitorTaskHandler extends TaskHandler {
  final Battery _battery = Battery();

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // Initialize SharedPreferences inside this background isolate
    await StorageService.init();
    AlarmService.isBackgroundIsolate = true;
    debugPrint('Background Battery Service Started');
  }

  @override
  void onRepeatEvent(DateTime timestamp) async {
    try {
      // Force reload settings from disk to sync with UI isolate updates
      await StorageService.reload();

      final level = await _battery.batteryLevel;
      final state = await _battery.batteryState;

      final isCharging = state == BatteryState.charging || state == BatteryState.full;
      final target = StorageService.getTargetLevel();
      final isRinging = AlarmService.isPlaying;

      if (isCharging && level >= target) {
        if (!isRinging) {
          await AlarmService.startAlarm();
          FlutterForegroundTask.updateService(
            notificationTitle: 'Charge Mate - ALARM!',
            notificationText: 'Battery level reached $level%! Unplug charger.',
          );
        }
      } else if (state == BatteryState.discharging) {
        if (isRinging) {
          await AlarmService.stopAlarm();
          FlutterForegroundTask.updateService(
            notificationTitle: 'Charge Mate is active',
            notificationText: 'Monitoring battery in the background...',
          );
        }
      }

      // Send live status back to UI isolate
      FlutterForegroundTask.sendDataToMain({
        'level': level,
        'state': state.index,
        'isRinging': AlarmService.isPlaying,
      });
    } catch (e) {
      debugPrint('Background check error: $e');
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    await AlarmService.stopAlarm();
    debugPrint('Background Battery Service Destroyed');
  }

  @override
  void onReceiveData(Object data) async {
    debugPrint('Background Service received command: $data');
    if (data == 'stopAlarm') {
      await AlarmService.stopAlarm();
      
      // Update notification back to normal
      FlutterForegroundTask.updateService(
        notificationTitle: 'Charge Mate is active',
        notificationText: 'Monitoring battery in the background...',
      );
      
      // Force status update back to UI
      final level = await _battery.batteryLevel;
      final state = await _battery.batteryState;
      FlutterForegroundTask.sendDataToMain({
        'level': level,
        'state': state.index,
        'isRinging': false,
      });
    } else if (data == 'startAlarm') {
      await AlarmService.startAlarm();
      
      FlutterForegroundTask.updateService(
        notificationTitle: 'Charge Mate - ALARM!',
        notificationText: 'Alarm triggered manually.',
      );
      
      final level = await _battery.batteryLevel;
      final state = await _battery.batteryState;
      FlutterForegroundTask.sendDataToMain({
        'level': level,
        'state': state.index,
        'isRinging': true,
      });
    } else if (data == 'syncSettings') {
      // Reload SharedPreferences in background isolate
      await StorageService.init();
    }
  }
}

class BackgroundService {
  // Initialize Foreground Task configuration
  static Future<void> init() async {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'charge_mate_foreground_service',
        channelName: 'Charge Mate Monitor',
        channelDescription: 'Monitors battery charge to alert when full',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(10000), // Check battery every 10 seconds
        autoRunOnBoot: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  // Start the background service
  static Future<bool> start() async {
    if (await FlutterForegroundTask.isRunningService) {
      return true;
    }
    final result = await FlutterForegroundTask.startService(
      serviceId: 256,
      notificationTitle: 'Charge Mate is active',
      notificationText: 'Monitoring battery in the background...',
      callback: startCallback,
    );
    return result is ServiceRequestSuccess;
  }

  // Stop the background service
  static Future<bool> stop() async {
    final result = await FlutterForegroundTask.stopService();
    return result is ServiceRequestSuccess;
  }

  // Check if service is currently running
  static Future<bool> get isRunning async {
    return await FlutterForegroundTask.isRunningService;
  }
}
