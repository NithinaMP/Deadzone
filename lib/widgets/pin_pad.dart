import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';

/// The 4-dot display plus a number pad. Calls [onComplete] with the 4
/// digits, then clears itself so it's ready for the next step.
class PinPad extends StatefulWidget {
  final String title;
  final String? subtitle;
  final String? errorText;
  final bool disabled;
  final ValueChanged<String> onComplete;

  const PinPad({
    super.key,
    required this.title,
    this.subtitle,
    this.errorText,
    this.disabled = false,
    required this.onComplete,
  });

  @override
  State<PinPad> createState() => _PinPadState();
}

class _PinPadState extends State<PinPad> {
  static const int _length = 4;
  String _entered = '';

  void _tapDigit(String digit) {
    if (widget.disabled || _entered.length >= _length) return;
    HapticFeedback.lightImpact();
    setState(() => _entered += digit);
    if (_entered.length == _length) {
      final pin = _entered;
      // Show the 4th dot for a moment, then clear and report.
      Future.delayed(const Duration(milliseconds: 120), () {
        if (!mounted) return;
        setState(() => _entered = '');
        widget.onComplete(pin);
      });
    }
  }

  void _backspace() {
    if (widget.disabled || _entered.isEmpty) return;
    setState(() => _entered = _entered.substring(0, _entered.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        if (widget.subtitle != null) ...[
          const SizedBox(height: 6),
          Text(
            widget.subtitle!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
        ],
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(_length, (i) {
            final filled = i < _entered.length;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 8),
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: filled ? AppColors.signal : Colors.transparent,
                border: Border.all(
                  color: filled ? AppColors.signal : AppColors.textMuted,
                  width: 2,
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 20,
          child: Text(
            widget.errorText ?? '',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.danger, fontSize: 12),
          ),
        ),
        const SizedBox(height: 12),
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Row(
            mainAxisSize: MainAxisSize.min,
            children: row.map(_key).toList(),
          ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: 88, height: 88),
            _key('0'),
            _circleButton(
              onTap: _backspace,
              child: const Icon(Icons.backspace_outlined,
                  color: AppColors.textMuted),
            ),
          ],
        ),
      ],
    );
  }

  Widget _key(String digit) {
    return _circleButton(
      onTap: () => _tapDigit(digit),
      child: Text(
        digit,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 26,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _circleButton({required Widget child, required VoidCallback onTap}) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Material(
        color: AppColors.surfaceRaised,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(width: 72, height: 72, child: Center(child: child)),
        ),
      ),
    );
  }
}