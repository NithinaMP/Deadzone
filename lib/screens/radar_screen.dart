import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../providers/mesh_provider.dart';
import '../models/peer_device.dart';
import '../widgets/pulse_radar.dart';
import 'chat_screen.dart';
import 'broadcast_screen.dart';
import 'metrics_screen.dart';

class RadarScreen extends StatelessWidget {
  const RadarScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MeshProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('DEADZONE'),
        actions: [
          IconButton(
            icon: const Icon(Icons.bar_chart, color: AppColors.textMuted),
            tooltip: 'Routing comparison',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MetricsScreen()),
            ),
          ),
          IconButton(
            icon: Icon(
              provider.isMeshActive ? Icons.wifi_tethering : Icons.wifi_off,
              color: provider.isMeshActive ? AppColors.signal : AppColors.textMuted,
            ),
            onPressed: () {
              provider.isMeshActive ? provider.stopMesh() : provider.startMesh();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  provider.isMeshActive
                      ? '${provider.peers.where((p) => p.status == PeerStatus.connected).length} connected nearby'
                      : 'Mesh offline — tap the signal icon to go live',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                ),
              ],
            ),
          ),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: PulseRadar(
                  peers: provider.peers,
                  isActive: provider.isMeshActive,
                  onPeerTap: (peer) => _openChat(context, peer),
                ),
              ),
            ),
          ),
          _buildPeerList(context, provider),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.danger,
        icon: const Icon(Icons.campaign, color: Colors.white),
        label: const Text('SOS BROADCAST', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const BroadcastScreen()),
        ),
      ),
    );
  }

  Widget _buildPeerList(BuildContext context, MeshProvider provider) {
    final connected = provider.peers
        .where((p) => p.status == PeerStatus.connected)
        .toList();
    if (connected.isEmpty) return const SizedBox(height: 80);

    return SizedBox(
      height: 90,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: connected.length,
        itemBuilder: (context, i) {
          final peer = connected[i];
          return GestureDetector(
            onTap: () => _openChat(context, peer),
            child: Container(
              width: 72,
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.divider),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.phone_android, color: AppColors.signal, size: 20),
                  const SizedBox(height: 4),
                  Text(
                    peer.displayName,
                    style: const TextStyle(fontSize: 10, color: AppColors.textPrimary),
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _openChat(BuildContext context, PeerDevice peer) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ChatScreen(peer: peer)),
    );
  }
}