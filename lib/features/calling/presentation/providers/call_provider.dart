import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/network/stomp_client_manager.dart';
import '../../../../core/utils/call_notification_service.dart';
import '../../../../core/utils/logger.dart';
import '../../../../core/utils/ringtone_service.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../chat/data/models/chat_models.dart';
import '../../../chat/data/repositories/chat_repository.dart';

// Call state
enum CallStatus {
  idle,
  outgoingRinging,
  incomingRinging,
  connecting,
  connected,
  ended,
}

enum CallType { voice, video }

class CallState {
  final CallStatus status;
  final CallType callType;
  final String? remoteUserId;
  final String? remoteUserName;
  final String? channelName;
  final RtcTokenResponse? rtcToken;
  final bool isMuted;
  final bool isSpeakerOn;
  final bool isVideoEnabled;
  final String? errorMessage;

  const CallState({
    this.status = CallStatus.idle,
    this.callType = CallType.voice,
    this.remoteUserId,
    this.remoteUserName,
    this.channelName,
    this.rtcToken,
    this.isMuted = false,
    this.isSpeakerOn = false,
    this.isVideoEnabled = true,
    this.errorMessage,
  });

  CallState copyWith({
    CallStatus? status,
    CallType? callType,
    String? remoteUserId,
    String? remoteUserName,
    String? channelName,
    RtcTokenResponse? rtcToken,
    bool? isMuted,
    bool? isSpeakerOn,
    bool? isVideoEnabled,
    String? errorMessage,
  }) {
    return CallState(
      status: status ?? this.status,
      callType: callType ?? this.callType,
      remoteUserId: remoteUserId ?? this.remoteUserId,
      remoteUserName: remoteUserName ?? this.remoteUserName,
      channelName: channelName ?? this.channelName,
      rtcToken: rtcToken ?? this.rtcToken,
      isMuted: isMuted ?? this.isMuted,
      isSpeakerOn: isSpeakerOn ?? this.isSpeakerOn,
      isVideoEnabled: isVideoEnabled ?? this.isVideoEnabled,
      errorMessage: errorMessage,
    );
  }
}

class CallNotifier extends StateNotifier<CallState> {
  final ChatRepository _chatRepo;
  final StompClientManager _stompManager;
  final AuthState _authState;
  Timer? _callTimeoutTimer;

  CallNotifier(this._chatRepo, this._stompManager, this._authState)
    : super(const CallState()) {
    _subscribeToCallEvents();
  }

  /// Auto-end outgoing calls after 45 s if nobody picks up.
  void _startCallTimeout() {
    _callTimeoutTimer?.cancel();
    _callTimeoutTimer = Timer(const Duration(seconds: 45), () {
      if (state.status == CallStatus.outgoingRinging ||
          state.status == CallStatus.connecting) {
        log.i('Call timed out — no answer after 45 s');
        endCall();
      }
    });
  }

  void _cancelCallTimeout() {
    _callTimeoutTimer?.cancel();
    _callTimeoutTimer = null;
  }

  void _subscribeToCallEvents() {
    _stompManager.registerSubscription(StompDestinations.callEvent, (body) {
      try {
        final event = CallEventResponse.fromJson(body);
        _handleCallEvent(event);
      } catch (e) {
        log.e('Error parsing call event: $e');
      }
    });
  }

  void _handleCallEvent(CallEventResponse event) {
    switch (event.eventType) {
      case 'call-start':
        _cancelCallTimeout(); // clear any previous
        final callType = event.channelName?.contains('video') == true
            ? CallType.video
            : CallType.voice;

        state = CallState(
          status: CallStatus.incomingRinging,
          remoteUserId: event.fromUserId,
          remoteUserName: event.fromUserName,
          channelName: event.channelName,
          callType: callType,
        );

        // Start ringtone + notification (only when app is active; background
        // handler does this when app is killed).
        RingtoneService.startRinging();
        final payload = CallNotificationService.buildCallPayload(
          callerName: event.fromUserName,
          channelName: event.channelName ?? '',
          callType: callType == CallType.video ? 'video' : 'voice',
          senderId: event.fromUserId,
        );
        CallNotificationService.showIncomingCallNotification(
          callerName: event.fromUserName,
          isVideo: callType == CallType.video,
          callPayload: payload,
        );
        break;

      case 'call-accept':
        _cancelCallTimeout(); // receiver picked up — stop the timeout
        if (state.status != CallStatus.connected) {
          state = state.copyWith(status: CallStatus.connecting);
        }
        break;

      case 'call-reject':
      case 'call-end':
        _cancelCallTimeout();
        _stopRinging();
        state = const CallState(status: CallStatus.ended);
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) state = const CallState();
        });
        break;
    }
  }

  /// Called by [main.dart] when the user taps "Decline" on the notification.
  /// [payload] is the JSON call payload embedded in the notification.
  void handleNotificationDecline(String? payload) {
    // If the app was killed, state may be idle. Restore it so rejectCall()
    // knows who to notify.
    if (state.status == CallStatus.idle && payload != null) {
      _restoreStateFromPayload(payload);
    }
    _stopRinging();
    rejectCall();
  }

  /// Called by [main.dart] when the user taps "Accept" on the notification.
  /// [payload] is the JSON call payload embedded in the notification.
  ///
  /// When the app was killed this is the ONLY source of call data.
  /// We restore the call state from the payload, then proceed with acceptCall().
  void handleNotificationAccept(String? payload) {
    _stopRinging();
    if (state.status == CallStatus.idle && payload != null) {
      _restoreStateFromPayload(payload);
    }
    acceptCall();
  }

  /// Restore [CallState] from the JSON payload stored in the notification.
  /// This is the cold-start path: app was killed, user tapped Accept/Decline.
  void _restoreStateFromPayload(String payload) {
    final data = CallNotificationService.decodeCallPayload(payload);
    if (data == null) return;
    final callType = data['callType'] == 'video'
        ? CallType.video
        : CallType.voice;
    state = CallState(
      status: CallStatus.incomingRinging,
      remoteUserId: data['senderId'],
      remoteUserName: data['callerName'],
      channelName: data['channelName'],
      callType: callType,
    );
    log.i(
      'Call state restored from notification payload: ${data['callerName']} / ${data['channelName']}',
    );
  }

  /// Public variant for plain notification body tap (no action button).
  /// Restores state to [incomingRinging] WITHOUT calling acceptCall(), so
  /// [MainShell] shows [IncomingCallScreen] and the user can decide there.
  void restoreCallFromPayload(String? payload) {
    if (payload == null) return;
    if (state.status != CallStatus.idle) return; // already have call data
    _restoreStateFromPayload(payload);
  }

  void _stopRinging() {
    RingtoneService.stopRinging();
    CallNotificationService.cancelCallNotification();
  }

  Future<bool> _requestPermissions(CallType type) async {
    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) {
      state = state.copyWith(
        errorMessage: 'Microphone permission is required for calls',
      );
      return false;
    }

    if (type == CallType.video) {
      final camStatus = await Permission.camera.request();
      if (!camStatus.isGranted) {
        state = state.copyWith(
          errorMessage: 'Camera permission is required for video calls',
        );
        return false;
      }
    }
    return true;
  }

  String _channelPart(String id) {
    final compact = id.replaceAll('-', '');
    if (compact.length <= 12) return compact;
    return compact.substring(0, 12);
  }

  Future<void> initiateCall(
    String targetUserId,
    String targetUserName,
    CallType type,
  ) async {
    final currentUserId = _authState.user?.id;
    if (currentUserId == null) {
      state = state.copyWith(
        errorMessage: 'Please sign in again before starting a call',
      );
      return;
    }

    final granted = await _requestPermissions(type);
    if (!granted) {
      return;
    }

    final prefix = type == CallType.video ? 'v' : 'a';
    final shortA = _channelPart(currentUserId);
    final shortB = _channelPart(targetUserId);
    final ts = DateTime.now().millisecondsSinceEpoch.toString();
    final channel =
        '${prefix}_${shortA}_${shortB}_${ts.substring(ts.length - 8)}';

    // Get RTC token
    RtcTokenResponse? rtcToken;
    try {
      rtcToken = await _chatRepo.getRtcToken(channel, targetUserId);
    } catch (e) {
      log.e('Failed to get RTC token: $e');
      state = state.copyWith(
        status: CallStatus.ended,
        errorMessage: 'Failed to set up call',
      );
      return;
    }

    state = CallState(
      status: CallStatus.outgoingRinging,
      callType: type,
      remoteUserId: targetUserId,
      remoteUserName: targetUserName,
      channelName: channel,
      rtcToken: rtcToken,
    );

    // Start 45-second no-answer timeout
    _startCallTimeout();

    // Notify the other user
    _stompManager.sendWhenReady(StompDestinations.callEventSend, {
      'targetUserId': targetUserId,
      'eventType': 'call-start',
      'channelName': channel,
    });
  }

  Future<void> acceptCall() async {
    if (state.status != CallStatus.incomingRinging) {
      log.w('acceptCall() called but status=${state.status} — ignoring');
      return;
    }

    _stopRinging();

    final granted = await _requestPermissions(state.callType);
    if (!granted) {
      rejectCall();
      return;
    }

    // Use sendWhenReady so the call-accept signal is queued if STOMP hasn't
    // reconnected yet (cold-start from a killed app).
    _stompManager.sendWhenReady(StompDestinations.callEventSend, {
      'targetUserId': state.remoteUserId!,
      'eventType': 'call-accept',
      'channelName': state.channelName,
    });

    // Get RTC token
    try {
      final rtcToken = await _chatRepo.getRtcToken(
        state.channelName!,
        state.remoteUserId!,
      );
      state = state.copyWith(rtcToken: rtcToken, status: CallStatus.connecting);
    } catch (e) {
      log.e('Failed to get RTC token: $e');
      endCall();
    }
  }

  void rejectCall() {
    _cancelCallTimeout();
    _stopRinging();
    if (state.remoteUserId != null) {
      _stompManager.sendWhenReady(StompDestinations.callEventSend, {
        'targetUserId': state.remoteUserId!,
        'eventType': 'call-reject',
        'channelName': state.channelName,
      });
    }
    state = const CallState(); // straight to idle
  }

  void endCall() {
    _cancelCallTimeout();
    _stopRinging();
    if (state.remoteUserId != null) {
      _stompManager.sendWhenReady(StompDestinations.callEventSend, {
        'targetUserId': state.remoteUserId!,
        'eventType': 'call-end',
        'channelName': state.channelName,
      });
    }
    state = const CallState(status: CallStatus.ended);
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) state = const CallState();
    });
  }

  void toggleMute() {
    state = state.copyWith(isMuted: !state.isMuted);
  }

  void toggleSpeaker() {
    state = state.copyWith(isSpeakerOn: !state.isSpeakerOn);
  }

  void toggleVideo() {
    state = state.copyWith(isVideoEnabled: !state.isVideoEnabled);
  }

  void setConnected() {
    state = state.copyWith(status: CallStatus.connected);
  }
}

final callProvider = StateNotifierProvider<CallNotifier, CallState>((ref) {
  final chatRepo = ref.read(chatRepositoryProvider);
  final stompManager = ref.read(stompClientManagerProvider);
  final authState = ref.watch(authProvider);
  return CallNotifier(chatRepo, stompManager, authState);
});
