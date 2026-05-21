import 'dart:io';
import 'package:flutter/foundation.dart';

// API and App Constants
class ApiConstants {
  ApiConstants._();

  static String get baseUrl {
    if (kDebugMode) {
      if (!kIsWeb && Platform.isAndroid) {
        return 'http://10.0.2.2:5000';
      }
      return 'http://localhost:5000';
    }
    return 'https://delamate.me';
  }

  static String get apiBaseUrl => '$baseUrl/api';

  static String get wsNativeUrl {
    if (kDebugMode) {
      if (!kIsWeb && Platform.isAndroid) {
        return 'ws://10.0.2.2:5000/ws-native';
      }
      return 'ws://localhost:5000/ws-native';
    }
    return 'wss://delamate.me/ws-native';
  }

  // Auth
  static const String login = '/auth/login';
  static const String register = '/auth/register';
  static const String verifyEmail = '/auth/verify';

  // Users
  static const String users = '/users';

  // Messages
  static const String messages = '/messages';

  // RTC (Agora)
  static const String rtcToken = '/rtc/token';
  static const String rtcAppId = '/rtc/app-id';
}

class AppConstants {
  AppConstants._();

  static const String appName = 'Delamate';
  static const String tokenKey = 'jwt_token';
  static const String userKey = 'user_data';
}

// STOMP Destinations
class StompDestinations {
  StompDestinations._();

  // Subscribe
  static const String userMessages = '/user/queue/messages';
  static const String videoSignal = '/user/queue/video-signal';
  static const String callEvent = '/user/queue/call-event';
  static const String streamEvents = '/topic/stream-events';

  // Publish
  static const String chatSend = '/app/chat.send';
  static const String videoSignalSend = '/app/video.signal';
  static const String callEventSend = '/app/call.event';
}
