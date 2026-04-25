import 'dart:convert';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../utils/logger.dart';

/// Notification ID for the incoming call notification.
const int kCallNotificationId = 1001;

/// Action identifiers — must match what [main.dart] checks.
const String kActionAccept = 'action_accept_call';
const String kActionDecline = 'action_decline_call';

/// Callback type for notification actions.
/// [actionId] is kActionAccept / kActionDecline / 'notification_tap'.
/// [payload]  is the JSON string embedded in the notification (contains call data).
typedef CallNotificationActionCallback = void Function(
    String actionId, String? payload);

class CallNotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static CallNotificationActionCallback? _onActionCallback;

  // ──────────────────────────────────────────────────────────────────────────
  // NOTE: The notification channel (delamate_call_v2) is created natively in
  // MainActivity.kt with the system ringtone URI.  We must NOT recreate it
  // here — flutter_local_notifications would overwrite the channel sound.
  // ──────────────────────────────────────────────────────────────────────────

  /// Full init — must be called once in [main()].
  static Future<void> initialize({
    required CallNotificationActionCallback onAction,
  }) async {
    _onActionCallback = onAction;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onResponse,
      onDidReceiveBackgroundNotificationResponse: _onBackgroundResponse,
    );
  }

  /// Lightweight init for the Firebase background isolate.
  static Future<void> initializeForBackground() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      const InitializationSettings(android: androidSettings),
    );
  }

  static void _onResponse(NotificationResponse response) {
    final actionId = response.actionId ?? 'notification_tap';
    log.i('Notification response: actionId=$actionId payload=${response.payload}');
    _onActionCallback?.call(actionId, response.payload);
  }

  /// Safety-net for the Decline button (showsUserInterface:false).
  /// Fires in a background isolate — cannot access ProviderContainer.
  /// We cancel the notification which stops the ringtone + vibration.
  /// The caller will hit the 45-second timeout on their side.
  @pragma('vm:entry-point')
  static void _onBackgroundResponse(NotificationResponse response) {
    FlutterLocalNotificationsPlugin().cancel(kCallNotificationId);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Call payload helpers
  // ─────────────────────────────────────────────────────────────────────────

  /// Build a JSON payload string that travels inside the notification.
  /// Tapping Accept/Decline delivers this payload to [_onResponse] so the
  /// main isolate can reconstruct the call state even when the app was killed.
  static String buildCallPayload({
    required String callerName,
    required String channelName,
    required String callType,
    required String senderId,
  }) {
    return jsonEncode({
      'callerName': callerName,
      'channelName': channelName,
      'callType': callType,
      'senderId': senderId,
    });
  }

  /// Decode a payload produced by [buildCallPayload].
  /// Returns null if the string is null/malformed.
  static Map<String, String>? decodeCallPayload(String? payload) {
    if (payload == null) return null;
    try {
      final map = jsonDecode(payload) as Map<String, dynamic>;
      return {
        'callerName': map['callerName'] as String? ?? 'Unknown',
        'channelName': map['channelName'] as String? ?? '',
        'callType': map['callType'] as String? ?? 'voice',
        'senderId': map['senderId'] as String? ?? '',
      };
    } catch (_) {
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Show / cancel
  // ─────────────────────────────────────────────────────────────────────────

  /// Show an incoming-call notification with Accept and Decline action buttons.
  ///
  /// [callPayload] is the JSON string from [buildCallPayload].  It is stored
  /// inside the notification so that Accept/Decline taps can restore the call
  /// state when the app was killed.
  static Future<void> showIncomingCallNotification({
    required String callerName,
    required bool isVideo,
    String? callPayload, // null when called from background isolate
  }) async {
    final androidDetails = AndroidNotificationDetails(
      'delamate_call_v2',
      'Incoming Calls',
      channelDescription: 'Incoming call alerts with ringtone',
      importance: Importance.max,
      priority: Priority.max,
      fullScreenIntent: true,
      ongoing: true,
      autoCancel: false,
      // Sound & vibration handled by native channel; don't override here.
      playSound: false,
      enableVibration: false,
      category: AndroidNotificationCategory.call,
      visibility: NotificationVisibility.public,
      actions: const [
        // ── Decline ─────────────────────────────────────────────────────────
        // showsUserInterface:false → app does NOT open when Decline is tapped.
        // _onBackgroundResponse fires instead and cancels the notification
        // (which stops the ringtone).  The caller gets a 45-second timeout.
        AndroidNotificationAction(
          kActionDecline,
          'Decline',
          showsUserInterface: false,  // ← do NOT open the app on decline
          cancelNotification: true,
        ),
        // ── Accept ──────────────────────────────────────────────────────────
        // showsUserInterface:true → app opens → callback fires in main isolate
        // → handleNotificationAccept restores call state → call connects.
        AndroidNotificationAction(
          kActionAccept,
          'Accept',
          showsUserInterface: true,
          cancelNotification: true,
        ),
      ],
    );

    await _plugin.show(
      kCallNotificationId,
      isVideo ? '📹 Incoming Video Call' : '📞 Incoming Voice Call',
      callerName,
      NotificationDetails(android: androidDetails),
      // ← The payload travels with the notification action response.
      //   It's how we restore call state when the app was killed.
      payload: callPayload,
    );
  }

  /// Dismiss the call notification (stops the OS ringtone + vibration).
  static Future<void> cancelCallNotification() async {
    await _plugin.cancel(kCallNotificationId);
  }
}
