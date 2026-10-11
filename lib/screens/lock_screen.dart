import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/pin_service.dart';
import '../widgets/pin_pad.dart';

/// The screen that covers the app until the right PIN is entered.
class LockScreen extends StatefulWidget {
  final PinService pinService;
  final VoidCallback onUnlocked;

  const LockScreen({
    super.key,
    required this.pinService,
    required this.onUnlocked,
  });

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  String? _error;
  int _lockSeconds = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _syncLock();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// If we're in a "too many tries" wait, run a countdown.
  void _syncLock() {
    _timer?.cancel();
    final remaining = widget.pinService.lockRemaining;
    if (remaining == null) {
      _lockSeconds = 0;
      return;
    }
    _lockSeconds = remaining.inSeconds + 1;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      final r = widget.pinService.lockRemaining;
      setState(() {
        if (r == null) {
          _lockSeconds = 0;
          _error = null;
          t.cancel();
        } else {
          _lockSeconds = r.inSeconds + 1;
        }
      });
    });
  }

  Future<void> _check(String pin) async {
    final ok = await widget.pinService.verify(pin);
    if (!mounted) return;
    if (ok) {
      widget.onUnlocked();
      return;
    }
    setState(() {
      _error = 'Wrong PIN, try again';
      _syncLock();
    });
  }

  @override
  Widget build(BuildContext context) {
    final waiting = _lockSeconds > 0;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.sensors, size: 40, color: AppColors.signal),
                const SizedBox(height: 16),
                PinPad(
                  title: 'Welcome back 👋',
                  subtitle: 'Enter your PIN',
                  errorText: waiting
                      ? 'Too many tries. Try again in ${_lockSeconds}s'
                      : _error,
                  disabled: waiting,
                  onComplete: _check,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Forgot it? Clearing Deadzone\'s data in Android settings\n'
                      'resets the app, but your chats will be erased.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}