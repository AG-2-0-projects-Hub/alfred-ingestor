import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../screens/auth_screen.dart';

class InactivityWrapper extends StatefulWidget {
  final Widget child;
  final Duration timeout;
  const InactivityWrapper({
    super.key,
    required this.child,
    this.timeout = const Duration(hours: 1),
  });

  @override
  State<InactivityWrapper> createState() => _InactivityWrapperState();
}

class _InactivityWrapperState extends State<InactivityWrapper> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _resetTimer();
    // Was pointer-events only -- a host composing a long reply using only
    // the keyboard, mouse idle, could be silently signed out mid-reply with
    // the draft lost. A global handler (not tied to any one widget's focus)
    // catches keystrokes anywhere in the subtree without consuming them.
    HardwareKeyboard.instance.addHandler(_onKeyEvent);
  }

  bool _onKeyEvent(KeyEvent event) {
    _resetTimer();
    return false;
  }

  void _resetTimer() {
    _timer?.cancel();
    _timer = Timer(widget.timeout, _logout);
  }

  Future<void> _logout() async {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    await Supabase.instance.client.auth.signOut();
    if (!mounted) return;
    messenger.showSnackBar(
      const SnackBar(content: Text('You were signed out due to inactivity.')),
    );
    navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthScreen()),
      (_) => false,
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    HardwareKeyboard.instance.removeHandler(_onKeyEvent);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _resetTimer(),
      onPointerMove: (_) => _resetTimer(),
      onPointerSignal: (_) => _resetTimer(),
      child: widget.child,
    );
  }
}
