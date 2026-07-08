import 'package:flutter/services.dart';

class MyRingtonePlayer {
  static const MethodChannel _channel = MethodChannel('my_ringtone_player');

  static Future<void> play(String uri) async {
    try {
      await _channel.invokeMethod('play', {'uri': uri});
    } catch (e) {
      print('Error in MyRingtonePlayer.play: $e');
    }
  }

  static Future<void> stop() async {
    try {
      await _channel.invokeMethod('stop');
    } catch (e) {
      print('Error in MyRingtonePlayer.stop: $e');
    }
  }
}
