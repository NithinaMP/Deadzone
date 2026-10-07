import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../providers/mesh_provider.dart';
import '../widgets/message_bubble.dart';

/// Renamed from "SOS Broadcast" to "Mesh Broadcast" — "SOS" implies an
/// official emergency service (like cellular Wireless Emergency Alerts),
/// which this is NOT. This only reaches other Deadzone users who have
/// the app installed and the mesh active — never a substitute for real
/// emergency services.
class BroadcastScreen extends StatefulWidget {
  const BroadcastScreen({super.key});

  @override
  State<BroadcastScreen> createState() => _BroadcastScreenState();
}

class _BroadcastScreenState extends State<BroadcastScreen> {
  final _controller = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MeshProvider>();
    final messages = provider.conversationWith('BROADCAST');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mesh Broadcast'),
        backgroundColor: AppColors.void_,
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: AppColors.danger.withOpacity(0.12),
            child: const Text(
              'Reaches only other Deadzone users with the app open and '
                  'mesh active, within relay range. Not encrypted — treat as '
                  'a public in-app alert, not a private message.\n\n'
                  'This is NOT a replacement for emergency services. If you '
                  'are in real danger, contact local emergency services '
                  'through any available means.',
              style: TextStyle(color: AppColors.danger, fontSize: 12, height: 1.4),
            ),
          ),
          Expanded(
            child: messages.isEmpty
                ? const Center(
              child: Text('No broadcasts yet', style: TextStyle(color: AppColors.textMuted)),
            )
                : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 12),
              itemCount: messages.length,
              itemBuilder: (context, i) => MessageBubble(
                message: messages[i],
                isMine: messages[i].senderId == provider.myDeviceId,
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(
              left: 12, right: 12, top: 8,
              bottom: MediaQuery.of(context).viewInsets.bottom + 12,
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    style: const TextStyle(color: AppColors.textPrimary),
                    decoration: const InputDecoration(hintText: 'Broadcast message...'),
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  backgroundColor: AppColors.danger,
                  child: IconButton(
                    icon: const Icon(Icons.campaign, color: Colors.white),
                    onPressed: () async {
                      final text = _controller.text.trim();
                      if (text.isEmpty) return;
                      _controller.clear();
                      await provider.sendBroadcast(text);
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}