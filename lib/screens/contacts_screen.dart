import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../providers/mesh_provider.dart';
import '../models/peer_device.dart';
import 'chat_screen.dart';

/// Every device you've ever directly handshaken with, whether or not
/// they're in range right now. This is the piece that makes "message
/// someone far away through the mesh" actually usable: without this
/// screen, you could only open a chat with whoever happens to be
/// connected at this exact moment, which defeats the point of relaying.
class ContactsScreen extends StatelessWidget {
  const ContactsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MeshProvider>();
    final contacts = provider.getAllContacts()
      ..sort((a, b) {
        final aOnline = a.status == PeerStatus.connected ? 0 : 1;
        final bOnline = b.status == PeerStatus.connected ? 0 : 1;
        if (aOnline != bOnline) return aOnline.compareTo(bOnline);
        return a.displayName.compareTo(b.displayName);
      });

    return Scaffold(
      appBar: AppBar(title: const Text('Known Devices')),
      body: contacts.isEmpty
          ? const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No devices met yet. Go to the radar screen, go live, '
                'and let the app discover someone nearby — once you '
                'connect directly once, they show up here permanently, '
                'even after they walk out of range.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textMuted),
          ),
        ),
      )
          : ListView.separated(
        itemCount: contacts.length,
        separatorBuilder: (_, __) =>
        const Divider(height: 1, color: AppColors.divider),
        itemBuilder: (context, i) {
          final peer = contacts[i];
          final isOnline = peer.status == PeerStatus.connected;
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: AppColors.surfaceRaised,
              child: Icon(Icons.person,
                  color: isOnline ? AppColors.signal : AppColors.textMuted),
            ),
            title: Text(peer.displayName,
                style: const TextStyle(color: AppColors.textPrimary)),
            subtitle: Text(
              isOnline
                  ? 'In range now'
                  : 'Not in direct range — will relay through mesh',
              style: TextStyle(
                color: isOnline ? AppColors.signal : AppColors.textMuted,
                fontSize: 12,
              ),
            ),
            trailing: Icon(
              isOnline ? Icons.wifi_tethering : Icons.wifi_tethering_off,
              color: isOnline ? AppColors.signal : AppColors.textMuted,
              size: 18,
            ),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ChatScreen(
                  deviceId: peer.deviceId ?? peer.id,
                  displayName: peer.displayName,
                ),
              ),
            ),          );
        },
      ),
    );
  }
}