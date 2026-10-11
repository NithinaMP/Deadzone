import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../services/pin_service.dart';
import '../widgets/pin_pad.dart';

enum PinFlowMode { enable, disable, change }

enum _Step { verifyCurrent, enterNew, confirmNew }

class PinFlowScreen extends StatefulWidget {
  final PinFlowMode mode;
  const PinFlowScreen({super.key, required this.mode});

  @override
  State<PinFlowScreen> createState() => _PinFlowScreenState();
}

class _PinFlowScreenState extends State<PinFlowScreen> {
  late _Step _step;
  String? _firstEntry;
  String? _error;

  @override
  void initState() {
    super.initState();
    _step = widget.mode == PinFlowMode.enable
        ? _Step.enterNew
        : _Step.verifyCurrent;
  }

  Future<void> _onComplete(String pin) async {
    final pins = context.read<PinService>();

    switch (_step) {
      case _Step.verifyCurrent:
        final ok = await pins.verify(pin);
        if (!mounted) return;
        if (!ok) {
          final locked = pins.lockRemaining != null;
          setState(() => _error = locked
              ? 'Too many tries. Wait a little and try again.'
              : 'Wrong PIN, try again');
          return;
        }
        if (widget.mode == PinFlowMode.disable) {
          await pins.clearPin();
          _finish('PIN lock is off');
        } else {
          setState(() {
            _step = _Step.enterNew;
            _error = null;
          });
        }
        break;

      case _Step.enterNew:
        setState(() {
          _firstEntry = pin;
          _step = _Step.confirmNew;
          _error = null;
        });
        break;

      case _Step.confirmNew:
        if (pin == _firstEntry) {
          await pins.setPin(pin);
          _finish(widget.mode == PinFlowMode.enable
              ? 'PIN lock is on 🔒'
              : 'PIN changed 🔒');
        } else {
          setState(() {
            _firstEntry = null;
            _step = _Step.enterNew;
            _error = "PINs didn't match, start again";
          });
        }
        break;
    }
  }

  void _finish(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    Navigator.pop(context);
  }

  String get _appBarTitle {
    switch (widget.mode) {
      case PinFlowMode.enable:
        return 'Turn on PIN lock';
      case PinFlowMode.disable:
        return 'Turn off PIN lock';
      case PinFlowMode.change:
        return 'Change PIN';
    }
  }

  String get _title {
    switch (_step) {
      case _Step.verifyCurrent:
        return 'Enter your current PIN';
      case _Step.enterNew:
        return widget.mode == PinFlowMode.enable
            ? 'Choose a PIN'
            : 'Choose a new PIN';
      case _Step.confirmNew:
        return 'Type it once more';
    }
  }

  String get _subtitle {
    switch (_step) {
      case _Step.verifyCurrent:
        return 'Just to make sure it\'s you';
      case _Step.enterNew:
        return '4 digits you\'ll remember';
      case _Step.confirmNew:
        return 'Just to be sure';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_appBarTitle)),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PinPad(
                title: _title,
                subtitle: _subtitle,
                errorText: _error,
                onComplete: _onComplete,
              ),
              if (_step == _Step.enterNew && widget.mode != PinFlowMode.disable)
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: Text(
                    'If you forget it, the only way back in is clearing\n'
                        'Deadzone\'s data (your chats will be erased).',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}