import 'package:flutter/material.dart';
import '../services/pin_service.dart';
import '../screens/lock_screen.dart';

/// Sits above the whole app. Shows the lock screen when the app opens and
/// when you come back after being away for more than 30 seconds.
class AppLock extends StatefulWidget {
  final PinService pinService;
  final Widget child;

  const AppLock({super.key, required this.pinService, required this.child});

  @override
  State<AppLock> createState() => _AppLockState();
}

class _AppLockState extends State<AppLock> with WidgetsBindingObserver {
  static const Duration _grace = Duration(seconds: 30);

  bool _locked = false;
  DateTime? _pausedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _locked = widget.pinService.hasPin;
    widget.pinService.addListener(_onPinChanged);
  }

  @override
  void dispose() {
    widget.pinService.removeListener(_onPinChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onPinChanged() {
    // If the PIN was just turned off, make sure we're not stuck locked.
    if (!widget.pinService.hasPin && _locked) {
      setState(() => _locked = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _pausedAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final left = _pausedAt;
      _pausedAt = null;
      if (widget.pinService.hasPin &&
          left != null &&
          DateTime.now().difference(left) > _grace) {
        setState(() => _locked = true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (_locked)
          Positioned.fill(
            child: LockScreen(
              pinService: widget.pinService,
              onUnlocked: () => setState(() => _locked = false),
            ),
          ),
      ],
    );
  }
}