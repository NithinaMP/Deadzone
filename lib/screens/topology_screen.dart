import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../providers/mesh_provider.dart';
import '../models/peer_device.dart';

/// A live view of THIS device's local mesh neighborhood — not a
/// full network-wide map. No single device can know the WHOLE mesh
/// topology without a much heavier gossip protocol where every device
/// broadcasts its own neighbor list (out of scope for this project).
/// What this honestly shows: who I'm directly connected to right now,
/// who I know about but can't currently reach directly, and — the real
/// payoff — edges that flash the instant actual traffic flows across
/// them, driven by MeshService.relayActivity rather than faked.
class TopologyScreen extends StatefulWidget {
  const TopologyScreen({super.key});

  @override
  State<TopologyScreen> createState() => _TopologyScreenState();
}

class _TopologyScreenState extends State<TopologyScreen> {
  final Set<String> _activePeerIds = {};
  StreamSubscription<List<String>>? _sub;

  @override
  void initState() {
    super.initState();
    final provider = context.read<MeshProvider>();
    _sub = provider.relayActivity.listen((targetIds) {
      if (!mounted) return;
      setState(() => _activePeerIds.addAll(targetIds));
      Future.delayed(const Duration(milliseconds: 700), () {
        if (!mounted) return;
        setState(() => _activePeerIds.removeAll(targetIds));
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MeshProvider>();
    final contacts = provider.getAllContacts();

    return Scaffold(
      appBar: AppBar(title: const Text('Mesh Topology')),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Text(
              "This device's local view only — direct connections and "
                  "previously-met devices. No device can see the full "
                  "network without everyone sharing neighbor lists, which "
                  "this project scopes out.",
              style: TextStyle(color: AppColors.textMuted, fontSize: 11),
            ),
          ),
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 1,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: CustomPaint(
                    painter: _TopologyPainter(
                      contacts: contacts,
                      activePeerIds: _activePeerIds,
                    ),
                  ),
                ),
              ),
            ),
          ),
          _buildLegend(),
        ],
      ),
    );
  }

  Widget _buildLegend() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Wrap(
        spacing: 16,
        runSpacing: 8,
        children: [
          _legendDot(AppColors.signal, 'Traffic flowing now'),
          _legendDot(AppColors.secure, 'Connected, idle'),
          _legendDot(AppColors.textMuted, 'Known, out of range'),
        ],
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
      ],
    );
  }
}

class _TopologyPainter extends CustomPainter {
  final List<PeerDevice> contacts;
  final Set<String> activePeerIds;

  _TopologyPainter({required this.contacts, required this.activePeerIds});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 30;
    final count = max(contacts.length, 1);

    for (var i = 0; i < contacts.length; i++) {
      final peer = contacts[i];
      final angle = (2 * pi * i) / count;
      final pos = Offset(
        center.dx + radius * cos(angle),
        center.dy + radius * sin(angle),
      );
      final isOnline = peer.status == PeerStatus.connected;
      final isActive = activePeerIds.contains(peer.id);

      final edgePaint = Paint()
        ..color = isActive
            ? AppColors.signal
            : (isOnline ? AppColors.secure.withOpacity(0.5) : AppColors.divider)
        ..strokeWidth = isActive ? 3 : (isOnline ? 1.5 : 1);

      if (isOnline || isActive) {
        canvas.drawLine(center, pos, edgePaint);
      } else {
        _drawDashedLine(canvas, center, pos, edgePaint);
      }
    }

    canvas.drawCircle(center, 14, Paint()..color = AppColors.signal);
    _drawLabel(canvas, 'You', center + const Offset(-10, 18));

    for (var i = 0; i < contacts.length; i++) {
      final peer = contacts[i];
      final angle = (2 * pi * i) / count;
      final pos = Offset(
        center.dx + radius * cos(angle),
        center.dy + radius * sin(angle),
      );
      final isOnline = peer.status == PeerStatus.connected;
      final isActive = activePeerIds.contains(peer.id);

      final nodeColor = isActive
          ? AppColors.signal
          : (isOnline ? AppColors.secure : AppColors.textMuted);
      canvas.drawCircle(pos, isActive ? 10 : 7, Paint()..color = nodeColor);
      if (isActive) {
        canvas.drawCircle(
          pos,
          16,
          Paint()
            ..color = AppColors.signal.withOpacity(0.3)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }

      _drawLabel(canvas, peer.displayName, pos + const Offset(-20, 12));
    }
  }

  void _drawLabel(Canvas canvas, String text, Offset position) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(color: AppColors.textPrimary, fontSize: 10),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: 60);
    painter.paint(canvas, position);
  }

  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint) {
    const dashWidth = 5.0;
    const dashSpace = 4.0;
    final totalDistance = (end - start).distance;
    if (totalDistance == 0) return;
    final dashCount = (totalDistance / (dashWidth + dashSpace)).floor();
    final direction = (end - start) / totalDistance;
    var current = start;
    for (var i = 0; i < dashCount; i++) {
      final dashEnd = current + direction * dashWidth;
      canvas.drawLine(current, dashEnd, paint);
      current = dashEnd + direction * dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant _TopologyPainter oldDelegate) =>
      oldDelegate.activePeerIds.length != activePeerIds.length ||
          !oldDelegate.activePeerIds.containsAll(activePeerIds) ||
          oldDelegate.contacts.length != contacts.length;
}