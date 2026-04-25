import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cryptography/cryptography.dart';
import 'package:cryptography_flutter/cryptography_flutter.dart';
import 'core/utils/call_notification_service.dart';
import 'features/calling/presentation/providers/call_provider.dart';
import 'app.dart';

/// Global ProviderContainer — notification-action callbacks (in the main
/// Dart isolate) use this to reach the call provider.
late ProviderContainer _container;

// ─────────────────────────────────────────────────────────────────────────────
// Firebase background handler (separate isolate, app killed or backgrounded)
// ─────────────────────────────────────────────────────────────────────────────
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // REQUIRED: must be called before using any Flutter plugin from a background
  // isolate, otherwise plugin method channels fail silently.
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  final data = message.data;
  if (data['type'] != 'call') return;

  final callerName  = data['callerName']  ?? 'Unknown';
  final channelName = data['channelName'] ?? '';
  final callType    = data['callType']    ?? 'voice';
  final senderId    = data['senderId']    ?? '';

  // Build the JSON payload that will travel inside the notification and be
  // delivered back to [_onResponse] when the user taps Accept.
  final payload = CallNotificationService.buildCallPayload(
    callerName: callerName,
    channelName: channelName,
    callType: callType,
    senderId: senderId,
  );

  await CallNotificationService.initializeForBackground();
  await CallNotificationService.showIncomingCallNotification(
    callerName: callerName,
    isVideo: callType == 'video',
    callPayload: payload,
  );
}


// ─────────────────────────────────────────────────────────────────────────────
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Cryptography.instance = FlutterCryptography.defaultInstance;

  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // ────────────────────────────────────────────────────────────────────────
  // CRITICAL: Create the ProviderContainer BEFORE initialising the
  // notification plugin.
  //
  // When the app is opened by tapping a notification action button,
  // flutter_local_notifications fires onDidReceiveNotificationResponse
  // DURING plugin.initialize() — not after.  If _container is assigned
  // after initialize() (as it was before), the callback catches a
  // LateInitializationError, silently does nothing, and the call never
  // connects.
  // ────────────────────────────────────────────────────────────────────────
  _container = ProviderContainer();

  await CallNotificationService.initialize(
    onAction: (actionId, payload) {
      // By the time this fires, _container is always initialised (see above).
      final notifier = _container.read(callProvider.notifier);

      if (actionId == kActionAccept) {
        // Restore call state from payload (when app was killed, provider starts
        // idle).  acceptCall() uses sendWhenReady() so call-accept is queued
        // and sent as soon as STOMP reconnects.
        notifier.handleNotificationAccept(payload);
      } else if (actionId == kActionDecline) {
        // Decline is now showsUserInterface:false so the app does NOT open.
        // This callback should not fire for Decline; the background handler
        // (_onBackgroundResponse) cancels the notification instead.
        // Kept here as a safety-net if the OS routes it here anyway.
        notifier.handleNotificationDecline(payload);
      } else {
        // Plain notification body tap — restore state so MainShell's
        // initState postFrameCallback finds incomingRinging and shows
        // IncomingCallScreen automatically.
        notifier.restoreCallFromPayload(payload);
      }
    },
  );

  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF1D1F33),
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  runApp(
    UncontrolledProviderScope(
      container: _container,
      child: const DelamateApp(),
    ),
  );
}
