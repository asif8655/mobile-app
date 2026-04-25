import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/ringtone_service.dart';
import '../providers/call_provider.dart';

class IncomingCallScreen extends ConsumerStatefulWidget {
  const IncomingCallScreen({super.key});

  @override
  ConsumerState<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends ConsumerState<IncomingCallScreen>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final AnimationController _rippleController;
  bool _isDismissing = false; // guard against duplicate pops

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _rippleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _rippleController.dispose();
    super.dispose();
  }

  // ── Single exit point for this screen ──────────────────────────────────
  void _dismiss() {
    if (_isDismissing || !mounted) return;
    _isDismissing = true;
    RingtoneService.stopRinging();
    Navigator.of(context).pop();
  }

  void _decline() {
    ref.read(callProvider.notifier).rejectCall();
    // rejectCall() sets state → idle, which the ref.listen below catches → _dismiss()
  }

  void _accept() {
    ref.read(callProvider.notifier).acceptCall();
    // acceptCall() sets state → connecting, which MainShell catches and pushes
    // CallScreen.  This screen is then popped by MainShell's pop() before the push.
    // We still call _dismiss() here so the screen exits even if MainShell misses it.
    _dismiss();
  }

  @override
  Widget build(BuildContext context) {
    final callState = ref.watch(callProvider);
    final isVideo = callState.callType == CallType.video;

    // ── Single listener: exit when state leaves incomingRinging ───────────
    ref.listen<CallState>(callProvider, (prev, next) {
      // Dismiss when:
      //  • caller hung up (idle/ended)
      //  • call was accepted and is now connecting/connected (MainShell pushes CallScreen)
      if (next.status != CallStatus.incomingRinging) {
        _dismiss();
      }
    });

    return Scaffold(
      backgroundColor: AppTheme.darkBg,
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 2),

            // Incoming label
            Text(
              isVideo ? 'Incoming Video Call' : 'Incoming Voice Call',
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 16,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 40),

            // Ripple + Pulsing avatar
            _RippleAvatar(
              pulseController: _pulseController,
              rippleController: _rippleController,
              name: callState.remoteUserName ?? '?',
            ),
            const SizedBox(height: 24),

            // Caller name
            Text(
              callState.remoteUserName ?? 'Unknown Caller',
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isVideo
                  ? 'wants to video call you'
                  : 'is calling you via Delamate',
              style: const TextStyle(fontSize: 14, color: AppTheme.textHint),
            ),

            const Spacer(flex: 3),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _CallActionButton(
                    icon: Icons.call_end_rounded,
                    label: 'Decline',
                    color: AppTheme.error,
                    onPressed: _decline, // ← no Navigator.pop() here
                  ),
                  _CallActionButton(
                    icon: isVideo ? Icons.videocam_rounded : Icons.call_rounded,
                    label: 'Accept',
                    color: AppTheme.success,
                    onPressed: _accept, // ← no Navigator.pop() here
                  ),
                ],
              ),
            ),

            const SizedBox(height: 56),
          ],
        ),
      ),
    );
  }
}

// ─── Ripple Avatar ───
class _RippleAvatar extends StatelessWidget {
  final AnimationController pulseController;
  final AnimationController rippleController;
  final String name;

  const _RippleAvatar({
    required this.pulseController,
    required this.rippleController,
    required this.name,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 180,
      height: 180,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: rippleController,
            builder: (context, child) {
              final value = rippleController.value;
              return Opacity(
                opacity: (1.0 - value).clamp(0.0, 1.0),
                child: Transform.scale(
                  scale: 0.85 + value * 0.5,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppTheme.primary.withValues(alpha: 0.4),
                        width: 2,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          AnimatedBuilder(
            animation: rippleController,
            builder: (context, child) {
              final value = (rippleController.value + 0.4) % 1.0;
              return Opacity(
                opacity: (1.0 - value).clamp(0.0, 1.0),
                child: Transform.scale(
                  scale: 0.7 + value * 0.5,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppTheme.primary.withValues(alpha: 0.25),
                        width: 2,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          AnimatedBuilder(
            animation: pulseController,
            builder: (context, child) {
              return Transform.scale(
                scale: 0.96 + pulseController.value * 0.04,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        AppTheme.primary.withValues(alpha: 0.35),
                        AppTheme.accent.withValues(alpha: 0.35),
                      ],
                    ),
                    border: Border.all(
                      color: AppTheme.primary.withValues(alpha: 0.6),
                      width: 2,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: const TextStyle(
                        fontSize: 52,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.primary,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ─── Call Action Button ───
class _CallActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onPressed;

  const _CallActionButton({
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
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.45),
                blurRadius: 20,
                spreadRadius: 2,
              ),
            ],
          ),
          child: IconButton(
            icon: Icon(icon, color: Colors.white, size: 34),
            onPressed: onPressed,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          label,
          style: const TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
