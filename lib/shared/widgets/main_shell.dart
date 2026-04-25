import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:delamate/core/theme/app_theme.dart';
import 'package:delamate/features/calling/presentation/providers/call_provider.dart';
import 'package:delamate/features/calling/presentation/screens/call_screen.dart';
import 'package:delamate/features/calling/presentation/screens/incoming_call_screen.dart';

class MainShell extends ConsumerStatefulWidget {
  final int currentIndex;
  final Widget child;
  final ValueChanged<int> onTabChanged;

  const MainShell({
    super.key,
    required this.currentIndex,
    required this.child,
    required this.onTabChanged,
  });

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  /// Prevents pushing IncomingCallScreen twice if the state fires rapidly.
  bool _incomingShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final callState = ref.read(callProvider);

      // Cold-start: app opened from a notification — callProvider already has
      // state set (by handleNotificationAccept / restoreCallFromPayload before runApp).
      if (callState.status == CallStatus.incomingRinging && !_incomingShown) {
        // Either plain tap or Accept that hasn't completed getRtcToken yet.
        _pushIncomingCall();
      } else if ((callState.status == CallStatus.connecting ||
                  callState.status == CallStatus.connected) &&
                 !_incomingShown) {
        // Accept from notification AND getRtcToken already finished before
        // the first frame — go straight to CallScreen, skip IncomingCallScreen.
        _pushCallScreen();
      }
    });
  }


  void _pushIncomingCall() {
    if (_incomingShown || !mounted) return;
    _incomingShown = true;
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const IncomingCallScreen()))
        .then((_) => _incomingShown = false);
  }

  void _pushCallScreen() {
    if (!mounted) return;
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const CallScreen()));
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<CallState>(callProvider, (prev, next) {
      if (!context.mounted) return;

      // ── Incoming call ────────────────────────────────────────────────────
      if (next.status == CallStatus.incomingRinging &&
          prev?.status != CallStatus.incomingRinging) {
        _pushIncomingCall();
      }

      // ── Receiver accepted → IncomingCallScreen pops itself via its own
      //    ref.listen. MainShell pushes CallScreen on top of whatever is there.
      if (next.status == CallStatus.connecting &&
          prev?.status == CallStatus.incomingRinging) {
        // Give IncomingCallScreen one frame to dismiss itself, then push CallScreen.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) _pushCallScreen();
        });
      }

      // ── Outgoing call started from within the shell (e.g. Calls tab) ────
      // ChatDetailScreen handles its own outgoing call push.
      if (next.status == CallStatus.outgoingRinging &&
          prev?.status != CallStatus.outgoingRinging) {
        _pushCallScreen();
      }

      // ── NOTE: We do NOT popUntil here.  Each screen (IncomingCallScreen,
      //    CallScreen) listens to the provider and pops itself when the call
      //    ends.  Popping from MainShell would race with those pops and leave
      //    the app in a blank/stuck state.
    });

    return Scaffold(
      body: widget.child,
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(
            top: BorderSide(color: AppTheme.darkDivider, width: 0.5),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: widget.currentIndex,
          onTap: widget.onTabChanged,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.chat_bubble_rounded),
              activeIcon: Icon(Icons.chat_bubble_rounded),
              label: 'Chats',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.call_rounded),
              activeIcon: Icon(Icons.call_rounded),
              label: 'Calls',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_rounded),
              activeIcon: Icon(Icons.person_rounded),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}
