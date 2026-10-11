import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../providers/mesh_provider.dart';
import '../models/peer_device.dart';
import '../utils/avatar.dart';
import '../widgets/pulse_radar.dart';
import 'chat_screen.dart';
import 'lobby_screen.dart';
import 'contacts_screen.dart';
import 'topology_screen.dart';
import 'activity_screen.dart';
import 'profile_screen.dart';

class RadarScreen extends StatelessWidget {
  const RadarScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MeshProvider>();
    final nearby = provider.peers
        .where((p) => p.status == PeerStatus.connected)
        .length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('DEADZONE'),
        actions: [
          IconButton(
            icon: const Icon(Icons.contacts, color: AppColors.textMuted),
            tooltip: 'Known devices',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ContactsScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.hub, color: AppColors.textMuted),
            tooltip: 'Mesh topology',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const TopologyScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.insights, color: AppColors.textMuted),
            tooltip: 'Recent activity',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ActivityScreen()),
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
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                _profileChip(context, provider),
                const Spacer(),
                Text(
                  provider.isMeshActive
                      ? '$nearby ${nearby == 1 ? 'friend' : 'friends'} nearby'
                      : 'Offline',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!provider.isMeshActive)
                    const Text(
                      'Tap the signal icon to go live 📡',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                    ),
                  if (provider.outboxCount > 0)
                    Text(
                      '${provider.outboxCount} waiting to send',
                      style: const TextStyle(color: AppColors.secure, fontSize: 12),
                    ),
                ],
              ),
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
        icon: const Icon(Icons.forum),
        label: const Text('LOBBY', style: TextStyle(fontWeight: FontWeight.bold)),
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const LobbyScreen()),
        ),
      ),
    );
  }

  Widget _profileChip(BuildContext context, MeshProvider provider) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ProfileScreen()),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              avatarEmojiFor(provider.myDisplayName),
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(
                provider.myDisplayName,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.edit, size: 12, color: AppColors.textMuted),
          ],
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
              width: 80,
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
                  Text(
                    avatarEmojiFor(peer.displayName),
                    style: const TextStyle(fontSize: 20),
                  ),
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
    final deviceId = peer.deviceId;
    if (deviceId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Still saying hi to this phone… try again in a sec 👋'),
        ),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          deviceId: deviceId,
          displayName: peer.displayName,
        ),
      ),
    );
  }
}