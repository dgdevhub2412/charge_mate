import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:file_picker/file_picker.dart';
import '../app_colors.dart';
import '../services/storage_service.dart';
import '../services/alarm_service.dart';
import '../services/battery_service.dart';
import '../services/background_service.dart';
import '../widgets/battery_indicator.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late AnimationController _bellController;
  StreamSubscription<BatteryStatus>? _batterySubscription;
  
  // Local state mirrored from services
  int _currentLevel = 50;
  BatteryState _batteryState = BatteryState.unknown;
  bool _isRinging = false;
  
  // Settings values
  int _targetLevel = 80;
  bool _alarmEnabled = true;
  bool _vibrationEnabled = true;
  int _alarmDuration = 60;
  String? _customAudioPath;
  String? _customAudioTitle;

  // Charging session tracking
  DateTime? _chargeStartTime;
  int? _chargeStartLevel;

  // Live stats from native
  double _voltage = 0.0;
  double _current = 0.0;
  double _temperature = 0.0;
  double _wattage = 0.0;

  Timer? _statsTimer;

  @override
  void initState() {
    super.initState();
    _bellController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _loadSettings();
    _requestPermissionsAndStartService();
    _initBatteryMonitoring();

    // Start battery stats timer
    _updateNativeStats();
    _statsTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      _updateNativeStats();
    });
  }

  Future<void> _requestPermissionsAndStartService() async {
    // Request permission for Android 13+ notifications
    await FlutterForegroundTask.requestNotificationPermission();
    
    // Start persistent background service
    await BackgroundService.start();
    
    // Register callback to listen for battery data from task isolate
    FlutterForegroundTask.addTaskDataCallback(_onReceiveTaskData);
  }

  void _onReceiveTaskData(dynamic data) {
    if (data is Map<dynamic, dynamic>) {
      setState(() {
        _currentLevel = data['level'] as int;
        final stateIndex = data['state'] as int;
        _batteryState = BatteryState.values[stateIndex];
        _isRinging = data['isRinging'] as bool;
      });

      if (_isRinging && !_bellController.isAnimating) {
        _bellController.repeat(reverse: true);
      } else if (!_isRinging && _bellController.isAnimating) {
        _bellController.stop();
      }
    }
  }

  // Load configuration from local storage
  void _loadSettings() {
    setState(() {
      _targetLevel = StorageService.getTargetLevel();
      _alarmEnabled = StorageService.isAlarmEnabled();
      _vibrationEnabled = StorageService.isVibrationEnabled();
      _alarmDuration = StorageService.getAlarmDuration();
      _customAudioPath = StorageService.getCustomAudioPath();
      _customAudioTitle = StorageService.getCustomAudioTitle();
    });
  }

  // Initialize and subscribe to battery monitoring stream
  void _initBatteryMonitoring() async {
    await BatteryService.init();
    
    // Set initial values
    setState(() {
      _currentLevel = BatteryService.currentLevel;
      _batteryState = BatteryService.currentState;
      _isRinging = AlarmService.isPlaying;
    });

    final initialCharging = _batteryState == BatteryState.charging || _batteryState == BatteryState.full;
    if (initialCharging) {
      _chargeStartTime = DateTime.now();
      _chargeStartLevel = _currentLevel;
    }

    if (_isRinging) {
      _bellController.repeat(reverse: true);
    }

    // Listen for live updates
    _batterySubscription = BatteryService.statusStream.listen((status) {
      final wasCharging = _batteryState == BatteryState.charging || _batteryState == BatteryState.full;
      final isCharging = status.state == BatteryState.charging || status.state == BatteryState.full;

      setState(() {
        _currentLevel = status.level;
        _batteryState = status.state;
        _isRinging = status.isRinging;
      });

      if (isCharging && !wasCharging) {
        _chargeStartTime = DateTime.now();
        _chargeStartLevel = _currentLevel;
        _updateNativeStats();
      } else if (!isCharging) {
        _chargeStartTime = null;
        _chargeStartLevel = null;
      }

      if (_isRinging && !_bellController.isAnimating) {
        _bellController.repeat(reverse: true);
      } else if (!_isRinging && _bellController.isAnimating) {
        _bellController.stop();
      }
    });
  }

  @override
  void dispose() {
    _statsTimer?.cancel();
    FlutterForegroundTask.removeTaskDataCallback(_onReceiveTaskData);
    _batterySubscription?.cancel();
    _bellController.dispose();
    super.dispose();
  }

  // Pick custom audio file
  Future<void> _pickAudioFile() async {
    try {
      FilePickerResult? result = await FilePicker.pickFiles(
        type: FileType.audio,
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        await StorageService.setCustomAudioPath(path);
        setState(() {
          _customAudioPath = path;
        });
        FlutterForegroundTask.sendDataToTask('syncSettings');
        // SnackBar removed
      }
    } catch (e) {
      debugPrint('Error picking file: $e');
    }
  }

  // Clear custom audio
  Future<void> _clearAudioFile() async {
    await StorageService.setCustomAudioPath(null);
    await StorageService.setCustomAudioTitle(null);
    setState(() {
      _customAudioPath = null;
      _customAudioTitle = null;
    });
    FlutterForegroundTask.sendDataToTask('syncSettings');
    // SnackBar removed
  }

  // Format filename from path
  String _getFileName(String? path) {
    if (path == null) return 'Default (Beep sound)';
    if (_customAudioTitle != null) return _customAudioTitle!;
    if (path.startsWith('content://')) return 'System Sound';
    return path.split(Platform.pathSeparator).last;
  }

  // Pick System Ringtone using native MethodChannel on Android
  Future<void> _pickSystemRingtone() async {
    try {
      if (Platform.isAndroid) {
        const platform = MethodChannel('charge_mate/ringtone_picker');
        final Map<dynamic, dynamic>? result = await platform.invokeMethod('pickRingtone');
        
        if (result != null) {
          final uri = result['uri'] as String?;
          final title = result['title'] as String?;
          
          if (uri != null) {
            await StorageService.setCustomAudioPath(uri);
            await StorageService.setCustomAudioTitle(title);
            setState(() {
              _customAudioPath = uri;
              _customAudioTitle = title;
            });
            FlutterForegroundTask.sendDataToTask('syncSettings');
            // SnackBar removed
          }
        }
      } else {
        await _pickAudioFile();
      }
    } catch (e) {
      debugPrint('Error picking system ringtone: $e');
      await _pickAudioFile();
    }
  }

  // Stop current ringing
  void _dismissAlarm() async {
    await AlarmService.stopAlarm();
    FlutterForegroundTask.sendDataToTask('stopAlarm');
    setState(() {
      _isRinging = false;
    });
    _bellController.stop();
  }

  // Start test ringing
  void _testAlarmSettings() async {
    setState(() {
      _isRinging = true;
    });
    _bellController.repeat(reverse: true);

    // SnackBar removed
    AlarmService.testAlarm();

    // After 5s check again to reset UI
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) {
        setState(() {
          _isRinging = AlarmService.isPlaying;
        });
        if (!_isRinging) {
          _bellController.stop();
        }
      }
    });
  }

  void _updateNativeStats() async {
    final isCharging = _batteryState == BatteryState.charging || _batteryState == BatteryState.full;
    if (!isCharging) {
      if (mounted) {
        setState(() {
          _voltage = 0.0;
          _current = 0.0;
          _wattage = 0.0;
        });
      }
      return;
    }

    final stats = await BatteryService.getNativeBatteryStats();
    if (stats != null && mounted) {
      final int rawCurrent = stats['currentNow'] as int? ?? 0;
      final int rawVoltage = stats['voltage'] as int? ?? 0;
      final double temp = stats['temperature'] as double? ?? 0.0;

      final double currentMa = (rawCurrent.abs()) / 1000.0;
      final double voltageV = rawVoltage / 1000.0;
      final double watts = voltageV * (currentMa / 1000.0);

      setState(() {
        _voltage = voltageV;
        _current = currentMa;
        _temperature = temp;
        _wattage = watts;
      });
    }
  }

  String _getRemainingTimeText() {
    final isCharging = _batteryState == BatteryState.charging || _batteryState == BatteryState.full;
    if (!isCharging) {
      return 'Not charging';
    }
    if (_currentLevel >= _targetLevel) {
      return 'Target level reached';
    }

    double minutesPerPercent = 1.5;

    if (_chargeStartTime != null && _chargeStartLevel != null) {
      final elapsed = DateTime.now().difference(_chargeStartTime!);
      final levelDiff = _currentLevel - _chargeStartLevel!;
      if (levelDiff > 0 && elapsed.inSeconds > 10) {
        minutesPerPercent = elapsed.inSeconds / 60.0 / levelDiff;
      }
    }

    final remainingPercent = _targetLevel - _currentLevel;
    final remainingMinutes = (remainingPercent * minutesPerPercent).round();

    if (remainingMinutes <= 0) {
      return 'Almost reached';
    } else if (remainingMinutes < 60) {
      return '$remainingMinutes min remaining';
    } else {
      final hours = remainingMinutes ~/ 60;
      final mins = remainingMinutes % 60;
      return '$hours h $mins m remaining';
    }
  }

  Widget _buildChargingStatsCard() {
    final isCharging = _batteryState == BatteryState.charging || _batteryState == BatteryState.full;
    final remainingText = _getRemainingTimeText();

    if (!isCharging) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'CHARGING ESTIMATE',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    remainingText,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.bolt_rounded,
                  color: AppColors.primary,
                  size: 28,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Divider(color: AppColors.border.withValues(alpha: 0.5), height: 1),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatItem(
                icon: Icons.flash_on_rounded,
                value: _wattage > 0.0 ? '${_wattage.toStringAsFixed(1)} W' : '-- W',
                label: 'Power',
                color: AppColors.accent,
              ),
              _buildStatItem(
                icon: Icons.electric_bolt_rounded,
                value: _current > 0.0 ? '${_current.round()} mA' : '-- mA',
                label: 'Current',
                color: AppColors.secondary,
              ),
              _buildStatItem(
                icon: Icons.thermostat_rounded,
                value: _temperature > 0.0 ? '${_temperature.toStringAsFixed(1)} °C' : '-- °C',
                label: 'Temp',
                color: _temperature > 40.0 ? AppColors.alert : AppColors.success,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isCharging = _batteryState == BatteryState.charging || _batteryState == BatteryState.full;
    
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: AppColors.backgroundGradient,
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              // Main Scrollable Content
              SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Top App Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Charge Mate',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                                color: AppColors.textPrimary,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                    color: AppColors.primary,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'Background Monitoring Active',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        // Flashing bell and STOP button if ringing, else normal logo
                        _isRinging
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  RotationTransition(
                                    turns: Tween(begin: -0.1, end: 0.1).animate(_bellController),
                                    child: const Icon(
                                      Icons.notifications_active,
                                      color: AppColors.secondary,
                                      size: 32,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  IconButton(
                                    onPressed: _dismissAlarm,
                                    icon: const Icon(
                                      Icons.stop_circle_rounded,
                                      color: AppColors.alert,
                                      size: 32,
                                    ),
                                    tooltip: 'Stop Alarm',
                                    padding: EdgeInsets.zero,
                                  ),
                                ],
                              )
                            : Image.asset(
                                'assets/charge_mate_logo.png',
                                width: 44,
                                height: 44,
                                errorBuilder: (context, error, stackTrace) => const CircleAvatar(
                                  backgroundColor: AppColors.surface,
                                  radius: 22,
                                  child: Icon(Icons.bolt, color: AppColors.primary),
                                ),
                              ),
                      ],
                    ),
                    const SizedBox(height: 40),

                    // Custom Circular Battery Gauge
                    BatteryIndicator(
                      level: _currentLevel,
                      isCharging: isCharging,
                    ),
                    const SizedBox(height: 40),

                    // Live Charging Stats Card
                    _buildChargingStatsCard(),
                    if (isCharging) const SizedBox(height: 20),

                    // Target Slider Card
                    _buildTargetSliderCard(),
                    const SizedBox(height: 20),

                    // Action Controls Card (Switch Toggles)
                    _buildSettingsCard(),
                    const SizedBox(height: 20),

                    // Custom Sound Selector Card
                    _buildSoundSelectorCard(),
                    const SizedBox(height: 40),

                    // Test Action Button
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton.icon(
                        onPressed: _isRinging ? null : _testAlarmSettings,
                        icon: const Icon(Icons.volume_up_rounded, color: AppColors.background),
                        label: const Text(
                          'Test Alert Settings',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.background,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 8,
                          shadowColor: AppColors.primary.withValues(alpha: 0.4),
                        ),
                      ),
                    ),
                    const SizedBox(height: 100), // Spacing for dismissal overlay
                  ],
                ),
              ),

              // Ringing Alert Overlay (Slided in or floating bottom sheet)
              if (_isRinging) _buildRingingOverlay(),
            ],
          ),
        ),
      ),
    );
  }

  // Widget: Target Battery Percentage Slider Card
  Widget _buildTargetSliderCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Alert Threshold',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$_targetLevel%',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'App will trigger an alert when battery charge reaches $_targetLevel%.',
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 20),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 6,
              activeTrackColor: AppColors.primary,
              inactiveTrackColor: AppColors.border,
              thumbColor: AppColors.primary,
              overlayColor: AppColors.primary.withValues(alpha: 0.2),
              valueIndicatorColor: AppColors.primary,
              valueIndicatorTextStyle: const TextStyle(color: AppColors.background),
            ),
            child: Slider(
              value: _targetLevel.toDouble(),
              min: 1,
              max: 100,
              divisions: 99,
              label: '$_targetLevel%',
              onChanged: (value) async {
                final newTarget = value.round();
                setState(() {
                  _targetLevel = newTarget;
                });
                await StorageService.setTargetLevel(newTarget);
                FlutterForegroundTask.sendDataToTask('syncSettings');
              },
            ),
          ),
        ],
      ),
    );
  }

  // Widget: Toggle Switches Card
  Widget _buildSettingsCard() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      child: Column(
        children: [
          // Alarm sound enabled switch
          SwitchListTile(
            value: _alarmEnabled,
            title: const Text(
              'Play Alarm Sound',
              style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary),
            ),
            subtitle: const Text('Sound reminder on target reached', style: TextStyle(color: AppColors.textSecondary)),
            activeThumbColor: AppColors.primary,
            activeTrackColor: AppColors.primary.withValues(alpha: 0.3),
            inactiveThumbColor: AppColors.textMuted,
            inactiveTrackColor: AppColors.border,
            onChanged: (value) async {
              setState(() {
                _alarmEnabled = value;
              });
              await StorageService.setAlarmEnabled(value);
              FlutterForegroundTask.sendDataToTask('syncSettings');
            },
          ),
          Divider(color: AppColors.border.withValues(alpha: 0.5), height: 1),
          // Vibration enabled switch
          SwitchListTile(
            value: _vibrationEnabled,
            title: const Text(
              'Vibrate Device',
              style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary),
            ),
            subtitle: const Text('Device physical vibrations', style: TextStyle(color: AppColors.textSecondary)),
            activeThumbColor: AppColors.secondary,
            activeTrackColor: AppColors.secondary.withValues(alpha: 0.3),
            inactiveThumbColor: AppColors.textMuted,
            inactiveTrackColor: AppColors.border,
            onChanged: (value) async {
              setState(() {
                _vibrationEnabled = value;
              });
              await StorageService.setVibrationEnabled(value);
              FlutterForegroundTask.sendDataToTask('syncSettings');
            },
          ),
          Divider(color: AppColors.border.withValues(alpha: 0.5), height: 1),
          // Alarm duration settings
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'Alarm Duration',
                      style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Auto-stop alert after',
                      style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: DropdownButton<int>(
                    value: _alarmDuration,
                    dropdownColor: AppColors.surface,
                    underline: const SizedBox(),
                    iconEnabledColor: AppColors.primary,
                    style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold),
                    items: const [
                      DropdownMenuItem(value: 15, child: Text('15 Sec')),
                      DropdownMenuItem(value: 30, child: Text('30 Sec')),
                      DropdownMenuItem(value: 60, child: Text('1 Min')),
                      DropdownMenuItem(value: 120, child: Text('2 Min')),
                      DropdownMenuItem(value: 300, child: Text('5 Min')),
                    ],
                    onChanged: (value) async {
                      if (value != null) {
                        setState(() {
                          _alarmDuration = value;
                        });
                        await StorageService.setAlarmDuration(value);
                        FlutterForegroundTask.sendDataToTask('syncSettings');
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Widget: Ringtone / Sound Selector Card
  Widget _buildSoundSelectorCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Alarm Sound',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.border.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(
                  _customAudioPath != null ? Icons.music_note : Icons.music_off_outlined,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _getFileName(_customAudioPath),
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_customAudioPath != null)
                  IconButton(
                    icon: const Icon(Icons.close, color: AppColors.alert, size: 20),
                    onPressed: _clearAudioFile,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              if (Platform.isAndroid) ...[
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _pickSystemRingtone,
                    icon: const Icon(Icons.ring_volume_rounded, size: 18),
                    label: const Text('System Sound'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.surfaceLight,
                      foregroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      elevation: 0,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickAudioFile,
                  icon: const Icon(Icons.audio_file_rounded, size: 18),
                  label: Text(Platform.isAndroid ? 'Local File' : 'Choose Audio File'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Widget: Flashing Ringing Overlay
  Widget _buildRingingOverlay() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(32),
            topRight: Radius.circular(32),
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.secondary.withValues(alpha: 0.25),
              blurRadius: 30,
              spreadRadius: 10,
            )
          ],
          border: Border.all(color: AppColors.secondary.withValues(alpha: 0.5), width: 2),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Warning Glow Icons
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                RotationTransition(
                  turns: Tween(begin: -0.15, end: 0.15).animate(_bellController),
                  child: const Icon(
                    Icons.notifications_active_rounded,
                    color: AppColors.secondary,
                    size: 56,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'THRESHOLD REACHED!',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: AppColors.secondary,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your phone charge level is $_currentLevel%. Unplug your charger now!',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 24),
            // Huge Dismiss Button
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _dismissAlarm,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.alert,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 8,
                  shadowColor: AppColors.alert.withValues(alpha: 0.4),
                ),
                child: const Text(
                  'DISMISS ALERT',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
