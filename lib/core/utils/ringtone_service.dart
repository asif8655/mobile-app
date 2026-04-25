import 'package:flutter/services.dart';

/// Plays / stops the device's default ringtone + vibration pattern
/// via a native Android MethodChannel.
class RingtoneService {
  static const _channel = MethodChannel('com.delamate.chat/ringtone');

  static Future<void> startRinging() async {
    try {
      await _channel.invokeMethod('startRinging');
    } catch (e) {
      // ignore — ringtone is nice-to-have, not critical
    }
  }

  static Future<void> stopRinging() async {
    try {
      await _channel.invokeMethod('stopRinging');
    } catch (e) {
      // ignore
    }
  }
}
