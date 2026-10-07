import 'dart:math';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/peer_device.dart';

/// The radar that makes Deadzone feel like Deadzone instead of a form.
/// Concentric rings pulse outward from center (you), discovered peers
/// render as dots at a distance proportional to signal strength, and
/// everything glows faintly orange when the mesh is active.
class PulseRadar extends StatefulWidget {
  final List<PeerDevice> peers;
  final bool isActive;
  final void Function(PeerDevice)? onPeerTap;

  const PulseRadar({
    super.key,
    required this.peers,
    required this.isActive,
    this.onPeerTap,
  });

  @override
  State<PulseRadar> createState() => _PulseRadarState();
}

class _PulseRadarState extends State<PulseRadar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.maxWidth;
          return AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              return Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    size: Size(size, size),
                    painter: _RadarPainter(
                      progress: _controller.value,
                      isActive: widget.isActive,
                    ),
                  ),
                  ..._buildPeerDots(size),
                  _buildCenterDot(),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildCenterDot() {
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.signal,
        boxShadow: [
          BoxShadow(
            color: AppColors.signal.withOpacity(0.6),
            blurRadius: 12,
            spreadRadius: 2,
          ),
        ],
      ),
    );
  }

  List<Widget> _buildPeerDots(double size) {
    final radius = size / 2;
    final widgets = <Widget>[];
    for (var i = 0; i < widget.peers.length; i++) {
      final peer = widget.peers[i];
      // Distance from center: stronger signal = closer in.
      final distanceFactor = 1.0 - (peer.signalBars / 4.0) * 0.6;
      final distance = radius * 0.3 + (radius * 0.6 * distanceFactor);
      // Spread peers evenly around the circle, offset by a stable hash
      // of their id so they don't all cluster at angle 0.
      final angle = (peer.id.hashCode % 360) * pi / 180 +
          (i * (2 * pi / max(widget.peers.length, 1)));

      final dx = radius + distance * cos(angle);
      final dy = radius + distance * sin(angle);

      widgets.add(Positioned(
        left: dx - 20,
        top: dy - 20,
        child: GestureDetector(
          onTap: widget.onPeerTap != null ? () => widget.onPeerTap!(peer) : null,
          child: _PeerBlip(peer: peer),
        ),
      ));
    }
    return widgets;
  }
}

class _PeerBlip extends StatelessWidget {
  final PeerDevice peer;
  const _PeerBlip({required this.peer});

  @override
  Widget build(BuildContext context) {
    final color = signalStrengthColor(peer.signalBars);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            boxShadow: [
              BoxShadow(color: color.withOpacity(0.5), blurRadius: 8),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          peer.displayName,
          style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _RadarPainter extends CustomPainter {
  final double progress; // 0.0 - 1.0, looping
  final bool isActive;

  _RadarPainter({required this.progress, required this.isActive});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;

    // Static faint rings for reference
    final ringPaint = Paint()
      ..color = AppColors.divider
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final frac in [0.33, 0.66, 1.0]) {
      canvas.drawCircle(center, maxRadius * frac, ringPaint);
    }

    if (!isActive) return;

    // Animated outward pulse, fading as it expands
    final pulseRadius = maxRadius * progress;
    final pulseOpacity = (1.0 - progress).clamp(0.0, 1.0);
    final pulsePaint = Paint()
      ..color = AppColors.signal.withOpacity(pulseOpacity * 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, pulseRadius, pulsePaint);
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.isActive != isActive;
}