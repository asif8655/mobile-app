import 'dart:async';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/logger.dart';
import '../providers/call_provider.dart';

class CallScreen extends ConsumerStatefulWidget {
  const CallScreen({super.key});

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen> {
  RtcEngine? _engine;
  bool _remoteUserJoined = false;
  int? _remoteUid;
  Timer? _callTimer;
  int _callDuration = 0;
  bool _isDismissing = false; // guard against duplicate pops

  @override
  void initState() {
    super.initState();
    _initAgora();
  }

  Future<void> _initAgora() async {
    final callState = ref.read(callProvider);
    final rtcToken = callState.rtcToken;

    if (rtcToken == null) {
      log.e('No RTC token available');
      return;
    }

    _engine = createAgoraRtcEngine();
    await _engine!.initialize(RtcEngineContext(appId: rtcToken.appId));

    _engine!.registerEventHandler(
      RtcEngineEventHandler(
        onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
          log.i('Joined Agora channel: ${connection.channelId}');
        },
        onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) {
          log.i('Remote user joined: $remoteUid');
          if (mounted) {
            setState(() {
              _remoteUserJoined = true;
              _remoteUid = remoteUid;
            });
          }
          ref.read(callProvider.notifier).setConnected();
          if (_callTimer == null) {
            _startCallTimer();
          }
        },
        onUserOffline: (RtcConnection connection, int remoteUid, UserOfflineReasonType reason) {
          log.i('Remote user offline: $remoteUid');
          setState(() {
            _remoteUserJoined = false;
            _remoteUid = null;
          });
          ref.read(callProvider.notifier).endCall();
        },
        onError: (ErrorCodeType err, String msg) {
          log.e('Agora error: $err — $msg');
        },
      ),
    );

    if (callState.callType == CallType.video) {
      await _engine!.enableVideo();
      await _engine!.startPreview();
    }

    await _engine!.joinChannel(
      token: rtcToken.token,
      channelId: rtcToken.channelName,
      uid: int.parse(rtcToken.uid),
      options: ChannelMediaOptions(
        channelProfile: ChannelProfileType.channelProfileCommunication,
        clientRoleType: ClientRoleType.clientRoleBroadcaster,
        autoSubscribeAudio: true,
        autoSubscribeVideo: callState.callType == CallType.video,
      ),
    );
  }

  void _startCallTimer() {
    _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _callDuration++);
    });
  }

  String _formatDuration(int seconds) {
    final mins = (seconds ~/ 60).toString().padLeft(2, '0');
    final secs = (seconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  Future<void> _endCall() async {
    _callTimer?.cancel();
    await _engine?.leaveChannel();
    await _engine?.release();
    ref.read(callProvider.notifier).endCall();
  }

  @override
  void dispose() {
    _callTimer?.cancel();
    _engine?.leaveChannel();
    _engine?.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final callState = ref.watch(callProvider);
    final isVideo = callState.callType == CallType.video;

    // Pop this screen when the call ends or is rejected.
    // Use a simple pop() — not popUntil — so we go back exactly one screen
    // (either the chat screen or the calls tab), regardless of nav stack depth.
    ref.listen<CallState>(callProvider, (prev, next) {
      if ((next.status == CallStatus.idle || next.status == CallStatus.ended) &&
          mounted &&
          !_isDismissing) {
        _isDismissing = true;
        Navigator.of(context).pop();
      }
    });

    return Scaffold(
      backgroundColor: AppTheme.darkBg,
      body: Stack(
        children: [
          // Video views
          if (isVideo) ...[
            // Remote video (full screen)
            if (_remoteUserJoined && _remoteUid != null)
              AgoraVideoView(
                controller: VideoViewController.remote(
                  rtcEngine: _engine!,
                  canvas: VideoCanvas(uid: _remoteUid!),
                  connection: RtcConnection(channelId: callState.channelName),
                ),
              )
            else
              _buildAudioOnlyUI(callState),

            // Local video (pip)
            if (_engine != null)
              Positioned(
                top: MediaQuery.of(context).padding.top + 16,
                right: 16,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 120,
                    height: 160,
                    child: AgoraVideoView(
                      controller: VideoViewController(
                        rtcEngine: _engine!,
                        canvas: const VideoCanvas(uid: 0),
                      ),
                    ),
                  ),
                ),
              ),
          ] else
            _buildAudioOnlyUI(callState),

          // Controls
          Positioned(
            left: 0,
            right: 0,
            bottom: MediaQuery.of(context).viewPadding.bottom + 32,
            child: _buildControls(callState),
          ),
        ],
      ),
    );
  }

  Widget _buildAudioOnlyUI(CallState callState) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 55,
            backgroundColor: AppTheme.primary.withValues(alpha: 0.2),
            child: Text(
              callState.remoteUserName?.isNotEmpty == true
                  ? callState.remoteUserName![0].toUpperCase()
                  : '?',
              style: const TextStyle(
                fontSize: 44,
                fontWeight: FontWeight.w700,
                color: AppTheme.primary,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            callState.remoteUserName ?? 'Unknown',
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            callState.status == CallStatus.connected
                ? _formatDuration(_callDuration)
                : callState.status == CallStatus.connecting
                    ? 'Connecting...'
                    : 'Ringing...',
            style: const TextStyle(
              fontSize: 16,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls(CallState callState) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // Mute
        _CallButton(
          icon: callState.isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
          label: callState.isMuted ? 'Unmute' : 'Mute',
          color: callState.isMuted ? AppTheme.error : AppTheme.darkCard,
          onPressed: () {
            ref.read(callProvider.notifier).toggleMute();
            _engine?.muteLocalAudioStream(!callState.isMuted);
          },
        ),

        // Speaker
        _CallButton(
          icon: callState.isSpeakerOn ? Icons.volume_up_rounded : Icons.volume_down_rounded,
          label: 'Speaker',
          color: callState.isSpeakerOn ? AppTheme.primary : AppTheme.darkCard,
          onPressed: () {
            ref.read(callProvider.notifier).toggleSpeaker();
            _engine?.setEnableSpeakerphone(!callState.isSpeakerOn);
          },
        ),

        // Video toggle (only for video calls)
        if (callState.callType == CallType.video)
          _CallButton(
            icon: callState.isVideoEnabled ? Icons.videocam_rounded : Icons.videocam_off_rounded,
            label: 'Video',
            color: callState.isVideoEnabled ? AppTheme.darkCard : AppTheme.error,
            onPressed: () {
              ref.read(callProvider.notifier).toggleVideo();
              _engine?.muteLocalVideoStream(callState.isVideoEnabled);
            },
          ),

        // End call
        _CallButton(
          icon: Icons.call_end_rounded,
          label: 'End',
          color: AppTheme.error,
          onPressed: _endCall,
        ),
      ],
    );
  }
}

class _CallButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onPressed;

  const _CallButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: IconButton(
            icon: Icon(icon, color: Colors.white, size: 26),
            onPressed: onPressed,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
        ),
      ],
    );
  }
}
